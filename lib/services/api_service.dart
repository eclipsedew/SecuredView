import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  static String get _defaultBaseUrl {
    if (kIsWeb) return 'http://localhost:8080';
    if (Platform.isAndroid) return 'https://artists-friends-feelings-rss.trycloudflare.com';
    return 'http://localhost:8080';
  }

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

  String get baseUrl => _defaultBaseUrl;
  String? get token => _token;
  String? get accountId => _accountId;
  String? get deviceId => _deviceId;
  bool get isAuthenticated => _token != null && _accountId != null;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _token = _prefs!.getString(_tokenKey);
    _accountId = _prefs!.getString(_accountIdKey)?.toUpperCase();
    _deviceId = _prefs!.getString(_deviceIdKey);
    if (_deviceId == null) {
      _deviceId = _generateDeviceId();
      await _prefs!.setString(_deviceIdKey, _deviceId!);
    }
    _httpClient = _createSecureClient();
  }

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
    _token = null;
    _accountId = null;
    await _prefs!.remove(_tokenKey);
    await _prefs!.remove(_accountIdKey);
  }

  Future<void> clearAll() async {
    _token = null;
    _accountId = null;
    _deviceId = null;
    await _prefs!.clear();
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

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

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
  }) async {
    final resp = await _httpClient.post(
      _uri('/api/accounts/register'),
      headers: _publicHeaders,
      body: jsonEncode({
        'pin': pin,
        'device_id': _deviceId,
        'device_name': deviceName,
        'platform': platform,
      }),
    );
    final data = await _handleResponse(resp);
    await _saveAuth(data['access_token'], data['account_id']);
    return RegisterResult(
      accountId: data['account_id'].toString().toUpperCase(),
      isPremium: data['is_premium'] ?? false,
    );
  }

  Future<LoginResult> login({
    required String accountId,
    required String pin,
    required String deviceName,
    required String platform,
  }) async {
    final resp = await _httpClient.post(
      _uri('/api/accounts/login'),
      headers: _publicHeaders,
      body: jsonEncode({
        'account_id': accountId.trim().toUpperCase(),
        'pin': pin,
        'device_id': _deviceId,
        'device_name': deviceName,
        'platform': platform,
      }),
    );
    final data = await _handleResponse(resp);
    await _saveAuth(data['access_token'], data['account_id']);
    return LoginResult(
      accountId: data['account_id'].toString().toUpperCase(),
      isPremium: data['is_premium'] ?? false,
    );
  }

  Future<AccountInfo> getAccountInfo() async {
    final resp = await _httpClient.get(_uri('/api/accounts/me'), headers: _headers);
    final data = await _handleResponse(resp);
    return AccountInfo.fromJson(data);
  }

  // Servers
  Future<List<ServerData>> getAvailableServers() async {
    final resp = await _httpClient.get(_uri('/api/servers/'), headers: _headers);
    final list = await _handleListResponse(resp);
    return list.map((s) => ServerData.fromJson(s)).toList();
  }

  Future<List<ServerData>> getAllServersPublic() async {
    final resp = await _httpClient.get(_uri('/api/servers/all'), headers: _publicHeaders);
    final list = await _handleListResponse(resp);
    return list.map((s) => ServerData.fromJson(s)).toList();
  }

  // Devices
  Future<List<DeviceInfoData>> getDevices() async {
    final resp = await _httpClient.get(_uri('/api/accounts/me/devices'), headers: _headers);
    final list = await _handleListResponse(resp);
    return list.map((d) => DeviceInfoData.fromJson(d)).toList();
  }

  Future<void> removeDevice(String deviceId) async {
    await _httpClient.delete(_uri('/api/accounts/me/devices/$deviceId'), headers: _headers);
  }

  // Premium
  Future<List<PlanData>> getPlans() async {
    final resp = await _httpClient.get(_uri('/api/premium/plans'), headers: _publicHeaders);
    final list = await _handleListResponse(resp);
    return list.map((p) => PlanData.fromJson(p)).toList();
  }

  Future<PremiumStatus> getPremiumStatus() async {
    final resp = await _httpClient.get(_uri('/api/premium/status'), headers: _headers);
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
      final resp = await _httpClient.get(_uri('/health'), headers: _publicHeaders)
          .timeout(const Duration(seconds: 5));
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
  RegisterResult({required this.accountId, required this.isPremium});
}

class LoginResult {
  final String accountId;
  final bool isPremium;
  LoginResult({required this.accountId, required this.isPremium});
}

class AccountInfo {
  final String id;
  final String displayName;
  final bool isPremium;
  final DateTime? premiumExpiresAt;
  final int deviceCount;
  final int maxDevices;
  final DateTime createdAt;

  AccountInfo({
    required this.id,
    required this.displayName,
    required this.isPremium,
    this.premiumExpiresAt,
    required this.deviceCount,
    required this.maxDevices,
    required this.createdAt,
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

  ServerData({
    required this.id, required this.name, required this.country,
    required this.countryCode, required this.city,
    required this.latitude, required this.longitude,
    required this.tier, required this.isActive,
    required this.speedMbps, required this.pingMs,
  });

  factory ServerData.fromJson(Map<String, dynamic> json) => ServerData(
        id: json['id'] ?? '',
        name: json['name'] ?? '',
        country: json['country'] ?? '',
        countryCode: json['country_code'] ?? '',
        city: json['city'] ?? '',
        latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
        longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
        tier: json['tier'] ?? 'free',
        isActive: json['is_active'] ?? true,
        speedMbps: json['speed_mbps'] ?? 100,
        pingMs: json['ping_ms'] ?? 20,
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

  PremiumStatus({required this.isPremium, this.expiresAt, this.remainingSeconds});

  factory PremiumStatus.fromJson(Map<String, dynamic> json) => PremiumStatus(
        isPremium: json['is_premium'] ?? false,
        expiresAt: json['expires_at'] != null ? DateTime.tryParse(json['expires_at']) : null,
        remainingSeconds: (json['remaining_seconds'] as num?)?.toDouble(),
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
