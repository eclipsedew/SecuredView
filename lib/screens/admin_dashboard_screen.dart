import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/account_service.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/securedview_logo.dart';

/// In-app admin dashboard — shown instead of the user UI when the logged-in
/// account has is_admin (seeded account 0595184915).
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  AccountService? _svc;
  int _tab = 0;
  bool _loading = false;
  List<AccountInfo> _accounts = [];
  Map<String, dynamic>? _stats;
  String _query = '';

  // Create form
  String _newType = 'normal';
  bool _creating = false;
  final _nameCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  final _daysCtrl = TextEditingController(text: '30');

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_svc == null) {
      _svc = context.read<AccountService>();
      _refresh();
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _pinCtrl.dispose();
    _daysCtrl.dispose();
    super.dispose();
  }

  ApiService get _api => _svc!.api;

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.publicSans()),
      backgroundColor: AppTheme.ink,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
      duration: const Duration(seconds: 3),
    ));
  }

  Future<void> _refresh() async {
    setState(() { _loading = true; });
    try {
      final accounts = await _api.adminListAccounts();
      Map<String, dynamic>? stats;
      try {
        final resp = await _api.get('/api/admin/stats');
        if (resp.statusCode == 200) {
          stats = jsonDecode(resp.body) as Map<String, dynamic>;
        }
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _accounts = accounts;
        _stats = stats;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _toast(e is ApiException ? e.message : 'Failed to load accounts');
    }
  }

  // ── Create ───────────────────────────────────────────────
  Future<void> _create() async {
    final days = int.tryParse(_daysCtrl.text.trim());
    if (_newType == 'premium' && (days == null || days < 1)) {
      _toast('Enter the number of premium days');
      return;
    }
    final pin = _pinCtrl.text.trim();
    if (pin.isNotEmpty && !RegExp(r'^\d{4}$').hasMatch(pin)) {
      _toast('PIN must be exactly 4 digits (or leave empty to auto-generate)');
      return;
    }
    setState(() => _creating = true);
    try {
      final res = await _api.adminCreateAccount(
        accountType: _newType,
        pin: pin.isEmpty ? null : pin,
        displayName: _nameCtrl.text.trim(),
        days: _newType == 'premium' ? days : null,
      );
      if (!mounted) return;
      setState(() => _creating = false);
      _nameCtrl.clear();
      _pinCtrl.clear();
      await _showCreatedDialog(res);
      _refresh();
    } catch (e) {
      if (!mounted) return;
      setState(() => _creating = false);
      _toast(e is ApiException ? e.message : 'Failed to create account');
    }
  }

  Future<void> _showCreatedDialog(Map<String, dynamic> res) async {
    final id = res['account_id'] ?? '';
    final pin = res['pin'] ?? '';
    final note = res['note'] ?? '';
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        title: Text('Account created',
            style: GoogleFonts.archivo(fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _copyRow('Account ID', '$id'),
            const SizedBox(height: 14),
            _copyRow('PIN', '$pin'),
            if (note.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(note,
                  style: GoogleFonts.publicSans(
                      fontSize: 12.5, color: AppTheme.textMed)),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Done',
                style: GoogleFonts.archivo(
                    color: AppTheme.accent, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _copyRow(String label, String value) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: GoogleFonts.publicSans(
                      fontSize: 11, color: AppTheme.textLow)),
              const SizedBox(height: 2),
              SelectableText(value,
                  style: GoogleFonts.jetBrainsMono(
                      fontSize: 19, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Copy',
          icon: const Icon(Icons.copy_rounded, size: 18),
          color: AppTheme.accent,
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: value));
            if (mounted) _toast('$label copied');
          },
        ),
      ],
    );
  }

  // ── User actions ─────────────────────────────────────────
  Future<void> _grant(AccountInfo acc, int? days) async {
    try {
      await _api.adminGrantPremium(acc.id, days: days);
      _toast(days == null
          ? '${acc.id} → premium until 2099'
          : '${acc.id} → +$days days premium');
      _refresh();
    } catch (e) {
      _toast(e is ApiException ? e.message : 'Grant failed');
    }
  }

  void _grantSheet(AccountInfo acc) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(4))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Row(
                children: [
                  Text('Grant premium',
                      style: GoogleFonts.archivo(
                          fontWeight: FontWeight.w700, fontSize: 16)),
                  const SizedBox(width: 8),
                  Text(acc.id,
                      style: GoogleFonts.jetBrainsMono(
                          fontSize: 12, color: AppTheme.textLow)),
                ],
              ),
            ),
            for (final d in const [7, 30, 90, 365])
              ListTile(
                dense: true,
                leading: const Icon(Icons.calendar_month_outlined,
                    size: 18, color: AppTheme.accent),
                title: Text('$d days',
                    style: GoogleFonts.publicSans(fontSize: 14)),
                onTap: () { Navigator.pop(ctx); _grant(acc, d); },
              ),
            ListTile(
              dense: true,
              leading: const Icon(Icons.all_inclusive_rounded,
                  size: 18, color: AppTheme.success),
              title: Text('Unlimited (until 2099)',
                  style: GoogleFonts.publicSans(fontSize: 14)),
              onTap: () { Navigator.pop(ctx); _grant(acc, null); },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _delete(AccountInfo acc) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        title: Text('Delete account?',
            style: GoogleFonts.archivo(fontWeight: FontWeight.w700)),
        content: Text(
          '${acc.id} and its devices will be removed. Trial claims are kept '
          'so the device cannot re-claim a free trial.',
          style: GoogleFonts.publicSans(fontSize: 13.5),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel',
                  style: GoogleFonts.publicSans(color: AppTheme.textMed))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Delete',
                  style: GoogleFonts.publicSans(
                      color: AppTheme.error,
                      fontWeight: FontWeight.w600))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _api.adminDeleteAccount(acc.id);
      _toast('${acc.id} deleted');
      _refresh();
    } catch (e) {
      _toast(e is ApiException ? e.message : 'Delete failed');
    }
  }

  // ── Status helpers ───────────────────────────────────────
  static DateTime? _utc(String? iso) {
    if (iso == null || iso.isEmpty) return null;
    var s = iso;
    if (!s.endsWith('Z') && !s.contains('+')) s = '$s' 'Z';
    return DateTime.tryParse(s);
  }

  String _status(AccountInfo a) {
    final now = DateTime.now().toUtc();
    if (a.isTrial) {
      final end = _utc(a.trialEndsAt?.toIso8601String());
      if (end == null) return 'Trial pending — starts on first login';
      if (end.isAfter(now)) {
        final left = end.difference(now);
        final d = left.inDays;
        final h = left.inHours % 24;
        return 'Trial active — ${d > 0 ? '${d}d ' : ''}$h h left';
      }
      return 'Trial expired';
    }
    if (a.isPremium) {
      final exp = _utc(a.premiumExpiresAt?.toIso8601String());
      if (exp == null) return 'Premium active';
      if (exp.isAfter(now)) {
        return 'Premium until ${exp.toIso8601String().substring(0, 10)}';
      }
      return 'Premium expired';
    }
    if (a.accountType == 'normal' || a.accountType == 'special') {
      return 'Trial pending — starts on first login';
    }
    return 'No active plan';
  }

  Color _typeColor(String t) {
    switch (t) {
      case 'premium': return AppTheme.success;
      case 'special': return const Color(0xFF7C3AED);
      case 'legacy': return AppTheme.textLow;
      case 'admin': return AppTheme.ink;
      default: return AppTheme.accent;
    }
  }

  String _typeLabel(String t) {
    switch (t) {
      case 'premium': return 'PREMIUM';
      case 'special': return 'SPECIAL';
      case 'legacy': return 'LEGACY';
      case 'admin': return 'ADMIN';
      default: return 'NORMAL';
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = context.watch<AccountService>();
    final user = account.account;

    return Scaffold(
      backgroundColor: AppTheme.paper,
      body: SafeArea(
        child: Column(
          children: [
            _header(user?.accountId ?? account.api.accountId ?? ''),
            _tabBar(),
            Expanded(
              child: _tab == 0 ? _buildCreate() : _buildUsers(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(String accountId) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
      color: AppTheme.surface,
      child: Row(
        children: [
          const SecuredViewLogo(size: 30),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('SecuredView Admin',
                    style: GoogleFonts.archivo(
                        fontWeight: FontWeight.w700, fontSize: 16)),
                Text(accountId,
                    style: GoogleFonts.jetBrainsMono(
                        fontSize: 11, color: AppTheme.textLow)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout_rounded, size: 20),
            color: AppTheme.textMed,
            onPressed: () async {
              await context.read<AccountService>().logout();
            },
          ),
        ],
      ),
    );
  }

  Widget _tabBar() {
    Widget seg(int i, String label, IconData icon) {
      final active = _tab == i;
      return Expanded(
        child: InkWell(
          onTap: () => setState(() => _tab = i),
          child: Container(
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? AppTheme.blueWash : Colors.transparent,
              border: Border(
                bottom: BorderSide(
                    color: active ? AppTheme.blue : AppTheme.line,
                    width: 2),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon,
                    size: 16,
                    color: active ? AppTheme.blue : AppTheme.textLow),
                const SizedBox(width: 6),
                Text(label,
                    style: GoogleFonts.archivo(
                        fontSize: 13.5,
                        fontWeight:
                            active ? FontWeight.w700 : FontWeight.w500,
                        color: active ? AppTheme.blue : AppTheme.textMed)),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      color: AppTheme.surface,
      child: Row(children: [
        seg(0, 'Create account', Icons.person_add_alt_1_rounded),
        seg(1, 'Users', Icons.people_alt_outlined),
      ]),
    );
  }

  // ── Create tab ───────────────────────────────────────────
  Widget _buildCreate() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: AppTheme.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Account class',
                style: GoogleFonts.archivo(
                    fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 4),
            Text('No signup — you create every account here.',
                style: GoogleFonts.publicSans(
                    fontSize: 12.5, color: AppTheme.textLow)),
            const SizedBox(height: 12),
            _typeOption('normal', 'Normal',
                '3-day free trial — starts on first login'),
            _typeOption('special', 'Special',
                '15-day free trial — starts on first login'),
            _typeOption('premium', 'Premium',
                'Active immediately — you choose the number of days'),
            if (_newType == 'premium') ...[
              const SizedBox(height: 14),
              Text('Premium days',
                  style: GoogleFonts.publicSans(
                      fontSize: 12, color: AppTheme.textMed)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final d in const [7, 30, 90, 365])
                    ChoiceChip(
                      label: Text('$d d'),
                      selected: _daysCtrl.text.trim() == '$d',
                      onSelected: (_) =>
                          setState(() => _daysCtrl.text = '$d'),
                      selectedColor: AppTheme.blueWash,
                      labelStyle: GoogleFonts.publicSans(
                          fontSize: 12.5,
                          color: AppTheme.blue,
                          fontWeight: FontWeight.w600),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: 140,
                child: TextField(
                  controller: _daysCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: 'Days',
                    isDense: true,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(3)),
                  ),
                  style: GoogleFonts.publicSans(fontSize: 14),
                ),
              ),
            ],
            const SizedBox(height: 18),
            TextField(
              controller: _nameCtrl,
              maxLength: 40,
              decoration: InputDecoration(
                labelText: 'Display name (optional)',
                counterText: '',
                isDense: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(3)),
              ),
              style: GoogleFonts.publicSans(fontSize: 14),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _pinCtrl,
              keyboardType: TextInputType.number,
              maxLength: 4,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'PIN (optional — auto-generated if empty)',
                helperText: 'Give this PIN to the user with the account ID',
                helperMaxLines: 2,
                counterText: '',
                isDense: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(3)),
              ),
              style: GoogleFonts.publicSans(fontSize: 14),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton(
                onPressed: _creating ? null : _create,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.blue,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(2)),
                ),
                child: _creating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text('Create account',
                        style: GoogleFonts.archivo(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _typeOption(String value, String title, String subtitle) {
    final selected = _newType == value;
    return InkWell(
      onTap: () => setState(() => _newType = value),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: selected ? AppTheme.blueWash : AppTheme.bgElevated,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
              color: selected ? AppTheme.blue : AppTheme.line, width: 1.2),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              size: 18,
              color: selected ? AppTheme.blue : AppTheme.textLow,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: GoogleFonts.archivo(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: selected
                              ? AppTheme.blue
                              : AppTheme.textHigh)),
                  Text(subtitle,
                      style: GoogleFonts.publicSans(
                          fontSize: 12, color: AppTheme.textMed)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Users tab ────────────────────────────────────────────
  Widget _buildUsers() {
    final q = _query.trim().toLowerCase();
    final list = _accounts.where((a) {
      if (q.isEmpty) return true;
      return a.id.toLowerCase().contains(q) ||
          a.displayName.toLowerCase().contains(q);
    }).toList();

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_stats != null) ...[
            Row(children: [
              _statCard('Accounts', '${_stats!['total_accounts'] ?? 0}'),
              const SizedBox(width: 8),
              _statCard('Premium', '${_stats!['total_premium_accounts'] ?? 0}'),
              const SizedBox(width: 8),
              _statCard('Devices on', '${_stats!['total_active_devices'] ?? 0}'),
            ]),
            const SizedBox(height: 12),
          ],
          Row(children: [
            Expanded(
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: 'Search ID or name…',
                  hintStyle: GoogleFonts.publicSans(fontSize: 13),
                  prefixIcon: const Icon(Icons.search_rounded, size: 18),
                  isDense: true,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(3)),
                ),
                style: GoogleFonts.publicSans(fontSize: 13.5),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Refresh',
              onPressed: _refresh,
              icon: _loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh_rounded, size: 20),
              color: AppTheme.textMed,
            ),
          ]),
          const SizedBox(height: 12),
          if (list.isEmpty && !_loading)
            Container(
              padding: const EdgeInsets.all(28),
              alignment: Alignment.center,
              child: Text('No accounts yet — create one above',
                  style: GoogleFonts.publicSans(color: AppTheme.textLow)),
            ),
          for (final a in list) _userCard(a),
        ],
      ),
    );
  }

  Widget _statCard(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: AppTheme.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                style: GoogleFonts.archivo(
                    fontWeight: FontWeight.w700, fontSize: 18)),
            Text(label,
                style: GoogleFonts.publicSans(
                    fontSize: 11, color: AppTheme.textLow)),
          ],
        ),
      ),
    );
  }

  Widget _userCard(AccountInfo a) {
    final color = _typeColor(a.accountType);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 8),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppTheme.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onLongPress: () async {
                    await Clipboard.setData(ClipboardData(text: a.id));
                    if (mounted) _toast('Account ID copied');
                  },
                  child: Text(a.id,
                      style: GoogleFonts.jetBrainsMono(
                          fontWeight: FontWeight.w700, fontSize: 14.5)),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(2),
                  border: Border.all(color: color.withValues(alpha: 0.4)),
                ),
                child: Text(_typeLabel(a.accountType),
                    style: GoogleFonts.archivo(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                        color: color)),
              ),
              const SizedBox(width: 6),
            ],
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              Expanded(
                child: Text(
                  a.displayName == 'User' || a.displayName.isEmpty
                      ? _status(a)
                      : '${a.displayName} · ${_status(a)}',
                  style: GoogleFonts.publicSans(
                      fontSize: 12.5,
                      color: _status(a).contains('expired')
                          ? AppTheme.error
                          : AppTheme.textMed),
                ),
              ),
              Text('${a.deviceCount}/${a.maxDevices} devices',
                  style: GoogleFonts.publicSans(
                      fontSize: 11.5, color: AppTheme.textLow)),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: () => _grantSheet(a),
                icon: const Icon(Icons.workspace_premium_outlined, size: 16),
                label: Text('Grant',
                    style: GoogleFonts.publicSans(
                        fontSize: 12.5, fontWeight: FontWeight.w600)),
                style: TextButton.styleFrom(
                    foregroundColor: AppTheme.success,
                    visualDensity: VisualDensity.compact),
              ),
              TextButton.icon(
                onPressed: () => _delete(a),
                icon: const Icon(Icons.delete_outline_rounded, size: 16),
                label: Text('Delete',
                    style: GoogleFonts.publicSans(
                        fontSize: 12.5, fontWeight: FontWeight.w600)),
                style: TextButton.styleFrom(
                    foregroundColor: AppTheme.error,
                    visualDensity: VisualDensity.compact),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
