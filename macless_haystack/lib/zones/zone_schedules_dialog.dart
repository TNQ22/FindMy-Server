import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:macless_haystack/dashboard/app_toast.dart';
import 'package:macless_haystack/zones/zone_model.dart';
import 'package:macless_haystack/zones/zone_registry.dart';

class ZoneSchedulesDialog extends StatefulWidget {
  final ZoneItem zone;

  const ZoneSchedulesDialog({super.key, required this.zone});

  @override
  State<ZoneSchedulesDialog> createState() => _ZoneSchedulesDialogState();
}

class _ZoneSchedulesDialogState extends State<ZoneSchedulesDialog> {
  List<ZoneScheduleItem> _schedules = [];
  bool _loading = true;

  final List<String> _dayNames = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];

  @override
  void initState() {
    super.initState();
    _loadSchedules();
  }

  Future<void> _loadSchedules() async {
    setState(() => _loading = true);
    final registry = Provider.of<ZoneRegistry>(context, listen: false);
    final list = await registry.fetchZoneSchedules(widget.zone.id);
    if (mounted) {
      setState(() {
        _schedules = list;
        _loading = false;
      });
    }
  }

  Future<void> _openScheduleFormDialog({ZoneScheduleItem? existing}) async {
    final isEditing = existing != null;
    TimeOfDay selectedTime;
    if (existing != null) {
      try {
        final parts = existing.targetTime.split(':');
        selectedTime = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
      } catch (_) {
        selectedTime = const TimeOfDay(hour: 8, minute: 0);
      }
    } else {
      selectedTime = const TimeOfDay(hour: 8, minute: 0);
    }

    String selectedRule = existing?.ruleType ?? 'MUST_LEAVE_BY';
    int? selectedDeviceId = existing?.deviceId;
    Set<int> selectedDays = existing != null
        ? existing.daysOfWeek.toSet()
        : {1, 2, 3, 4, 5}; // Default Monday - Friday

    final success = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Icon(
                    isEditing ? Icons.edit_calendar : Icons.alarm_add,
                    color: Colors.teal.shade700,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isEditing ? 'Sửa Lịch Trình Nhắc Nhở' : 'Thêm Lịch Trình Nhắc Nhở',
                    style: const TextStyle(fontSize: 16),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. Time Picker
                    const Text('1. Giờ kiểm tra:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: () async {
                        final picked = await showTimePicker(
                          context: ctx,
                          initialTime: selectedTime,
                        );
                        if (picked != null) {
                          setDialogState(() => selectedTime = picked);
                        }
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.teal.shade400),
                          borderRadius: BorderRadius.circular(8),
                          color: Colors.teal.shade50.withOpacity(0.3),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.access_time, color: Colors.teal, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.teal),
                            ),
                            const SizedBox(width: 8),
                            const Text('(Bấm để đổi)', style: TextStyle(fontSize: 11, color: Colors.grey)),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 14),

                    // 2. Rule Type
                    const Text('2. Loại quy tắc nhắc nhở:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      value: selectedRule,
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'MUST_LEAVE_BY',
                          child: Text('Phải rời vùng (Nhắc quên đồ buổi sáng)', style: TextStyle(fontSize: 12)),
                        ),
                        DropdownMenuItem(
                          value: 'MUST_ENTER_BY',
                          child: Text('Phải về vùng (Cảnh báo chưa về / thất lạc)', style: TextStyle(fontSize: 12)),
                        ),
                      ],
                      onChanged: (v) => setDialogState(() => selectedRule = v ?? 'MUST_LEAVE_BY'),
                    ),

                    const SizedBox(height: 14),

                    // 3. Applicable device
                    const Text('3. Áp dụng cho thiết bị:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<int?>(
                      value: selectedDeviceId,
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('Tất cả thiết bị trong khu vực', style: TextStyle(fontSize: 12)),
                        ),
                        ...widget.zone.devices.map((d) => DropdownMenuItem(
                              value: d.deviceId,
                              child: Text(d.deviceName, style: const TextStyle(fontSize: 12)),
                            )),
                      ],
                      onChanged: (v) => setDialogState(() => selectedDeviceId = v),
                    ),

                    const SizedBox(height: 14),

                    // 4. Days of week
                    const Text('4. Ngày áp dụng trong tuần:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 4,
                      children: List.generate(7, (i) {
                        final dayNum = i + 1;
                        final isSelected = selectedDays.contains(dayNum);
                        return FilterChip(
                          label: Text(_dayNames[i], style: TextStyle(fontSize: 11, color: isSelected ? Colors.white : Colors.black87)),
                          selected: isSelected,
                          selectedColor: Colors.teal,
                          checkmarkColor: Colors.white,
                          onSelected: (val) {
                            setDialogState(() {
                              if (val) {
                                selectedDays.add(dayNum);
                              } else {
                                if (selectedDays.length > 1) {
                                  selectedDays.remove(dayNum);
                                }
                              }
                            });
                          },
                        );
                      }),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Hủy'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    final timeStr =
                        '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}';
                    final registry = Provider.of<ZoneRegistry>(context, listen: false);

                    bool ok = false;
                    if (isEditing) {
                      ok = await registry.updateZoneSchedule(
                        scheduleId: existing.id,
                        deviceId: selectedDeviceId,
                        ruleType: selectedRule,
                        targetTime: timeStr,
                        daysOfWeek: selectedDays.toList()..sort(),
                      );
                    } else {
                      ok = await registry.createZoneSchedule(
                        zoneId: widget.zone.id,
                        deviceId: selectedDeviceId,
                        ruleType: selectedRule,
                        targetTime: timeStr,
                        daysOfWeek: selectedDays.toList()..sort(),
                      );
                    }
                    if (ctx.mounted) {
                      Navigator.pop(ctx, ok);
                    }
                  },
                  child: Text(isEditing ? 'Lưu' : 'Thêm'),
                ),
              ],
            );
          },
        );
      },
    );

    if (success == true && mounted) {
      AppToast.showText(
        context,
        isEditing ? 'Đã cập nhật lịch trình nhắc nhở!' : 'Đã thêm lịch trình nhắc nhở!',
        icon: Icons.alarm_on,
        backgroundColor: Colors.teal.shade800,
      );
      _loadSchedules();
      Provider.of<ZoneRegistry>(context, listen: false).fetchZones();
    }
  }

  Future<void> _deleteSchedule(int scheduleId) async {
    final registry = Provider.of<ZoneRegistry>(context, listen: false);
    final ok = await registry.deleteZoneSchedule(scheduleId);
    if (ok && mounted) {
      AppToast.showText(context, 'Đã xóa lịch trình nhắc nhở.', icon: Icons.delete_outline, backgroundColor: Colors.red.shade800);
      _loadSchedules();
      registry.fetchZones();
    }
  }

  @override
  Widget build(BuildContext context) {
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
          maxWidth: 580,
          maxHeight: mediaQuery.size.height * 0.85,
        ),
        child: Column(
          children: [
            // Top Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [Colors.teal.shade800, Colors.teal.shade600]),
              ),
              child: Row(
                children: [
                  const Icon(Icons.alarm, color: Colors.white, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Lịch Trình Nhắc Nhở Theo Giờ',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        Text(
                          'Khu vực: ${widget.zone.name}',
                          style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 12),
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

            // Content
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: Colors.teal))
                  : _schedules.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.alarm_off, size: 48, color: Colors.grey.shade400),
                                const SizedBox(height: 12),
                                const Text(
                                  'Chưa có lịch trình nhắc nhở nào',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'Cài đặt giờ để hệ thống nhắc quên chìa khóa/balo khi đi làm, hoặc báo động nếu xe/người thân chưa về nhà.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.teal,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  icon: const Icon(Icons.add_alarm, size: 18),
                                  label: const Text('Thêm Lịch Trình Đầu Tiên'),
                                  onPressed: () => _openScheduleFormDialog(),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(14),
                          itemCount: _schedules.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (ctx, i) {
                            final s = _schedules[i];
                            final isLeave = s.ruleType == 'MUST_LEAVE_BY';
                            final ruleColor = isLeave ? Colors.orange.shade800 : Colors.purple.shade700;
                            final ruleBadge = isLeave ? 'Phải rời trước' : 'Phải về trước';
                            final daysStr = s.daysOfWeek.map((d) => _dayNames[(d - 1) % 7]).join(', ');

                            return Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: ruleColor.withOpacity(0.3)),
                                color: ruleColor.withOpacity(0.04),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: ruleColor.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      s.targetTime,
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: ruleColor,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: ruleColor,
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                ruleBadge,
                                                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Flexible(
                                              child: Text(
                                                s.deviceName,
                                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Lặp lại: $daysStr',
                                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined, color: Colors.teal, size: 20),
                                    tooltip: 'Sửa lịch trình',
                                    onPressed: () => _openScheduleFormDialog(existing: s),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                                    tooltip: 'Xóa lịch trình',
                                    onPressed: () => _deleteSchedule(s.id),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
            ),

            // Bottom Add Button
            if (_schedules.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: SizedBox(
                  width: double.infinity,
                  height: 42,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.add_alarm, size: 18),
                    label: const Text('Thêm Lịch Trình Mới'),
                    onPressed: () => _openScheduleFormDialog(),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
