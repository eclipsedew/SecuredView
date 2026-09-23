package com.warpvpn.app

import android.content.Intent
import android.net.VpnService
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import mobile.Mobile

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.warpvpn/vpn"
    private val VPN_REQUEST_CODE = 1001

    private var pendingConnectResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "register" -> handleRegister(call, result)
                    "getFingerprint" -> {
                        // Stable hardware id for trial anti-abuse (never sent to 3rd parties)
                        val androidId = try {
                            android.provider.Settings.Secure.getString(
                                contentResolver,
                                android.provider.Settings.Secure.ANDROID_ID
                            ) ?: ""
                        } catch (_: Exception) {
                            ""
                        }
                        val parts = listOf(
                            androidId,
                            Build.MANUFACTURER ?: "",
                            Build.MODEL ?: "",
                            Build.DEVICE ?: "",
                        ).joinToString("|")
                        result.success(parts)
                    }
                    "hasConfig" -> {
                        result.success(WarpVpnService.hasConfig(this))
                    }
                    "connect" -> handleConnect(call, result)
                    "disconnect" -> {
                        val intent = Intent(this, WarpVpnService::class.java).apply {
                            action = WarpVpnService.ACTION_STOP
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(true)
                    }
                    "getStatus" -> {
                        // Prefer live Go engine status; fall back to service state.
                        val status = try {
                            Mobile.getStatus()
                        } catch (_: Exception) {
                            null
                        }
                        if (!status.isNullOrBlank()) {
                            result.success(status)
                        } else {
                            result.success(
                                """{"state":"${WarpVpnService.currentState()}","bytes_sent":0,"bytes_recv":0,"uptime":""}"""
                            )
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun handleRegister(call: MethodCall, result: MethodChannel.Result) {
        if (WarpVpnService.hasConfig(this)) {
            result.success(true)
            return
        }
        val deviceName = call.argument<String>("deviceName") ?: "SecuredView"
        Thread {
            try {
                val config = Mobile.registerAccount("", deviceName)
                runOnUiThread {
                    if (config.startsWith("error:")) {
                        result.error("REGISTER_FAILED", config.removePrefix("error: "), null)
                    } else {
                        WarpVpnService.saveConfig(this, config)
                        result.success(true)
                    }
                }
            } catch (e: Exception) {
                runOnUiThread {
                    result.error("REGISTER_FAILED", e.message ?: "registration failed", null)
                }
            }
        }.start()
    }

    private fun handleConnect(call: MethodCall, result: MethodChannel.Result) {
        if (!WarpVpnService.hasConfig(this)) {
            result.error("NO_CONFIG", "No WARP configuration. Call register first.", null)
            return
        }
        val prepareIntent = VpnService.prepare(this)
        if (prepareIntent != null) {
            pendingConnectResult = result
            startActivityForResult(prepareIntent, VPN_REQUEST_CODE)
        } else {
            startVpnService(result)
        }
    }

    private fun startVpnService(result: MethodChannel.Result) {
        val intent = Intent(this, WarpVpnService::class.java).apply {
            action = WarpVpnService.ACTION_START
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
        result.success(true)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == VPN_REQUEST_CODE) {
            val pending = pendingConnectResult
            pendingConnectResult = null
            if (resultCode == RESULT_OK) {
                if (pending != null) {
                    startVpnService(pending)
                }
            } else {
                pending?.error("PERMISSION_DENIED", "VPN permission denied by user", null)
            }
        }
    }
}
