import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Hardware-backed trial identity that survives sign-out and new accounts.
///
/// Seed preference key is intentionally *not* cleared by logout
/// (`ApiService.clearAuth` only removes JWT/account keys).
/// On Android the seed is ANDROID_ID + model/brand — reinstall keeps ANDROID_ID.
class DeviceFingerprint {
  static const _channel = MethodChannel('com.warpvpn/vpn');
  static const _seedKey = 'device_fp_seed';

  static String? _cached;

  /// Stable hex fingerprint (32+ chars) for server TrialClaim.device_key.
  static Future<String> get() async {
    if (_cached != null) return _cached!;
    final prefs = await SharedPreferences.getInstance();
    var seed = prefs.getString(_seedKey);
    if (seed == null || seed.isEmpty) {
      seed = await _nativeSeed() ?? _fallbackSeed();
      await prefs.setString(_seedKey, seed);
    }
    final digest = sha256.convert(utf8.encode('sv-fp:$seed'));
    _cached = digest.toString();
    return _cached!;
  }

  static Future<String?> _nativeSeed() async {
    if (kIsWeb) return null;
    try {
      final raw = await _channel.invokeMethod<String>('getFingerprint');
      if (raw != null && raw.isNotEmpty && raw != '|') return raw;
    } on MissingPluginException {
      // desktop / no handler
    } catch (_) {}
    return null;
  }

  static String _fallbackSeed() {
    if (kIsWeb) return 'web-${DateTime.now().millisecondsSinceEpoch}';
    try {
      final host = Platform.localHostname;
      final os = Platform.operatingSystem;
      final info = Platform.operatingSystemVersion;
      return '$host|$os|$info';
    } catch (_) {
      return 'unknown-${DateTime.now().millisecondsSinceEpoch}';
    }
  }
}
