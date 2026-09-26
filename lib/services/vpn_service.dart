import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/vpn_models.dart';
import 'account_service.dart';
import 'api_service.dart';
import 'usque_service.dart';
import 'warp_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class VPNService extends ChangeNotifier {
  final WarpService _warp = WarpService();
  final UsqueService _usque = UsqueService();
  /// True when the active desktop tunnel is usque MASQUE (vs warp-cli).
  bool _usingUsque = false;

  VPNState _state = VPNState.disconnected;
  bool _restored = false;
  String? _egressIp;
  bool _egressChecking = false;

  /// Parse warp-cli status output to get the exact status word.
  static String _parseWarpStatus(String output) {
    for (final line in output.split('\n')) {
      final trimmed = line.trim().toLowerCase();
      if (trimmed.startsWith('status update:')) {
        return trimmed.replaceFirst('status update:', '').trim();
      }
    }
    return output.toLowerCase();
  }

  ServerConfig? _currentServer;
  ConnectionStats _stats = const ConnectionStats();
  Timer? _statsTimer;
  Timer? _durationTimer;
  Timer? _killSwitchMonitor;
  Timer? _entitlementTimer;
  Timer? _entitlementSyncTimer;
  Timer? _egressTimer;
  bool _entitlementCutting = false;
  bool _verifyInFlight = false;
  bool _restoreInFlight = false;

  // ── Server-authoritative entitlement ──────────────────────────────
  // Device wall-clock is NOT trusted (users can set date/time).
  // Backend returns remaining_seconds; we count it down with a monotonic
  // Stopwatch so rolling the clock back cannot extend access.
  // Offline after create: no server grant → no tunnel ("we don't care").
  double? _verifiedRemainingSec;
  final Stopwatch _sinceServerVerify = Stopwatch()..start();
  bool _sessionHadServerEntitlement = false;
  static const Duration _maxOfflineGrace = Duration(seconds: 90);

  DateTime? _connectedAt;
  DateTime? _lastConnectTime;
  List<ServerConfig> _servers = [];
  bool _killSwitch = true;
  bool _autoConnect = false;
  String? _error;
  AccountService? _accountService;
  bool _serversLoaded = false;
  bool _autoConnectDone = false;
  bool _isConnecting = false;

  VPNState get state => _state;
  ServerConfig? get currentServer => _currentServer;
  ConnectionStats get stats => _stats;
  List<ServerConfig> get allServers => _servers;
  String? get egressIp => _egressIp;
  bool get egressChecking => _egressChecking;

  /// All 13 locations require an active trial or paid plan.
  List<ServerConfig> get availableServers {
    if (_accountService?.isPremiumActive ?? false) return _servers;
    return const [];
  }

  bool get killSwitch => _killSwitch;
  bool get autoConnect => _autoConnect;
  String? get error => _error;
  bool get isConnected => _state == VPNState.connected;
  bool get isDisconnected => _state == VPNState.disconnected;
  bool get isConnecting => _state == VPNState.connecting;
  bool get isDisconnecting => _state == VPNState.disconnecting;
  bool get isPremium => _accountService?.isPremiumActive ?? false;

  VPNService() {
    _initServersFallback();
    _currentServer = _servers.isNotEmpty ? _servers.first : null;
    _loadSettings();
    // Adopt native tunnel state after the channel is up (app cold start).
    Future.delayed(const Duration(milliseconds: 400), () {
      _takeTunnelOwnership();
      restoreFromNative();
    });
  }

  /// Sync UI with the native VpnService / Go engine after process restart.
  /// Without this, swipe-away → reopen always shows DISCONNECTED even if
  /// the sticky foreground service is still masking traffic.
  /// Adopts ONLY with a fresh server verdict — an orphan tunnel without
  /// entitlement is torn down (fail closed, never adopt-then-check).
  Future<void> restoreFromNative() async {
    if (_restored || _restoreInFlight || kIsWeb) return;
    // Wait for the account/token before deciding anything — a verify or a
    // tunnel kill at this point would run against a half-loaded session.
    // updateAccount() retries once the session is ready.
    if (_accountService == null ||
        !(_accountService?.api.isAuthenticated ?? false)) {
      return;
    }
    if (!(Platform.isAndroid || Platform.isIOS)) {
      // Desktop: engine/daemon may have outlived the Flutter engine.
      if (Platform.isWindows && _usque.isConnected()) {
        final ok = await _verifyEntitlementWithServer();
        if (ok && _serverEntitlementLive()) {
          _adoptConnected();
        } else {
          try {
            await _usque.disconnect().timeout(const Duration(seconds: 3));
          } catch (_) {}
        }
      } else if (Platform.isLinux && await _warpCliTunnelUp()) {
        final ok = await _verifyEntitlementWithServer();
        if (ok && _serverEntitlementLive()) {
          _adoptConnected();
        } else {
          try {
            await Process.run('warp-cli', ['--accept-tos', 'disconnect'])
                .timeout(const Duration(seconds: 5));
          } catch (_) {}
        }
      }
      _restored = true;
      return;
    }
    _restoreInFlight = true;
    try {
      final up = await _warp.hasRunningTunnel().timeout(
            const Duration(seconds: 3),
            onTimeout: () => false,
          );
      if (up) {
        final ok = await _verifyEntitlementWithServer();
        if (ok && _serverEntitlementLive()) {
          _adoptConnected();
        } else {
          // Sticky tunnel is up but not entitled (expired / logged out /
          // offline cold start) — kill it. No unverified traffic, ever.
          try {
            await _warp.disconnect().timeout(const Duration(seconds: 4));
          } catch (_) {}
        }
        _restored = true;
        return;
      }
      // Tunnel is down. If we (or the service) thought we were up, treat as
      // a drop — kill-switch monitor will revive if still entitled.
      final wanted = await _warp.wasConnectedPreviously().timeout(
            const Duration(seconds: 2),
            onTimeout: () => false,
          );
      _restored = true;
      if (wanted && _state == VPNState.disconnected) {
        // Leave state disconnected; kick kill-switch so a live entitlement
        // brings the tunnel back without the user tapping Connect.
        _startKillSwitchMonitor();
        // One immediate revive attempt (kill-switch waits for isConnected).
        unawaited(_tryReviveAfterDrop());
      }
    } catch (_) {
      _restored = true;
    } finally {
      _restoreInFlight = false;
    }
  }

  void _adoptConnected() {
    _state = VPNState.connected;
    _connectedAt ??= DateTime.now();
    _sessionHadServerEntitlement = true;
    _startTimers();
    _startKillSwitchMonitor();
    _startEntitlementWatch();
    unawaited(_refreshEgressIp());
    notifyListeners();
  }

  Future<void> _tryReviveAfterDrop() async {
    if (_isConnecting || isConnected) return;
    if (_accountService == null || !_accountService!.hasAccount) return;
    if (!_killSwitch && !_autoConnect) return;
    final ok = await _verifyEntitlementWithServer();
    if (!ok || !_serverEntitlementLive()) return;
    if (_isConnecting || isConnected) return;
    await connect();
  }

  void updateAccount(AccountService accountService) {
    _accountService = accountService;
    // First time we have an account after cold start — finish native restore.
    if (!_restored) {
      unawaited(restoreFromNative());
    }

    if (!_accountService!.hasAccount) {
      if (isConnected || isConnecting) {
        disconnect();
      }
      _autoConnectDone = false;
      _sessionHadServerEntitlement = false;
      _verifiedRemainingSec = null;
    } else if (isConnected || isConnecting) {
      unawaited(_enforceEntitlement(localOnly: true));
    }

    if (!_serversLoaded) {
      _fetchServersFromBackend();
    }
    if (_currentServer == null && _servers.isNotEmpty) {
      _currentServer = _servers.first;
    }
    notifyListeners();

    if (!_autoConnectDone && _autoConnect && _accountService!.hasAccount && isDisconnected) {
      _autoConnectDone = true;
      Future.delayed(const Duration(seconds: 1), () {
        if (isDisconnected && _autoConnect && _accountService?.hasAccount == true) {
          connect();
        }
      });
    }
  }

  /// Seconds left on the last successful server grant (monotonic countdown).
  double? get _serverRemainingNow {
    final base = _verifiedRemainingSec;
    if (base == null) return null;
    final used = _sinceServerVerify.elapsedMilliseconds / 1000.0;
    return base - used;
  }

  bool _serverEntitlementLive() {
    final left = _serverRemainingNow;
    if (left == null) return false;
    return left > 0;
  }

  /// Must stop the tunnel the instant trial or subscription ends.
  /// [localOnly] skips network (still uses server-granted remaining).
  Future<void> _enforceEntitlement({bool localOnly = false}) async {
    if (_entitlementCutting) return;
    if (!(isConnected || isConnecting)) return;

    final acc = _accountService?.account;
    if (acc == null) {
      await _cutTunnel('Signed out.');
      return;
    }

    // 1) Server-granted remaining hit zero (monotonic — clock-proof)
    if (_sessionHadServerEntitlement && !_serverEntitlementLive()) {
      await _cutTunnel('Trial or subscription ended. Disconnected.');
      return;
    }

    // 2) Device clock jumped past server absolute end — only cuts earlier
    final end = acc.premiumExpiry ?? acc.trialEndsAt;
    final clockPastEnd = end != null && !DateTime.now().isBefore(end);
    if (_sessionHadServerEntitlement && clockPastEnd && !_serverEntitlementLive()) {
      await _cutTunnel('Trial or subscription ended. Disconnected.');
      return;
    }

    if (localOnly) return;

    // 3) Server truth (required — device clock cannot authorize access)
    final ok = await _verifyEntitlementWithServer();
    if (!ok) {
      if (_sessionHadServerEntitlement &&
          _sinceServerVerify.elapsed > _maxOfflineGrace) {
        await _cutTunnel('Could not verify subscription. Disconnected.');
      }
      return;
    }
    if (!_serverEntitlementLive()) {
      await _cutTunnel('Trial or subscription ended. Disconnected.');
    }
  }

  /// Ask backend for trial/paid remaining. Resets monotonic grant on success.
  Future<bool> _verifyEntitlementWithServer() async {
    if (_verifyInFlight) return _serverEntitlementLive();
    if (!(_accountService?.api.isAuthenticated ?? false)) return false;
    _verifyInFlight = true;
    try {
      final status = await _accountService!.api
          .getPremiumStatus()
          .timeout(const Duration(seconds: 8));
      // Keep AccountService tier in sync with backend
      await _accountService!.syncPremiumStatus();
      if (status.isPremium && (status.remainingSeconds ?? 0) > 0) {
        _verifiedRemainingSec = status.remainingSeconds;
        _sinceServerVerify
          ..reset()
          ..start();
        _sessionHadServerEntitlement = true;
        return true;
      }
      _verifiedRemainingSec = 0;
      _sinceServerVerify.reset();
      return false;
    } on ApiException catch (e) {
      final code = e.statusCode;
      if (code == 401 || code == 402 || code == 403) {
        // Definitive server denial (bad token / no entitlement) — fail
        // closed NOW. Never grant the offline-grace window on an answer
        // that says "no": that was a free tunnel for up to 90s per check.
        _verifiedRemainingSec = 0;
        _sinceServerVerify.reset();
        return false;
      }
      // 429 / 5xx / unreachable host → last grant only within grace.
      return _serverEntitlementLive() &&
          _sinceServerVerify.elapsed < _maxOfflineGrace;
    } catch (_) {
      // Network fail: keep last grant only within grace window
      return _serverEntitlementLive() &&
          _sinceServerVerify.elapsed < _maxOfflineGrace;
    } finally {
      _verifyInFlight = false;
    }
  }

  Future<void> _cutTunnel(String reason) async {
    if (_entitlementCutting) return;
    if (!(isConnected || isConnecting || _state == VPNState.error)) return;
    _entitlementCutting = true;
    try {
      _error = reason;
      _stopKillSwitchMonitor();
      _stopEntitlementWatch();
      await disconnect();
      _error = reason;
      notifyListeners();
    } finally {
      _entitlementCutting = false;
    }
  }

  void _startEntitlementWatch() {
    _stopEntitlementWatch();
    // Fast local tick: server-granted remaining countdown (not device clock)
    _entitlementTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      unawaited(_enforceEntitlement(localOnly: true));
    });
    // Full server verification while tunnel is up
    _entitlementSyncTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(_enforceEntitlement(localOnly: false));
    });
    Timer(const Duration(seconds: 3), () {
      if (isConnected) unawaited(_enforceEntitlement(localOnly: false));
    });
  }

  void _stopEntitlementWatch() {
    _entitlementTimer?.cancel();
    _entitlementSyncTimer?.cancel();
    _entitlementTimer = null;
    _entitlementSyncTimer = null;
  }

  Future<void> _fetchServersFromBackend() async {
    try {
      final api = _accountService?.api;
      if (api == null) return;

      List<ServerData> serverData;
      if (api.isAuthenticated) {
        serverData = await api.getAvailableServers();
      } else {
        serverData = await api.getAllServersPublic();
      }

      if (serverData.isNotEmpty) {
        _servers = serverData.map((sd) => ServerConfig(
          id: sd.id,
          name: sd.name,
          country: sd.country,
          countryCode: sd.countryCode,
          endpoint: 'engage.cloudflareclient.com',
          port: 2408,
          publicKey: 'bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=',
          ipAddress: (sd.ipAddress != null && sd.ipAddress!.isNotEmpty)
              ? '${sd.ipAddress}/32'
              : '162.159.193.1/32',
          dns: '1.1.1.1',
          // Product rule: every location is paid (trial unlocks all).
          isPremium: true,
          sortOrder: 0,
          latitude: sd.latitude,
          longitude: sd.longitude,
        )).toList();
        _serversLoaded = true;

        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.get('selectedServer');
        final serverId = raw is String ? raw : '';
        if (serverId.isNotEmpty) {
          final match = _servers.where((s) => s.id == serverId);
          if (match.isNotEmpty) {
            _currentServer = match.first;
          }
        } else if (_servers.isNotEmpty) {
          _currentServer = _servers.first;
        }
        notifyListeners();
      }
    } catch (e) {
      // Silent — will use fallback servers
    }
  }

  void _initServersFallback() {
    ServerConfig loc(
      String id,
      String name,
      String country,
      String cc,
      String ip,
      int order,
      double lat,
      double lng,
    ) =>
        ServerConfig(
          id: id,
          name: name,
          country: country,
          countryCode: cc,
          endpoint: 'engage.cloudflareclient.com',
          port: 2408,
          publicKey: 'bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=',
          ipAddress: '$ip/32',
          dns: '1.1.1.1',
          isPremium: true,
          sortOrder: order,
          latitude: lat,
          longitude: lng,
        );

    // All 13 locations — paid plan / active trial required for all.
    _servers = [
      loc('us-east', 'US East', 'United States', 'US', '162.159.192.1', 0, 40.7128, -74.0060),
      loc('us-west', 'US West', 'United States', 'US', '162.159.193.1', 1, 37.7749, -122.4194),
      loc('uk-london', 'UK London', 'United Kingdom', 'GB', '162.159.194.1', 2, 51.5074, -0.1278),
      loc('de-frankfurt', 'Germany Frankfurt', 'Germany', 'DE', '162.159.195.1', 3, 50.1109, 8.6821),
      loc('jp-tokyo', 'Japan Tokyo', 'Japan', 'JP', '162.159.196.1', 4, 35.6762, 139.6503),
      loc('sg-singapore', 'Singapore', 'Singapore', 'SG', '162.159.197.1', 5, 1.3521, 103.8198),
      loc('au-sydney', 'Australia Sydney', 'Australia', 'AU', '162.159.198.1', 6, -33.8688, 151.2093),
      loc('br-saopaulo', 'Brazil Sao Paulo', 'Brazil', 'BR', '162.159.199.1', 7, -23.5505, -46.6333),
      loc('in-mumbai', 'India Mumbai', 'India', 'IN', '162.159.200.1', 8, 19.0760, 72.8777),
      loc('ca-toronto', 'Canada Toronto', 'Canada', 'CA', '162.159.201.1', 9, 43.6532, -79.3832),
      loc('nl-amsterdam', 'Netherlands Amsterdam', 'Netherlands', 'NL', '162.159.202.1', 10, 52.3676, 4.9041),
      loc('kr-seoul', 'South Korea Seoul', 'South Korea', 'KR', '162.159.203.1', 11, 37.5665, 126.9780),
      loc('fr-paris', 'France Paris', 'France', 'FR', '162.159.204.1', 12, 48.8566, 2.3522),
    ];
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _killSwitch = prefs.getBool('killSwitch') ?? true;
      // Default ON: app launches (incl. autostart after reboot) → connects
      // when entitled, so "open the app and it just works".
      _autoConnect = prefs.getBool('autoConnect') ?? true;
      final raw = prefs.get('selectedServer');
      final serverId = raw is String ? raw : '';
      if (serverId.isNotEmpty) {
        try {
          final match = _servers.where((s) => s.id == serverId);
          if (match.isNotEmpty) {
            _currentServer = match.first;
          }
        } catch (_) {}
      }
      notifyListeners();
    } catch (e) {
      // Settings load error — use defaults
    }
  }

  Future<void> connect() async {
    if (_state == VPNState.connecting || _state == VPNState.connected || _isConnecting) return;

    if (_accountService == null || !_accountService!.hasAccount) {
      _state = VPNState.error;
      _error = 'Create an account to connect.';
      notifyListeners();
      return;
    }

    // Backend is the only source of truth — device clock cannot grant access.
    _state = VPNState.connecting;
    _error = null;
    _isConnecting = true;
    notifyListeners();

    try {
      final verified = await _verifyEntitlementWithServer();
      if (!verified || !_serverEntitlementLive()) {
        _state = VPNState.error;
        _error = 'Trial or subscription required. Subscribe to connect.';
        notifyListeners();
        return;
      }

      if (kIsWeb) throw UnsupportedError('VPN not supported on web');

      if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
        await _connectDesktop();
      } else if (Platform.isAndroid || Platform.isIOS) {
        await _connectMobile();
      }

      _state = VPNState.connected;
      _connectedAt = DateTime.now();
      _stats = const ConnectionStats();
      _sessionHadServerEntitlement = _serverEntitlementLive();
      _startTimers();
      _startKillSwitchMonitor();
      _startEntitlementWatch();
      unawaited(_enforceEntitlement(localOnly: false));
      unawaited(_refreshEgressIp());
      notifyListeners();
    } catch (e) {
      _state = VPNState.error;
      _error = e.toString();
      notifyListeners();
    } finally {
      _isConnecting = false;
    }
  }

  Future<void> disconnect() async {
    if (_state == VPNState.disconnecting || _state == VPNState.disconnected) return;

    if (_state == VPNState.error) {
      _state = VPNState.disconnected;
      _error = null;
      _stopEntitlementWatch();
      notifyListeners();
      return;
    }

    _state = VPNState.disconnecting;
    notifyListeners();

    try {
      if (!kIsWeb) {
        if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
          await _disconnectDesktop();
        } else if (Platform.isAndroid || Platform.isIOS) {
          await _disconnectMobile();
        }
      }

      _stopTimers();
      _stopKillSwitchMonitor();
      _stopEntitlementWatch();
      _sessionHadServerEntitlement = false;
      _state = VPNState.disconnected;
      _connectedAt = null;
      _stats = const ConnectionStats();
      _egressIp = null;
      notifyListeners();
    } catch (e) {
      _state = VPNState.error;
      _error = e.toString();
      notifyListeners();
    }
  }

  /// Switch server — requires live server-verified entitlement.
  Future<void> switchServer(ServerConfig server) async {
    if (!isPremium) {
      _error = 'Trial or subscription required for all locations.';
      notifyListeners();
      return;
    }

    _currentServer = server;
    _saveSelectedServer();
    notifyListeners();

    if (isConnected || isConnecting) {
      _stopKillSwitchMonitor();
      _stopTimers();
      await disconnect();
      await Future.delayed(const Duration(milliseconds: 500));
    }
    await connect();
  }

  Future<void> _connectDesktop() async {
    // Windows: MASQUE only (bundled usque.exe) — never fall back to warp-cli.
    // Linux/macOS: warp-cli only — usque needs root/CAP_NET_ADMIN for TUN and
    // is not bundled; a present-but-unusable usque binary must not break
    // the warp-cli path.
    if (Platform.isWindows) {
      if (!_usque.binaryExists) {
        throw Exception(
          'usque.exe not found next to securedview.exe — reinstall from the release zip',
        );
      }
      await _usque.connect();
      _usingUsque = true;
      return;
    }
    await _connectWarpCli();
  }

  /// Linux: Cloudflare's warp-taskbar tray fights us for warp-svc and shows a
  /// second IP/cloud window. SecuredView must be the only VPN UI — stop the
  /// tray and mask its user unit so it cannot come back after relogin.
  Future<void> _takeTunnelOwnership() async {
    if (kIsWeb || !Platform.isLinux) return;
    try {
      await Process.run('systemctl', ['--user', 'mask', 'warp-taskbar.service'])
          .timeout(const Duration(seconds: 5));
      await Process.run('systemctl', ['--user', 'stop', 'warp-taskbar.service'])
          .timeout(const Duration(seconds: 5));
      await Process.run('pkill', ['-x', 'warp-taskbar'])
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // Best effort — missing user session bus is not fatal.
    }
  }

  /// True when warp-cli reports a tunnel (and the daemon answers).
  Future<bool> _warpCliTunnelUp() async {
    if (!_warpCliPresent()) return false;
    try {
      final r = await Process.run('warp-cli', ['--accept-tos', 'status'])
          .timeout(const Duration(seconds: 4));
      final raw = r.stdout.toString();
      final low = '$raw ${r.stderr}'.toLowerCase();
      if (low.contains('unable to connect') || low.contains('daemon')) {
        return false; // warp-svc is down — nothing is actually tunnelling
      }
      return _parseWarpStatus(raw) != 'disconnected';
    } catch (_) {
      return false;
    }
  }

  /// warp-svc dead → every warp-cli call just fails with a confusing timeout.
  /// Try to start it via polkit (GUI password prompt), else return an
  /// actionable error message for the UI.
  Future<String?> _ensureWarpDaemon() async {
    Future<bool> up() async {
      try {
        final r = await Process.run('warp-cli', ['--accept-tos', 'status'])
            .timeout(const Duration(seconds: 5));
        final low = '${r.stdout} ${r.stderr}'.toLowerCase();
        if (low.contains('unable to connect') || low.contains('daemon')) {
          return false;
        }
        return r.exitCode == 0;
      } catch (_) {
        return false;
      }
    }

    if (await up()) return null;
    try {
      await Process.run('pkexec', ['systemctl', 'start', 'warp-svc'])
          .timeout(const Duration(seconds: 30));
    } catch (_) {}
    await Future.delayed(const Duration(seconds: 2));
    if (await up()) return null;
    return 'The Cloudflare service (warp-svc) is not running. '
        'Run: sudo systemctl start warp-svc — then Connect again.';
  }

  Future<void> _connectWarpCli() async {
    try {
      _usingUsque = false;
      await _takeTunnelOwnership();
      final daemonErr = await _ensureWarpDaemon();
      if (daemonErr != null) throw Exception(daemonErr);
      await Process.run('warp-cli', ['--accept-tos', 'registration', 'new']);
      await Future.delayed(const Duration(seconds: 1));
      await Process.run('warp-cli', ['--accept-tos', 'mode', 'warp']);
      await Future.delayed(const Duration(milliseconds: 500));

      final currentStatus = await Process.run('warp-cli', ['--accept-tos', 'status']);
      final currentOutput = _parseWarpStatus(currentStatus.stdout.toString());
      if (currentOutput == 'connected') {
        _lastConnectTime = DateTime.now();
        return;
      }

      await Process.run('warp-cli', ['--accept-tos', 'connect']);

      for (int i = 0; i < 40; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
        final statusResult = await Process.run('warp-cli', ['--accept-tos', 'status']);
        final status = _parseWarpStatus(statusResult.stdout.toString());
        if (status == 'connected') {
          _lastConnectTime = DateTime.now();
          return;
        }
      }
      throw Exception('Connection timed out');
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      throw Exception(msg.startsWith('Desktop') ? msg : 'Desktop connection failed: $msg');
    }
  }

  Future<void> _disconnectDesktop() async {
    if (_usingUsque || _usque.isRunning) {
      await _usque.disconnect();
      _usingUsque = false;
      if (Platform.isWindows || !_warpCliPresent()) return;
    }
    await Process.run('warp-cli', ['--accept-tos', 'disconnect']);
    for (int i = 0; i < 10; i++) {
      await Future.delayed(const Duration(milliseconds: 500));
      final result = await Process.run('warp-cli', ['--accept-tos', 'status']);
      final status = _parseWarpStatus(result.stdout.toString());
      if (status != 'connected' && status != 'connecting') break;
    }
  }

  bool _warpCliPresent() {
    try {
      final check = Process.runSync(
        Platform.isWindows ? 'where' : 'which',
        ['warp-cli'],
      );
      return check.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Monotonic grant budget (ms) for the native Android watchdog — the
  /// sticky service must cut the tunnel itself when the UI process is dead
  /// and the trial/plan runs out.
  int? _grantBudgetMs() {
    final left = _serverRemainingNow;
    if (left == null || left <= 0) return null;
    return (left * 1000).round();
  }

  Future<void> _connectMobile() async {
    try {
      await _warp.connect(grantBudgetMs: _grantBudgetMs());
      _lastConnectTime = DateTime.now();
    } catch (e) {
      throw Exception('Mobile connection failed: $e');
    }
  }

  Future<void> _disconnectMobile() async {
    try {
      await _warp.disconnect();
    } catch (e) {
      throw Exception('Mobile disconnect failed: $e');
    }
  }

  /// Kill switch: monitor tunnel; revive only if still entitled.
  void _startKillSwitchMonitor() {
    _stopKillSwitchMonitor();

    if (!kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
      if (Platform.isWindows) {
        if (!_usque.binaryExists) {
          debugPrint('usque.exe not found — kill switch disabled');
          return;
        }
      } else {
        final hasUsque = _usque.binaryExists;
        final hasWarp = _warpCliPresent();
        if (!hasUsque && !hasWarp) {
          debugPrint('no desktop tunnel backend — kill switch disabled');
          return;
        }
      }
    }

    _killSwitchMonitor = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (kIsWeb) return;

      // UI thinks connected — verify native still is; revive/cut as needed.
      if (isConnected) {
        // Entitlement cut → never keep or revive the tunnel
        if (_sessionHadServerEntitlement && !_serverEntitlementLive()) {
          await _cutTunnel('Trial or subscription ended. Disconnected.');
          return;
        }
        if (!(_accountService?.isPremiumActive ?? false)) {
          await _cutTunnel('Trial or subscription required. Disconnected.');
          return;
        }

        if (_lastConnectTime != null) {
          final elapsed = DateTime.now().difference(_lastConnectTime!);
          if (elapsed < const Duration(seconds: 15)) return;
        }

        try {
          if (Platform.isAndroid || Platform.isIOS) {
            final up = await _warp.isConnected();
            if (!up && !_isConnecting) {
              if (_killSwitch) {
                final ok = await _verifyEntitlementWithServer();
                if (!ok || !_serverEntitlementLive()) {
                  await _cutTunnel('Trial or subscription ended. Disconnected.');
                  return;
                }
                _state = VPNState.connecting;
                notifyListeners();
                try {
                  await _connectMobile();
                  _state = VPNState.connected;
                  _connectedAt = DateTime.now();
                  _stats = const ConnectionStats();
                  unawaited(_refreshEgressIp());
                  notifyListeners();
                } catch (_) {
                  _state = VPNState.disconnected;
                  _error = 'Connection lost. Kill switch active.';
                  _stopTimers();
                  notifyListeners();
                }
              } else {
                _state = VPNState.disconnected;
                _connectedAt = null;
                _stats = const ConnectionStats();
                _stopTimers();
                notifyListeners();
              }
            }
            return;
          }
          if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
            bool tunnelUp;
            if (_usingUsque) {
              tunnelUp = _usque.isConnected();
            } else {
              if (!_warpCliPresent()) return;
              final result = await Process.run('warp-cli', ['--accept-tos', 'status']);
              final raw = result.stdout.toString();
              final status = _parseWarpStatus(raw);
              // Daemon down prints an error, not "disconnected" — do not
              // mistake a dead warp-svc for a live tunnel.
              tunnelUp = status != 'disconnected' &&
                  !raw.toLowerCase().contains('unable to connect');
            }
            if (tunnelUp || _isConnecting) return;

            if (_killSwitch) {
              final ok = await _verifyEntitlementWithServer();
              if (!ok || !_serverEntitlementLive()) {
                await _cutTunnel('Trial or subscription ended. Disconnected.');
                return;
              }
              _state = VPNState.connecting;
              notifyListeners();
              try {
                await _connectDesktop();
                _state = VPNState.connected;
                _connectedAt = DateTime.now();
                _stats = const ConnectionStats();
                notifyListeners();
              } catch (_) {
                _state = VPNState.disconnected;
                _error = 'Connection lost. Kill switch active.';
                _stopTimers();
                notifyListeners();
              }
            } else {
              _state = VPNState.disconnected;
              _connectedAt = null;
              _stats = const ConnectionStats();
              _stopTimers();
              notifyListeners();
            }
          }
        } catch (_) {
          // Monitor error — ignore
        }
        return;
      }

      // UI is disconnected but we previously wanted a tunnel (process death /
      // swipe-away). Keep trying to revive while still entitled.
      if (!_killSwitch && !_autoConnect) return;
      if (_isConnecting || isDisconnecting) return;
      if (_accountService == null || !_accountService!.hasAccount) return;
      if (!(_accountService?.isPremiumActive ?? false)) return;
      // Don't fight an intentional disconnect: only revive shortly after a drop.
      // wasConnected flag is cleared on explicit disconnect via native STOP.
      try {
        final wanted = await _warp.wasConnectedPreviously();
        if (!wanted) return;
        final ok = await _verifyEntitlementWithServer();
        if (!ok || !_serverEntitlementLive()) return;
        if (_isConnecting || isConnected) return;
        _state = VPNState.connecting;
        _error = null;
        notifyListeners();
        try {
          if (Platform.isAndroid || Platform.isIOS) {
            await _connectMobile();
          } else {
            await _connectDesktop();
          }
          _state = VPNState.connected;
          _connectedAt = DateTime.now();
          _stats = const ConnectionStats();
          _startTimers();
          _startEntitlementWatch();
          unawaited(_refreshEgressIp());
          notifyListeners();
        } catch (_) {
          _state = VPNState.disconnected;
          _stopTimers();
          notifyListeners();
        }
      } catch (_) {}
    });
  }

  void _stopKillSwitchMonitor() {
    _killSwitchMonitor?.cancel();
    _killSwitchMonitor = null;
  }

  void _startTimers() {
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (_) => _updateStats());
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      // Re-check native tunnel every second while UI claims connected —
      // catches service death that the 5s kill-switch tick would miss.
      unawaited(_assertNativeStillUp());
      notifyListeners();
    });
    // Keep the displayed IP fresh while connected (stale-IP bug).
    _egressTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (isConnected) unawaited(_refreshEgressIp());
    });
  }

  Future<void> _assertNativeStillUp() async {
    if (!isConnected || kIsWeb || _isConnecting) return;
    if (!(Platform.isAndroid || Platform.isIOS)) return;
    // Grace period right after connect.
    if (_lastConnectTime != null &&
        DateTime.now().difference(_lastConnectTime!) < const Duration(seconds: 8)) {
      return;
    }
    try {
      final up = await _warp.hasRunningTunnel().timeout(
        const Duration(seconds: 2),
        onTimeout: () => true, // don't flap on a slow channel
      );
      if (!up && isConnected && !_isConnecting) {
        if (_killSwitch) {
          // Kill-switch monitor will revive; surface honest state first.
          _state = VPNState.disconnected;
          _connectedAt = null;
          _stats = const ConnectionStats();
          _egressIp = null;
          _stopTimers();
          notifyListeners();
          unawaited(_tryReviveAfterDrop());
        } else {
          _state = VPNState.disconnected;
          _connectedAt = null;
          _stats = const ConnectionStats();
          _egressIp = null;
          _stopTimers();
          _stopKillSwitchMonitor();
          _stopEntitlementWatch();
          _error = 'Connection lost.';
          notifyListeners();
        }
      }
    } catch (_) {}
  }

  /// Fetch the public egress IP through whatever path the device is using.
  /// Called after connect so the UI can prove masking (and catch leaks).
  Future<void> refreshEgressIp() => _refreshEgressIp();

  Future<void> _refreshEgressIp() async {
    if (_egressChecking) return;
    _egressChecking = true;
    notifyListeners();
    try {
      final trace =
          await fetchEgressTrace().timeout(const Duration(seconds: 8));
      _egressIp = trace.ip;
      // warp=off while we claim connected → system traffic is NOT masked.
      // warp-cli path only (usque MASQUE cannot be verified this way).
      if (isConnected && trace.warpOff == true && !_usingUsque) {
        final since = _connectedAt;
        if (since != null &&
            DateTime.now().difference(since) > const Duration(seconds: 10)) {
          // Treat as a drop: show honest state; kill-switch revives if
          // still entitled.
          _state = VPNState.disconnected;
          _connectedAt = null;
          _stats = const ConnectionStats();
          _stopTimers();
          notifyListeners();
          unawaited(_tryReviveAfterDrop());
        }
      }
      notifyListeners();
    } catch (_) {
      // Never show a stale IP — an old address while "connected" lies.
      if (_egressIp != null) {
        _egressIp = null;
      }
    } finally {
      _egressChecking = false;
      notifyListeners();
    }
  }

  /// Public IP as seen by a remote host (goes through the tunnel when up).
  static Future<String> fetchEgressIp() async =>
      (await fetchEgressTrace()).ip;

  /// Cloudflare trace: egress IP + whether Cloudflare sees us on WARP.
  static Future<EgressTrace> fetchEgressTrace() async {
    // Cloudflare trace is small, CN-reachable, and returns `ip=` + `warp=`.
    final client = http.Client();
    try {
      final resp = await client
          .get(Uri.parse('https://www.cloudflare.com/cdn-cgi/trace'))
          .timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200) {
        String? ip;
        bool? warpOff;
        for (final line in resp.body.split('\n')) {
          if (line.startsWith('ip=')) {
            final v = line.substring(3).trim();
            if (v.isNotEmpty) ip = v;
          } else if (line.startsWith('warp=')) {
            final v = line.substring(5).trim();
            if (v == 'off') {
              warpOff = true;
            } else if (v == 'on') {
              warpOff = false;
            }
          }
        }
        if (ip != null) return EgressTrace(ip: ip, warpOff: warpOff);
      }
    } finally {
      client.close();
    }
    // Fallback (no warp field available)
    final client2 = http.Client();
    try {
      final resp = await client2
          .get(Uri.parse('https://api.ipify.org?format=text'))
          .timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200 && resp.body.trim().isNotEmpty) {
        return EgressTrace(ip: resp.body.trim());
      }
    } finally {
      client2.close();
    }
    throw Exception('Could not determine egress IP');
  }

  /// App is exiting (desktop): the tunnel must not outlive us — nobody
  /// would enforce entitlement on an orphan. Mobile keeps the sticky
  /// service by design; restoreFromNative verifies-or-kills on relaunch.
  Future<void> shutdownTunnel() async {
    if (kIsWeb) return;
    if (Platform.isAndroid || Platform.isIOS) return;
    try {
      if (_usque.isRunning || _usingUsque) {
        await _usque.disconnect().timeout(const Duration(seconds: 2));
      }
      if (_warpCliPresent()) {
        await Process.run('warp-cli', ['--accept-tos', 'disconnect'])
            .timeout(const Duration(seconds: 3));
      }
    } catch (_) {}
  }

  void _stopTimers() {
    _statsTimer?.cancel();
    _durationTimer?.cancel();
    _egressTimer?.cancel();
    _statsTimer = null;
    _durationTimer = null;
    _egressTimer = null;
  }

  void _updateStats() {
    if (!isConnected) return;
    // Prefer real byte counters from the native engine when available.
    unawaited(_pullNativeStats());
    final connectedDuration = _connectedAt != null
        ? DateTime.now().difference(_connectedAt!)
        : Duration.zero;
    _stats = ConnectionStats(
      bytesSent: _stats.bytesSent,
      bytesReceived: _stats.bytesReceived,
      connectedDuration: connectedDuration,
    );
    notifyListeners();
  }

  Future<void> _pullNativeStats() async {
    if (!(Platform.isAndroid || Platform.isIOS)) return;
    try {
      final st = await _warp.status().timeout(const Duration(seconds: 1));
      if (st == null) return;
      final sent = (st['bytes_sent'] as num?)?.toInt();
      final recv = (st['bytes_recv'] as num?)?.toInt();
      if (sent != null && recv != null && (sent > 0 || recv > 0)) {
        _stats = ConnectionStats(
          bytesSent: sent,
          bytesReceived: recv,
          connectedDuration: _connectedAt != null
              ? DateTime.now().difference(_connectedAt!)
              : Duration.zero,
        );
      }
    } catch (_) {}
  }

  void selectServer(ServerConfig server) {
    // Server catalog is fully paid — no free locations to select.
    if (!(_accountService?.isPremiumActive ?? false)) {
      _error = 'Trial or subscription required for all locations.';
      notifyListeners();
      return;
    }
    _currentServer = server;
    _saveSelectedServer();
    notifyListeners();
  }

  void setKillSwitch(bool value) {
    _killSwitch = value;
    _saveSetting('killSwitch', value);
    // The liveness monitor keeps running either way — it detects drops and
    // reports honest state; only AUTO-REVIVE is gated on the toggle
    // (handled inside the monitor). Stopping it on "off" meant a dropped
    // tunnel was never noticed or cut.
    if (isConnected) {
      _startKillSwitchMonitor();
    }
    notifyListeners();
  }

  void setAutoConnect(bool value) {
    _autoConnect = value;
    _saveSetting('autoConnect', value);
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  Future<void> _saveSelectedServer() async {
    final prefs = await SharedPreferences.getInstance();
    if (_currentServer != null) {
      await prefs.setString('selectedServer', _currentServer!.id);
    }
  }

  Future<void> _saveSetting(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is bool) {
      await prefs.setBool(key, value);
    } else if (value is int) {
      await prefs.setInt(key, value);
    } else if (value is String) {
      await prefs.setString(key, value);
    }
  }

  @override
  void dispose() {
    _stopTimers();
    _stopKillSwitchMonitor();
    _stopEntitlementWatch();
    super.dispose();
  }
}

/// One Cloudflare trace sample: public IP + WARP visibility.
class EgressTrace {
  final String ip;
  /// null = unknown (trace didn't report / fallback endpoint used).
  final bool? warpOff;
  EgressTrace({required this.ip, this.warpOff});
}
