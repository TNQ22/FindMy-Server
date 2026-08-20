import 'package:flutter/material.dart';
import 'package:macless_haystack/dashboard/app_toast.dart';
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
      AppToast.showText(
        context,
        'Đã tạo khu vực an toàn mới thành công!',
        icon: Icons.check_circle,
        backgroundColor: Colors.teal.shade800,
      );
    }
  }

  void _openEditZone(ZoneItem zone) async {
    final updated = await showDialog<bool>(
      context: context,
      builder: (ctx) => ZoneFormDialog(zone: zone),
    );
    if (updated == true && mounted) {
      AppToast.showText(
        context,
        'Đã cập nhật khu vực an toàn thành công!',
        icon: Icons.check_circle,
        backgroundColor: Colors.teal.shade800,
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
    final mediaQuery = MediaQuery.of(context);
    final isMobile = mediaQuery.size.width < 600;

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 24,
        vertical: isMobile ? 16 : 24,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: isMobile ? double.infinity : 680,
          maxHeight: mediaQuery.size.height * 0.90,
        ),
        child: Column(
          children: [
            // Top Bar with Emerald Green / Teal Gradient
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: isMobile ? 14 : 20,
                vertical: isMobile ? 12 : 16,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.teal.shade800, Colors.teal.shade600],
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.shield_outlined, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Khu Vực Cảnh Báo',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: isMobile ? 16 : 18,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Ranh giới an toàn & cảnh báo thẻ ra vào vùng',
                          style: TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Dialog Content Body
            Expanded(
              child: Padding(
                padding: EdgeInsets.all(isMobile ? 12 : 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Action Toolbar
                    Consumer<ZoneRegistry>(
                      builder: (context, registry, _) {
                        final switchWidget = Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Switch(
                              value: registry.showZonesOnMap,
                              activeColor: Colors.teal,
                              onChanged: (val) => registry.toggleShowZonesOnMap(val),
                            ),
                            const SizedBox(width: 4),
                            const Text('Hiện trên bản đồ', style: TextStyle(fontSize: 13)),
                          ],
                        );

                        final actionButtons = Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Alerts History Button
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text('Thêm Khu vực', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              onPressed: _openCreateZone,
                            ),
                          ],
                        );

                        return LayoutBuilder(
                          builder: (context, constraints) {
                            if (constraints.maxWidth < 450) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  switchWidget,
                                  const SizedBox(height: 8),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: actionButtons,
                                  ),
                                ],
                              );
                            }
                            return Row(
                              children: [
                                switchWidget,
                                const Spacer(),
                                actionButtons,
                              ],
                            );
                          },
                        );
                      },
                    ),
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 10),

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
                            'Chưa có Khu vực Cảnh báo nào',
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

                      final actionButtons = Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Tooltip(
                            message: 'Xem vị trí trên bản đồ',
                            child: InkWell(
                              borderRadius: BorderRadius.circular(6),
                              onTap: () {
                                registry.focusZone(zone);
                                Navigator.pop(context);
                              },
                              child: const Padding(
                                padding: EdgeInsets.all(4),
                                child: Icon(Icons.center_focus_strong, size: 18, color: Colors.teal),
                              ),
                            ),
                          ),
                          const SizedBox(width: 2),
                          Tooltip(
                            message: 'Chỉnh sửa',
                            child: InkWell(
                              borderRadius: BorderRadius.circular(6),
                              onTap: () => _openEditZone(zone),
                              child: const Padding(
                                padding: EdgeInsets.all(4),
                                child: Icon(Icons.edit_outlined, size: 18, color: Colors.teal),
                              ),
                            ),
                          ),
                          const SizedBox(width: 2),
                          Tooltip(
                            message: 'Xóa khu vực',
                            child: InkWell(
                              borderRadius: BorderRadius.circular(6),
                              onTap: () async {
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
                              child: const Padding(
                                padding: EdgeInsets.all(4),
                                child: Icon(Icons.delete_outline, size: 18, color: Colors.red),
                              ),
                            ),
                          ),
                        ],
                      );

                      return Container(
                        padding: const EdgeInsets.all(12),
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
                            // Hàng 1: Icon Khiên + (Tên khu vực + Cụm Badges) + 3 nút thao tác (Góc trên phải)
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(7),
                                  decoration: BoxDecoration(
                                    color: zone.isActive ? Colors.teal.shade50 : Colors.grey.shade100,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    zone.shapeType == 'polygon' ? Icons.polyline : Icons.shield,
                                    color: zone.isActive ? Colors.teal : Colors.grey,
                                    size: 17,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Wrap(
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    spacing: 6,
                                    runSpacing: 4,
                                    children: [
                                      Text(
                                        zone.name,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                      ),
                                      // Cụm [HÌNH TRÒN] và [ĐANG BẬT] gom chung trong Row để khi rớt dòng sẽ rớt CẢ CỤM
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.teal.shade100,
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              zone.shapeType == 'polygon'
                                                  ? 'ĐA GIÁC (${zone.polygonPoints.length} điểm)'
                                                  : 'HÌNH TRÒN ($radiusStr)',
                                              style: TextStyle(
                                                fontSize: 9.5,
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
                                                fontSize: 9.5,
                                                fontWeight: FontWeight.bold,
                                                color: zone.isActive ? Colors.green.shade900 : Colors.grey.shade700,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 6),
                                actionButtons,
                              ],
                            ),

                            // Dòng cờ cảnh báo (Alert Flags & Cooldown) - Sát lề trái
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
                                        Text('Báo khi Đến', style: TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.bold)),
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
            ),
          ],
        ),
      ),
    );
  }
}
