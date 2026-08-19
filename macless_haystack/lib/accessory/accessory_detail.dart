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

  /// A page displaying the editable information of a specific [accessory].
  ///
  /// This shows the editable information of a specific [accessory] and
  /// allows the user to edit them.
  const AccessoryDetail({
    super.key,
    required this.accessory,
  });

  @override
  State<StatefulWidget> createState() {
    return _AccessoryDetailState();
  }

// @override
// _AccessoryDetailState createState() => _AccessoryDetailState();
}

class _AccessoryDetailState extends State<AccessoryDetail> {
  // An accessory storing the changed values.
  late Accessory newAccessory;
  final _formKey = GlobalKey<FormState>();
  String _macAddress = "Đang tính toán...";

  @override
  void initState() {
    // Initialize changed accessory with existing accessory properties.
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
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.accessory.name),
      ),
      body: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              Center(
                child: Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: AccessoryIcon(
                        size: 100,
                        icon: newAccessory.icon,
                        color: newAccessory.color,
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Padding(
                        padding: const EdgeInsets.all(10.0),
                        child: Container(
                          decoration: const BoxDecoration(
                            color: Color.fromARGB(255, 200, 200, 200),
                            shape: BoxShape.circle,
                          ),
                          child: IconButton(
                            onPressed: () async {
                              // Show icon selection
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
                                  // Show color selection only when icon is selected
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
                            icon: Icon(
                              Icons.edit,
                              color: Theme.of(context).primaryColor,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              AccessoryNameInput(
                initialValue: newAccessory.name,
                onChanged: (value) {
                  setState(() {
                    newAccessory.name = value;
                  });
                },
              ),
              SwitchListTile(
                value: newAccessory.isActive,
                title: const Text('Is Active'),
                onChanged: (checked) {
                  setState(() {
                    newAccessory.isActive = checked;
                  });
                },
              ),
              _buildBatteryTile(),
              ListTile(
                title: const Text('Địa chỉ MAC:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: Text(_macAddress, style: const TextStyle(fontSize: 16)),
              ),
              ListTile(
                title: OutlinedButton(
                  onPressed: _formKey.currentState == null ||
                          !_formKey.currentState!.validate()
                      ? null
                      : () {
                          if (_formKey.currentState != null &&
                              _formKey.currentState!.validate()) {
                            // Update accessory with changed values
                            var accessoryRegistry =
                                Provider.of<AccessoryRegistry>(context,
                                    listen: false);
                            accessoryRegistry.editAccessory(
                                widget.accessory, newAccessory);
                            AppToast.showText(
                              context,
                              'Đã lưu thay đổi!',
                              icon: Icons.check_circle,
                              backgroundColor: Colors.teal.shade800,
                            );
                          }
                        },
                  child: const Text('Save'),
                ),
              ),
              ListTile(
                title: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                  onPressed: () {
                    // Update accessory with changed values
                    var accessoryRegistry =
                        Provider.of<AccessoryRegistry>(context, listen: false);
                    accessoryRegistry.deleteData(widget.accessory);
                    AppToast.showText(
                      context,
                      'Đã xóa toàn bộ dữ liệu lịch sử của thiết bị',
                      icon: Icons.delete_outline,
                      backgroundColor: Colors.amber.shade900,
                    );
                  },
                  child: const Text('Reset Accessory'),
                ),
              ),
              ListTile(
                title: ElevatedButton(
                  style: ButtonStyle(
                    backgroundColor: WidgetStateProperty.resolveWith<Color?>(
                      (Set<WidgetState> states) {
                        return Theme.of(context).colorScheme.error;
                      },
                    ),
                  ),
                  child: const Text(
                    'Delete Accessory',
                    style: TextStyle(color: Colors.white),
                  ),
                  onPressed: () {
                    // Delete accessory
                    var accessoryRegistry =
                        Provider.of<AccessoryRegistry>(context, listen: false);
                    accessoryRegistry.removeAccessory(widget.accessory);
                    Navigator.pop(context);
                  },
                ),
              ),
            ],
          ),
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

    return ListTile(
      leading: Icon(icon, color: color, size: 28),
      title: const Text('Trạng thái pin', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      subtitle: Text(text, style: TextStyle(fontSize: 16, color: color)),
    );
  }
}
