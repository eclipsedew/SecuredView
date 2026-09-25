import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  /// Primary public host — custom domain on Render (Cloudflare-fronted, CN-OK).
  static const publicDomainUrl = 'https://securedviewvpn.com';

  /// Direct Render origin — works if the custom domain has issues.
  static const renderOriginUrl = 'https://securedview-api.onrender.com';

  /// Legacy Vercel rewrite — often RST/reset in mainland CN; last resort only.
  static const publicTunnelUrl = 'https://meridianglobal.site';

  /// Ordered fallbacks. First success is sticky via SharedPreferences.
  /// Custom domain first (CN-safe); never burn a try on Vercel from mainland CN.
  static const List<String> apiBases = [
    publicDomainUrl,
    renderOriginUrl,
    publicTunnelUrl,
  ];

  static const String _basePrefKey = 'api_base_preferred';

  // Embedded API key — matches backend .app_key
  static const String appApiKey = 'df6b1d450fbfd724e2d099c9e0949da65cf8f43ba607c87ffe646e7465f34eb5';

  // Certificate pin SHA-256 hashes (add production server cert here)
  static const List<String> _pinnedCerts = [
    // Will be populated with production server cert hash
  ];

  static const _tokenKey = 'jwt_token';
  static const _accountIdKey = 'account_id';
  static const _deviceIdKey = 'device_id';

  String? _token;
  String? _accountId;
  String? _deviceId;
  SharedPreferences? _prefs;
  late http.Client _httpClient;
  http.Client get httpClient => _httpClient;

  String _preferredBase = apiBases.first;

  String get baseUrl => _preferredBase;
  String? get token => _token;
  String? get accountId => _accountId;
  String? get deviceId => _deviceId;
  bool get isAuthenticated => _token != null && _accountId != null;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _token = _prefs!.getString(_tokenKey);
    _accountId = _prefs!.getString(_accountIdKey)?.toUpperCase();
    _deviceId = _prefs!.getString(_deviceIdKey);
    final savedBase = _prefs!.getString(_basePrefKey);
    if (savedBase != null && apiBases.contains(savedBase)) {
      _preferredBase = savedBase;
    }
    if (_deviceId == null) {
      _deviceId = _generateDeviceId();
      await _prefs!.setString(_deviceIdKey, _deviceId!);
    }
    _httpClient = _createSecureClient();
  }

  /// Bases to try: sticky preferred first, then the other endpoint(s).
  List<String> _orderedBases() {
    final rest = apiBases.where((b) => b != _preferredBase).toList();
    return [_preferredBase, ...rest];
  }

  Future<void> _stickTo(String base) async {
    if (_preferredBase == base) return;
    _preferredBase = base;
    await _prefs?.setString(_basePrefKey, base);
  }

  /// Single choke point: multi-host failover + short per-try timeout.
  /// Transport errors (RST, DNS, timeout) and 5xx responses fall through to
  /// the next host — a 502 mid-deploy on one base must not fail the request
  /// when another base is healthy. Any other HTTP status is the real answer.
  Future<http.Response> send(
    String method,
    String path, {
    Map<String, String>? headers,
    Object? body,
    Duration timeout = const Duration(seconds: 8),
    int rounds = 2,
  }) async {
    Object? lastError;
    http.Response? lastResp;
    for (var round = 0; round < rounds; round++) {
      for (final base in _orderedBases()) {
        try {
          final uri = Uri.parse('$base$path');
          final req = http.Request(method, uri);
          req.headers.addAll(headers ?? _headers);
          if (body != null) {
            req.body = body is String ? body : jsonEncode(body);
          }
          final streamed = await _httpClient.send(req).timeout(timeout);
          final resp = await http.Response.fromStream(streamed)
              .timeout(const Duration(seconds: 8));
          if (resp.statusCode < 500) {
            await _stickTo(base);
            return resp;
          }
          // 5xx: this host is down/restarting — try the next base.
          lastResp = resp;
          lastError = null;
        } catch (e) {
          lastError = e;
          // next host immediately (RST is usually <1s)
        }
      }
      if (round == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
    }
    if (lastResp != null) {
      // Every reachable host returned 5xx — surface the real status.
      return lastResp;
    }
    if (lastError is TimeoutException) {
      throw ApiException('Network timeout. Check your connection and retry.',
          statusCode: null);
    }
    throw ApiException(
      'Cannot reach SecuredView servers. The network may be blocking this route — retry in a moment.',
      statusCode: null,
    );
  }

  Future<http.Response> get(String path,
          {Map<String, String>? headers, Duration? timeout}) =>
      send('GET', path,
          headers: headers ?? _headers,
          timeout: timeout ?? const Duration(seconds: 8));

  Future<http.Response> post(String path,
          {Map<String, String>? headers, Object? body, Duration? timeout}) =>
      send('POST', path,
          headers: headers ?? _headers,
          body: body,
          timeout: timeout ?? const Duration(seconds: 8));

  Future<http.Response> delete(String path,
          {Map<String, String>? headers, Duration? timeout}) =>
      send('DELETE', path,
          headers: headers ?? _headers,
          timeout: timeout ?? const Duration(seconds: 8));

  /// Create an HTTP client with certificate pinning
  http.Client _createSecureClient() {
    if (_pinnedCerts.isEmpty || kIsWeb) {
      return http.Client();
    }

    // In production, pin specific certs. For now, use default with extra validation.
    final httpClient = HttpClient()
      ..badCertificateCallback = (X509Certificate cert, String host, int port) {
        // In production, verify against _pinnedCerts here
        // For now, reject any invalid cert
        return false;
      };

    return IOClient(httpClient);
  }

  String _generateDeviceId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<void> _saveAuth(String token, String accountId) async {
    accountId = accountId.toUpperCase();
    _token = token;
    _accountId = accountId;
    await _prefs!.setString(_tokenKey, token);
    await _prefs!.setString(_accountIdKey, accountId);
  }

  Future<void> clearAuth() async {
    // Sign-out: drop session only. device_id + fingerprint seed stay so
    // a "new account" on the same hardware cannot mint a second trial.
    _token = null;
    _accountId = null;
    await _prefs!.remove(_tokenKey);
    await _prefs!.remove(_accountIdKey);
  }

  Future<void> clearAll() async {
    // Full wipe (factory reset path) — still keep fingerprint seed if present
    // so clear-data cannot farm trials. Android ANDROID_ID also survives.
    final fpSeed = _prefs?.getString('device_fp_seed');
    final did = _deviceId;
    _token = null;
    _accountId = null;
    _deviceId = null;
    await _prefs!.clear();
    if (fpSeed != null) await _prefs!.setString('device_fp_seed', fpSeed);
    if (did != null) await _prefs!.setString(_deviceIdKey, did);
    _deviceId = did ?? _prefs!.getString(_deviceIdKey);
    if (_deviceId == null) {
      _deviceId = _generateDeviceId();
      await _prefs!.setString(_deviceIdKey, _deviceId!);
    }
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'X-Api-Key': appApiKey,
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  Map<String, String> get _publicHeaders => {
        'Content-Type': 'application/json',
        'X-Api-Key': appApiKey,
      };

  Future<Map<String, dynamic>> _handleResponse(http.Response resp) async {
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      if (resp.body.isEmpty) return {};
      return jsonDecode(resp.body) as Map<String, dynamic>;
    }
    if (resp.statusCode == 401) {
      throw ApiException('Invalid credentials', statusCode: 401);
    }
    if (resp.statusCode == 403) {
      throw ApiException('Access denied', statusCode: 403);
    }
    if (resp.statusCode == 404) {
      throw ApiException('Not found', statusCode: 404);
    }
    if (resp.statusCode == 429) {
      throw ApiException('Too many requests. Try again later.', statusCode: 429);
    }
    throw ApiException('Request failed', statusCode: resp.statusCode);
  }

  Future<List<dynamic>> _handleListResponse(http.Response resp) async {
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      if (resp.body.isEmpty) return [];
      return jsonDecode(resp.body) as List<dynamic>;
    }
    throw ApiException('Request failed', statusCode: resp.statusCode);
  }

  // Account
  Future<RegisterResult> register({
    required String pin,
    required String deviceName,
    required String platform,
    String? fingerprint,
  }) async {
    final resp = await send(
      'POST',
      '/api/accounts/register',
      headers: _publicHeaders,
      body: {
        'pin': pin,
        'device_id': _deviceId,
        'device_name': deviceName,
        'platform': platform,
        if (fingerprint != null && fingerprint.isNotEmpty)
          'fingerprint': fingerprint,
      },
    );
    final data = await _handleResponse(resp);
    await _saveAuth(data['access_token'], data['account_id']);
    return RegisterResult(
      accountId: data['account_id'].toString().toUpperCase(),
      isPremium: data['is_premium'] ?? false,
      isTrial: data['is_trial'] ?? false,
      trialEndsAt: data['trial_ends_at'] != null
          ? DateTime.tryParse(data['trial_ends_at'])
          : null,
    );
  }

  Future<LoginResult> login({
    required String accountId,
    required String pin,
    required String deviceName,
    required String platform,
    String? fingerprint,
  }) async {
    final resp = await send(
      'POST',
      '/api/accounts/login',
      headers: _publicHeaders,
      body: {
        'account_id': accountId.trim().toUpperCase(),
        'pin': pin,
        'device_id': _deviceId,
        'device_name': deviceName,
        'platform': platform,
        if (fingerprint != null && fingerprint.isNotEmpty)
          'fingerprint': fingerprint,
      },
    );
    final data = await _handleResponse(resp);
    await _saveAuth(data['access_token'], data['account_id']);
    return LoginResult(
      accountId: data['account_id'].toString().toUpperCase(),
      isPremium: data['is_premium'] ?? false,
      isAdmin: data['is_admin'] ?? false,
    );
  }

  Future<AccountInfo> getAccountInfo() async {
    final resp = await get('/api/accounts/me');
    final data = await _handleResponse(resp);
    return AccountInfo.fromJson(data);
  }

  // ── Admin dashboard API (admin account token only) ──────
  Future<List<AccountInfo>> adminListAccounts() async {
    final resp = await get('/api/admin/accounts');
    final list = await _handleListResponse(resp);
    return list
        .map((e) => AccountInfo.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> adminCreateAccount({
    required String accountType,
    String? pin,
    String? displayName,
    int? days,
  }) async {
    final resp = await post('/api/admin/accounts', body: {
      'account_type': accountType,
      if (pin != null && pin.isNotEmpty) 'pin': pin,
      if (displayName != null && displayName.isNotEmpty)
        'display_name': displayName,
      if (days != null) 'days': days,
    });
    return _handleResponse(resp);
  }

  Future<Map<String, dynamic>> adminGrantPremium(
      String accountId, {int? days}) async {
    final resp = await post(
      '/api/admin/accounts/$accountId/premium',
      body: days != null ? {'days': days} : <String, dynamic>{},
    );
    return _handleResponse(resp);
  }

  Future<void> adminDeleteAccount(String accountId) async {
    final resp = await delete('/api/admin/accounts/$accountId');
    await _handleResponse(resp);
  }

  // Servers
  Future<List<ServerData>> getAvailableServers() async {
    final resp = await get('/api/servers/');
    final list = await _handleListResponse(resp);
    return list.map((s) => ServerData.fromJson(s)).toList();
  }

  Future<List<ServerData>> getAllServersPublic() async {
    final resp = await get('/api/servers/all', headers: _publicHeaders);
    final list = await _handleListResponse(resp);
    return list.map((s) => ServerData.fromJson(s)).toList();
  }

  // Devices
  Future<List<DeviceInfoData>> getDevices() async {
    final resp = await get('/api/accounts/me/devices');
    final list = await _handleListResponse(resp);
    return list.map((d) => DeviceInfoData.fromJson(d)).toList();
  }

  Future<void> removeDevice(String deviceId) async {
    await delete('/api/accounts/me/devices/$deviceId');
  }

  // Premium
  Future<List<PlanData>> getPlans() async {
    final resp = await get('/api/premium/plans', headers: _publicHeaders);
    final list = await _handleListResponse(resp);
    return list.map((p) => PlanData.fromJson(p)).toList();
  }

  Future<PremiumStatus> getPremiumStatus() async {
    final resp = await get('/api/premium/status');
    final data = await _handleResponse(resp);
    return PremiumStatus.fromJson(data);
  }

  Future<Map<String, String>> getDeviceNames() async {
    if (_prefs == null) return {};
    final map = <String, String>{};
    for (final key in _prefs!.getKeys()) {
      if (key.startsWith('device_name_')) {
        final deviceId = key.replaceFirst('device_name_', '');
        final val = _prefs!.getString(key);
        if (val != null) map[deviceId] = val;
      }
    }
    return map;
  }

  Future<void> saveDeviceName(String deviceId, String name) async {
    await _prefs?.setString('device_name_$deviceId', name);
  }

  Future<bool> checkHealth() async {
    try {
      final resp = await get('/health',
          headers: _publicHeaders, timeout: const Duration(seconds: 5));
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}

// Data classes

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  ApiException(this.message, {this.statusCode});
  @override
  String toString() => message;
}

class RegisterResult {
  final String accountId;
  final bool isPremium;
  final bool isTrial;
  final DateTime? trialEndsAt;
  RegisterResult({
    required this.accountId,
    required this.isPremium,
    this.isTrial = false,
    this.trialEndsAt,
  });
}

class LoginResult {
  final String accountId;
  final bool isPremium;
  final bool isTrial;
  final DateTime? trialEndsAt;
  final bool isAdmin;
  LoginResult({
    required this.accountId,
    required this.isPremium,
    this.isTrial = false,
    this.trialEndsAt,
    this.isAdmin = false,
  });
}

class AccountInfo {
  final String id;
  final String displayName;
  final bool isPremium;
  final DateTime? premiumExpiresAt;
  final int deviceCount;
  final int maxDevices;
  final DateTime createdAt;
  final bool isTrial;
  final DateTime? trialEndsAt;
  final bool isAdmin;
  final String accountType;

  AccountInfo({
    required this.id,
    required this.displayName,
    required this.isPremium,
    this.premiumExpiresAt,
    required this.deviceCount,
    required this.maxDevices,
    required this.createdAt,
    this.isTrial = false,
    this.trialEndsAt,
    this.isAdmin = false,
    this.accountType = 'normal',
  });

  factory AccountInfo.fromJson(Map<String, dynamic> json) => AccountInfo(
        id: json['id'] ?? '',
        displayName: json['display_name'] ?? 'User',
        isPremium: json['is_premium'] ?? false,
        premiumExpiresAt: json['premium_expires_at'] != null
            ? DateTime.tryParse(json['premium_expires_at'])
            : null,
        deviceCount: json['device_count'] ?? 0,
        maxDevices: json['max_devices'] ?? 2,
        createdAt: json['created_at'] != null
            ? DateTime.parse(json['created_at'])
            : DateTime.now(),
        isTrial: json['is_trial'] ?? false,
        trialEndsAt: json['trial_ends_at'] != null
            ? DateTime.tryParse(json['trial_ends_at'])
            : null,
        isAdmin: json['is_admin'] ?? false,
        accountType: json['account_type'] ?? 'normal',
      );
}

class ServerData {
  final String id;
  final String name;
  final String country;
  final String countryCode;
  final String city;
  final double latitude;
  final double longitude;
  final String tier;
  final bool isActive;
  final int speedMbps;
  final int pingMs;
  final String? ipAddress;

  ServerData({
    required this.id, required this.name, required this.country,
    required this.countryCode, required this.city,
    required this.latitude, required this.longitude,
    required this.tier, required this.isActive,
    required this.speedMbps, required this.pingMs,
    this.ipAddress,
  });

  factory ServerData.fromJson(Map<String, dynamic> json) => ServerData(
        id: json['id'] ?? '',
        name: json['name'] ?? '',
        country: json['country'] ?? '',
        countryCode: json['country_code'] ?? '',
        city: json['city'] ?? '',
        latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
        longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
        // Product rule: no free tier — treat missing/legacy free as paid.
        tier: json['tier'] == 'free' ? 'premium' : (json['tier'] ?? 'premium'),
        isActive: json['is_active'] ?? true,
        speedMbps: json['speed_mbps'] ?? 100,
        pingMs: json['ping_ms'] ?? 20,
        ipAddress: json['ip_address'] as String?,
      );
}

class PlanData {
  final String id;
  final String name;
  final int days;
  final double price;
  final int maxDevices;

  PlanData({required this.id, required this.name, required this.days,
      required this.price, required this.maxDevices});

  factory PlanData.fromJson(Map<String, dynamic> json) => PlanData(
        id: json['id'] ?? '',
        name: json['name'] ?? '',
        days: json['days'] ?? 30,
        price: (json['price'] as num?)?.toDouble() ?? 0,
        maxDevices: json['max_devices'] ?? 2,
      );

  String get priceDisplay =>
      '\$${price.toStringAsFixed(price.truncateToDouble() == price ? 0 : 2)}';
}

class PremiumStatus {
  final bool isPremium;
  final DateTime? expiresAt;
  final double? remainingSeconds;
  final bool isTrial;
  final DateTime? trialEndsAt;
  final double? trialRemainingSeconds;
  final DateTime? serverTime;

  PremiumStatus({
    required this.isPremium,
    this.expiresAt,
    this.remainingSeconds,
    this.isTrial = false,
    this.trialEndsAt,
    this.trialRemainingSeconds,
    this.serverTime,
  });

  factory PremiumStatus.fromJson(Map<String, dynamic> json) => PremiumStatus(
        isPremium: json['is_premium'] ?? false,
        expiresAt: json['expires_at'] != null ? DateTime.tryParse(json['expires_at']) : null,
        remainingSeconds: (json['remaining_seconds'] as num?)?.toDouble(),
        isTrial: json['is_trial'] ?? false,
        trialEndsAt: json['trial_ends_at'] != null
            ? DateTime.tryParse(json['trial_ends_at'])
            : null,
        trialRemainingSeconds: (json['trial_remaining_seconds'] as num?)?.toDouble(),
        serverTime: json['server_time'] != null ? DateTime.tryParse(json['server_time']) : null,
      );
}

class DeviceInfoData {
  final String id;
  final String deviceName;
  final String platform;
  final DateTime? lastSeen;
  final bool isActive;

  DeviceInfoData({
    required this.id,
    required this.deviceName,
    required this.platform,
    this.lastSeen,
    required this.isActive,
  });

  factory DeviceInfoData.fromJson(Map<String, dynamic> json) => DeviceInfoData(
        id: json['id'] ?? '',
        deviceName: json['device_name'] ?? 'Unknown Device',
        platform: json['platform'] ?? 'unknown',
        lastSeen: json['last_seen'] != null ? DateTime.tryParse(json['last_seen']) : null,
        isActive: json['is_active'] ?? true,
      );
}
