import 'package:flutter/material.dart';
import 'package:macless_haystack/dashboard/app_toast.dart';
import 'package:provider/provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:macless_haystack/findMy/find_my_controller.dart';
import 'package:macless_haystack/accessory/accessory_battery.dart';
import 'package:macless_haystack/accessory/accessory_color_selector.dart';
import 'package:macless_haystack/accessory/accessory_icon.dart';
import 'package:macless_haystack/accessory/accessory_icon_selector.dart';
import 'package:macless_haystack/accessory/accessory_model.dart';
import 'package:macless_haystack/accessory/accessory_registry.dart';
import 'package:macless_haystack/item_management/accessory_name_input.dart';
import 'package:intl/intl.dart';

class AccessoryDetail extends StatefulWidget {
  final Accessory accessory;

  /// A dialog displaying the editable information of a specific [accessory].
  const AccessoryDetail({
    super.key,
    required this.accessory,
  });

  @override
  State<StatefulWidget> createState() {
    return _AccessoryDetailState();
  }
}

class _AccessoryDetailState extends State<AccessoryDetail> {
  // An accessory storing the changed values.
  late Accessory newAccessory;
  final _formKey = GlobalKey<FormState>();
  String _macAddress = "Đang tính toán...";
  late TextEditingController _notesController;

