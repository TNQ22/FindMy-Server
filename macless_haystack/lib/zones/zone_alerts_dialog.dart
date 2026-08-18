import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:macless_haystack/zones/zone_model.dart';
import 'package:macless_haystack/zones/zone_registry.dart';

class ZoneAlertsDialog extends StatefulWidget {
  const ZoneAlertsDialog({super.key});

  @override
  State<ZoneAlertsDialog> createState() => _ZoneAlertsDialogState();
}

class _ZoneAlertsDialogState extends State<ZoneAlertsDialog> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAlerts();
  }

  Future<void> _loadAlerts() async {
    final registry = Provider.of<ZoneRegistry>(context, listen: false);
    await registry.fetchAlerts();
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _openMap(double lat, double lon) async {
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lon');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 600,
        constraints: const BoxConstraints(maxHeight: 650),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.notifications_active_outlined, color: Colors.red, size: 24),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Nhật ký Cảnh báo Vùng',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Lịch sử các sự kiện ra/vào khu vực an toàn',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                Consumer<ZoneRegistry>(
                  builder: (context, registry, _) {
                    if (registry.alerts.isEmpty) return const SizedBox.shrink();
                    return IconButton(
                      tooltip: 'Xóa toàn bộ lịch sử',
                      icon: const Icon(Icons.delete_sweep_outlined, color: Colors.red),
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Xác nhận xóa'),
                            content: const Text('Bạn có chắc chắn muốn xóa toàn bộ lịch sử cảnh báo không?'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Hủy'),
                              ),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Xóa tất cả'),
                              ),
                            ],
                          ),
                        );

                        if (confirm == true && context.mounted) {
                          await registry.clearAllAlerts();
                        }
                      },
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 12),

            // Content
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : Consumer<ZoneRegistry>(
                      builder: (context, registry, _) {
                        final alerts = registry.alerts;

                        if (alerts.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.check_circle_outline, size: 54, color: Colors.green.shade400),
                                const SizedBox(height: 12),
                                const Text(
                                  'Chưa có sự kiện cảnh báo nào',
                                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Tất cả thẻ định vị đều đang ở trạng thái an toàn.',
                                  style: TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                              ],
                            ),
                          );
                        }

                        return ListView.separated(
                          itemCount: alerts.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final item = alerts[index];
                            final isExit = item.alertType.toUpperCase() == 'EXIT';
                            final timeStr = DateFormat('dd/MM/yyyy HH:mm:ss').format(item.createdAt);

                            return Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.grey.shade900
                                    : (isExit ? Colors.red.shade50.withOpacity(0.5) : Colors.green.shade50.withOpacity(0.5)),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isExit ? Colors.red.withOpacity(0.3) : Colors.green.withOpacity(0.3),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: isExit ? Colors.red : Colors.green,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      isExit ? Icons.exit_to_app : Icons.login,
                                      color: Colors.white,
                                      size: 16,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              item.deviceName,
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                            ),
                                            const SizedBox(width: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: isExit ? Colors.red.shade100 : Colors.green.shade100,
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                isExit ? 'RỜI KHỎI' : 'ĐI VÀO',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: isExit ? Colors.red.shade900 : Colors.green.shade900,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Khu vực: ${item.zoneName} • Khoảng cách: ${item.distance.toStringAsFixed(1)} m',
                                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          timeStr,
                                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.map_outlined, size: 20, color: Colors.teal),
                                    tooltip: 'Xem trên Google Maps',
                                    onPressed: () => _openMap(item.latitude, item.longitude),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, size: 20, color: Colors.grey),
                                    tooltip: 'Xóa bản ghi này',
                                    onPressed: () async {
                                      await registry.deleteAlert(item.id);
                                    },
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
