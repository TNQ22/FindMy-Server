import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:macless_haystack/dashboard/app_toast.dart';
import 'package:provider/provider.dart';
import 'package:macless_haystack/accessory/accessory_registry.dart';
import 'package:macless_haystack/location/location_model.dart';
import 'package:macless_haystack/zones/zone_model.dart';
import 'package:macless_haystack/zones/zone_registry.dart';
import 'package:macless_haystack/zones/zone_map_picker.dart';

class ZoneFormDialog extends StatefulWidget {
  final ZoneItem? zone;

  const ZoneFormDialog({super.key, this.zone});

  @override
  State<ZoneFormDialog> createState() => _ZoneFormDialogState();
}

class _ZoneFormDialogState extends State<ZoneFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameController;
  late TextEditingController _latController;
  late TextEditingController _lonController;

  late double _radius;
  late String _shapeType;
  late List<LatLng> _polygonPoints;
  late bool _alertOnExit;
  late bool _alertOnEnter;
  late int _cooldownMinutes;
  late bool _isActive;
  late Set<String> _selectedHashedKeys;

  bool _submitting = false;

  final List<double> _presetRadiuses = [50, 100, 200, 500, 1000, 2000, 5000];

  @override
  void initState() {
    super.initState();
    final z = widget.zone;
    _nameController = TextEditingController(text: z?.name ?? '');
    _latController = TextEditingController(text: z?.latitude.toString() ?? '');
    _lonController = TextEditingController(text: z?.longitude.toString() ?? '');

    _radius = z?.radius ?? 100.0;
    _shapeType = z?.shapeType ?? 'circle';
    _polygonPoints = z != null ? List<LatLng>.from(z.polygonPoints) : [];
    _alertOnExit = z?.alertOnExit ?? true;
    _alertOnEnter = z?.alertOnEnter ?? false;
    _cooldownMinutes = z?.cooldownMinutes ?? 15;
    _isActive = z?.isActive ?? true;

    _selectedHashedKeys = z != null ? z.devices.map((d) => d.hashedAdvKey).toSet() : {};
  }

  @override
  void dispose() {
    _nameController.dispose();
    _latController.dispose();
    _lonController.dispose();
    super.dispose();
  }

  void _useCurrentLocation() {
    final locationModel = Provider.of<LocationModel>(context, listen: false);
    if (locationModel.here != null) {
      setState(() {
        _latController.text = locationModel.here!.latitude.toStringAsFixed(6);
        _lonController.text = locationModel.here!.longitude.toStringAsFixed(6);
      });
    } else {
      AppToast.showText(
        context,
        'Chưa lấy được vị trí GPS thiết bị này.',
        icon: Icons.location_off,
        backgroundColor: Colors.amber.shade900,
      );
    }
  }

  void _useAccessoryLocation(double lat, double lon, [String? hashedAdvKey]) {
    setState(() {
      _latController.text = lat.toStringAsFixed(6);
      _lonController.text = lon.toStringAsFixed(6);
      if (hashedAdvKey != null) {
        _selectedHashedKeys.add(hashedAdvKey);
      }
    });
  }

  void _openMapPicker() async {
    final lat = double.tryParse(_latController.text.trim());
    final lon = double.tryParse(_lonController.text.trim());
    LatLng? initialLoc;
    if (lat != null && lon != null) {
      initialLoc = LatLng(lat, lon);
    }

    final result = await Navigator.push<ZoneMapPickerResult>(
      context,
      MaterialPageRoute(
        builder: (ctx) => ZoneMapPicker(
          initialLocation: initialLoc,
          initialRadius: _radius,
          initialShapeType: _shapeType,
          initialPolygonPoints: _polygonPoints,
        ),
      ),
    );

    if (result != null && mounted) {
      setState(() {
        _latController.text = result.location.latitude.toStringAsFixed(6);
        _lonController.text = result.location.longitude.toStringAsFixed(6);
        _radius = result.radius;
        _shapeType = result.shapeType;
        _polygonPoints = result.polygonPoints;
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final lat = double.tryParse(_latController.text.trim());
    final lon = double.tryParse(_lonController.text.trim());
    if (lat == null || lon == null) {
      AppToast.showText(
        context,
        'Tọa độ không hợp lệ.',
        icon: Icons.error_outline,
        backgroundColor: Colors.red.shade700,
      );
      return;
    }

    setState(() => _submitting = true);
    final registry = Provider.of<ZoneRegistry>(context, listen: false);

    bool ok = false;
    if (widget.zone == null) {
      ok = await registry.createZone(
        name: _nameController.text.trim(),
        latitude: lat,
        longitude: lon,
        radius: _radius,
        shapeType: _shapeType,
        polygonPoints: _polygonPoints,
        alertOnExit: _alertOnExit,
        alertOnEnter: _alertOnEnter,
        cooldownMinutes: _cooldownMinutes,
        isActive: _isActive,
        hashedAdvKeys: _selectedHashedKeys.toList(),
      );
    } else {
      ok = await registry.updateZone(
        zoneId: widget.zone!.id,
        name: _nameController.text.trim(),
        latitude: lat,
        longitude: lon,
        radius: _radius,
        shapeType: _shapeType,
        polygonPoints: _polygonPoints,
        alertOnExit: _alertOnExit,
        alertOnEnter: _alertOnEnter,
        cooldownMinutes: _cooldownMinutes,
        isActive: _isActive,
        hashedAdvKeys: _selectedHashedKeys.toList(),
      );
    }

    if (mounted) {
      setState(() => _submitting = false);
      if (ok) {
        Navigator.pop(context, true);
      } else {
        AppToast.showText(
          context,
          'Có lỗi xảy ra khi lưu khu vực.',
          icon: Icons.error_outline,
          backgroundColor: Colors.red.shade700,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final accessories = Provider.of<AccessoryRegistry>(context).accessories;
    final isEditing = widget.zone != null;
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
          maxWidth: isMobile ? double.infinity : 600,
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
                    child: Icon(
                      isEditing ? Icons.edit_location_alt_outlined : Icons.add_location_alt_outlined,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isEditing ? 'Chỉnh Sửa Khu Vực An Toàn' : 'Tạo Khu Vực An Toàn Mới',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: isMobile ? 16 : 18,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Cấu hình bán kính hoặc vùng đa giác định vị',
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

            // Form Body
            Expanded(
              child: Padding(
                padding: EdgeInsets.all(isMobile ? 12 : 18),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [

              // Form fields
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(top: 4, bottom: 4),
                  children: [
                    // Tên khu vực
                    TextFormField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        labelText: 'Tên khu vực',
                        hintText: 'VD: Nhà riêng, Công ty, Bãi gửi xe...',
                        prefixIcon: const Icon(Icons.label_outline),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      validator: (val) => (val == null || val.trim().isEmpty) ? 'Vui lòng nhập tên khu vực' : null,
                    ),
                    const SizedBox(height: 16),

                    // Thiết lập vùng an toàn qua Bản đồ
                    InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: _openMapPicker,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.teal.shade900.withOpacity(0.3)
                              : Colors.teal.shade50,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.teal.withOpacity(0.4), width: 1.5),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.teal,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                _shapeType == 'polygon' ? Icons.polyline : Icons.map_outlined,
                                color: Colors.white,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Thiết lập vùng trên Bản đồ',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    _shapeType == 'polygon'
                                        ? 'Đa giác • ${_polygonPoints.length} điểm đỉnh'
                                        : 'Hình tròn • Bán kính: ${_radius >= 1000 ? "${(_radius / 1000).toStringAsFixed(1)} km" : "${_radius.toInt()} m"}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(context).brightness == Brightness.dark
                                          ? Colors.tealAccent
                                          : Colors.teal.shade800,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.teal,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              onPressed: _openMapPicker,
                              child: const Text('Mở bản đồ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Danh sách Thẻ định vị áp dụng
                    const Text(
                      'Thẻ định vị áp dụng vùng này:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    if (accessories.isEmpty)
                      const Text(
                        'Chưa có thẻ định vị nào trong tài khoản.',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      )
                    else
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: accessories.map((acc) {
                            final checked = _selectedHashedKeys.contains(acc.hashedPublicKey);
                            return CheckboxListTile(
                              dense: true,
                              value: checked,
                              title: Text(acc.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Text(
                                acc.lastLocation != null ? 'Đã có vị trí gần nhất' : 'Chưa có vị trí',
                                style: const TextStyle(fontSize: 11),
                              ),
                              onChanged: (val) {
                                setState(() {
                                  if (val == true) {
                                    _selectedHashedKeys.add(acc.hashedPublicKey);
                                  } else {
                                    _selectedHashedKeys.remove(acc.hashedPublicKey);
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ),
                      ),
                    const SizedBox(height: 18),

                    // Cấu hình Cảnh báo
                    const Text(
                      'Tùy chọn Cảnh báo:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 6),
                    SwitchListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      secondary: const Icon(Icons.exit_to_app, color: Colors.red),
                      title: const Text('Cảnh báo khi RỜI KHỎI (Exit)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      subtitle: const Text('Gửi thông báo khi thẻ di chuyển ra ngoài vùng an toàn', style: TextStyle(fontSize: 11)),
                      value: _alertOnExit,
                      onChanged: (val) => setState(() => _alertOnExit = val),
                    ),
                    SwitchListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      secondary: const Icon(Icons.login, color: Colors.green),
                      title: const Text('Cảnh báo khi ĐI VÀO (Enter)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      subtitle: const Text('Gửi thông báo khi thẻ di chuyển vào lại vùng an toàn', style: TextStyle(fontSize: 11)),
                      value: _alertOnEnter,
                      onChanged: (val) => setState(() => _alertOnEnter = val),
                    ),
                    const SizedBox(height: 10),

                    // Thời gian Cooldown
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Thời gian giãn cách (Cooldown):', style: TextStyle(fontSize: 13)),
                        DropdownButton<int>(
                          value: _cooldownMinutes,
                          items: const [
                            DropdownMenuItem(value: 5, child: Text('5 phút')),
                            DropdownMenuItem(value: 10, child: Text('10 phút')),
                            DropdownMenuItem(value: 15, child: Text('15 phút')),
                            DropdownMenuItem(value: 30, child: Text('30 phút')),
                            DropdownMenuItem(value: 60, child: Text('1 giờ')),
                          ],
                          onChanged: (val) {
                            if (val != null) setState(() => _cooldownMinutes = val);
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 10),

              // Buttons & Active Switch (Trái: Kích hoạt theo dõi, Phải: Hủy bỏ & Tạo khu vực, tự xuống dòng khi màn hình hẹp)
              LayoutBuilder(
                builder: (context, constraints) {
                  final isCompact = constraints.maxWidth < 440;

                  final leftSwitch = InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => setState(() => _isActive = !_isActive),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Switch(
                            value: _isActive,
                            activeColor: Colors.teal,
                            onChanged: (val) => setState(() => _isActive = val),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Kích hoạt theo dõi',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: _isActive ? Colors.teal : Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );

                  final rightButtons = Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: _submitting ? null : () => Navigator.pop(context),
                        child: const Text('Hủy bỏ'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: _submitting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.check, size: 18),
                        label: Text(isEditing ? 'Lưu thay đổi' : 'Tạo Khu vực'),
                        onPressed: _submitting ? null : _submit,
                      ),
                    ],
                  );

                  if (isCompact) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        leftSwitch,
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: rightButtons,
                        ),
                      ],
                    );
                  }

                  return Row(
                    children: [
                      leftSwitch,
                      const Spacer(),
                      rightButtons,
                    ],
                  );
                },
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
}
