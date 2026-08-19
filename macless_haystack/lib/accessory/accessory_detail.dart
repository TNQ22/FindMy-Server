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

  @override
  void initState() {
    newAccessory = widget.accessory.clone();
    super.initState();
    _loadMacAddress();
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
                                    accessoryRegistry.editAccessory(
                                        widget.accessory, newAccessory);
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
        text = 'Không xác định / Chưa có dữ liệu';
        icon = Icons.battery_unknown;
        color = Colors.grey;
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.withAlpha(40)),
      ),
      child: ListTile(
        leading: Icon(icon, color: color, size: 26),
        title: const Text('Trạng thái pin', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        subtitle: Text(text, style: TextStyle(fontSize: 14, color: color, fontWeight: FontWeight.w600)),
      ),
    );
  }
}
