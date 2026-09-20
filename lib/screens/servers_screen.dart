import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../services/vpn_service.dart';
import '../services/account_service.dart';
import '../models/vpn_models.dart';
import '../theme/app_theme.dart';
import 'premium_screen.dart';

class ServersScreen extends StatelessWidget {
  const ServersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vpn = context.watch<VPNService>();
    final account = context.watch<AccountService>();

    final freeServers = vpn.availableServers;
    final premiumServers = vpn.allServers
        .where((s) => !vpn.availableServers.any((a) => a.id == s.id))
        .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        // Section header — matches website .sec-head
        Text(
          'LOCATIONS',
          style: GoogleFonts.jetBrainsMono(
            color: AppTheme.muted,
            fontSize: 10,
            fontWeight: FontWeight.w500,
            letterSpacing: 1.7,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          account.isPremiumActive
              ? 'All ${vpn.allServers.length} server locations available'
              : '${freeServers.length} free locations, ${premiumServers.length} premium',
          style: GoogleFonts.publicSans(color: AppTheme.ink2, fontSize: 14),
        ),
        const SizedBox(height: 28),

        // Free section
        Text(
          'FREE',
          style: GoogleFonts.jetBrainsMono(
            color: AppTheme.muted,
            fontSize: 10,
            fontWeight: FontWeight.w500,
            letterSpacing: 1.7,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: AppTheme.line2),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Column(
            children: [
              for (int i = 0; i < freeServers.length; i++) ...[
                _buildServerRow(
                  context: context,
                  vpn: vpn,
                  server: freeServers[i],
                  isSelected: vpn.currentServer?.id == freeServers[i].id,
                  isLocked: false,
                ),
                if (i < freeServers.length - 1)
                  const Divider(height: 1, color: AppTheme.line, indent: 0, endIndent: 0),
              ],
            ],
          ),
        ),

        const SizedBox(height: 28),

        // Premium section
        Text(
          'PREMIUM',
          style: GoogleFonts.jetBrainsMono(
            color: AppTheme.muted,
            fontSize: 10,
            fontWeight: FontWeight.w500,
            letterSpacing: 1.7,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: AppTheme.line2),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Column(
            children: [
              for (int i = 0; i < premiumServers.length; i++) ...[
                _buildServerRow(
                  context: context,
                  vpn: vpn,
                  server: premiumServers[i],
                  isSelected: vpn.currentServer?.id == premiumServers[i].id,
                  isLocked: !account.isPremiumActive,
                ),
                if (i < premiumServers.length - 1)
                  const Divider(height: 1, color: AppTheme.line, indent: 0, endIndent: 0),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildServerRow({
    required BuildContext context,
    required VPNService vpn,
    required ServerConfig server,
    required bool isSelected,
    required bool isLocked,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isLocked
            ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PremiumScreen()))
            : () {
                vpn.selectServer(server);
                if (vpn.isConnected) {
                  vpn.disconnect().then((_) => vpn.connect());
                }
              },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          color: isSelected ? AppTheme.blueWash : null,
          child: Row(
            children: [
              // Country code — mono font
              SizedBox(
                width: 36,
                child: Text(
                  server.countryCode,
                  style: GoogleFonts.jetBrainsMono(
                    color: isSelected ? AppTheme.blue : AppTheme.ink,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              // Server name
              Expanded(
                child: Text(
                  server.name,
                  style: GoogleFonts.publicSans(
                    color: isLocked ? AppTheme.muted : AppTheme.ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              // Status
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
}
