import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.paper,
      appBar: AppBar(
        title: Text('Privacy Policy', style: GoogleFonts.archivo(fontWeight: FontWeight.w700)),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _section('Privacy Policy', 'Last updated: September 19, 2026'),
          _section('1. Introduction',
            'SecuredView VPN ("we", "us", or "our") is committed to protecting your privacy. This Privacy Policy explains how we collect, use, disclose, and safeguard your information when you use our mobile application and related services (collectively, "the App").'),
          _section('2. Information We Collect',
            'We collect the following types of information:\n\n'
            'Account Information: When you create an account, we store a hashed version of your 4-digit PIN and a unique account identifier. We do not collect your name, email, or phone number at signup. Email is requested only by our payment provider when you choose to purchase a plan, for the receipt.\n\n'
            'Device Information: We store a device identifier and a hashed hardware fingerprint (Android ID + device model) solely to enforce device limits and prevent free-trial abuse. This stays on the device account record and is never sold.\n\n'
            'Free Trial: Premium trials run for exactly 3 days from account creation. When the trial ends, server access stops until you purchase a plan (there is no free tier). We do not store card numbers and never auto-charge — subscriptions are one-time purchases through Paystack’s hosted checkout. Entitlement is checked against our servers; device clock changes cannot extend access.\n\n'
            'Subscription Information: If you purchase a premium subscription, we store your subscription status, plan details, and expiration date. Payment information is processed by Paystack and is never stored on our servers.\n\n'
            'Connection Data: We do NOT log your internet traffic, browsing history, DNS queries, or the content of your communications. We do not log your original IP address or the IP addresses you connect to through our servers.\n\n'
            'Usage Data: We may collect anonymized, aggregated statistics such as total number of accounts, devices, and servers to improve the service.'),
          _section('3. How We Use Your Information',
            'We use the collected information to:\n'
            '• Provide and maintain the VPN service\n'
            '• Authenticate your account and enforce device limits\n'
            '• Process subscription purchases\n'
            '• Detect and prevent fraud and abuse\n'
            '• Improve the App and user experience\n'
            '• Comply with legal obligations'),
          _section('4. Information Sharing',
            'We do NOT sell, trade, or rent your personal information to third parties. We may share information only in the following circumstances:\n'
            '• With your explicit consent\n'
            '• To comply with a legal obligation\n'
            '• To protect our rights and safety\n'
            '• With service providers who assist in operating the App (e.g., Paystack for payment processing), subject to strict data protection agreements'),
          _section('5. Data Retention',
            'We retain your account information for as long as your account is active. If you delete your account, we will remove your personal data within 30 days. Aggregated, anonymized data may be retained indefinitely.'),
          _section('6. Data Security',
            'We implement industry-standard security measures to protect your information, including:\n'
            '• Encryption of data in transit (TLS)\n'
            '• Hashing of PINs with unique salts\n'
            '• Secure JWT-based authentication\n'
            '• Regular security audits\n\n'
            'However, no method of transmission over the Internet or electronic storage is 100% secure, and we cannot guarantee absolute security.'),
          _section('7. Your Rights',
            'You have the right to:\n'
            '• Access the personal information we hold about you\n'
            '• Request correction of inaccurate data\n'
            '• Request deletion of your account and associated data\n'
            '• Opt out of non-essential data collection\n'
            '• Withdraw consent at any time'),
          _section('8. Children\'s Privacy',
            'The App is not intended for children under 13 years of age. We do not knowingly collect personal information from children under 13. If you are a parent or guardian and believe your child has provided us with personal information, please contact us.'),
          _section('9. International Data Transfers',
            'Your information may be processed in countries other than your own. We ensure appropriate safeguards are in place for international data transfers in compliance with applicable data protection laws.'),
          _section('10. Changes to This Policy',
            'We may update this Privacy Policy from time to time. Material changes will be communicated through the App or via email. The "Last updated" date at the top indicates when this policy was last revised.'),
          _section('11. Contact Us',
            'If you have questions about this Privacy Policy or wish to exercise your rights, please contact us at securedviewvpn@protonmail.com.'),
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
