import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages the Cloudflare WARP MASQUE tunnel (via native usque engine).
///
/// Android path: method channel `com.warpvpn/vpn` → Go `mobile.Mobile`
/// (MASQUE / QUIC / HTTP3) — reliable behind the GFW, unlike WireGuard UDP.
class WarpService {
  static const _channel = MethodChannel('com.warpvpn/vpn');
  static const _identityKey = 'warp_identity';
  static const _registeredFlag = 'masque_registered';

  /// Returns true if a WARP MASQUE config exists (native side or cached flag).
  Future<bool> hasIdentity() async {
    try {
      final has = await _channel.invokeMethod<bool>('hasConfig');
      if (has == true) return true;
    } catch (_) {
      // Channel may not be ready yet — fall back to local flag.
    }
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_registeredFlag) ?? false;
  }

  /// Register a WARP account if needed. Returns when native config is ready.
  Future<void> ensureRegistered() async {
    if (await hasIdentity()) return;
    try {
      await _channel.invokeMethod('register', {'deviceName': 'SecuredView'});
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_registeredFlag, true);
    } on PlatformException catch (e) {
      throw Exception(e.message ?? 'WARP registration failed');
    }
  }

  /// Start the MASQUE tunnel and wait until it reports connected.
  Future<void> connect() async {
    await ensureRegistered();
    try {
      await _channel.invokeMethod('connect');
    } on PlatformException catch (e) {
      throw Exception(e.message ?? 'Failed to start tunnel');
    }

    // Wait for tunnel to come up (max 20s)
    for (var i = 0; i < 40; i++) {
      await Future.delayed(const Duration(milliseconds: 500));
      final state = await _rawState();
      if (state == 'connected') return;
      if (state == 'error') {
        throw Exception('MASQUE tunnel failed to start');
      }
    }
    throw Exception('MASQUE tunnel did not come up in time');
  }

  Future<void> disconnect() async {
    try {
      await _channel.invokeMethod('disconnect');
    } catch (_) {
      // Tunnel may not be running
    }
  }

  Future<bool> isConnected() async {
    final state = await _rawState();
    return state == 'connected' || state == 'reconnecting';
  }

  Future<String> _rawState() async {
    try {
      final status = await _channel.invokeMethod<String>('getStatus');
      if (status == null || status.isEmpty) return 'stopped';
      final data = jsonDecode(status) as Map<String, dynamic>;
      return (data['state'] as String?) ?? 'stopped';
    } catch (_) {
      return 'stopped';
    }
  }

  /// Full status JSON from the Go engine (state, bytes_sent, bytes_recv, uptime).
  Future<Map<String, dynamic>?> status() async {
    try {
      final status = await _channel.invokeMethod<String>('getStatus');
      if (status == null || status.isEmpty) return null;
      return jsonDecode(status) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Clear cached registration flag (does not delete native config).
  Future<void> clearLocalFlag() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_registeredFlag);
    await prefs.remove(_identityKey);
  }
}
