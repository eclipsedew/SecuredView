import 'package:url_launcher/url_launcher.dart';

import '../app_version.dart';

/// User-facing contact for bugs and product suggestions.
class SupportService {
  static const String email = kSupportEmail;

  /// Opens a plain email to support (used by Contact Support).
  static Future<bool> openSupport() => _open('mailto:$email');

  static Future<bool> reportBug({String? details}) async {
    final subject = Uri.encodeComponent('SecuredView VPN — Bug report');
    final body = Uri.encodeComponent(
      (details == null || details.isEmpty)
          ? 'Describe the bug:\n\n\nSteps to reproduce:\n\n\nDevice / app version: '
          : details,
    );
    return _open('mailto:$email?subject=$subject&body=$body');
  }

  static Future<bool> sendSuggestion({String? details}) async {
    final subject = Uri.encodeComponent('SecuredView VPN — Suggestion');
    final body = Uri.encodeComponent(
      details ?? 'Your suggestion:\n\n',
    );
    return _open('mailto:$email?subject=$subject&body=$body');
  }

  /// Opens the default mail client; falls back to copying address via mailto.
  static Future<bool> _open(String mailto) async {
    final uri = Uri.tryParse(mailto);
    if (uri == null) return false;
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        return true;
      }
    } catch (_) {}
    try {
      return await launchUrl(Uri.parse('mailto:$email'));
    } catch (_) {
      return false;
    }
  }
}
