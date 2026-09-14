import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:universal_html/html.dart' as html;

import 'app_update_service.dart';
import '../preferences/app_download_dialog.dart';

/// Interactive dialog that notifies the user of a new app version,
/// allowing them to update immediately, postpone, or choose "Không hỏi lại" (Skip/Don't ask again).
class AppUpdateDialog extends StatefulWidget {
  final ReleaseInfo releaseInfo;
  final bool manualTrigger;

  const AppUpdateDialog({
    super.key,
    required this.releaseInfo,
    this.manualTrigger = false,
  });

  /// Displays the update dialog.
  static Future<void> show(
    BuildContext context, {
    required ReleaseInfo releaseInfo,
    bool manualTrigger = false,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AppUpdateDialog(
        releaseInfo: releaseInfo,
        manualTrigger: manualTrigger,
      ),
    );
  }

  @override
  State<AppUpdateDialog> createState() => _AppUpdateDialogState();
}

class _AppUpdateDialogState extends State<AppUpdateDialog> {
  late bool _isIgnored;

  @override
  void initState() {
    super.initState();
    _isIgnored = widget.releaseInfo.isIgnored;
  }

  Future<void> _openDownloadUrl(String url) async {
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

  Future<void> _onDoNotAskAgain() async {
    await AppUpdateService.ignoreVersion(widget.releaseInfo.tagName);
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Đã bỏ qua thông báo bản ${widget.releaseInfo.tagName}. Bạn có thể cập nhật trong Menu tài khoản bất cứ lúc nào.',
          style: const TextStyle(fontSize: 13),
        ),
        backgroundColor: Colors.teal.shade800,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _onReEnableReminders() async {
    await AppUpdateService.clearIgnoredVersion();
    if (!mounted) return;
    setState(() {
      _isIgnored = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Đã bật lại thông báo cập nhật tự động!'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final rel = widget.releaseInfo;

    return AlertDialog(
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      actionsPadding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      title: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.teal.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.system_update_alt_rounded, color: Colors.teal, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Có phiên bản mới!',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 3),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  children: [
                    Text(
                      'Hiện tại: v${AppUpdateService.currentAppVersion}',
                      style: TextStyle(fontSize: 12, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                    ),
                    const Icon(Icons.arrow_forward, size: 12, color: Colors.teal),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.teal,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        rel.tagName,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Package details pill
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.android, size: 18, color: Colors.green),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        rel.apkFileName,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      rel.apkSizeStr,
                      style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),

              // Release notes / changelog if available
              if (rel.body.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text(
                  'Nội dung cập nhật:',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
                ),
                const SizedBox(height: 6),
                Container(
                  constraints: const BoxConstraints(maxHeight: 130),
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF0F172A).withOpacity(0.5) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: isDark ? Colors.white10 : Colors.black.withOpacity(0.06)),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      rel.body.trim(),
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: isDark ? Colors.grey.shade300 : Colors.black87,
                      ),
                    ),
                  ),
                ),
              ],

              // Ignored status alert (when user previously chose "Không hỏi lại" and opened via menu)
              if (_isIgnored) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber.shade300, width: 0.8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, size: 15, color: Colors.amber.shade900),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Đang tắt nhắc nhở phiên bản này',
                          style: TextStyle(fontSize: 11, color: Colors.amber.shade900, fontWeight: FontWeight.w500),
                        ),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          foregroundColor: Colors.teal,
                        ),
                        onPressed: _onReEnableReminders,
                        child: const Text('Bật lại', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
              ],

              // QR Code option for Web users
              if (kIsWeb) ...[
                const SizedBox(height: 10),
                Center(
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.teal,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    ),
                    icon: const Icon(Icons.qr_code, size: 16),
                    label: const Text('Quét mã QR để tải về điện thoại', style: TextStyle(fontSize: 12)),
                    onPressed: () {
                      Navigator.of(context).pop();
                      AppDownloadDialog.show(context);
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        // Top row: "Không hỏi lại" button + "Để sau" button
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // "Không hỏi lại" (Don't ask again) button
            if (!_isIgnored)
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.notifications_off_outlined, size: 16),
                label: const Text(
                  'Không hỏi lại',
                  style: TextStyle(fontSize: 12),
                ),
                onPressed: _onDoNotAskAgain,
              )
            else
              const SizedBox.shrink(),

            // "Để sau" (Later) button
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              ),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Để sau', style: TextStyle(fontSize: 13)),
            ),
          ],
        ),
        const SizedBox(height: 6),

        // Primary Action: "Cập nhật ngay"
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
            icon: const Icon(Icons.download_rounded, size: 20),
            label: Text(
              'Cập nhật ngay (${rel.tagName})',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            onPressed: () {
              Navigator.of(context).pop();
              _openDownloadUrl(rel.apkUrl);
            },
          ),
        ),
      ],
    );
  }
}
