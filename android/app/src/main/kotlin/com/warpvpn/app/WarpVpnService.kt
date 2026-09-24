package com.warpvpn.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.IBinder
import android.os.ParcelFileDescriptor
import android.util.Log
import androidx.core.app.NotificationCompat
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import mobile.Mobile
import mobile.TunnelListener
import org.json.JSONObject

/**
 * MASQUE (Cloudflare WARP over QUIC/HTTP3) VPN service.
 * Bridges Android VpnService TUN + protect()'d UDP socket to the Go usque engine.
 */
class WarpVpnService : VpnService() {

    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    @Volatile private var tunnelStopped = false
    private var tunPfd: ParcelFileDescriptor? = null
    private var tunFd: Int = -1
    private var udpFd: Long = -1
    private var trafficJob: Job? = null
    private var lastSent: Long = 0
    private var lastRecv: Long = 0
    private var lastTrafficTime: Long = 0

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        instance = this
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> startTunnel()
            ACTION_STOP -> stopTunnel()
            null -> {
                // System restarted us after process death — revive tunnel if we
                // were up (START_STICKY). Otherwise just die quietly.
                if (wasConnected() && loadConfigJson() != null) {
                    startTunnel()
                } else {
                    stopSelf()
                }
            }
        }
        // Sticky: keep the tunnel alive when the UI process is swiped away.
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        stopIfRunning(blocking = true)
        serviceScope.cancel()
        clearInstanceIfSelf()
        super.onDestroy()
    }

    override fun onRevoke() {
        stopIfRunning(blocking = true)
        serviceScope.cancel()
        clearInstanceIfSelf()
    }

    @Synchronized
    private fun stopIfRunning(blocking: Boolean) {
        if (tunnelStopped) return
        tunnelStopped = true
        stopTrafficUpdates()
        if (blocking) {
            stopTunnelInternalBlocking()
        } else {
            stopTunnelInternalAsync()
        }
    }

    @Synchronized
    private fun clearInstanceIfSelf() {
        if (instance === this) {
            instance = null
        }
    }

    private fun loadConfigJson(): String? {
        return getSharedPreferences(PREFS_NAME, android.content.Context.MODE_PRIVATE)
            .getString(KEY_CONFIG, null)
            ?.takeIf { it.isNotBlank() }
    }

    private fun startTunnel() {
        val configJson = loadConfigJson()
        if (configJson == null) {
            _tunnelState.value = TunnelState.Error("No configuration set")
            return
        }

        // Reset stop guard for a fresh start on this instance
        tunnelStopped = false

        startForeground(NOTIFICATION_ID, buildNotification("Connecting…"))
        _tunnelState.value = TunnelState.Connecting

        val parsed = parseVpnConfig(configJson)
        if (parsed == null) {
            _tunnelState.value = TunnelState.Error("Failed to parse config")
            stopSelf()
            return
        }

        val builder = Builder().setMtu(parsed.mtu).setSession("SecuredView")

        if (parsed.enableIPv4 && parsed.ipv4Address != null) {
            builder.addAddress(parsed.ipv4Address, 32)
        }
        if (parsed.enableIPv6 && parsed.ipv6Address != null) {
            builder.addAddress(parsed.ipv6Address, 128)
        }

        // Route only address families we actually have an address for.
        // Routing ::/0 without a working IPv6 path either blackholes or
        // (worse, if we skip the route) lets IPv6 leak around the tunnel.
        if (parsed.enableIPv4 && parsed.ipv4Address != null) {
            try {
                builder.addRoute("0.0.0.0", 0)
            } catch (e: Exception) {
                Log.w(TAG, "addRoute IPv4 default failed: ${e.message}")
            }
        }
        val ipv6Up = parsed.enableIPv6 && parsed.ipv6Address != null
        if (ipv6Up) {
            try {
                builder.addRoute("::", 0)
            } catch (e: Exception) {
                Log.w(TAG, "addRoute IPv6 default failed: ${e.message}")
            }
        } else {
            // No IPv6 in the tunnel → block family so it cannot bypass TUN.
            try {
                // AF_INET = 2. java.net has no AF_INET; OsConstants is the Android API.
                builder.allowFamily(android.system.OsConstants.AF_INET)
            } catch (e: Exception) {
                Log.w(TAG, "allowFamily(AF_INET) failed: ${e.message}")
            }
        }

        for (dns in parsed.dnsServers) {
            builder.addDnsServer(dns)
        }

        // GLOBAL: all apps through tunnel. protect() on MASQUE UDP prevents loops;
        // do not disallow self so the whole device (and app control plane) is covered.
        // If a specific backend must bypass, add it here.

        tunPfd?.close()
        tunPfd = null
        val pfd = builder.establish()
        if (pfd == null) {
            _tunnelState.value = TunnelState.Error("Failed to establish VPN interface")
            stopSelf()
            return
        }
        tunPfd = pfd
        tunFd = pfd.fd

        if (udpFd >= 0) {
            Mobile.closeSocket(udpFd)
        }
        udpFd = Mobile.createUDPSocket()
        if (udpFd < 0) {
            _tunnelState.value = TunnelState.Error("Failed to create UDP socket")
            stopTunnelInternalAsync()
            stopSelf()
            return
        }
        protect(udpFd.toInt())

        val listener = object : TunnelListener {
            override fun onStateChange(state: String?) {
                Log.d(TAG, "State change: $state")
                _tunnelState.value = when (state) {
                    "connecting" -> TunnelState.Connecting
                    "connected" -> TunnelState.Connected()
                    "reconnecting" -> TunnelState.Reconnecting()
                    "stopped" -> TunnelState.Stopped
                    "error" -> TunnelState.Error("Tunnel error")
                    else -> _tunnelState.value
                }
                updateNotification()
                if (state == "stopped" || state == "error") {
                    stopTrafficUpdates()
                    markConnected(false)
                    stopSelf()
                } else if (state == "connected") {
                    markConnected(true)
                }
            }

            override fun onTraffic(sent: Long, recv: Long) {
                val current = _tunnelState.value
                _tunnelState.value = when (current) {
                    is TunnelState.Connected -> current.copy(bytesSent = sent, bytesRecv = recv)
                    is TunnelState.Reconnecting -> current.copy(bytesSent = sent, bytesRecv = recv)
                    else -> current
                }
            }
        }

        Mobile.registerListener(listener)
        val err = Mobile.startTunnel(tunFd.toLong(), udpFd, configJson)
        if (err.isNotEmpty()) {
            Mobile.unregisterListener()
            _tunnelState.value = TunnelState.Error(err)
            stopTunnelInternalAsync()
            stopSelf()
        } else {
            startTrafficUpdates()
            markConnected(true)
        }
    }

    private fun stopTunnel() {
        _tunnelState.value = TunnelState.Stopped
        markConnected(false)
        updateNotification()
        stopIfRunning(blocking = false)
        stopSelf()
    }

    @Synchronized
    private fun snapshotAndClearFds(): FdSnapshot {
        val udpFdToClose = udpFd
        udpFd = -1
        // Go's StopTunnel closes the TUN fd via FdAdapter; detach so Kotlin doesn't double-close.
        tunPfd?.detachFd()
        tunPfd = null
        tunFd = -1
        return FdSnapshot(udpFdToClose)
    }

    private fun teardownGoEngine(snap: FdSnapshot) {
        try {
            Mobile.stopTunnel()
        } catch (_: Exception) {}
        try {
            Mobile.unregisterListener()
        } catch (_: Exception) {}
        if (snap.udpFd >= 0) {
            try {
                Mobile.closeSocket(snap.udpFd)
            } catch (_: Exception) {}
        }
        _tunnelState.value = TunnelState.Stopped
        markConnected(false)
    }

    private fun stopTunnelInternalAsync() {
        val snap = snapshotAndClearFds()
        try {
            serviceScope.launch { teardownGoEngine(snap) }
        } catch (_: Exception) {
            teardownGoEngine(snap)
        }
    }

    private fun stopTunnelInternalBlocking() {
        val snap = snapshotAndClearFds()
        runBlocking {
            withTimeoutOrNull(STOP_TIMEOUT) {
                withContext(Dispatchers.IO) { teardownGoEngine(snap) }
            } ?: Log.w(TAG, "Tunnel stop timed out after ${STOP_TIMEOUT}ms")
        }
    }

    private data class FdSnapshot(val udpFd: Long)

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "VPN Tunnel",
                NotificationManager.IMPORTANCE_LOW
            )
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(contentText: String): Notification {
        val pendingIntent = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("SecuredView VPN")
            .setContentText(contentText)
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()
    }

    private fun updateNotification() {
        val contentText = when (val state = _tunnelState.value) {
            is TunnelState.Connected -> {
                val rateText = "↑ ${formatRate(state.rateSent)}  ↓ ${formatRate(state.rateRecv)}"
                "Connected · $rateText"
            }
            is TunnelState.Reconnecting -> "Reconnecting…"
            is TunnelState.Connecting -> "Connecting…"
            is TunnelState.Stopped -> "Disconnected"
            is TunnelState.Error -> "Tunnel error"
        }
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(NOTIFICATION_ID, buildNotification(contentText))
    }

    private fun startTrafficUpdates() {
        trafficJob?.cancel()
        lastSent = 0
        lastRecv = 0
        lastTrafficTime = System.currentTimeMillis()
        trafficJob = serviceScope.launch {
            while (true) {
                delay(1000)
                updateTrafficRate()
            }
        }
    }

    private fun stopTrafficUpdates() {
        trafficJob?.cancel()
        trafficJob = null
    }

    private fun updateTrafficRate() {
        val current = _tunnelState.value
        if (current !is TunnelState.Connected) return
        val now = System.currentTimeMillis()
        val dt = (now - lastTrafficTime) / 1000.0
        lastTrafficTime = now

        val dSent = (current.bytesSent - lastSent).coerceAtLeast(0)
        val dRecv = (current.bytesRecv - lastRecv).coerceAtLeast(0)
        lastSent = current.bytesSent
        lastRecv = current.bytesRecv

        val rateSent = if (dt > 0) (dSent / dt).toLong() else 0
        val rateRecv = if (dt > 0) (dRecv / dt).toLong() else 0

        _tunnelState.value = current.copy(rateSent = rateSent, rateRecv = rateRecv)
        updateNotification()
    }

    private fun formatRate(bytesPerSec: Long): String = when {
        bytesPerSec < 1024 -> "$bytesPerSec B/s"
        bytesPerSec < 1024 * 1024 -> "%.1f KB/s".format(bytesPerSec / 1024.0)
        bytesPerSec < 1024 * 1024 * 1024 -> "%.1f MB/s".format(bytesPerSec / (1024.0 * 1024))
        else -> "%.2f GB/s".format(bytesPerSec / (1024.0 * 1024 * 1024))
    }

    private data class VpnConfig(
        val ipv4Address: String?,
        val ipv6Address: String?,
        val enableIPv4: Boolean,
        val enableIPv6: Boolean,
        val dnsServers: List<String>,
        val mtu: Int
    )

    private fun parseVpnConfig(json: String): VpnConfig? {
        return try {
            val root = JSONObject(json)
            val account = root.optJSONObject("account")
            val ipv4Addr = account?.optString("ipv4")?.ifEmpty { null }
            val ipv6Addr = account?.optString("ipv6")?.ifEmpty { null }

            val inbound = root.optJSONObject("inbound")
            val tunSettings = inbound?.optJSONObject("settings")

            val enableIPv4 = tunSettings?.optBoolean("ipv4", true) ?: true
            val enableIPv6 = tunSettings?.optBoolean("ipv6", true) ?: true
            val mtu = tunSettings?.optInt("mtu", 1280) ?: 1280

            val dnsList = mutableListOf<String>()
            val dnsArray = tunSettings?.optJSONArray("dns")
            if (dnsArray != null) {
                for (i in 0 until dnsArray.length()) {
                    dnsArray.optString(i)?.let { dnsList.add(it) }
                }
            }
            if (dnsList.isEmpty()) {
                if (enableIPv4) {
                    dnsList.add("1.1.1.1")
                    dnsList.add("1.0.0.1")
                }
                if (enableIPv6) {
                    dnsList.add("2606:4700:4700::1111")
                }
            }

            VpnConfig(
                ipv4Address = ipv4Addr,
                ipv6Address = ipv6Addr,
                enableIPv4 = enableIPv4 && ipv4Addr != null,
                enableIPv6 = enableIPv6 && ipv6Addr != null,
                dnsServers = dnsList,
                mtu = mtu
            )
        } catch (e: Exception) {
            Log.e(TAG, "Failed to parse VPN config", e)
            null
        }
    }

    companion object {
        private const val TAG = "WarpVpnService"
        private const val CHANNEL_ID = "warp_vpn_channel"
        private const val NOTIFICATION_ID = 1
        private const val STOP_TIMEOUT = 5_000L
        private const val PREFS_NAME = "warpvpn_masque"
        private const val KEY_CONFIG = "config_json"
        private const val KEY_WAS_CONNECTED = "was_connected"

        const val ACTION_START = "com.warpvpn.START"
        const val ACTION_STOP = "com.warpvpn.STOP"

        private val _tunnelState = MutableStateFlow<TunnelState>(TunnelState.Stopped)
        val tunnelState: StateFlow<TunnelState> = _tunnelState.asStateFlow()

        var instance: WarpVpnService? = null
            private set

        fun hasConfig(context: android.content.Context): Boolean {
            return !context.getSharedPreferences(PREFS_NAME, android.content.Context.MODE_PRIVATE)
                .getString(KEY_CONFIG, null).isNullOrBlank()
        }

        fun saveConfig(context: android.content.Context, configJson: String) {
            context.getSharedPreferences(PREFS_NAME, android.content.Context.MODE_PRIVATE)
                .edit().putString(KEY_CONFIG, configJson).apply()
        }

        fun markConnected(context: android.content.Context, up: Boolean) {
            context.getSharedPreferences(PREFS_NAME, android.content.Context.MODE_PRIVATE)
                .edit().putBoolean(KEY_WAS_CONNECTED, up).apply()
        }

        private fun markConnected(up: Boolean) {
            // Prefer live instance context; fall back is no-op if already gone.
            instance?.let { markConnected(it, up) }
        }

        fun wasConnected(context: android.content.Context): Boolean {
            return context.getSharedPreferences(PREFS_NAME, android.content.Context.MODE_PRIVATE)
                .getBoolean(KEY_WAS_CONNECTED, false)
        }

        private fun wasConnected(): Boolean = instance?.let { wasConnected(it) } ?: false

        fun currentState(): String {
            return when (_tunnelState.value) {
                is TunnelState.Stopped -> "stopped"
                is TunnelState.Connecting -> "connecting"
                is TunnelState.Connected -> "connected"
                is TunnelState.Reconnecting -> "reconnecting"
                is TunnelState.Error -> "error"
            }
        }
    }
}

sealed class TunnelState {
    data object Stopped : TunnelState()
    data object Connecting : TunnelState()
    data class Connected(
        val bytesSent: Long = 0,
        val bytesRecv: Long = 0,
        val rateSent: Long = 0,
        val rateRecv: Long = 0
    ) : TunnelState()
    data class Reconnecting(
        val bytesSent: Long = 0,
        val bytesRecv: Long = 0
    ) : TunnelState()
    data class Error(val message: String) : TunnelState()
}
