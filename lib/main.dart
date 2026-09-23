import 'dart:async';
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
      // Returning from background: refresh server truth, then cut if ended
      _enforceFromRoot(syncServer: true);
    } else if (state == AppLifecycleState.paused) {
      // Still enforce local clock while backgrounded via residual timer
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
