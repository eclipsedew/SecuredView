package com.warpvpn.app

import android.content.Intent
import android.net.VpnService
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.warpvpn/vpn"
    private val VPN_REQUEST_CODE = 1001

    private var vpnMethodCall: MethodCall? = null
    private var vpnResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "connect" -> {
                        val prepareIntent = VpnService.prepare(this)
                        if (prepareIntent != null) {
                            vpnMethodCall = call
                            vpnResult = result
                            startActivityForResult(prepareIntent, VPN_REQUEST_CODE)
                        } else {
                            startVpnService(call, result)
                        }
                    }
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
                        result.success(WarpVpnService::class.java.simpleName)
                    }
                    else -> {
                        result.notImplemented()
                    }
                }
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == VPN_REQUEST_CODE) {
            if (resultCode == RESULT_OK) {
                vpnMethodCall?.let { call ->
                    vpnResult?.let { result ->
                        startVpnService(call, result)
                    }
                }
            } else {
                vpnResult?.error("PERMISSION_DENIED", "VPN permission denied by user", null)
            }
            vpnMethodCall = null
            vpnResult = null
        }
    }

    @Suppress("UNCHECKED_CAST")
    private fun startVpnService(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<String, Any> ?: emptyMap()
        val endpoint = args["endpoint"] as? String ?: ""
        val port = args["port"] as? Int ?: 2408
        val publicKey = args["publicKey"] as? String ?: ""
        val ipAddress = args["ipAddress"] as? String ?: "172.19.0.2/32"
        val dns = args["dns"] as? String ?: "1.1.1.1"

        val intent = Intent(this, WarpVpnService::class.java).apply {
            action = WarpVpnService.ACTION_START
            putExtra("endpoint", endpoint)
            putExtra("port", port)
            putExtra("publicKey", publicKey)
            putExtra("ipAddress", ipAddress)
            putExtra("dns", dns)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }

        result.success(true)
    }
}
