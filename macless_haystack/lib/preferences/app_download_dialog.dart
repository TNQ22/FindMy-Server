import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:universal_html/html.dart' as html;

/// Dialog that displays Android APK download QR Code, direct link, and GitHub release page.
class AppDownloadDialog extends StatelessWidget {
  const AppDownloadDialog({super.key});

  /// Permanent direct link that GitHub automatically redirects to the latest release APK file.
  static const String directApkUrl =
      'https://github.com/TNQ22/FindMy-Server/releases/latest/download/FindMy-Server.apk';

  /// GitHub releases web page (for viewing changelog, older versions, etc.)
  static const String githubReleasesUrl =
      'https://github.com/TNQ22/FindMy-Server/releases/latest';

  /// QR code pointing directly to the APK download stream
  static final String qrImageUrl =
      'https://api.qrserver.com/v1/create-qr-code/?size=240x240&margin=4&data=${Uri.encodeComponent(directApkUrl)}';

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (ctx) => const AppDownloadDialog(),
    );
  }

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
          const Expanded(
            child: Text(
              'Tải ứng dụng Android (APK)',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
                        qrImageUrl,
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
                    const Text(
                      '📷 Quét bằng camera điện thoại để tải trực tiếp APK',
                      textAlign: TextAlign.center,
                      style: TextStyle(
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
                    const Expanded(
                      child: Text(
                        directApkUrl,
                        style: TextStyle(fontSize: 11, fontFamily: 'monospace'),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 18),
                      tooltip: 'Sao chép liên kết tải APK trực tiếp',
                      onPressed: () async {
                        await Clipboard.setData(
                          const ClipboardData(text: directApkUrl),
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
                  label: const Text(
                    'Tải trực tiếp APK (Bản mới nhất)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  onPressed: () => _openUrl(directApkUrl),
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
