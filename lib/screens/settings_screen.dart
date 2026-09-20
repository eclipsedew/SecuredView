import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../services/vpn_service.dart';
import '../services/account_service.dart';
import '../theme/app_theme.dart';
import '../widgets/securedview_logo.dart';
import 'account_screen.dart';
import 'devices_screen.dart';
import 'premium_screen.dart';
import 'tos_screen.dart';
import 'privacy_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vpn = context.watch<VPNService>();
    final account = context.watch<AccountService>();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        // Section header
        Text(
          'SETTINGS',
          style: GoogleFonts.jetBrainsMono(
            color: AppTheme.muted,
            fontSize: 10,
            fontWeight: FontWeight.w500,
            letterSpacing: 1.7,
          ),
        ),
        const SizedBox(height: 24),

        // Account card
        if (account.hasAccount) ...[
          _buildAccountCard(context, account),
          const SizedBox(height: 28),
        ],

        // Security
        _buildSectionLabel('Security'),
        const SizedBox(height: 10),
        _buildCard([
          _switchTile(Icons.shield_outlined, 'Kill Switch', 'Block traffic if VPN drops', vpn.killSwitch, vpn.setKillSwitch),
          const Divider(height: 1, color: AppTheme.line, indent: 0, endIndent: 0),
          _switchTile(Icons.sync_rounded, 'Auto-Connect', 'Connect on app launch', vpn.autoConnect, vpn.setAutoConnect),
        ]),

        const SizedBox(height: 28),

        // Network
        _buildSectionLabel('Network'),
        const SizedBox(height: 10),
        _buildCard([
          _infoTile(Icons.dns_outlined, 'DNS', '1.1.1.1'),
          const Divider(height: 1, color: AppTheme.line, indent: 0, endIndent: 0),
          _infoTile(Icons.lock_outline, 'Protocol', 'WireGuard'),
          const Divider(height: 1, color: AppTheme.line, indent: 0, endIndent: 0),
          _infoTile(Icons.enhanced_encryption_outlined, 'Encryption', 'AES-256-GCM'),
        ]),

        const SizedBox(height: 28),

        // Account
        _buildSectionLabel('Account'),
        const SizedBox(height: 10),
        _buildCard(account.hasAccount
            ? [
                _actionTile(Icons.person_outline_rounded, 'Account Details', () =>
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const AccountScreen()))),
                const Divider(height: 1, color: AppTheme.line, indent: 0, endIndent: 0),
                _actionTile(Icons.devices_rounded, 'Manage Devices', () =>
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const DevicesScreen()))),
                const Divider(height: 1, color: AppTheme.line, indent: 0, endIndent: 0),
                _actionTile(Icons.logout_rounded, 'Sign Out', () => _signOut(context, account, vpn), isDestructive: true),
              ]
            : [
                _actionTile(Icons.person_add_outlined, 'Create Account', () => _createAccount(context, account)),
                const Divider(height: 1, color: AppTheme.line, indent: 0, endIndent: 0),
                _actionTile(Icons.workspace_premium_outlined, 'Upgrade', () =>
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const PremiumScreen())), isAccent: true),
              ]),

        const SizedBox(height: 28),

        // About
        _buildSectionLabel('About'),
        const SizedBox(height: 10),
        _buildCard([
          _infoTile(Icons.info_outline_rounded, 'Version', '1.0.0'),
          const Divider(height: 1, color: AppTheme.line, indent: 0, endIndent: 0),
          _actionTile(Icons.description_outlined, 'Terms of Service', () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const TOSScreen()));
          }),
          const Divider(height: 1, color: AppTheme.line, indent: 0, endIndent: 0),
          _actionTile(Icons.privacy_tip_outlined, 'Privacy Policy', () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const PrivacyScreen()));
          }),
        ]),

        const SizedBox(height: 32),

        // Footer branding
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SecuredViewLogo(size: 16),
            const SizedBox(width: 8),
            Text(
              'SecuredView VPN',
              style: GoogleFonts.archivo(
                color: AppTheme.muted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAccountCard(BuildContext context, AccountService account) {
    final isPremium = account.isPremiumActive;
    final acc = account.account!;

    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AccountScreen())),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: AppTheme.blueWash),
        ),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppTheme.blueWash,
                borderRadius: BorderRadius.circular(2),
              ),
              child: Icon(
                isPremium ? Icons.workspace_premium_rounded : Icons.person_rounded,
                color: AppTheme.blue,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        isPremium ? 'Premium Account' : 'Free Account',
                        style: GoogleFonts.archivo(
                          color: AppTheme.ink,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      if (isPremium) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.blueWash,
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: Text(
                            'PRO',
                            style: GoogleFonts.jetBrainsMono(
                              color: AppTheme.blue,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    acc.accountId,
                    style: GoogleFonts.jetBrainsMono(
                      color: AppTheme.muted,
                      fontSize: 11,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: AppTheme.line2, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionLabel(String title) {
    return Text(
      title.toUpperCase(),
      style: GoogleFonts.jetBrainsMono(
        color: AppTheme.muted,
        fontSize: 10,
        fontWeight: FontWeight.w500,
        letterSpacing: 1.7,
      ),
    );
  }

  Widget _buildCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: AppTheme.line2),
      ),
      child: Column(children: children),
    );
  }

  Widget _switchTile(IconData icon, String title, String subtitle, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.muted, size: 20),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: GoogleFonts.publicSans(fontWeight: FontWeight.w500, fontSize: 14, color: AppTheme.ink)),
                Text(subtitle, style: GoogleFonts.publicSans(color: AppTheme.muted, fontSize: 12)),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _infoTile(IconData icon, String title, String trailing) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.muted, size: 20),
          const SizedBox(width: 14),
          Expanded(child: Text(title, style: GoogleFonts.publicSans(fontWeight: FontWeight.w500, fontSize: 14, color: AppTheme.ink))),
          Text(trailing, style: GoogleFonts.jetBrainsMono(color: AppTheme.muted, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _actionTile(IconData icon, String title, VoidCallback onTap, {bool isDestructive = false, bool isAccent = false}) {
    final color = isDestructive ? AppTheme.error : isAccent ? AppTheme.blue : AppTheme.muted;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: GoogleFonts.publicSans(
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                  color: isDestructive ? AppTheme.error : AppTheme.ink,
                ),
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: AppTheme.line2, size: 18),
          ],
        ),
      ),
    );
  }

  void _signOut(BuildContext context, AccountService account, VPNService vpn) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('You will be signed out and disconnected.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel', style: GoogleFonts.publicSans(color: AppTheme.muted))),
          ElevatedButton(
            onPressed: () async {
              if (vpn.isConnected) await vpn.disconnect();
              account.logout();
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
  }

  Future<void> _createAccount(BuildContext context, AccountService account) async {
    final controller = TextEditingController();
    final pin = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Set a 4-digit PIN'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          maxLength: 4,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'PIN'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              if (RegExp(r'^\d{4}$').hasMatch(controller.text)) {
                Navigator.pop(ctx, controller.text);
              }
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (pin == null) return;
    await account.createAccount(pin);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Account created. ID: ${account.account!.accountId}')),
      );
    }
  }
}
