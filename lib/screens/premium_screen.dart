import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../services/account_service.dart';
import '../services/premium_service.dart';
import '../models/vpn_models.dart';
import '../theme/app_theme.dart';
import '../widgets/securedview_logo.dart';
import 'paystack_payment_screen.dart';

class PremiumScreen extends StatelessWidget {
  const PremiumScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final account = context.watch<AccountService>();
    final premium = context.watch<PremiumService>();

    return Scaffold(
      backgroundColor: AppTheme.paper,
      appBar: AppBar(
        title: Text('Premium', style: GoogleFonts.archivo(fontWeight: FontWeight.w700)),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildHero(),
          const SizedBox(height: 32),

          Text(
            'CHOOSE A PLAN',
            style: GoogleFonts.jetBrainsMono(
              color: AppTheme.muted,
              fontSize: 10,
              fontWeight: FontWeight.w500,
              letterSpacing: 1.7,
            ),
          ),
          const SizedBox(height: 14),

          ...premium.plans.asMap().entries.map((entry) {
            final index = entry.key;
            final plan = entry.value;
            final isBest = index == premium.getBestValuePlanIndex();
            return _buildPlanCard(context, account, premium, plan, isBest);
          }),
          const SizedBox(height: 32),

          // Free vs Premium comparison
          _buildComparison(),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildHero() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: AppTheme.blueWash),
      ),
      child: Column(
        children: [
          const SecuredViewLogo(size: 48),
          const SizedBox(height: 18),
          Text(
            'Unlock SecuredView VPN Premium',
            style: GoogleFonts.archivo(
              color: AppTheme.ink,
              fontWeight: FontWeight.w700,
              fontSize: 20,
              letterSpacing: -0.3,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            '9 locations worldwide. No ads. 3 devices.',
            style: GoogleFonts.publicSans(color: AppTheme.muted, fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildPlanCard(
    BuildContext context,
    AccountService account,
    PremiumService premium,
    PremiumPlan plan,
    bool isBest,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(
          color: isBest ? AppTheme.blue : AppTheme.line2,
          width: isBest ? 1.5 : 1,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          plan.name,
                          style: GoogleFonts.archivo(fontWeight: FontWeight.w600, fontSize: 16, color: AppTheme.ink),
                        ),
                        if (isBest) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.blueWash,
                              borderRadius: BorderRadius.circular(2),
                            ),
                            child: Text(
                              'BEST VALUE',
                              style: GoogleFonts.jetBrainsMono(
                                color: AppTheme.blue,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${plan.days} days',
                      style: GoogleFonts.publicSans(color: AppTheme.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Text(
                plan.priceDisplay,
                style: GoogleFonts.archivo(
                  fontWeight: FontWeight.w700,
                  fontSize: 24,
                  color: isBest ? AppTheme.blue : AppTheme.ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton(
              onPressed: account.isPremiumActive
                  ? null
                  : () => _purchase(context, account, premium, plan),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.blue,
                disabledBackgroundColor: AppTheme.muted,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
              ),
              child: premium.isLoading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(
                      account.isPremiumActive ? 'Active' : 'Subscribe',
                      style: GoogleFonts.archivo(color: Colors.white, fontWeight: FontWeight.w600),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComparison() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'FREE VS PREMIUM',
          style: GoogleFonts.jetBrainsMono(
            color: AppTheme.muted,
            fontSize: 10,
            fontWeight: FontWeight.w500,
            letterSpacing: 1.7,
          ),
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _buildColumn('Free', [
              '2 locations',
              'AES-256 encryption',
              'Kill switch',
              'No-logs policy',
              'Ads shown',
              '1 device',
            ])),
            const SizedBox(width: 12),
            Expanded(child: _buildColumn('Premium', [
              'All 9 locations',
              'AES-256 encryption',
              'Kill switch',
              'No-logs policy',
              'No ads',
              '2 devices',
            ], isPremium: true)),
          ],
        ),
      ],
    );
  }

  Widget _buildColumn(String title, List<String> features, {bool isPremium = false}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: isPremium ? AppTheme.blue : AppTheme.line2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.archivo(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: isPremium ? AppTheme.blue : AppTheme.muted,
            ),
          ),
          const SizedBox(height: 12),
          ...features.map((f) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.check_rounded, color: AppTheme.signal, size: 14),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(f, style: GoogleFonts.publicSans(color: AppTheme.ink2, fontSize: 12)),
                ),
              ],
            ),
          )),
        ],
      ),
    );
  }

  Future<void> _purchase(
    BuildContext context,
    AccountService account,
    PremiumService premium,
    PremiumPlan plan,
  ) async {
    if (!account.hasAccount) {
      final pin = await _showPinDialog(context);
      if (pin == null) return;
      final created = await account.createAccount(pin);
      if (!created || !context.mounted) return;
    }

    // Open Paystack payment screen
    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaystackPaymentScreen(
          planId: plan.id,
          planName: plan.name,
          amount: plan.priceUSD,
        ),
      ),
    );
  }

  Future<String?> _showPinDialog(BuildContext context) {
    final controller = TextEditingController();
    return showDialog<String>(
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
  }
}
