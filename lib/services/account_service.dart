import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/vpn_models.dart';
import 'api_service.dart';
import 'device_fingerprint.dart';

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
  bool get onTrial => _account?.onTrial ?? false;
  DateTime? get entitlementEndsAt =>
      _account?.premiumExpiry ?? _account?.trialEndsAt;
  bool get pinSetupComplete => _pinSetupComplete;
  bool get isAdmin => _account?.isAdmin ?? false;
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
          isTrial: info.isTrial,
          trialEndsAt: info.trialEndsAt,
          isAdmin: info.isAdmin,
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

  /// Register with a user-set PIN. No email (privacy) — Paystack asks at checkout only.
  Future<bool> createAccount(String pin) async {
    if (pin.length != 4 || !RegExp(r'^\d{4}$').hasMatch(pin)) {
      _error = 'PIN must be exactly 4 digits';
      notifyListeners();
      return false;
    }

    final platform = _getPlatformName();

    try {
      final fp = await DeviceFingerprint.get();
      final result = await _api.register(
        pin: pin,
        deviceName: platform,
        platform: platform,
        fingerprint: fp,
      );
      _account = UserAccount(
        accountId: result.accountId,
        tier: result.isPremium ? SubscriptionTier.premium : SubscriptionTier.free,
        premiumExpiry: result.trialEndsAt,
        deviceIds: [_api.deviceId ?? 'unknown'],
        createdAt: DateTime.now(),
        isTrial: result.isTrial,
        trialEndsAt: result.trialEndsAt,
      );
      _error = null;
    } on ApiException catch (e) {
      if (e.statusCode == 409) {
        _error = 'This device already has an account. Please login instead.';
      } else if (e.statusCode == 429) {
        _error = 'Too many attempts. Please wait a few minutes and try again.';
      } else {
        _error = e.message.isNotEmpty ? e.message : 'Failed to create account.';
      }
      notifyListeners();
      return false;
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
      final fp = await DeviceFingerprint.get();
      final result = await _api.login(
        accountId: accountId.trim().toUpperCase(),
        pin: pin,
        deviceName: platform,
        platform: platform,
        fingerprint: fp,
      );
      _account = UserAccount(
        accountId: result.accountId,
        tier: result.isPremium ? SubscriptionTier.premium : SubscriptionTier.free,
        premiumExpiry: result.trialEndsAt,
        deviceIds: [_api.deviceId ?? 'unknown'],
        createdAt: DateTime.now(),
        isTrial: result.isTrial,
        trialEndsAt: result.trialEndsAt,
        isAdmin: result.isAdmin,
      );
      _error = null;
      final prefs = await SharedPreferences.getInstance();
      await _saveAccountLocal(prefs);
      _pinSetupComplete = true;
      await prefs.setBool(_pinSetupKey, true);
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      if (e.statusCode == 429) {
        _error = 'Too many attempts. Please wait a few minutes and try again.';
      } else if (e.statusCode == 401) {
        _error = 'Invalid Account ID or PIN';
      } else {
        _error = 'Login failed. Check your connection.';
      }
      notifyListeners();
      return false;
    } catch (e) {
      _error = 'Login failed. Check your connection.';
      notifyListeners();
      return false;
    }
  }

  /// Sync premium status with backend.
  Future<void> syncPremiumStatus() async {
    if (!_api.isAuthenticated || _account == null) return;
    try {
      final status = await _api.getPremiumStatus();
      _account = _account!.copyWith(
        tier: status.isPremium ? SubscriptionTier.premium : SubscriptionTier.free,
        premiumExpiry: status.expiresAt,
        isTrial: status.isTrial,
        trialEndsAt: status.trialEndsAt,
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

  /// Local entitlement check (no network) — true if trial/paid already ended.
  bool entitlementExpiredLocally() {
    final end = entitlementEndsAt;
    if (end == null) return false;
    return !DateTime.now().isBefore(end);
  }

  /// External callers (app clock) can force a notify so watchers re-check.
  void recheckEntitlement() => notifyListeners();

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
    bool? isTrial,
    DateTime? trialEndsAt,
    bool? isAdmin,
  }) {
    return UserAccount(
      accountId: accountId ?? this.accountId,
      tier: tier ?? this.tier,
      premiumExpiry: premiumExpiry ?? this.premiumExpiry,
      deviceIds: deviceIds ?? this.deviceIds,
      createdAt: createdAt ?? this.createdAt,
      deviceCount: deviceCount ?? this.deviceCount,
      isTrial: isTrial ?? this.isTrial,
      trialEndsAt: trialEndsAt ?? this.trialEndsAt,
      isAdmin: isAdmin ?? this.isAdmin,
    );
  }
}
