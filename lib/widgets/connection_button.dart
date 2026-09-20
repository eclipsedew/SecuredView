import 'package:flutter/material.dart';
import '../services/vpn_service.dart';
import '../models/vpn_models.dart';
import '../theme/app_theme.dart';

class ConnectionButton extends StatelessWidget {
  final VPNService vpn;
  final AnimationController pulseController;
  final AnimationController rotateController;

  const ConnectionButton({
    super.key,
    required this.vpn,
    required this.pulseController,
    required this.rotateController,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GestureDetector(
        onTap: () {
          if (vpn.isConnected) {
            vpn.disconnect();
          } else if (vpn.isDisconnected) {
            vpn.connect();
          }
        },
        child: AnimatedBuilder(
          animation: pulseController,
          builder: (context, child) {
            final t = pulseController.value;
            final isActive = vpn.isConnected;
            final isConnecting = vpn.state == VPNState.connecting;

            return Stack(
              alignment: Alignment.center,
              children: [
                // Outer ring
                if (isActive || isConnecting)
                  Container(
                    width: 180 + (t * 20),
                    height: 180 + (t * 20),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _color().withValues(alpha: 0.1 - (t * 0.06)),
                        width: 1.5,
                      ),
                    ),
                  ),
                // Glow
                if (isActive)
                  Container(
                    width: 160 + (t * 10),
                    height: 160 + (t * 10),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _color().withValues(alpha: 0.03),
                    ),
                  ),
                // Main button
                Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: isConnecting
                        ? LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [AppTheme.warning.withValues(alpha: 0.8), AppTheme.warning],
                          )
                        : isActive
                            ? LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [AppTheme.success.withValues(alpha: 0.8), AppTheme.success],
                              )
                            : const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [AppTheme.accent, AppTheme.accentDark],
                              ),
                    boxShadow: [
                      BoxShadow(
                        color: _color().withValues(alpha: isActive ? 0.25 : 0.0),
                        blurRadius: 40,
                        spreadRadius: 6,
                      ),
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                    border: Border.all(
                      color: isActive
                          ? AppTheme.success.withValues(alpha: 0.4)
                          : isConnecting
                              ? AppTheme.warning.withValues(alpha: 0.4)
                              : AppTheme.border,
                      width: 1.5,
                    ),
                  ),
                  child: isConnecting
                      ? Padding(
                          padding: const EdgeInsets.all(36),
                          child: CircularProgressIndicator(
                            color: Colors.white.withValues(alpha: 0.8),
                            strokeWidth: 2.5,
                          ),
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.power_settings_new_rounded,
                              color: isActive ? Colors.white : AppTheme.textMuted,
                              size: 44,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              isActive ? 'ON' : 'OFF',
                              style: TextStyle(
                                color: isActive ? Colors.white : AppTheme.textMuted,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                                letterSpacing: 2,
                              ),
                            ),
                          ],
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Color _color() {
    switch (vpn.state) {
      case VPNState.connected:
        return AppTheme.success;
      case VPNState.connecting:
      case VPNState.disconnecting:
        return AppTheme.warning;
      case VPNState.error:
        return AppTheme.error;
      default:
        return AppTheme.textMuted;
    }
  }
}