import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:universal_html/html.dart' as html;

/// Dialog that displays Android APK download QR Code, direct link, and GitHub release page.
class AppDownloadDialog extends StatefulWidget {
  const AppDownloadDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (ctx) => const AppDownloadDialog(),
    );
  }

  @override
  State<AppDownloadDialog> createState() => _AppDownloadDialogState();
}

class _AppDownloadDialogState extends State<AppDownloadDialog> {
  static const String fallbackApkUrl =
      'https://github.com/TNQ22/FindMy-Server/releases/download/v2.1.5/FindMy-Server-v2.1.5.apk';
  static const String githubReleasesUrl =
      'https://github.com/TNQ22/FindMy-Server/releases/latest';

  String _directApkUrl = fallbackApkUrl;
  String _apkFileName = 'FindMy-Server-v2.1.5.apk';
  String? _apkSizeStr = '71.6 MB';
  String? _versionTag = 'v2.1.5';

  @override
  void initState() {
    super.initState();
    _fetchLatestReleaseInfo();
  }

  /// Automatically queries GitHub API for the latest release asset with exact version name.
  Future<void> _fetchLatestReleaseInfo() async {
    try {
      final res = await http.get(
        Uri.parse('https://api.github.com/repos/TNQ22/FindMy-Server/releases/latest'),
        headers: {'Accept': 'application/vnd.github.v3+json'},
      ).timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final tag = data['tag_name'] as String? ?? '';
        final assets = data['assets'] as List<dynamic>? ?? [];

        // Prioritize APK with version name (e.g. FindMy-Server-v2.1.5.apk)
        dynamic targetAsset;
        for (final a in assets) {
          final name = a['name'] as String? ?? '';
          if (name.endsWith('.apk') && name.contains('v')) {
            targetAsset = a;
            break;
          }
        }
        targetAsset ??= assets.firstWhere(
          (a) => (a['name'] as String? ?? '').endsWith('.apk'),
          orElse: () => null,
        );

        if (targetAsset != null && mounted) {
          final downloadUrl = targetAsset['browser_download_url'] as String;
          final fileName = targetAsset['name'] as String;
          final sizeBytes = targetAsset['size'] as int? ?? 0;
          final sizeMb = (sizeBytes / (1024 * 1024)).toStringAsFixed(1);

          setState(() {
            _directApkUrl = downloadUrl;
            _apkFileName = fileName;
            _apkSizeStr = '$sizeMb MB';
            _versionTag = tag;
          });
          return;
        }
      }
    } catch (_) {}
  }

  String get _qrImageUrl =>
      'https://api.qrserver.com/v1/create-qr-code/?size=240x240&margin=4&data=${Uri.encodeComponent(_directApkUrl)}';

  Future<void> _openUrl(String url) async {
    if (kIsWeb) {
      try {
        html.window.open(url, '_blank');
        return;
      } catch (_) {}
    }
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AlertDialog(
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.android, color: Colors.green, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Tải ứng dụng Android (APK)',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
                if (_versionTag != null)
                  Text(
                    'Phiên bản mới nhất: $_versionTag',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.teal,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // QR Code Container
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                  border: Border.all(color: Colors.teal.shade200, width: 1.5),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        _qrImageUrl,
                        width: 190,
                        height: 190,
                        fit: BoxFit.contain,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return const SizedBox(
                            width: 190,
                            height: 190,
                            child: Center(
                              child: CircularProgressIndicator(color: Colors.teal),
                            ),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) => const SizedBox(
                          width: 190,
                          height: 190,
                          child: Center(
                            child: Text(
                              'Không thể tải mã QR',
                              style: TextStyle(color: Colors.grey, fontSize: 12),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '📷 Quét bằng camera để tải trực tiếp $_apkFileName',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.teal,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Direct link and copy row
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isDark ? Colors.white12 : Colors.black12,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.file_download, size: 18, color: Colors.teal),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _directApkUrl,
                        style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 18),
                      tooltip: 'Sao chép liên kết tải APK trực tiếp',
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: _directApkUrl),
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Đã sao chép link tải trực tiếp APK!'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Action button 1: Download APK directly
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                    elevation: 2,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.download, size: 20),
                  label: Text(
                    'Tải $_apkFileName${_apkSizeStr != null ? ' ($_apkSizeStr)' : ''}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                  onPressed: () => _openUrl(_directApkUrl),
                ),
              ),
              const SizedBox(height: 8),

              // Action button 2: Open GitHub Releases page
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: isDark ? Colors.grey.shade300 : Colors.black87,
                    side: BorderSide(color: isDark ? Colors.white24 : Colors.black26),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text(
                    'Xem trên GitHub Releases',
                    style: TextStyle(fontSize: 13),
                  ),
                  onPressed: () => _openUrl(githubReleasesUrl),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Đóng'),
        ),
      ],
    );
  }
}
