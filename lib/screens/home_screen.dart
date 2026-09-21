import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../services/vpn_service.dart';
import '../services/account_service.dart';
import '../services/premium_service.dart';
import '../models/vpn_models.dart';
import '../theme/app_theme.dart';
import '../widgets/world_map.dart';
import '../widgets/securedview_logo.dart';
import '../widgets/stats_card.dart';
import 'servers_screen.dart';
import 'settings_screen.dart';
import 'premium_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  int _currentIndex = 0;
  late AnimationController _connectAnimController;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _connectAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _connectAnimController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _animateConnect() {
    _connectAnimController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final vpn = context.watch<VPNService>();
    final account = context.watch<AccountService>();

    // Listen for errors and show snackbar
    if (vpn.error != null && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (vpn.error != null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(vpn.error!, style: GoogleFonts.publicSans()),
            backgroundColor: AppTheme.ink,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
            duration: const Duration(seconds: 3),
          ));
          vpn.clearError();
        }
      });
    }

    return Scaffold(
      backgroundColor: AppTheme.paper,
      body: SafeArea(
        child: IndexedStack(
          index: _currentIndex,
          children: [
            _buildHome(vpn, account),
            const ServersScreen(),
            const SettingsScreen(),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          border: Border(top: BorderSide(color: AppTheme.line, width: 1)),
        ),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (i) => setState(() => _currentIndex = i),
          backgroundColor: Colors.transparent,
          elevation: 0,
          height: 64,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.power_settings_new_rounded), label: 'Connect'),
            NavigationDestination(icon: Icon(Icons.public_rounded), label: 'Locations'),
            NavigationDestination(icon: Icon(Icons.settings_rounded), label: 'Settings'),
          ],
        ),
      ),
    );
  }

  Widget _buildHome(VPNService vpn, AccountService account) {
    final isConnected = vpn.isConnected;
    final isConnecting = vpn.isConnecting;
    final isDisconnecting = vpn.isDisconnecting;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      children: [
        // Header
        _buildHeader(vpn),
        const SizedBox(height: 20),

        // Map card
        _buildMapCard(vpn),
        const SizedBox(height: 16),

        // Server selector + Connect button
        _buildServerSelector(vpn, account),
        const SizedBox(height: 12),
        _buildConnectButton(vpn, account, isConnected, isConnecting, isDisconnecting),
        const SizedBox(height: 16),

        // Stats when connected
        if (isConnected) ...[
          StatsCard(stats: vpn.stats),
          const SizedBox(height: 16),
        ],

        // Upgrade bar
        if (!account.isPremiumActive) _buildUpgradeBar(),
      ],
    );
  }

  Widget _buildHeader(VPNService vpn) {
    final isConnected = vpn.isConnected;
    final isConnecting = vpn.isConnecting;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            const SecuredViewLogo(size: 26),
            const SizedBox(width: 10),
            Text(
              'SecuredView VPN',
              style: GoogleFonts.archivo(
                color: AppTheme.ink,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(2),
            border: Border.all(color: AppTheme.line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedBuilder(
                animation: _pulseController,
                builder: (context, _) {
                  return Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: isConnected
                          ? AppTheme.signal
                          : isConnecting
                              ? AppTheme.warning
                              : AppTheme.line2,
                      shape: BoxShape.circle,
                      boxShadow: isConnected
                          ? [BoxShadow(color: AppTheme.signal.withValues(alpha: 0.4 + _pulseController.value * 0.3), blurRadius: 6)]
                          : null,
                    ),
                  );
                },
              ),
              const SizedBox(width: 8),
              Text(
                isConnected
                    ? 'CONNECTED'
                    : isConnecting
                        ? 'CONNECTING'
                        : 'DISCONNECTED',
                style: GoogleFonts.jetBrainsMono(
                  color: isConnected
                      ? AppTheme.signal
                      : isConnecting
                          ? AppTheme.warning
                          : AppTheme.muted,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMapCard(VPNService vpn) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border.all(color: AppTheme.line2),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppTheme.line)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'EXIT NODE',
                  style: GoogleFonts.jetBrainsMono(
                    color: AppTheme.muted,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 1.5,
                  ),
                ),
                Text(
                  vpn.currentServer?.name ?? 'None selected',
                  style: GoogleFonts.publicSans(
                    color: AppTheme.ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 200,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(3)),
              child: WorldMap(
                servers: vpn.allServers,
                selectedId: vpn.currentServer?.id,
                onTap: (s) => vpn.selectServer(s),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Server selector — tap to open location picker
  Widget _buildServerSelector(VPNService vpn, AccountService account) {
    final server = vpn.currentServer;
    return GestureDetector(
      onTap: () => _showLocationPicker(vpn, account),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          border: Border.all(color: AppTheme.line2),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Row(
          children: [
            // Country flag area
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppTheme.blueWash,
                borderRadius: BorderRadius.circular(2),
              ),
              child: Center(
                child: Text(
                  server?.countryCode ?? '--',
                  style: GoogleFonts.jetBrainsMono(
                    color: AppTheme.blue,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Switch Location',
                    style: GoogleFonts.jetBrainsMono(
                      color: AppTheme.muted,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    server?.name ?? 'Select a server',
                    style: GoogleFonts.publicSans(
                      color: AppTheme.ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.unfold_more_rounded, color: AppTheme.muted, size: 20),
          ],
        ),
      ),
    );
  }

  void _showLocationPicker(VPNService vpn, AccountService account) {
    final freeServers = vpn.allServers.where((s) => !s.isPremium).toList();
    final premiumServers = vpn.allServers.where((s) => s.isPremium).toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.85,
        minChildSize: 0.3,
        builder: (ctx, scrollController) => Container(
          decoration: const BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(3)),
          ),
          child: Column(
            children: [
              // Handle
              Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                decoration: BoxDecoration(color: AppTheme.line, borderRadius: BorderRadius.circular(2)),
              ),
              // Title
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Row(
                  children: [
                    Text(
                      'SWITCH LOCATION',
                      style: GoogleFonts.jetBrainsMono(
                        color: AppTheme.muted,
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 1.7,
                      ),
                    ),
                    const Spacer(),
                    if (vpn.isConnected)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppTheme.signal.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: Text(
                          'WILL RECONNECT',
                          style: GoogleFonts.jetBrainsMono(
                            color: AppTheme.signal,
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1, color: AppTheme.line),
              // Server list
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    // Free servers
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      child: Text(
                        'FREE',
                        style: GoogleFonts.jetBrainsMono(
                          color: AppTheme.muted,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 1.7,
                        ),
                      ),
                    ),
                    ...freeServers.map((s) => _buildPickerTile(vpn, s)),
                    // Premium servers
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      child: Text(
                        'PREMIUM',
                        style: GoogleFonts.jetBrainsMono(
                          color: AppTheme.muted,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 1.7,
                        ),
                      ),
                    ),
                    ...premiumServers.map((s) => _buildPickerTile(vpn, s, isLocked: !account.isPremiumActive)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPickerTile(VPNService vpn, ServerConfig server, {bool isLocked = false}) {
    final isSelected = vpn.currentServer?.id == server.id;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isLocked
            ? () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const PremiumScreen()));
              }
            : () {
                Navigator.pop(context);
                _animateConnect();
                vpn.switchServer(server);
              },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          color: isSelected ? AppTheme.blueWash : null,
          child: Row(
            children: [
              Container(
                width: 36,
                height: 28,
                decoration: BoxDecoration(
                  color: isSelected ? AppTheme.blue : AppTheme.paper,
                  borderRadius: BorderRadius.circular(2),
                  border: Border.all(color: isSelected ? AppTheme.blue : AppTheme.line),
                ),
                child: Center(
                  child: Text(
                    server.countryCode,
                    style: GoogleFonts.jetBrainsMono(
                      color: isSelected ? Colors.white : AppTheme.ink2,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  server.name,
                  style: GoogleFonts.publicSans(
                    color: isLocked ? AppTheme.muted : AppTheme.ink,
                    fontSize: 14,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
              if (isSelected)
                Icon(Icons.check_circle_rounded, color: AppTheme.blue, size: 18)
              else if (isLocked)
                Icon(Icons.lock_outline_rounded, color: AppTheme.muted, size: 16)
              else
                Icon(Icons.chevron_right_rounded, color: AppTheme.line2, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConnectButton(
    VPNService vpn,
    AccountService account,
    bool isConnected,
    bool isConnecting,
    bool isDisconnecting,
  ) {
    final label = isConnected
        ? 'Disconnect'
        : isConnecting
            ? 'Connecting...'
            : isDisconnecting
                ? 'Disconnecting...'
                : 'Connect';

    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        onPressed: isConnecting || isDisconnecting
            ? null
            : () {
                if (isConnected) {
                  vpn.disconnect();
                } else {
                  if (!account.hasAccount) {
                    _showCreateAccountSheet(context);
                    return;
                  }
                  _animateConnect();
                  vpn.connect();
                }
              },
        style: ElevatedButton.styleFrom(
          backgroundColor: isConnected ? AppTheme.ink : AppTheme.blue,
          disabledBackgroundColor: AppTheme.muted,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
        ),
        child: isConnecting
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    label,
                    style: GoogleFonts.archivo(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ],
              )
            : Text(
                label,
                style: GoogleFonts.archivo(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
              ),
      ),
    );
  }

  Widget _buildUpgradeBar() {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PremiumScreen())),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: AppTheme.line2),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppTheme.blueWash,
                borderRadius: BorderRadius.circular(2),
              ),
              child: const Icon(Icons.workspace_premium_rounded, color: AppTheme.blue, size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Upgrade to Premium',
                    style: GoogleFonts.archivo(color: AppTheme.ink, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Unlock all 9 server locations',
                    style: GoogleFonts.publicSans(color: AppTheme.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: AppTheme.blue, borderRadius: BorderRadius.circular(2)),
              child: Text(
                context.read<PremiumService>().plans.isNotEmpty
                    ? context.read<PremiumService>().plans.first.priceDisplay
                    : '\$3.99',
                style: GoogleFonts.archivo(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCreateAccountSheet(BuildContext context) {
    final pinController = TextEditingController();
    final accountIdController = TextEditingController();
    final loginPinController = TextEditingController();
    bool loading = false;
    bool isLogin = false;
    String? localError;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return Container(
            padding: EdgeInsets.fromLTRB(24, 12, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
            decoration: const BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(3)),
            ),
            child: AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 40, height: 4, decoration: BoxDecoration(color: AppTheme.line, borderRadius: BorderRadius.circular(2))),
                  const SizedBox(height: 24),
                  const SecuredViewLogo(size: 40),
                  const SizedBox(height: 16),
                  Text(
                    isLogin ? 'Welcome Back' : 'Create Account',
                    style: GoogleFonts.archivo(color: AppTheme.ink, fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    isLogin ? 'Enter your Account ID and PIN' : 'Set a 4-digit PIN to secure your connection',
                    style: GoogleFonts.publicSans(color: AppTheme.muted, fontSize: 13),
                  ),
                  const SizedBox(height: 24),

                  // Error message
                  if (localError != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.error.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(2),
                        border: Border.all(color: AppTheme.error.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        localError!,
                        style: GoogleFonts.publicSans(color: AppTheme.error, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  if (!isLogin) ...[
                    _buildTextField(
                      controller: pinController,
                      hint: '4-digit PIN',
                      keyboardType: TextInputType.number,
                      maxLength: 4,
                      obscureText: true,
                    ),
                  ] else ...[
                    _buildTextField(
                      controller: accountIdController,
                      hint: 'Account ID',
                      prefixIcon: Icons.person_outline_rounded,
                    ),
                    const SizedBox(height: 12),
                    _buildTextField(
                      controller: loginPinController,
                      hint: '4-digit PIN',
                      keyboardType: TextInputType.number,
                      maxLength: 4,
                      obscureText: true,
                    ),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: loading ? null : () async {
                        if (!isLogin && pinController.text.length != 4) return;
                        if (isLogin && (accountIdController.text.isEmpty || loginPinController.text.length != 4)) return;
                        setSheetState(() { loading = true; localError = null; });
                        final accountService = context.read<AccountService>();
                        final vpnService = context.read<VPNService>();
                        bool success;
                        if (isLogin) {
                          success = await accountService.loginWithPin(accountIdController.text.trim(), loginPinController.text);
                        } else {
                          success = await accountService.createAccount(pinController.text);
                        }
                        if (success && mounted) {
                          Navigator.pop(ctx);
                          _animateConnect();
                          vpnService.connect();
                        } else {
                          final errorMsg = accountService.error ?? (isLogin ? 'Invalid Account ID or PIN' : 'Failed to create account');
                          setSheetState(() { loading = false; localError = errorMsg; });
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.blue,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
                      ),
                      child: loading
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : Text(
                              isLogin ? 'Login & Connect' : 'Create & Connect',
                              style: GoogleFonts.archivo(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                            ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => setSheetState(() {
                      isLogin = !isLogin;
                      localError = null;
                      pinController.clear();
                      accountIdController.clear();
                      loginPinController.clear();
                    }),
                    child: Text(
                      isLogin ? "Don't have an account? Create one" : 'I already have an account',
                      style: GoogleFonts.publicSans(color: AppTheme.muted, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    IconData? prefixIcon,
    TextInputType? keyboardType,
    int? maxLength,
    bool obscureText = false,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLength: maxLength,
      obscureText: obscureText,
      style: GoogleFonts.publicSans(color: AppTheme.ink, fontSize: 15),
      decoration: InputDecoration(
        counterText: '',
        hintText: hint,
        hintStyle: GoogleFonts.publicSans(color: AppTheme.muted, fontSize: 14),
        filled: true,
        fillColor: AppTheme.surface,
        prefixIcon: prefixIcon != null ? Icon(prefixIcon, color: AppTheme.muted, size: 20) : null,
        border: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(2)),
          borderSide: BorderSide(color: AppTheme.line2),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(2)),
          borderSide: BorderSide(color: AppTheme.blue, width: 1.5),
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(2)),
          borderSide: BorderSide(color: AppTheme.line2),
        ),
      ),
    );
  }
}
