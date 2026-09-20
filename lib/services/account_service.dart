import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/vpn_models.dart';
import 'api_service.dart';

class AccountService extends ChangeNotifier {
  static const String _accountKey = 'user_account';
  static const String _pinSetupKey = 'pin_setup_complete';

  final ApiService _api;

  UserAccount? _account;
  bool _isInitialized = false;
  bool _pinSetupComplete = false;
  String? _error;

  UserAccount? get account => _account;
  bool get isInitialized => _isInitialized;
  bool get hasAccount => _account != null;
  bool get isPremiumActive => _account?.isPremiumActive ?? false;
  bool get pinSetupComplete => _pinSetupComplete;
  String? get error => _error;

  AccountService({ApiService? api}) : _api = api ?? ApiService();
  ApiService get api => _api;

  Future<void> init() async {
    await _api.init();

    final prefs = await SharedPreferences.getInstance();
    _pinSetupComplete = prefs.getBool(_pinSetupKey) ?? false;

    // If we have a stored JWT, try to fetch account from backend
    if (_api.isAuthenticated) {
      try {
        final info = await _api.getAccountInfo();
        _account = UserAccount(
          accountId: info.id,
          tier: info.isPremium ? SubscriptionTier.premium : SubscriptionTier.free,
          premiumExpiry: info.premiumExpiresAt,
          deviceCount: info.deviceCount,
          createdAt: info.createdAt,
        );
        await _saveAccountLocal(prefs);
        _error = null;
      } catch (e) {
        // JWT is invalid (e.g. backend restarted with new secret) — clear everything
        await _api.clearAuth();
        _account = null;
        _pinSetupComplete = false;
        await prefs.remove(_accountKey);
        await prefs.remove(_pinSetupKey);
      }
    } else {
      await _loadLocalAccount(prefs);
    }

    _isInitialized = true;
    notifyListeners();
  }

  Future<void> _loadLocalAccount(SharedPreferences prefs) async {
    final accountJson = prefs.getString(_accountKey);
    if (accountJson != null && accountJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(accountJson);
        if (decoded is Map<String, dynamic>) {
          _account = UserAccount.fromJson(decoded);
        }
      } catch (e) {
        await prefs.remove(_accountKey);
      }
    }
  }

  /// Register with a user-set PIN. No default PIN.
  Future<bool> createAccount(String pin) async {
    if (pin.length != 4 || !RegExp(r'^\d{4}$').hasMatch(pin)) {
      _error = 'PIN must be exactly 4 digits';
      notifyListeners();
      return false;
    }

    final platform = _getPlatformName();

    try {
      final result = await _api.register(
        pin: pin,
        deviceName: platform,
        platform: platform,
      );
      _account = UserAccount(
        accountId: result.accountId,
        tier: result.isPremium ? SubscriptionTier.premium : SubscriptionTier.free,
        deviceIds: [_api.deviceId ?? 'unknown'],
        createdAt: DateTime.now(),
      );
      _error = null;
    } catch (e) {
      _error = 'Failed to create account. Check your connection.';
      notifyListeners();
      return false;
    }

    final prefs = await SharedPreferences.getInstance();
    await _saveAccountLocal(prefs);
    _pinSetupComplete = true;
    await prefs.setBool(_pinSetupKey, true);
    notifyListeners();
    return true;
  }

  /// Login with account ID + PIN.
  Future<bool> loginWithPin(String accountId, String pin) async {
    final platform = _getPlatformName();
    try {
      final result = await _api.login(
        accountId: accountId,
        pin: pin,
        deviceName: platform,
        platform: platform,
      );
      _account = UserAccount(
        accountId: result.accountId,
        tier: result.isPremium ? SubscriptionTier.premium : SubscriptionTier.free,
        deviceIds: [_api.deviceId ?? 'unknown'],
        createdAt: DateTime.now(),
      );
      _error = null;
      final prefs = await SharedPreferences.getInstance();
      await _saveAccountLocal(prefs);
      _pinSetupComplete = true;
      await prefs.setBool(_pinSetupKey, true);
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Invalid credentials';
      notifyListeners();
      return false;
    }
  }

  /// Upgrade to premium — ONLY via backend. No local fallback.
  Future<bool> upgradeToPremium(int days) async {
    if (_account == null) return false;

    try {
      final planId = _planIdForDays(days);
      final result = await _api.purchasePremium(planId: planId);
      if (result.success) {
        _account = _account!.copyWith(
          tier: SubscriptionTier.premium,
          premiumExpiry: result.expiresAt,
        );
        _error = null;
        await _saveAccountLocal(await SharedPreferences.getInstance());
        notifyListeners();
        return true;
      }
      _error = result.message;
    } catch (e) {
      _error = 'Purchase failed. Please check your connection.';
    }
    notifyListeners();
    return false;
  }

  String _planIdForDays(int days) {
    if (days <= 30) return 'basic_30';
    if (days <= 60) return 'standard_60';
    return 'premium_90';
  }

  /// Sync premium status with backend.
  Future<void> syncPremiumStatus() async {
    if (!_api.isAuthenticated || _account == null) return;
    try {
      final status = await _api.getPremiumStatus();
      _account = _account!.copyWith(
        tier: status.isPremium ? SubscriptionTier.premium : SubscriptionTier.free,
        premiumExpiry: status.expiresAt,
      );
      await _saveAccountLocal(await SharedPreferences.getInstance());
      notifyListeners();
    } catch (e) {
      // Silent — will retry on next sync
    }
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accountKey);
    await prefs.remove(_pinSetupKey);
    await _api.clearAuth();
    _account = null;
    _pinSetupComplete = false;
    notifyListeners();
  }

  Future<void> _saveAccountLocal(SharedPreferences prefs) async {
    if (_account == null) return;
    await prefs.setString(_accountKey, jsonEncode(_account!.toJson()));
  }

  String _getPlatformName() {
    if (kIsWeb) return 'web';
    if (defaultTargetPlatform == TargetPlatform.android) return 'android';
    if (defaultTargetPlatform == TargetPlatform.iOS) return 'ios';
    if (defaultTargetPlatform == TargetPlatform.linux) return 'linux';
    if (defaultTargetPlatform == TargetPlatform.windows) return 'windows';
    if (defaultTargetPlatform == TargetPlatform.macOS) return 'macos';
    return 'unknown';
  }
}

extension UserAccountCopyWith on UserAccount {
  UserAccount copyWith({
    String? accountId,
    SubscriptionTier? tier,
    DateTime? premiumExpiry,
    List<String>? deviceIds,
    DateTime? createdAt,
    int? deviceCount,
  }) {
    return UserAccount(
      accountId: accountId ?? this.accountId,
      tier: tier ?? this.tier,
      premiumExpiry: premiumExpiry ?? this.premiumExpiry,
      deviceIds: deviceIds ?? this.deviceIds,
      createdAt: createdAt ?? this.createdAt,
      deviceCount: deviceCount ?? this.deviceCount,
    );
  }
}
