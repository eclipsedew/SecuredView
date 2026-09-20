import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import '../services/account_service.dart';
import '../services/paystack_service.dart';
import '../theme/app_theme.dart';

class PaystackPaymentScreen extends StatefulWidget {
  final String planId;
  final String planName;
  final double amount;

  const PaystackPaymentScreen({
    super.key,
    required this.planId,
    required this.planName,
    required this.amount,
  });

  @override
  State<PaystackPaymentScreen> createState() => _PaystackPaymentScreenState();
}

class _PaystackPaymentScreenState extends State<PaystackPaymentScreen> {
  bool _loading = true;
  String? _error;
  String? _authorizationUrl;
  String? _reference;

  @override
  void initState() {
    super.initState();
    _initPayment();
  }

  Future<void> _initPayment() async {
    try {
      final account = context.read<AccountService>();
      final paystack = PaystackService(account.api);

      // Prompt for email if needed
      final email = await _showEmailDialog();
      if (email == null) {
        if (mounted) Navigator.pop(context);
        return;
      }

      final result = await paystack.initializePayment(
        planId: widget.planId,
        email: email,
      );

      if (!mounted) return;

      setState(() {
        _authorizationUrl = result.authorizationUrl;
        _reference = result.reference;
        _loading = false;
      });

      // On desktop, open in browser; on mobile we'd use webview
      if (kIsWeb || Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
        await launchUrl(Uri.parse(result.authorizationUrl));
        _showVerificationSheet();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<String?> _showEmailDialog() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text(
          'Payment Email',
          style: GoogleFonts.archivo(fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter your email for the payment receipt.',
              style: GoogleFonts.publicSans(color: AppTheme.muted, fontSize: 13),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              keyboardType: TextInputType.emailAddress,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'you@example.com',
                hintStyle: GoogleFonts.publicSans(color: AppTheme.muted),
                filled: true,
                fillColor: AppTheme.paper,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(2),
                  borderSide: const BorderSide(color: AppTheme.line),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(2),
                  borderSide: const BorderSide(color: AppTheme.blue),
                ),
              ),
              style: GoogleFonts.publicSans(),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.publicSans(color: AppTheme.muted)),
          ),
          TextButton(
            onPressed: () {
              final email = controller.text.trim();
              if (email.isNotEmpty && email.contains('@') && email.contains('.')) {
                Navigator.pop(ctx, email);
              }
            },
            child: Text('Continue', style: GoogleFonts.publicSans(color: AppTheme.blue)),
          ),
        ],
      ),
    );
  }

  void _showVerificationSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _VerificationSheet(
        reference: _reference!,
        planId: widget.planId,
        planName: widget.planName,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.paper,
      appBar: AppBar(
        title: Text('Payment', style: GoogleFonts.archivo(fontWeight: FontWeight.w700)),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _loading
              ? _buildLoading()
              : _error != null
                  ? _buildError()
                  : _buildWaiting(),
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 32, height: 32,
          child: CircularProgressIndicator(strokeWidth: 2.5, color: AppTheme.blue),
        ),
        const SizedBox(height: 16),
        Text(
          'Initializing payment...',
          style: GoogleFonts.publicSans(color: AppTheme.muted, fontSize: 14),
        ),
      ],
    );
  }

  Widget _buildError() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.error_outline_rounded, color: Colors.red.shade400, size: 40),
        const SizedBox(height: 14),
        Text(
          'Payment Error',
          style: GoogleFonts.archivo(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        const SizedBox(height: 8),
        Text(
          _error!,
          style: GoogleFonts.publicSans(color: AppTheme.muted, fontSize: 13),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.blue,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
          ),
          child: Text('Go Back', style: GoogleFonts.archivo(color: Colors.white)),
        ),
      ],
    );
  }

  Widget _buildWaiting() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.open_in_browser_rounded, color: AppTheme.blue, size: 48),
        const SizedBox(height: 16),
        Text(
          'Complete Payment',
          style: GoogleFonts.archivo(fontWeight: FontWeight.w700, fontSize: 20),
        ),
        const SizedBox(height: 8),
        Text(
          'The Paystack checkout page has opened in your browser.\nComplete the payment, then tap the button below.',
          style: GoogleFonts.publicSans(color: AppTheme.muted, fontSize: 13),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: _showVerificationSheet,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.signal,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
            ),
            child: Text(
              'I Completed Payment',
              style: GoogleFonts.archivo(color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel', style: GoogleFonts.publicSans(color: AppTheme.muted)),
        ),
      ],
    );
  }
}