  @override
  void initState() {
    newAccessory = widget.accessory.clone();
    _notesController = TextEditingController(text: widget.accessory.notes ?? '');
    super.initState();
    _loadMacAddress();
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadMacAddress() async {
    try {
      const storage = FlutterSecureStorage();
      String? pkBase64 = await storage.read(key: widget.accessory.hashedPublicKey);
      if (pkBase64 == null || pkBase64.isEmpty) {
        try {
          pkBase64 = await widget.accessory.getPrivateKey();
        } catch (_) {}
      }
      if (pkBase64 != null && pkBase64.isNotEmpty) {
        if (mounted) {
          setState(() {
            _macAddress = FindMyController.calculateMacAddress(pkBase64!);
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _macAddress = "Không tìm thấy Private Key";
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _macAddress = "Lỗi tính toán";
        });
      }
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
          maxWidth: 520,
          maxHeight: mediaQuery.size.height * 0.90,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
                    child: const Icon(Icons.settings, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Thiết Lập "${widget.accessory.name}"',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: isMobile ? 16 : 18,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Chỉnh sửa thông tin, biểu tượng và cấu hình Tag',
                          style: TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Content
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: isMobile ? 14 : 22,
                  vertical: 18,
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Centered Icon with Edit Overlay
                      Center(
                        child: Stack(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: newAccessory.color.withOpacity(0.12),
                              ),
                              child: AccessoryIcon(
                                size: 84,
                                icon: newAccessory.icon,
                                color: newAccessory.color,
                              ),
                            ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Material(
                                elevation: 3,
                                shape: const CircleBorder(),
                                color: Colors.teal.shade700,
                                child: InkWell(
                                  customBorder: const CircleBorder(),
                                  onTap: () async {
                                    String? selectedIcon =
                                        await AccessoryIconSelector.showIconSelection(
                                            context,
                                            newAccessory.rawIcon,
                                            newAccessory.color);
                                    if (selectedIcon != null) {
                                      setState(() {
                                        newAccessory.setIcon(selectedIcon);
                                      });
                                      if (context.mounted) {
                                        Color? selectedColor =
                                            await AccessoryColorSelector
                                                .showColorSelection(
                                                    context, newAccessory.color);
                                        if (selectedColor != null) {
                                          setState(() {
                                            newAccessory.color = selectedColor;
                                          });
                                        }
                                      }
                                    }
                                  },
                                  child: const Padding(
                                    padding: EdgeInsets.all(8.0),
                                    child: Icon(
                                      Icons.edit,
                                      size: 18,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 18),

                      // Name Input
                      AccessoryNameInput(
                        initialValue: newAccessory.name,
                        onChanged: (value) {
                          setState(() {
                            newAccessory.name = value;
                          });
                        },
                      ),

                      const SizedBox(height: 10),

                      // Notes Input (ngay dưới tên tag)
                      TextFormField(
                        controller: _notesController,
                        maxLines: 2,
                        minLines: 1,
                        style: const TextStyle(fontSize: 13),
                        decoration: InputDecoration(
                          labelText: 'Ghi chú',
                          hintText: 'Ghi chú thẻ (ví dụ: Chìa khóa xe, Balo laptop...)',
                          hintStyle: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).brightness == Brightness.dark
                                ? Colors.white30
                                : Colors.black26,
                          ),
                          prefixIcon: const Icon(Icons.edit_note, color: Colors.teal, size: 20),
                          filled: true,
                          fillColor: Theme.of(context).brightness == Brightness.dark
                              ? Colors.white.withOpacity(0.04)
                              : Colors.grey.shade50,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: Colors.grey.withAlpha(50)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: Colors.grey.withAlpha(50)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: Colors.teal.shade600, width: 1.5),
                          ),
                        ),
                        onChanged: (value) {
                          newAccessory.notes = value;
                        },
                      ),

                      const SizedBox(height: 10),

                      // Active Switch Tile
                      Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: Colors.grey.withAlpha(40)),
                        ),
                        child: SwitchListTile(
                          value: newAccessory.isActive,
                          activeColor: Colors.teal,
                          title: const Text(
                            'Kích hoạt Tag (Hoạt động)',
                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                          ),
                          subtitle: Text(
                            newAccessory.isActive ? 'Đang định vị và đồng bộ dữ liệu' : 'Đang tạm dừng',
                            style: const TextStyle(fontSize: 12),
                          ),
                          onChanged: (checked) {
                            setState(() {
                              newAccessory.isActive = checked;
                            });
                          },
                        ),
                      ),

                      const SizedBox(height: 8),

                      // Battery Tile
                      _buildBatteryTile(),

                      const SizedBox(height: 8),

                      // MAC Address Card
                      Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: Colors.grey.withAlpha(40)),
                        ),
                        child: ListTile(
                          leading: const Icon(Icons.qr_code_2, color: Colors.teal, size: 24),
                          title: const Text('Địa chỉ MAC:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          subtitle: Text(
                            _macAddress,
                            style: const TextStyle(fontSize: 14, fontFamily: 'monospace', fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),

                      const SizedBox(height: 10),

                      // Companion Settings Card
                      _buildCompanionSettingsCard(),

                      const SizedBox(height: 20),
                      const Divider(),
                      const SizedBox(height: 12),

                      // Action Buttons
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: const Icon(Icons.save_outlined, size: 18),
                          label: const Text('Lưu Thay Đổi', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          onPressed: _formKey.currentState == null ||
                                  !_formKey.currentState!.validate()
                              ? null
                              : () {
                                  if (_formKey.currentState != null &&
                                      _formKey.currentState!.validate()) {
                                    var accessoryRegistry =
                                        Provider.of<AccessoryRegistry>(context,
                                            listen: false);
                                    final updatedNotes = _notesController.text.trim();
                                    newAccessory.notes = updatedNotes.isEmpty ? null : updatedNotes;
                                    accessoryRegistry.editAccessory(
                                        widget.accessory, newAccessory);
                                    accessoryRegistry.updateDeviceNotes(
                                        widget.accessory,
                                        notes: newAccessory.notes,
                                        batteryType: newAccessory.batteryType,
                                        batteryReplacedAt: newAccessory.batteryReplacedAt);
                                    if (newAccessory.serverId != null) {
                                      accessoryRegistry.updateCompanionSettings(
                                        newAccessory.serverId!,
                                        isMaster: newAccessory.isMaster,
                                        masterDeviceId: newAccessory.masterDeviceId,
                                        separationAlertEnabled: newAccessory.separationAlertEnabled,
                                        separationThresholdMeters: newAccessory.separationThresholdMeters,
                                        ignoreSeparationInSafeZones: newAccessory.ignoreSeparationInSafeZones,
                                      );
                                    }
                                    AppToast.showText(
                                      context,
                                      'Đã lưu thay đổi cho "${newAccessory.name}"',
                                      icon: Icons.check_circle,
                                      backgroundColor: Colors.teal.shade800,
                                    );
                                    Navigator.pop(context);
                                  }
                                },
                        ),
                      ),

                      const SizedBox(height: 10),

                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.amber.shade900,
                                side: BorderSide(color: Colors.amber.shade700),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              icon: const Icon(Icons.history_toggle_off, size: 16),
                              label: const Text('Đặt lại Lịch sử', style: TextStyle(fontSize: 12)),
                              onPressed: () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                    title: const Text('Đặt lại lịch sử Tag'),
                                    content: Text('Bạn có chắc muốn xóa toàn bộ lịch sử vị trí của "${widget.accessory.name}"?'),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(ctx, false),
                                        child: const Text('Hủy'),
                                      ),
                                      ElevatedButton(
                                        onPressed: () => Navigator.pop(ctx, true),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.amber.shade900,
                                          foregroundColor: Colors.white,
                                        ),
                                        child: const Text('Xác nhận đặt lại'),
                                      ),
                                    ],
                                  ),
                                );

                                if (confirm == true && context.mounted) {
                                  var accessoryRegistry =
                                      Provider.of<AccessoryRegistry>(context, listen: false);
                                  accessoryRegistry.deleteData(widget.accessory);
                                  AppToast.showText(
                                    context,
                                    'Đã xóa toàn bộ lịch sử vị trí của thiết bị',
                                    icon: Icons.delete_outline,
                                    backgroundColor: Colors.amber.shade900,
                                  );
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red.shade700,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              icon: const Icon(Icons.delete_outline, size: 16),
                              label: const Text('Xóa Tag', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              onPressed: () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                    title: const Text('Xóa Tag'),
                                    content: Text('Bạn có chắc chắn muốn xóa Tag "${widget.accessory.name}" khỏi tài khoản không? Hành động này không thể hoàn tác.'),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(ctx, false),
                                        child: const Text('Hủy'),
                                      ),
                                      ElevatedButton(
                                        onPressed: () => Navigator.pop(ctx, true),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.red.shade700,
                                          foregroundColor: Colors.white,
                                        ),
                                        child: const Text('Xóa vĩnh viễn'),
                                      ),
                                    ],
                                  ),
                                );

                                if (confirm == true && context.mounted) {
                                  var accessoryRegistry =
                                      Provider.of<AccessoryRegistry>(context, listen: false);
                                  accessoryRegistry.removeAccessory(widget.accessory);
                                  AppToast.showText(
                                    context,
                                    'Đã xóa Tag "${widget.accessory.name}"',
                                    icon: Icons.delete_forever,
                                    backgroundColor: Colors.red.shade800,
                                  );
                                  Navigator.pop(context);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBatteryTile() {
    String text;
    IconData icon;
    Color color;

    switch (widget.accessory.lastBatteryStatus) {
      case AccessoryBatteryStatus.ok:
        text = 'Đầy (Tốt)';
        icon = Icons.battery_full;
        color = Colors.green;
        break;
      case AccessoryBatteryStatus.medium:
        text = 'Trung bình';
        icon = Icons.battery_3_bar;
        color = Colors.orange;
        break;
      case AccessoryBatteryStatus.low:
        text = 'Thấp';
        icon = Icons.battery_1_bar;
        color = Colors.red;
        break;
      case AccessoryBatteryStatus.criticalLow:
        text = 'Sắp hết (Rất thấp)';
        icon = Icons.battery_alert;
        color = Colors.red;
        break;
      default:
        text = 'Chưa có dữ liệu';
        icon = Icons.battery_unknown;
        color = Colors.grey;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bType = (newAccessory.batteryType != null && newAccessory.batteryType!.isNotEmpty)
        ? newAccessory.batteryType!
        : 'CR2032';
    final replacedStr = newAccessory.batteryReplacedAt != null
        ? DateFormat('dd/MM/yyyy').format(newAccessory.batteryReplacedAt!)
        : 'Chưa đặt';
    final usageStr = _calculateBatteryUsage(newAccessory.batteryReplacedAt);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.withAlpha(40)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Left: Apple FindMy Battery Status
            Icon(icon, color: color, size: 28),
            const SizedBox(width: 10),
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Trạng thái Pin:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    text,
                    style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            // Divider separating Left and Right
            Container(
              height: 46,
              width: 1,
              color: isDark ? Colors.white12 : Colors.grey.shade300,
              margin: const EdgeInsets.symmetric(horizontal: 8),
            ),

            // Right: Battery Tracking Management
            Expanded(
              flex: 7,
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: _showBatteryManagementDialog,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: Colors.teal.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    bType,
                                    style: TextStyle(
                                      color: isDark ? Colors.tealAccent.shade100 : Colors.teal.shade800,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'Thay: $replacedStr',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                Icon(Icons.timer_outlined, size: 12, color: Colors.teal.shade600),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    'Đã dùng: $usageStr',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: isDark ? Colors.tealAccent.shade100 : Colors.teal.shade800,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 4),
                      Tooltip(
                        message: 'Thiết lập ngày thay & loại pin',
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white.withOpacity(0.08) : Colors.grey.shade100,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.edit, size: 14, color: Colors.teal),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _calculateBatteryUsage(DateTime? replacedAt) {
    if (replacedAt == null) return 'Chưa đặt';
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final startOfReplaced = DateTime(replacedAt.year, replacedAt.month, replacedAt.day);
    final days = startOfToday.difference(startOfReplaced).inDays;

    if (days < 0) return 'Mới thay';
    if (days == 0) return 'Hôm nay';
    if (days < 30) return '$days ngày';
    final months = days ~/ 30;
    final remDays = days % 30;
    if (remDays == 0) return '$months tháng';
    return '$months th $remDays ng ($days ng)';
  }

  void _showBatteryManagementDialog() {
    DateTime selectedDate = newAccessory.batteryReplacedAt ?? DateTime.now();
    final typeController = TextEditingController(
      text: newAccessory.batteryType ?? 'CR2032',
    );

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final dateStr = DateFormat('dd/MM/yyyy').format(selectedDate);
          final daysUsed = _calculateBatteryUsage(selectedDate);

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                const Icon(Icons.battery_charging_full, color: Colors.teal),
                const SizedBox(width: 8),
                const Text('Quản Lý & Theo Dõi Pin', style: TextStyle(fontSize: 16)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Loại Pin:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: typeController,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Ví dụ: CR2032, CR2025, AAA...',
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    children: ['CR2032', 'CR2025', 'CR2016', 'AAA'].map((t) {
                      return ActionChip(
                        label: Text(t, style: const TextStyle(fontSize: 11)),
                        padding: EdgeInsets.zero,
                        onPressed: () {
                          setDialogState(() {
                            typeController.text = t;
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),

                  const Text('Ngày Thay Pin:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          icon: const Icon(Icons.calendar_today, size: 16, color: Colors.teal),
                          label: Text(dateStr, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: selectedDate,
                              firstDate: DateTime(2020),
                              lastDate: DateTime.now().add(const Duration(days: 1)),
                            );
                            if (picked != null) {
                              setDialogState(() {
                                selectedDate = picked;
                              });
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () {
                          setDialogState(() {
                            selectedDate = DateTime.now();
                          });
                        },
                        child: const Text('Hôm nay', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Đã dùng: $daysUsed',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.teal.shade700,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Hủy'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () {
                  setState(() {
                    newAccessory.batteryType = typeController.text.trim().isEmpty ? null : typeController.text.trim();
                    newAccessory.batteryReplacedAt = selectedDate;
                  });
                  Navigator.pop(ctx);
                },
                child: const Text('Áp Dụng'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCompanionSettingsCard() {
    final registry = Provider.of<AccessoryRegistry>(context, listen: false);
    final candidateMasters = registry.accessories.where((a) {
      final isSelf = a.serverId == newAccessory.serverId ||
          (a.serverId == null && a.hashedPublicKey == newAccessory.hashedPublicKey);
      return !isSelf;
    }).toList();

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.blueGrey.withAlpha(50)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.devices_other, color: Colors.teal.shade700, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Thiết Bị Chủ & Tag Đồng Hành',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Cảnh báo khi tag bị bỏ quên hoặc tách xa khỏi iPhone/thiết bị chủ.',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
            const Divider(height: 16),

            // 1. Is Master Switch
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: newAccessory.isMaster,
              activeColor: Colors.teal,
              title: const Text(
                'Đặt làm Thiết bị chủ (iPhone / Điện thoại)',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              subtitle: const Text(
                'Các tag khác có thể chọn đi kèm theo thiết bị này',
                style: TextStyle(fontSize: 11),
              ),
              onChanged: (checked) {
                setState(() {
                  newAccessory.isMaster = checked;
                  if (checked) {
                    newAccessory.masterDeviceId = null;
                    newAccessory.separationAlertEnabled = false;
                  }
                });
              },
            ),

            // 2. If not master: Companion configuration
            if (!newAccessory.isMaster) ...[
              const SizedBox(height: 6),
              DropdownButtonFormField<int?>(
                value: newAccessory.masterDeviceId,
                decoration: InputDecoration(
                  labelText: 'Thiết bị chủ đi kèm',
                  labelStyle: const TextStyle(fontSize: 12),
                  prefixIcon: const Icon(Icons.link, size: 18),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('Không có (Thiết bị độc lập)', style: TextStyle(fontSize: 13)),
                  ),
                  ...candidateMasters.map((m) {
                    final label = m.isMaster
                        ? '📱 ${m.name} (Đang là Thiết bị chủ)'
                        : '${m.name} (Tự động bật Thiết bị chủ)';
                    return DropdownMenuItem<int?>(
                      value: m.serverId,
                      child: Text(label, style: const TextStyle(fontSize: 13)),
                    );
                  }),
                ],
                onChanged: (val) {
                  setState(() {
                    newAccessory.masterDeviceId = val;
                    if (val == null) {
                      newAccessory.separationAlertEnabled = false;
                    }
                  });
                },
              ),

              if (newAccessory.masterDeviceId != null) ...[
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: newAccessory.separationAlertEnabled,
                  activeColor: Colors.amber.shade800,
                  title: const Text(
                    'Cảnh báo khi tách rời khỏi thiết bị chủ',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  subtitle: const Text(
                    'Gửi thông báo nếu để quên hoặc làm rơi',
                    style: TextStyle(fontSize: 11),
                  ),
                  onChanged: (checked) {
                    setState(() {
                      newAccessory.separationAlertEnabled = checked;
                    });
                  },
                ),

                if (newAccessory.separationAlertEnabled) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Khoảng cách tách rời:', style: TextStyle(fontSize: 12)),
                            Text(
                              '${newAccessory.separationThresholdMeters.toInt()} mét',
                              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber.shade900, fontSize: 13),
                            ),
                          ],
                        ),
                        Slider(
                          value: newAccessory.separationThresholdMeters.clamp(50.0, 500.0),
                          min: 50.0,
                          max: 500.0,
                          divisions: 18,
                          label: '${newAccessory.separationThresholdMeters.toInt()}m',
                          activeColor: Colors.amber.shade800,
                          onChanged: (val) {
                            setState(() {
                              newAccessory.separationThresholdMeters = val;
                            });
                          },
                        ),
                      ],
                    ),
                  ),

                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: newAccessory.ignoreSeparationInSafeZones,
                    activeColor: Colors.teal,
                    title: const Text(
                      'Bỏ qua cảnh báo khi ở trong Vùng an toàn',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    subtitle: const Text(
                      'Không gửi thông báo nếu ở trong Vùng an toàn đã thiết lập',
                      style: TextStyle(fontSize: 11),
                    ),
                    onChanged: (checked) {
                      setState(() {
                        newAccessory.ignoreSeparationInSafeZones = checked;
                      });
                    },
                  ),
                ],
              ],
            ],
          ],
        ),
      ),
    );
  }
}
