import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Desktop MASQUE tunnel via the `usque` CLI (Cloudflare WARP Connect-IP).
///
/// Windows/Linux: runs the bundled `usque` binary next to the app
/// (register once → `usque run` with TUN + auto_route). Requires admin
/// on Windows for the Wintun adapter (runner manifest requests elevation).
class UsqueService {
  Process? _process;
  final _exitController = StreamController<int?>.broadcast();
  int? _lastExit;
  String? _configPath;
  String? _binPath;
  bool _registering = false;

  bool get isRunning => _process != null;

  /// Absolute path to usque / usque.exe (bundled next to the exe, else PATH).
  String get binaryName => Platform.isWindows ? 'usque.exe' : 'usque';

  String? findBinary() {
    if (_binPath != null) return _binPath;
    final exe = File(Platform.resolvedExecutable);
    final dir = exe.parent.path;
    final local = '$dir${Platform.pathSeparator}$binaryName';
    if (File(local).existsSync()) {
      _binPath = local;
      return _binPath;
    }
    // Dev / PATH fallback
    _binPath = binaryName;
    return _binPath;
  }

  bool get binaryExists {
    final bin = findBinary();
    if (bin == null) return false;
    if (bin.contains(Platform.pathSeparator)) return File(bin).existsSync();
    // Bare name — assume PATH
    return true;
  }

  String get configPath {
    if (_configPath != null) return _configPath!;
    final String base;
    if (Platform.isWindows) {
      base = Platform.environment['LOCALAPPDATA'] ??
          Platform.environment['USERPROFILE'] ??
          Directory.current.path;
    } else {
      base = Platform.environment['HOME'] ?? Directory.current.path;
    }
    final dir = Directory('$base${Platform.pathSeparator}SecuredView');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    _configPath = '${dir.path}${Platform.pathSeparator}usque.json';
    return _configPath!;
  }

  bool get hasIdentity {
    try {
      final f = File(configPath);
      if (!f.existsSync()) return false;
      final data = jsonDecode(f.readAsStringSync());
      final key = (data['account'] ?? data)['private_key'] as String?;
      return key != null && key.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> ensureRegistered() async {
    if (hasIdentity) return;
    if (_registering) return;
    _registering = true;
    try {
      final bin = findBinary();
      if (bin == null) throw Exception('usque binary not found');
      final result = await Process.run(
        bin,
        [
          'register',
          '-c',
          configPath,
          '-a',
          '-n',
          'SecuredView',
          '-m',
          'PC',
        ],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      if (result.exitCode != 0 || !hasIdentity) {
        final err = (result.stderr ?? result.stdout ?? '').toString();
        throw Exception('WARP MASQUE registration failed: $err');
      }
    } finally {
      _registering = false;
    }
  }

  /// Start `usque run` (TUN + auto_route MASQUE). Returns when the process
  /// is alive for a short warm-up (routes/DNS install).
  Future<void> connect({Duration warmup = const Duration(seconds: 3)}) async {
    if (_process != null) return;
    await ensureRegistered();
    final bin = findBinary();
    if (bin == null) throw Exception('usque binary not found');
    if (!File(bin).existsSync() && bin.contains(Platform.pathSeparator)) {
      throw Exception('usque not bundled at $bin');
    }

    final process = await Process.start(
      bin,
      ['run', '-c', configPath],
      mode: ProcessStartMode.normal,
    );
    _process = process;
    _lastExit = null;

    process.exitCode.then((code) {
      _lastExit = code;
      _exitController.add(code);
      if (identical(_process, process)) {
        _process = null;
      }
    });

    // Surface early fatal errors (not admin, bad config, etc.)
    final errBuf = StringBuffer();
    process.stderr.transform(utf8.decoder).listen((chunk) {
      errBuf.write(chunk);
      if (errBuf.length > 8000) errBuf.clear();
    });
    process.stdout.transform(utf8.decoder).listen((_) {});

    await Future.delayed(warmup);

    if (_process == null) {
      final code = _lastExit;
      final msg = errBuf.toString().trim();
      throw Exception(
        code == 1 && msg.contains('root/administrator')
            ? 'MASQUE TUN requires administrator. Run SecuredView as admin.'
            : 'usque exited early (code $code)${msg.isEmpty ? '' : ': $msg'}',
      );
    }
  }

  Future<void> disconnect() async {
    final p = _process;
    _process = null;
    if (p == null) return;
    p.kill(ProcessSignal.sigterm);
    // Force after grace
    await Future.delayed(const Duration(milliseconds: 800));
    if (_lastExit == null) {
      p.kill(ProcessSignal.sigkill);
    }
    // Windows: make sure no orphaned usque remains
    if (Platform.isWindows) {
      try {
        await Process.run('taskkill', ['/IM', 'usque.exe', '/F']);
      } catch (_) {}
    }
    await Future.delayed(const Duration(milliseconds: 300));
  }

  /// True if the tunnel process is still alive.
  bool isConnected() {
    if (_process != null) return true;
    if (Platform.isWindows) {
      // Orphan check (e.g. after app restart)
      try {
        final r = Process.runSync(
          'tasklist',
          ['/FI', 'IMAGENAME eq usque.exe', '/NH'],
        );
        final out = r.stdout.toString();
        return out.contains('usque.exe');
      } catch (_) {
        return false;
      }
    }
    return false;
  }

  Future<Map<String, dynamic>?> status() async {
    final up = isConnected();
    return {
      'state': up ? 'connected' : 'stopped',
      'mode': 'masque',
      'binary': findBinary(),
      'config': configPath,
      'hasIdentity': hasIdentity,
    };
  }

  void dispose() {
    unawaited(disconnect());
    _exitController.close();
  }
}
