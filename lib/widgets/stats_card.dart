import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/vpn_models.dart';
import '../theme/app_theme.dart';

class StatsCard extends StatelessWidget {
  final ConnectionStats stats;

  const StatsCard({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border.all(color: AppTheme.line2),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Column(
        children: [
          _buildRow('UPLOAD', stats.formattedSent),
          _divider(),
          _buildRow('DOWNLOAD', stats.formattedReceived),
          _divider(),
          _buildRow('DURATION', stats.formattedDuration),
        ],
      ),
    );
  }

  Widget _buildRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      child: Row(
        children: [
          // Label — matches website .ro dt
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.jetBrainsMono(
                color: AppTheme.muted,
                fontSize: 10,
                fontWeight: FontWeight.w500,
                letterSpacing: 1.5,
              ),
            ),
          ),
          // Value — matches website .ro dd
          Text(
            value,
            style: GoogleFonts.jetBrainsMono(
              color: AppTheme.ink,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() {
    return const Divider(height: 1, color: AppTheme.line, indent: 0, endIndent: 0);
  }
}
