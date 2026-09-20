import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

class TOSScreen extends StatelessWidget {
  const TOSScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.paper,
      appBar: AppBar(
        title: Text('Terms of Service', style: GoogleFonts.archivo(fontWeight: FontWeight.w700)),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _section('Terms of Service', 'Last updated: September 19, 2026'),
          _section('1. Acceptance of Terms',
            'By downloading, installing, or using SecuredView ("the App"), you agree to be bound by these Terms of Service ("Terms"). If you do not agree to these Terms, do not use the App.'),
          _section('2. Description of Service',
            'SecuredView provides a virtual private network (VPN) service that routes your internet traffic through encrypted tunnels. The App uses Cloudflare WARP technology to establish secure connections. Free accounts are limited to 2 server locations. Premium accounts unlock all server locations and additional features.'),
          _section('3. Account Registration',
            'To use the App, you must create an account with a 4-digit PIN. You are responsible for maintaining the confidentiality of your account credentials. You must be at least 13 years of age to create an account. You are responsible for all activity that occurs under your account.'),
          _section('4. Acceptable Use',
            'You agree not to:\n'
            '• Use the App for any unlawful purpose\n'
            '• Attempt to gain unauthorized access to any part of the App\n'
            '• Interfere with or disrupt the App or servers\n'
            '• Use the App to transmit malware, spam, or other harmful content\n'
            '• Share your account credentials with others\n'
            '• Exceed the device limit associated with your subscription tier\n'
            '• Resell or redistribute access to the App'),
          _section('5. Subscriptions and Payments',
            'Premium subscriptions are available for purchase within the App. All payments are processed through our payment processor (Paystack). Prices are listed in USD and may vary by region. Subscriptions auto-renew unless cancelled. You may cancel at any time through the App settings. Refunds are handled in accordance with applicable law and our refund policy.'),
          _section('6. Privacy',
            'Your use of the App is also governed by our Privacy Policy, which describes how we collect, use, and protect your personal information. By using the App, you consent to the data practices described in the Privacy Policy.'),
          _section('7. Disclaimer of Warranties',
            'THE APP IS PROVIDED "AS IS" AND "AS AVAILABLE" WITHOUT WARRANTIES OF ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, AND NON-INFRINGEMENT. We do not warrant that the App will be uninterrupted, error-free, or completely secure.'),
          _section('8. Limitation of Liability',
            'TO THE MAXIMUM EXTENT PERMITTED BY LAW, SECUREDVIEW AND ITS AFFILIATES SHALL NOT BE LIABLE FOR ANY INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, OR PUNITIVE DAMAGES, INCLUDING BUT NOT LIMITED TO LOSS OF DATA, USE, OR PROFITS, ARISING OUT OF OR IN CONNECTION WITH YOUR USE OF THE APP, REGARDLESS OF THE THEORY OF LIABILITY.'),
          _section('9. Service Availability',
            'We strive to maintain the App\'s availability but do not guarantee uninterrupted access. The App may be temporarily unavailable due to maintenance, updates, or circumstances beyond our control. Server locations and availability may change without notice.'),
          _section('10. Modifications to Terms',
            'We reserve the right to modify these Terms at any time. Material changes will be communicated through the App or via email. Your continued use of the App after changes constitutes acceptance of the modified Terms.'),
          _section('11. Termination',
            'We may suspend or terminate your access to the App at any time, with or without cause, with or without notice. Upon termination, your right to use the App ceases immediately. You may also terminate your account by deleting it through the App settings.'),
          _section('12. Governing Law',
            'These Terms are governed by and construed in accordance with applicable laws. Any disputes shall be resolved through binding arbitration or in courts of competent jurisdiction.'),
          _section('13. Contact',
            'If you have questions about these Terms, please contact us at support@securedview.com.'),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _section(String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.archivo(
              color: title.startsWith(RegExp(r'\d')) ? AppTheme.ink : AppTheme.blue,
              fontSize: title.startsWith(RegExp(r'\d')) ? 14 : 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: GoogleFonts.publicSans(color: AppTheme.ink2, fontSize: 13, height: 1.6),
          ),
        ],
      ),
    );
  }
}
