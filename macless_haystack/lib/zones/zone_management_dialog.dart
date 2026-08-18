import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:macless_haystack/zones/zone_model.dart';
import 'package:macless_haystack/zones/zone_registry.dart';
import 'package:macless_haystack/zones/zone_form_dialog.dart';
import 'package:macless_haystack/zones/zone_alerts_dialog.dart';

class ZoneManagementDialog extends StatefulWidget {
  const ZoneManagementDialog({super.key});

  @override
  State<ZoneManagementDialog> createState() => _ZoneManagementDialogState();
}

class _ZoneManagementDialogState extends State<ZoneManagementDialog> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      final registry = Provider.of<ZoneRegistry>(context, listen: false);
      registry.fetchZones();
      registry.fetchAlerts();
    });
  }

  void _openCreateZone() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => const ZoneFormDialog(),
    );
    if (created == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã tạo khu vực an toàn mới thành công!')),
      );
    }
  }

  void _openEditZone(ZoneItem zone) async {
    final updated = await showDialog<bool>(
      context: context,
      builder: (ctx) => ZoneFormDialog(zone: zone),
    );
    if (updated == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã cập nhật khu vực an toàn thành công!')),
      );
    }
  }

  void _openAlertsHistory() {
    showDialog(
      context: context,
      builder: (ctx) => const ZoneAlertsDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 680,
        constraints: const BoxConstraints(maxHeight: 700),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.teal.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.shield_outlined, color: Colors.teal, size: 26),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Khu vực Cảnh báo (Safe Zones)',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Quản lý ranh giới an toàn và nhận cảnh báo khi thẻ vượt rào',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Action Toolbar (Show on map toggle, Alerts button, Add Zone button)
            Consumer<ZoneRegistry>(
              builder: (context, registry, _) {
                return Row(
                  children: [
                    // Toggle Map Overlay
                    Row(
                      children: [
                        Switch(
                          value: registry.showZonesOnMap,
                          activeColor: Colors.teal,
                          onChanged: (val) => registry.toggleShowZonesOnMap(val),
                        ),
                        const SizedBox(width: 4),
                        const Text('Hiện trên bản đồ', style: TextStyle(fontSize: 13)),
                      ],
                    ),
                    const Spacer(),

                    // Alerts History Button
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: registry.totalAlerts > 0 ? Colors.red.shade700 : Colors.grey.shade700,
                        side: BorderSide(
                          color: registry.totalAlerts > 0 ? Colors.red.shade300 : Colors.grey.shade300,
                        ),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: Icon(
                        registry.totalAlerts > 0 ? Icons.notifications_active : Icons.history,
                        size: 16,
                        color: registry.totalAlerts > 0 ? Colors.red : null,
                      ),
                      label: Text(
                        registry.totalAlerts > 0 ? 'Nhật ký (${registry.totalAlerts})' : 'Nhật ký',
                        style: const TextStyle(fontSize: 12),
                      ),
                      onPressed: _openAlertsHistory,
                    ),
                    const SizedBox(width: 8),

                    // Add Zone Button
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Thêm Khu vực', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      onPressed: _openCreateZone,
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),

            // Zone List
            Expanded(
              child: Consumer<ZoneRegistry>(
                builder: (context, registry, _) {
                  if (registry.loading && registry.zones.isEmpty) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (registry.zones.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.fmd_bad_outlined, size: 54, color: Colors.grey.shade400),
                          const SizedBox(height: 12),
                          const Text(
                            'Chưa có Khu vực An toàn nào',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Tạo một khu vực (như Nhà, Cơ quan) để nhận cảnh báo khi thẻ rời khỏi.',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.teal,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Tạo Khu vực đầu tiên'),
                            onPressed: _openCreateZone,
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.separated(
                    itemCount: registry.zones.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final zone = registry.zones[index];
                      final radiusStr = zone.radius >= 1000
                          ? '${(zone.radius / 1000).toStringAsFixed(1)} km'
                          : '${zone.radius.toInt()} m';

                      return Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.grey.shade900 : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: zone.isActive ? Colors.teal.withOpacity(0.3) : Colors.grey.shade300,
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.03),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Zone Title Row
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: zone.isActive ? Colors.teal.shade50 : Colors.grey.shade100,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.shield,
                                    color: zone.isActive ? Colors.teal : Colors.grey,
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            zone.name,
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                          ),
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.teal.shade100,
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              zone.shapeType == 'polygon' ? 'ĐA GIÁC' : 'HÌNH TRÒN',
                                              style: TextStyle(
                                                fontSize: 9,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.teal.shade900,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: zone.isActive ? Colors.green.shade100 : Colors.grey.shade300,
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              zone.isActive ? 'ĐANG BẬT' : 'TẮT',
                                              style: TextStyle(
                                                fontSize: 9,
                                                fontWeight: FontWeight.bold,
                                                color: zone.isActive ? Colors.green.shade900 : Colors.grey.shade700,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        zone.shapeType == 'polygon'
                                            ? 'Đa giác: ${zone.polygonPoints.length} điểm • Tâm: ${zone.latitude.toStringAsFixed(4)}, ${zone.longitude.toStringAsFixed(4)}'
                                            : 'Bán kính: $radiusStr • Tâm: ${zone.latitude.toStringAsFixed(4)}, ${zone.longitude.toStringAsFixed(4)}',
                                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                                      ),
                                    ],
                                  ),
                                ),
                                // Focus on map button
                                IconButton(
                                  icon: const Icon(Icons.center_focus_strong, size: 20, color: Colors.teal),
                                  tooltip: 'Xem vị trí trên bản đồ',
                                  onPressed: () {
                                    registry.focusZone(zone);
                                    Navigator.pop(context);
                                  },
                                ),
                                // Edit button
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined, size: 20, color: Colors.teal),
                                  tooltip: 'Chỉnh sửa',
                                  onPressed: () => _openEditZone(zone),
                                ),
                                // Delete button
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                                  tooltip: 'Xóa khu vực',
                                  onPressed: () async {
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: const Text('Xác nhận xóa'),
                                        content: Text('Bạn có chắc chắn muốn xóa khu vực "${zone.name}" không?'),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
                                          ElevatedButton(
                                            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                                            onPressed: () => Navigator.pop(ctx, true),
                                            child: const Text('Xóa'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (confirm == true) {
                                      await registry.deleteZone(zone.id);
                                    }
                                  },
                                ),
                              ],
                            ),

                            // Alert Flags
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                if (zone.alertOnExit)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: Colors.red.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.exit_to_app, size: 12, color: Colors.red),
                                        SizedBox(width: 4),
                                        Text('Báo khi Rời đi', style: TextStyle(fontSize: 10, color: Colors.red, fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                  ),
                                if (zone.alertOnEnter)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: Colors.green.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.login, size: 12, color: Colors.green),
                                        SizedBox(width: 4),
                                        Text('Báo khi Đi vào', style: TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                  ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text('Cooldown: ${zone.cooldownMinutes}p', style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),

                            // Devices assigned
                            const SizedBox(height: 10),
                            const Divider(height: 1),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(Icons.sell_outlined, size: 14, color: Colors.grey),
                                const SizedBox(width: 6),
                                Text(
                                  'Thẻ áp dụng (${zone.devices.length}):',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            if (zone.devices.isEmpty)
                              const Text('Chưa gán thẻ nào cho khu vực này.', style: TextStyle(fontSize: 11, color: Colors.grey))
                            else
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: zone.devices.map((zd) {
                                  final isInside = zd.lastStatus == 'INSIDE';
                                  final isOutside = zd.lastStatus == 'OUTSIDE';
                                  Color badgeColor = Colors.grey;
                                  String statusText = 'Chưa xác định';
                                  if (isInside) {
                                    badgeColor = Colors.green;
                                    statusText = 'Trong vùng';
                                  } else if (isOutside) {
                                    badgeColor = Colors.orange;
                                    statusText = 'Ngoài vùng';
                                  }

                                  return Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: badgeColor.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: badgeColor.withOpacity(0.3)),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 6,
                                          height: 6,
                                          decoration: BoxDecoration(
                                            color: badgeColor,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          zd.deviceName,
                                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          '($statusText)',
                                          style: TextStyle(fontSize: 10, color: badgeColor),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
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
