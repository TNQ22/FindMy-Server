import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:macless_haystack/accessory/accessory_color_selector.dart';
import 'package:macless_haystack/accessory/accessory_icon_model.dart';
import 'package:macless_haystack/accessory/accessory_icon_selector.dart';
import 'package:macless_haystack/item_management/accessory_color_input.dart';
import 'package:macless_haystack/item_management/accessory_icon_input.dart';
import 'package:macless_haystack/preferences/auth_state.dart';
import 'package:macless_haystack/preferences/user_preferences_model.dart';
import 'package:universal_html/html.dart' as html;

class AdminAddTagDialog extends StatefulWidget {
  final int userId;
  final String userEmail;

  const AdminAddTagDialog({super.key, required this.userId, required this.userEmail});

  @override
  State<AdminAddTagDialog> createState() => _AdminAddTagDialogState();
}

class _AdminAddTagDialogState extends State<AdminAddTagDialog> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _keyController = TextEditingController();
  
  String _selectedIconStr = 'mappin';
  Color _selectedColor = Colors.blue;
  
  bool _loading = false;
  String? _error;

  String get _baseUrl {
    try {
      String origin = html.window.location.origin;
      if (origin.startsWith('http')) return origin;
    } catch (_) {}
    String configuredUrl = Settings.getValue<String>(endpointUrl, defaultValue: '')!;
    if (configuredUrl.endsWith('/')) {
      configuredUrl = configuredUrl.substring(0, configuredUrl.length - 1);
    }
    return configuredUrl.isEmpty ? 'http://localhost:6176' : configuredUrl;
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    final key = _keyController.text.trim();

    if (name.isEmpty || key.isEmpty) {
      setState(() => _error = 'Vui lòng nhập tên và khóa riêng');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    String rawPrivKey = key;
    try {
      final parsed = jsonDecode(key);
      if (parsed is Map && parsed.containsKey('privateKey')) {
        rawPrivKey = parsed['privateKey'].toString();
        if (parsed.containsKey('icon') && parsed['icon'] != null) {
          _selectedIconStr = parsed['icon'].toString();
        }
      }
    } catch (_) {}

    String colorHex = _selectedColor.value.toRadixString(16).padLeft(8, '0');
    final payloadJson = jsonEncode({
      'name': name,
      'icon': _selectedIconStr,
      'color': colorHex,
      'privateKey': rawPrivKey,
    });

    final token = Settings.getValue<String>(endpointUser, defaultValue: '')!;
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/api/admin/users/${widget.userId}/devices'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': token.trim().startsWith('Bearer ') ? token.trim() : 'Bearer ${token.trim()}',
        },
        body: jsonEncode({
          'name': name,
          'private_key_b64': payloadJson,
        }),
      );

      if (res.statusCode == 200) {
        if (mounted) Navigator.pop(context, true);
      } else {
        final data = jsonDecode(res.body);
        setState(() => _error = data['detail'] ?? 'Lỗi không xác định');
      }
    } catch (e) {
      setState(() => _error = 'Lỗi kết nối máy chủ');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    IconData currentIconData = AccessoryIconModel.mapIcon(_selectedIconStr) ?? Icons.push_pin;

    return AlertDialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 24,
        vertical: isMobile ? 16 : 24,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text('Thêm Tag cho ${widget.userEmail}', style: TextStyle(fontSize: isMobile ? 16 : 18)),
      content: SizedBox(
        width: isMobile ? double.maxFinite : 480.0,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
            if (_error != null)
              Container(
                padding: const EdgeInsets.all(8),
                margin: const EdgeInsets.only(bottom: 12),
                color: Colors.red.withOpacity(0.1),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Tên Tag (VD: Chìa khóa xe, Balo)',
                icon: Icon(Icons.label_outline),
              ),
            ),
            const SizedBox(height: 12),
            AccessoryIconInput(
              initialIcon: currentIconData,
              iconString: _selectedIconStr,
              color: _selectedColor,
              changeListener: (String? newIconStr) {
                if (newIconStr != null) {
                  setState(() {
                    _selectedIconStr = newIconStr;
                  });
                }
              },
            ),
            const SizedBox(height: 8),
            AccessoryColorInput(
              color: _selectedColor,
              changeListener: (Color? newColor) {
                if (newColor != null) {
                  setState(() {
                    _selectedColor = newColor;
                  });
                }
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _keyController,
              decoration: const InputDecoration(
                labelText: 'Khóa riêng (Base64 hoặc JSON)',
                icon: Icon(Icons.key),
              ),
              maxLines: 3,
            ),
          ],
        ),
      ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context, false),
          child: const Text('Hủy'),
        ),
        ElevatedButton(
          onPressed: _loading ? null : _submit,
          child: _loading
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Thêm Tag'),
        ),
      ],
    );
  }
}
