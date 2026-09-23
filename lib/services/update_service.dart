import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../app_version.dart';

/// Latest GitHub release published by CI (`build-N` tags).
class UpdateInfo {
  final int buildNumber;
  final String tagName;
  final String? releaseName;
  final String htmlUrl;
  final String? apkUrl;
  final String? windowsUrl;
  final String? linuxUrl;
  final String? macUrl;

  const UpdateInfo({
    required this.buildNumber,
    required this.tagName,
    this.releaseName,
    required this.htmlUrl,
    this.apkUrl,
    this.windowsUrl,
    this.linuxUrl,
    this.macUrl,
  });

  bool get isNewerThanCurrent => buildNumber > kBuildNumber;

  String get label => 'Build $buildNumber';

  /// Platform download URL for the update asset, if any.
  String? get assetUrl {
    if (kIsWeb) return htmlUrl;
    if (Platform.isAndroid) return apkUrl ?? htmlUrl;
    if (Platform.isWindows) return windowsUrl ?? htmlUrl;
    if (Platform.isLinux) return linuxUrl ?? htmlUrl;
    if (Platform.isMacOS) return macUrl ?? htmlUrl;
    return htmlUrl;
  }
}

/// Checks GitHub Releases for a newer `build-N` than this binary.
class UpdateService extends ChangeNotifier {
  UpdateService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  UpdateInfo? _pending;
  bool _checking = false;
  String? _lastError;
  bool _promptShownThisSession = false;

  UpdateInfo? get pending => _pending;
  bool get hasUpdate => _pending != null && _pending!.isNewerThanCurrent;
  bool get checking => _checking;
  String? get lastError => _lastError;
  bool get promptShownThisSession => _promptShownThisSession;

  /// Returns non-null only when a strictly newer release exists.
  Future<UpdateInfo?> check({bool force = false}) async {
    if (_checking && !force) return _pending;
    _checking = true;
    _lastError = null;
    notifyListeners();

    try {
      final uri = Uri.parse(
        'https://api.github.com/repos/$kGitHubRepo/releases/latest',
      );
      final resp = await _client.get(
        uri,
        headers: {
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'SecuredView-$kAppVersion',
        },
      ).timeout(const Duration(seconds: 12));

      if (resp.statusCode != 200) {
        _lastError = 'GitHub returned ${resp.statusCode}';
        _pending = null;
        return null;
      }

      final info = _parseRelease(resp.body);
      if (info != null && info.isNewerThanCurrent) {
        _pending = info;
      } else {
        _pending = null;
      }
      return _pending;
    } catch (e) {
      _lastError = 'Could not check for updates';
      _pending = null;
      return null;
    } finally {
      _checking = false;
      notifyListeners();
    }
  }

  UpdateInfo? _parseRelease(String body) {
    // Minimal tag parse without full JSON dependency on optional fields.
    final tag = RegExp(r'"tag_name"\s*:\s*"([^"]+)"').firstMatch(body)?[1];
    final html = RegExp(r'"html_url"\s*:\s*"([^"]+)"').firstMatch(body)?[1];
    final name = RegExp(r'"name"\s*:\s*"([^"]*)"').firstMatch(body)?[1];
    if (tag == null) return null;

    final build = int.tryParse(tag.replaceFirst(RegExp(r'^build-'), ''));
    if (build == null) return null;

    String? assetUrl(String fileName) {
      // Prefer browser_download_url for this asset name.
      final re = RegExp(
        '"browser_download_url"\\s*:\\s*"([^"]*${RegExp.escape(fileName)})"',
      );
      return re.firstMatch(body)?[1];
    }

    return UpdateInfo(
      buildNumber: build,
      tagName: tag,
      releaseName: name,
      htmlUrl: html ?? 'https://github.com/$kGitHubRepo/releases/latest',
      apkUrl: assetUrl('app-release.apk'),
      windowsUrl: assetUrl('SecuredView-Windows.zip'),
      linuxUrl: assetUrl('SecuredView-Linux.tar.gz'),
      macUrl: assetUrl('SecuredView-macOS.zip'),
    );
  }

  /// Opens the platform update package (APK / zip / tarball) so the user
  /// can install it. Desktop falls back to the release page if no asset.
  Future<bool> install(UpdateInfo info) async {
    final url = info.assetUrl;
    if (url == null) return false;
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  void markPromptShown() {
    _promptShownThisSession = true;
    notifyListeners();
  }

  void clearPending() {
    _pending = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }
}
