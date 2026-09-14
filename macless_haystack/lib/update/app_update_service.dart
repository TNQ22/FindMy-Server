import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:http/http.dart' as http;

/// Information about a GitHub release asset.
class ReleaseInfo {
  final String tagName;
  final String version;
  final String name;
  final String body;
  final String apkUrl;
  final String apkFileName;
  final int apkSizeBytes;
  final String apkSizeStr;
  final String publishedAt;
  final bool isNewer;
  final bool isIgnored;

  const ReleaseInfo({
    required this.tagName,
    required this.version,
    required this.name,
    required this.body,
    required this.apkUrl,
    required this.apkFileName,
    required this.apkSizeBytes,
    required this.apkSizeStr,
    required this.publishedAt,
    required this.isNewer,
    required this.isIgnored,
  });

  ReleaseInfo copyWith({
    bool? isIgnored,
  }) {
    return ReleaseInfo(
      tagName: tagName,
      version: version,
      name: name,
      body: body,
      apkUrl: apkUrl,
      apkFileName: apkFileName,
      apkSizeBytes: apkSizeBytes,
      apkSizeStr: apkSizeStr,
      publishedAt: publishedAt,
      isNewer: isNewer,
      isIgnored: isIgnored ?? this.isIgnored,
    );
  }
}

/// Service to check for new app releases from GitHub and manage version ignore state.
class AppUpdateService {
  static const String currentAppVersion = '2.1.5';
  static const String ignoredVersionKey = 'IGNORED_UPDATE_VERSION';
  static const String githubRepo = 'TNQ22/FindMy-Server';
  static const String fallbackApkUrl =
      'https://github.com/TNQ22/FindMy-Server/releases/download/v2.1.5/FindMy-Server-v2.1.5.apk';

  static ReleaseInfo? _cachedRelease;
  static DateTime? _lastFetchTime;

  /// Compares two semantic version strings (e.g. "2.1.6" and "2.1.5").
  /// Returns > 0 if v1 is newer than v2, < 0 if older, 0 if equal.
  static int compareVersions(String v1, String v2) {
    String clean(String v) {
      var s = v.trim().toLowerCase();
      if (s.startsWith('v')) s = s.substring(1);
      final dashIdx = s.indexOf('-');
      if (dashIdx != -1) s = s.substring(0, dashIdx);
      return s;
    }

    final p1 = clean(v1).split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final p2 = clean(v2).split('.').map((e) => int.tryParse(e) ?? 0).toList();

    final maxLen = p1.length > p2.length ? p1.length : p2.length;
    for (int i = 0; i < maxLen; i++) {
      final val1 = i < p1.length ? p1[i] : 0;
      final val2 = i < p2.length ? p2[i] : 0;
      if (val1 != val2) {
        return val1.compareTo(val2);
      }
    }
    return 0;
  }

  /// Returns true if [target] version is strictly newer than [base].
  static bool isNewer(String target, String base) {
    return compareVersions(target, base) > 0;
  }

  /// Returns the release tag the user chose not to be reminded about.
  static String getIgnoredVersion() {
    return Settings.getValue<String>(ignoredVersionKey, defaultValue: '')!.trim();
  }

  /// Sets the release tag to ignore so startup dialog does not appear again for this version.
  static Future<void> ignoreVersion(String tag) async {
    await Settings.setValue<String>(ignoredVersionKey, tag.trim());
    if (_cachedRelease != null && _cachedRelease!.tagName.toLowerCase() == tag.trim().toLowerCase()) {
      _cachedRelease = _cachedRelease!.copyWith(isIgnored: true);
    }
  }

  /// Clears the ignored version preference so updates are notified normally.
  static Future<void> clearIgnoredVersion() async {
    await Settings.setValue<String>(ignoredVersionKey, '');
    if (_cachedRelease != null) {
      _cachedRelease = _cachedRelease!.copyWith(isIgnored: false);
    }
  }

  /// Checks whether a given release tag is currently ignored.
  static bool isVersionIgnored(String tag) {
    final ignored = getIgnoredVersion();
    if (ignored.isEmpty) return false;
    return ignored.toLowerCase() == tag.trim().toLowerCase();
  }

  /// Fetches latest release from GitHub API, checking against [currentVersion].
  /// Caches result for 5 minutes unless [force] is true.
  static Future<ReleaseInfo?> checkUpdate({
    String currentVersion = currentAppVersion,
    bool force = false,
  }) async {
    final now = DateTime.now();
    if (!force && _cachedRelease != null && _lastFetchTime != null) {
      if (now.difference(_lastFetchTime!) < const Duration(minutes: 5)) {
        return _cachedRelease;
      }
    }

    try {
      final res = await http.get(
        Uri.parse('https://api.github.com/repos/$githubRepo/releases/latest'),
        headers: {'Accept': 'application/vnd.github.v3+json'},
      ).timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final tag = (data['tag_name'] as String? ?? '').trim();
        final name = (data['name'] as String? ?? tag).trim();
        final body = (data['body'] as String? ?? '').trim();
        final publishedAt = (data['published_at'] as String? ?? '').trim();
        final assets = data['assets'] as List<dynamic>? ?? [];

        // Find APK asset
        dynamic targetAsset;
        for (final a in assets) {
          final aName = (a['name'] as String? ?? '').toLowerCase();
          if (aName.endsWith('.apk') && aName.contains('v')) {
            targetAsset = a;
            break;
          }
        }
        targetAsset ??= assets.firstWhere(
          (a) => (a['name'] as String? ?? '').toLowerCase().endsWith('.apk'),
          orElse: () => null,
        );

        String apkUrl = fallbackApkUrl;
        String apkFileName = 'FindMy-Server-$tag.apk';
        int apkSizeBytes = 0;
        String apkSizeStr = '75 MB';

        if (targetAsset != null) {
          apkUrl = targetAsset['browser_download_url'] as String? ?? fallbackApkUrl;
          apkFileName = targetAsset['name'] as String? ?? apkFileName;
          apkSizeBytes = targetAsset['size'] as int? ?? 0;
          if (apkSizeBytes > 0) {
            apkSizeStr = '${(apkSizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
          }
        }

        final newer = isNewer(tag, currentVersion);
        final ignored = isVersionIgnored(tag);

        final release = ReleaseInfo(
          tagName: tag,
          version: tag.replaceFirst(RegExp(r'^[vV]'), ''),
          name: name,
          body: body,
          apkUrl: apkUrl,
          apkFileName: apkFileName,
          apkSizeBytes: apkSizeBytes,
          apkSizeStr: apkSizeStr,
          publishedAt: publishedAt,
          isNewer: newer,
          isIgnored: ignored,
        );

        _cachedRelease = release;
        _lastFetchTime = now;
        return release;
      }
    } catch (_) {}

    return _cachedRelease;
  }
}
