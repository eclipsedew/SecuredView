import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'services/api_service.dart';
import 'services/vpn_service.dart';
import 'services/account_service.dart';
import 'services/premium_service.dart';
import 'services/update_service.dart';
import 'theme/app_theme.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarColor: AppTheme.bg,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  runApp(const SecuredViewApp());
  unawaited(_ensureAutostart());
}

/// Launch the app at login so tunnel control (and the IP display) comes up
/// with the session — after a reboot the user just opens their desktop and
/// SecuredView is there. Linux: XDG autostart entry (Windows does the same
/// via an HKCU Run key in runner/main.cpp).
Future<void> _ensureAutostart() async {
  if (kDebugMode || kIsWeb) return;
  try {
    if (!Platform.isLinux) return;
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) return;
    final dir = Directory('$home/.config/autostart');
    await dir.create(recursive: true);
    final exe = Platform.resolvedExecutable;
    final file = File('${dir.path}/securedview-vpn.desktop');
    final content = '[Desktop Entry]\n'
        'Type=Application\n'
        'Name=SecuredView VPN\n'
        'Comment=SecuredView VPN autostart\n'
        'Exec="$exe"\n'
        'Terminal=false\n'
        'X-GNOME-Autostart-enabled=true\n';
    final existing = await file.exists() ? await file.readAsString() : null;
    if (existing != content) {
      await file.writeAsString(content);
    }
  } catch (_) {
    // Best effort — a locked-down home dir must not break startup.
  }
}

class SecuredViewApp extends StatefulWidget {
  const SecuredViewApp({super.key});

  @override
  State<SecuredViewApp> createState() => _SecuredViewAppState();
}

class _SecuredViewAppState extends State<SecuredViewApp> with WidgetsBindingObserver {
  final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();
  Timer? _clockTick;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // App-level 1s clock: kills VPN the moment trial/sub ends even if UI is idle.
    // VPNService also watches while connected; this is belt-and-suspenders.
    _clockTick = Timer.periodic(const Duration(seconds: 1), (_) => _enforceFromRoot());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clockTick?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Returning from background: re-adopt native tunnel state first
      // (service may have died or still be up), then refresh server truth.
      try {
        final vpn = context.read<VPNService>();
        vpn.restoreFromNative();
      } catch (_) {}
      _enforceFromRoot(syncServer: true);
    } else if (state == AppLifecycleState.paused) {
      // Still enforce local clock while backgrounded via residual timer
    } else if (state == AppLifecycleState.detached) {
      // Desktop window closing = app exiting. Drop the tunnel with us so
      // no unmanaged tunnel outlives the process (nobody would enforce
      // entitlement on it). Reopen/autostart reconnects cleanly.
      try {
        unawaited(context.read<VPNService>().shutdownTunnel());
      } catch (_) {}
    }
  }

  void _enforceFromRoot({bool syncServer = false}) {
    final ctx = _navKey.currentContext;
    if (ctx == null) return;
    try {
      final account = context.read<AccountService>();
      final vpn = context.read<VPNService>();
      if (syncServer && account.hasAccount) {
        unawaited(account.syncPremiumStatus());
      }
      // VPNService listens via updateAccount + its own 1s watch while connected.
      // Force a check here too when entitlement just died:
      if (account.entitlementExpiredLocally() && (vpn.isConnected || vpn.isConnecting)) {
        account.recheckEntitlement();
      }
    } catch (_) {
      // Provider not ready yet
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = ApiService();

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AccountService(api: api)..init()),
        ChangeNotifierProvider(create: (_) => PremiumService()),
        ChangeNotifierProvider(create: (_) => UpdateService()),
        ChangeNotifierProxyProvider<AccountService, VPNService>(
          create: (_) => VPNService(),
          update: (_, account, vpn) => vpn!..updateAccount(account),
        ),
      ],
      child: MaterialApp(
        title: 'SecuredView VPN',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        navigatorKey: _navKey,
        home: const HomeScreen(),
      ),
    );
  }
}
