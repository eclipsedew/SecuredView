import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'services/api_service.dart';
import 'services/vpn_service.dart';
import 'services/account_service.dart';
import 'services/premium_service.dart';
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

class SecuredViewApp extends StatelessWidget {
  const SecuredViewApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Shared API service instance
    final api = ApiService();

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AccountService(api: api)..init()),
        ChangeNotifierProvider(create: (_) => PremiumService()),
        ChangeNotifierProxyProvider<AccountService, VPNService>(
          create: (_) => VPNService(),
          update: (_, account, vpn) => vpn!..updateAccount(account),
        ),
      ],
      child: MaterialApp(
        title: 'SecuredView VPN',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: const HomeScreen(),
      ),
    );
  }
}
