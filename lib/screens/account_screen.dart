import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../services/account_service.dart';
import '../services/vpn_service.dart';
import '../models/vpn_models.dart';
import '../theme/app_theme.dart';
import '../widgets/securedview_logo.dart';
import 'premium_screen.dart';
import 'devices_screen.dart';

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final account = context.watch<AccountService>();

    if (!account.hasAccount) {
      return Scaffold(
        backgroundColor: AppTheme.paper,
        appBar: AppBar(title: Text('Account', style: GoogleFonts.archivo(fontWeight: FontWeight.w700))),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.person_off_rounded, size: 48, color: AppTheme.muted),
              const SizedBox(height: 14),
              Text('No account', style: GoogleFonts.archivo(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('Create one in Settings', style: GoogleFonts.publicSans(color: AppTheme.muted, fontSize: 13)),
            ],
          ),
        ),
      );
    }

    final acc = account.account!;
    final isPremium = account.isPremiumActive;

    return Scaffold(
      backgroundColor: AppTheme.paper,
      appBar: AppBar(
        title: Text('Account', style: GoogleFonts.archivo(fontWeight: FontWeight.w700)),
        leading: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildStatusCard(acc, isPremium),
          const SizedBox(height: 16),
          _buildIdCard(context, acc),
          const SizedBox(height: 16),
          _buildDevicesCard(account),
          if (isPremium) ...[
            const SizedBox(height: 16),
            _buildSubscriptionCard(acc),
          ],
          const SizedBox(height: 20),
          _buildActions(context, account, isPremium),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildStatusCard(UserAccount acc, bool isPremium) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: isPremium ? AppTheme.blue : AppTheme.line2),
      ),
      child: Column(
        children: [
          const SecuredViewLogo(size: 40),
          const SizedBox(height: 12),
          Text(
            isPremium
                ? (acc.onTrial ? 'Free Trial Active' : 'Premium Active')
                : 'No Active Plan',
            style: GoogleFonts.archivo(
              fontWeight: FontWeight.w600,
              fontSize: 16,
              color: isPremium ? AppTheme.blue : AppTheme.ink,
            ),
          ),
          if (isPremium && acc.premiumExpiry != null) ...[
            const SizedBox(height: 4),
            Text(
              acc.onTrial
                  ? 'Trial ends ${_formatDate(acc.premiumExpiry!)} — subscribe anytime'
                  : 'Expires ${_formatDate(acc.premiumExpiry!)}',
              style: GoogleFonts.publicSans(color: AppTheme.muted, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildIdCard(BuildContext context, UserAccount acc) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: AppTheme.line2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.badge_rounded, color: AppTheme.muted, size: 18),
              const SizedBox(width: 8),
              Text('Account ID', style: GoogleFonts.publicSans(fontWeight: FontWeight.w500, fontSize: 14, color: AppTheme.ink)),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.paper,
              borderRadius: BorderRadius.circular(2),
              border: Border.all(color: AppTheme.line),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    acc.accountId.toUpperCase(),
                    style: GoogleFonts.jetBrainsMono(fontSize: 14, letterSpacing: 1, fontWeight: FontWeight.w500, color: AppTheme.ink),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.copy_rounded, color: AppTheme.muted, size: 18),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: acc.accountId.toUpperCase()));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Copied')),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text('Share this ID to add a second device', style: GoogleFonts.publicSans(color: AppTheme.muted, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildDevicesCard(AccountService account) {
    final acc = account.account!;
    final count = acc.deviceIds.length;
    final maxDev = account.isPremiumActive ? 3 : 1;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: AppTheme.line2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.devices_rounded, color: AppTheme.muted, size: 18),
              const SizedBox(width: 8),
              Text('Devices', style: GoogleFonts.publicSans(fontWeight: FontWeight.w500, fontSize: 14, color: AppTheme.ink)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.paper,
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Text('$count/$maxDev', style: GoogleFonts.jetBrainsMono(color: AppTheme.muted, fontWeight: FontWeight.w500, fontSize: 11)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...acc.deviceIds.asMap().entries.map((entry) {
            final index = entry.key;
            final id = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: AppTheme.paper,
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: Center(
                      child: Text(
                        '${index + 1}',
                        style: GoogleFonts.publicSans(color: AppTheme.muted, fontWeight: FontWeight.w600, fontSize: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          index == 0 ? 'This device' : 'Linked device',
                          style: GoogleFonts.publicSans(fontWeight: FontWeight.w500, fontSize: 13, color: AppTheme.ink),
                        ),
                        Text(
                          '${id.substring(0, 8)}...${id.substring(id.length - 4)}',
                          style: GoogleFonts.jetBrainsMono(fontSize: 11, color: AppTheme.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildSubscriptionCard(UserAccount acc) {
    final daysLeft = acc.premiumExpiry != null ? acc.premiumExpiry!.difference(DateTime.now()).inDays : 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: AppTheme.blue),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.receipt_long_rounded, color: AppTheme.blue, size: 18),
              const SizedBox(width: 8),
              Text('Subscription', style: GoogleFonts.publicSans(fontWeight: FontWeight.w500, fontSize: 14, color: AppTheme.ink)),
            ],
          ),
          const SizedBox(height: 12),
          _detailRow('Plan', 'Premium ($daysLeft days left)'),
          _detailRow('Renews', _formatDate(acc.premiumExpiry!)),
          _detailRow('Devices', '${acc.deviceIds.length} of 2'),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.publicSans(color: AppTheme.muted, fontSize: 13)),
          Text(value, style: GoogleFonts.publicSans(fontSize: 13, fontWeight: FontWeight.w500, color: AppTheme.ink)),
        ],
      ),
    );
  }

  Widget _buildActions(BuildContext context, AccountService account, bool isPremium) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DevicesScreen())),
            child: Text('Manage Devices', style: GoogleFonts.archivo(fontWeight: FontWeight.w600)),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: isPremium
              ? OutlinedButton(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PremiumScreen())),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
                  ),
                  child: Text('Manage Subscription', style: GoogleFonts.archivo(fontWeight: FontWeight.w600)),
                )
              : ElevatedButton(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PremiumScreen())),
                  child: Text('Subscribe', style: GoogleFonts.archivo(fontWeight: FontWeight.w600)),
                ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton(
            onPressed: () => _signOut(context, account),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.error,
              side: const BorderSide(color: AppTheme.error),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
            ),
            child: Text('Sign Out', style: GoogleFonts.archivo(fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) => '${date.day}/${date.month}/${date.year}';

  void _signOut(BuildContext context, AccountService account) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('You will be signed out and disconnected.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel', style: GoogleFonts.publicSans(color: AppTheme.muted))),
          ElevatedButton(
            onPressed: () async {
              final vpn = context.read<VPNService>();
              if (vpn.isConnected) await vpn.disconnect();
              account.logout();
              if (context.mounted) {
                Navigator.pop(context);
                Navigator.pop(context);
              }
            },
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
  }
}
