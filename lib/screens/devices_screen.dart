import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../services/account_service.dart';
import '../theme/app_theme.dart';

class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});
  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  late AccountService _account;
  List<_DeviceEntry> _devices = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _account = context.read<AccountService>();
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    setState(() { _loading = true; _error = null; });
    try {
      final devices = await _account.api.getDevices();
      final currentDeviceId = _account.api.deviceId;
      final prefs = await _getDeviceNames();

      _devices = devices.map((d) {
        final name = d.id == currentDeviceId
            ? 'This Device'
            : (prefs[d.id] ?? d.deviceName);
        return _DeviceEntry(
          id: d.id,
          name: name,
          platform: d.platform,
          isThisDevice: d.id == currentDeviceId,
          lastSeen: d.lastSeen,
          isActive: d.isActive,
        );
      }).toList();
    } catch (e) {
      _error = 'Failed to load devices';
    }
    setState(() { _loading = false; });
  }

  Future<Map<String, String>> _getDeviceNames() async {
    return await _account.api.getDeviceNames();
  }

  Future<void> _saveDeviceName(String deviceId, String name) async {
    await _account.api.saveDeviceName(deviceId, name);
  }

  Future<void> _removeDevice(String deviceId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove Device', style: GoogleFonts.archivo(fontWeight: FontWeight.w700)),
        content: Text(
          'This device will be logged out and need to re-login.',
          style: GoogleFonts.publicSans(color: AppTheme.muted, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.publicSans(color: AppTheme.muted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            child: Text('Remove', style: GoogleFonts.archivo(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _account.api.removeDevice(deviceId);
      await _loadDevices();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Device removed', style: GoogleFonts.publicSans()), backgroundColor: AppTheme.ink),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to remove device', style: GoogleFonts.publicSans()), backgroundColor: AppTheme.error),
        );
      }
    }
  }

  Future<void> _renameDevice(String deviceId, String currentName) async {
    final controller = TextEditingController(text: currentName);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Rename Device', style: GoogleFonts.archivo(fontWeight: FontWeight.w700)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: GoogleFonts.publicSans(color: AppTheme.ink, fontSize: 15),
          decoration: InputDecoration(
            hintText: 'Device name',
            hintStyle: GoogleFonts.publicSans(color: AppTheme.muted),
            filled: true,
            fillColor: AppTheme.paper,
            border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(2)), borderSide: BorderSide(color: AppTheme.line2)),
            focusedBorder: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(2)), borderSide: BorderSide(color: AppTheme.blue, width: 1.5)),
            enabledBorder: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(2)), borderSide: BorderSide(color: AppTheme.line2)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: GoogleFonts.publicSans(color: AppTheme.muted))),
          TextButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) Navigator.pop(ctx, name);
            },
            child: Text('Save', style: GoogleFonts.publicSans(color: AppTheme.blue, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (newName != null && newName != currentName) {
      await _saveDeviceName(deviceId, newName);
      await _loadDevices();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPremium = _account.isPremiumActive;
    // Trial / paid plan: 3 devices. No active plan: management only (1).
    final maxDevices = isPremium ? 3 : 1;
    final currentCount = _devices.length;

    return Scaffold(
      backgroundColor: AppTheme.paper,
      appBar: AppBar(
        title: Text('Devices', style: GoogleFonts.archivo(fontWeight: FontWeight.w700)),
        leading: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.blue))
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_error!, style: GoogleFonts.publicSans(color: AppTheme.muted)),
                      const SizedBox(height: 16),
                      TextButton(onPressed: _loadDevices, child: const Text('Retry')),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Device counter
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        border: Border.all(color: AppTheme.line2),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.devices_rounded, color: AppTheme.blue, size: 22),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '$currentCount of $maxDevices devices',
                                  style: GoogleFonts.archivo(color: AppTheme.ink, fontSize: 15, fontWeight: FontWeight.w600),
                                ),
                                Text(
                                  isPremium ? 'Plan allows up to 3 devices' : 'Subscribe for up to 3 devices',
                                  style: GoogleFonts.publicSans(color: AppTheme.muted, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: currentCount >= maxDevices
                                  ? AppTheme.error.withValues(alpha: 0.1)
                                  : AppTheme.signal.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(2),
                            ),
                            child: Text(
                              '${maxDevices - currentCount} left',
                              style: GoogleFonts.jetBrainsMono(
                                color: currentCount >= maxDevices ? AppTheme.error : AppTheme.signal,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Section label
                    Text(
                      'LINKED DEVICES',
                      style: GoogleFonts.jetBrainsMono(
                        color: AppTheme.muted,
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 1.7,
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Device list
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: AppTheme.line2),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Column(
                        children: [
                          for (int i = 0; i < _devices.length; i++) ...[
                            _buildDeviceTile(_devices[i]),
                            if (i < _devices.length - 1)
                              const Divider(height: 1, color: AppTheme.line, indent: 0, endIndent: 0),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Info note
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.blueWash,
                        border: Border.all(color: AppTheme.blue.withValues(alpha: 0.15)),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline_rounded, color: AppTheme.blue, size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Each device gets a fun name for easy identification. Tap a name to rename it. Your 16-digit Account ID is shared across all linked devices.',
                              style: GoogleFonts.publicSans(color: AppTheme.ink2, fontSize: 12, height: 1.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildDeviceTile(_DeviceEntry device) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: device.isThisDevice
            ? null
            : () => _showDeviceActions(device),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              // Device icon
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: device.isThisDevice ? AppTheme.blueWash : AppTheme.paper,
                  borderRadius: BorderRadius.circular(2),
                  border: Border.all(
                    color: device.isThisDevice ? AppTheme.blue.withValues(alpha: 0.3) : AppTheme.line,
                  ),
                ),
                child: Center(
                  child: _platformIcon(device.platform, device.isThisDevice),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            device.name,
                            style: GoogleFonts.archivo(
                              color: AppTheme.ink,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (device.isThisDevice) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.signal.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(2),
                            ),
                            child: Text(
                              'THIS',
                              style: GoogleFonts.jetBrainsMono(
                                color: AppTheme.signal,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      device.platform.toUpperCase(),
                      style: GoogleFonts.jetBrainsMono(
                        color: AppTheme.muted,
                        fontSize: 10,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (!device.isThisDevice)
                Icon(Icons.chevron_right_rounded, color: AppTheme.line2, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  Widget _platformIcon(String platform, bool isCurrent) {
    final color = isCurrent ? AppTheme.blue : AppTheme.muted;
    switch (platform.toLowerCase()) {
      case 'android':
        return Icon(Icons.android_rounded, color: color, size: 18);
      case 'ios':
        return Icon(Icons.phone_iphone_rounded, color: color, size: 18);
      case 'linux':
        return Icon(Icons.computer_rounded, color: color, size: 18);
      case 'windows':
        return Icon(Icons.desktop_windows_rounded, color: color, size: 18);
      case 'macos':
        return Icon(Icons.laptop_mac_rounded, color: color, size: 18);
      default:
        return Icon(Icons.device_unknown_rounded, color: color, size: 18);
    }
  }

  void _showDeviceActions(_DeviceEntry device) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(3)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: AppTheme.line, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            Text(device.name, style: GoogleFonts.archivo(color: AppTheme.ink, fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(device.platform.toUpperCase(), style: GoogleFonts.jetBrainsMono(color: AppTheme.muted, fontSize: 11, letterSpacing: 1.5)),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: OutlinedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _renameDevice(device.id, device.name);
                },
                child: Text('Rename', style: GoogleFonts.archivo(fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _removeDevice(device.id);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.error,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
                ),
                child: Text('Remove Device', style: GoogleFonts.archivo(fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _DeviceEntry {
  final String id;
  final String name;
  final String platform;
  final bool isThisDevice;
  final DateTime? lastSeen;
  final bool isActive;

  _DeviceEntry({
    required this.id,
    required this.name,
    required this.platform,
    required this.isThisDevice,
    this.lastSeen,
    required this.isActive,
  });
}