class _VerificationSheet extends StatefulWidget {
  final String reference;
  final String planId;
  final String planName;

  const _VerificationSheet({
    required this.reference,
    required this.planId,
    required this.planName,
  });

  @override
  State<_VerificationSheet> createState() => _VerificationSheetState();
}

class _VerificationSheetState extends State<_VerificationSheet> {
  bool _verifying = true;
  bool? _success;
  String? _message;

  @override
  void initState() {
    super.initState();
    _verify();
  }

  Future<void> _verify() async {
    try {
      final account = context.read<AccountService>();
      final paystack = PaystackService(account.api);

      // Poll for verification (user might still be paying)
      for (int i = 0; i < 30; i++) {
        final result = await paystack.verifyPayment(
          reference: widget.reference,
          planId: widget.planId,
        );

        if (result.success) {
          if (!mounted) return;
          setState(() {
            _verifying = false;
            _success = true;
            _message = '${widget.planName} activated!';
          });

          // Update local account state
          if (result.expiresAt != null) {
            await account.upgradeToPremium(
              result.expiresAt!.difference(DateTime.now()).inDays,
            );
          }
          return;
        }

        // If failed (not just "pending"), stop
        if (result.message != 'Payment pending' && result.message.isNotEmpty) {
          if (!mounted) return;
          setState(() {
            _verifying = false;
            _success = false;
            _message = result.message;
          });
          return;
        }

        await Future.delayed(const Duration(seconds: 3));
      }

      // Timeout — still pending
      if (!mounted) return;
      setState(() {
        _verifying = false;
        _success = null;
        _message = 'Verification timed out. Payment may still be processing.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _verifying = false;
        _success = false;
        _message = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(3)),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40, height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(color: AppTheme.line, borderRadius: BorderRadius.circular(2)),
          ),
          if (_verifying) ...[
            const SizedBox(
              width: 32, height: 32,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: AppTheme.blue),
            ),
            const SizedBox(height: 16),
            Text(
              'Verifying payment...',
              style: GoogleFonts.publicSans(color: AppTheme.muted, fontSize: 14),
            ),
          ] else if (_success == true) ...[
            Icon(Icons.check_circle_rounded, color: AppTheme.signal, size: 48),
            const SizedBox(height: 14),
            Text(
              _message!,
              style: GoogleFonts.archivo(fontWeight: FontWeight.w700, fontSize: 18, color: AppTheme.signal),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context); // close sheet
                  Navigator.pop(context); // close payment screen
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.blue,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
                ),
                child: Text('Done', style: GoogleFonts.archivo(color: Colors.white, fontWeight: FontWeight.w600)),
              ),
            ),
          ] else ...[
            Icon(Icons.error_outline_rounded, color: Colors.orange, size: 48),
            const SizedBox(height: 14),
            Text(
              _message ?? 'Something went wrong',
              style: GoogleFonts.publicSans(color: AppTheme.ink2, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      setState(() { _verifying = true; _success = null; });
                      _verify();
                    },
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppTheme.line2),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
                    ),
                    child: Text('Retry', style: GoogleFonts.publicSans()),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.blue,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
                    ),
                    child: Text('Close', style: GoogleFonts.archivo(color: Colors.white)),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
