package com.warpvpn.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import androidx.core.app.NotificationCompat

class WarpVpnService : VpnService() {
    private var vpnInterface: ParcelFileDescriptor? = null
    @Volatile
    private var isRunning = false

    companion object {
        private const val CHANNEL_ID = "warp_vpn_channel"
        private const val NOTIFICATION_ID = 1
        const val ACTION_START = "com.warpvpn.START"
        const val ACTION_STOP = "com.warpvpn.STOP"
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopVpn()
                @Suppress("DEPRECATION")
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    stopForeground(STOP_FOREGROUND_REMOVE)
                } else {
                    stopForeground(true)
                }
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_START -> {
                startVpn()
            }
        }
        return START_STICKY
    }

    private fun startVpn() {
        if (isRunning) return

        try {
            val builder = Builder()
            builder.setSession("WarpVPN")
            builder.addAddress("172.19.0.2", 32)
            builder.addRoute("0.0.0.0", 0)
            builder.addDnsServer("1.1.1.1")
            builder.addDnsServer("1.0.0.1")
            builder.setMtu(1280)

            try {
                builder.addDisallowedApplication(packageName)
            } catch (_: Exception) {
            }

            vpnInterface = builder.establish()
            isRunning = true

            startForeground(NOTIFICATION_ID, buildNotification("Connected to WarpVPN"))

            Thread {
                handleTunnel()
            }.start()
        } catch (e: Exception) {
            e.printStackTrace()
            stopVpn()
        }
    }

    private fun handleTunnel() {
        while (isRunning) {
            try {
                Thread.sleep(1000)
            } catch (_: InterruptedException) {
                break
            }
        }
    }

    private fun stopVpn() {
        isRunning = false
        try {
            vpnInterface?.close()
        } catch (_: Exception) {
        }
        vpnInterface = null
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "WarpVPN",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "WarpVPN Connection Status"
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(text: String): Notification {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val stopIntent = Intent(this, WarpVpnService::class.java).apply {
            action = ACTION_STOP
        }
        val stopPendingIntent = PendingIntent.getService(
            this, 1, stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("WarpVPN")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setContentIntent(pendingIntent)
            .addAction(android.R.drawable.ic_delete, "Disconnect", stopPendingIntent)
            .setOngoing(true)
            .build()
    }

    override fun onDestroy() {
        stopVpn()
        super.onDestroy()
    }

    override fun onRevoke() {
        stopVpn()
        super.onRevoke()
    }
}
