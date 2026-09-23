import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
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

class _PaystackPaymentScreenState extends State<PaystackPaymentScreen>
    with WidgetsBindingObserver {
  bool _loading = true;
  String? _error;
  String? _authorizationUrl;
  String? _reference;
  bool _sheetOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initPayment();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// When the user comes back from the browser, auto-run verification
  /// (app-side "redirect" until a Paystack callback_url is configured).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (_reference == null || _loading || _error != null) return;
    if (_sheetOpen) return;
    _showVerificationSheet();
  }

  /// Open Paystack checkout in a **new browser tab** (not the current tab).
  Future<bool> _openCheckoutInNewTab(Uri uri) async {
    // Web: always target a new tab.
    if (kIsWeb) {
      return launchUrl(
        uri,
        mode: LaunchMode.platformDefault,
        webOnlyWindowName: '_blank',
      );
    }

    // Android/iOS: Chrome Custom Tab (browser UI as its own tab session).
    // Closing it returns focus to the app.
    try {
      if (await supportsLaunchMode(LaunchMode.inAppBrowserView)) {
        final ok = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
        if (ok) return true;
      }
    } catch (_) {
      // fall through to external browser
    }

    // Desktop / fallback: system browser (xdg-open / default handler) —
    // typically a new tab/window. webOnlyWindowName only affects web builds.
    return launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
      webOnlyWindowName: '_blank',
    );
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

      // Open checkout in a new browser tab.
      final opened = await _openCheckoutInNewTab(
        Uri.parse(result.authorizationUrl),
      );
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Could not open the browser. Use the button below for a new tab.',
            ),
            action: SnackBarAction(
              label: 'New Tab',
              onPressed: () => _openCheckoutInNewTab(
                Uri.parse(result.authorizationUrl),
              ),
            ),
          ),
        );
      }
      // Stay on the waiting screen; verification starts when the user
      // returns to the app (or taps "I Completed Payment").
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

  Future<void> _showVerificationSheet() async {
    if (_reference == null || _sheetOpen) return;
    _sheetOpen = true;
    try {
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => _VerificationSheet(
          reference: _reference!,
          planId: widget.planId,
          planName: widget.planName,
        ),
      );
    } finally {
      _sheetOpen = false;
    }
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
        Icon(Icons.open_in_new_rounded, color: AppTheme.blue, size: 48),
        const SizedBox(height: 16),
        Text(
          'Complete Payment',
          style: GoogleFonts.archivo(fontWeight: FontWeight.w700, fontSize: 20),
        ),
        const SizedBox(height: 8),
        Text(
          'Paystack checkout opened in a new browser tab.\n'
          'Finish payment there, then come back to this app —\n'
          'we verify automatically when you return.',
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
        OutlinedButton.icon(
          onPressed: () {
            if (_authorizationUrl != null) {
              _openCheckoutInNewTab(Uri.parse(_authorizationUrl!));
            }
          },
          icon: const Icon(Icons.open_in_new_rounded, size: 18),
          label: Text('Open in New Tab', style: GoogleFonts.publicSans()),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: AppTheme.line2),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
          ),
        ),
        const SizedBox(height: 8),
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

class _VerificationSheetState extends State<_VerificationSheet>
    with WidgetsBindingObserver {
  bool _verifying = true;
  bool? _success;
  String? _message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _verify();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Instant re-check when the user switches back from the browser tab.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _verifying) {
      _verify();
    }
  }

  Future<void> _verify() async {
    try {
      final account = context.read<AccountService>();
      final paystack = PaystackService(account.api);

      // Poll for verification (user might still be paying in the other tab)
      for (int i = 0; i < 40; i++) {
        if (!mounted || !_verifying) return;
        final result = await paystack.verifyPayment(
          reference: widget.reference,
          planId: widget.planId,
        );

        if (!mounted) return;
        if (result.success) {
          setState(() {
            _verifying = false;
            _success = true;
            _message = '${widget.planName} activated!';
          });

          // Backend already activated premium via /paystack/verify — just sync local state
          await account.syncPremiumStatus();
          return;
        }

        // If failed (not just "pending"), stop
        if (result.message != 'Payment pending' && result.message.isNotEmpty) {
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
                      setState(() {
                        _verifying = true;
                        _success = null;
                        _message = null;
                      });
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
