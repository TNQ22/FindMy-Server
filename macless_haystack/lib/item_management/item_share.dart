import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:http/http.dart' as http;
import 'package:universal_html/html.dart' as html;
import 'package:macless_haystack/accessory/accessory_model.dart';
import 'package:macless_haystack/preferences/user_preferences_model.dart';

class ItemShareAction extends StatelessWidget {
  final Accessory accessory;

  const ItemShareAction({
    super.key,
    required this.accessory,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Chia sẻ cho người thân',
      icon: const Icon(Icons.share, color: Colors.teal),
      onPressed: () {
        showDialog(
          context: context,
          builder: (ctx) => ItemShareDialog(accessory: accessory),
        );
      },
    );
  }
}

class ItemShareDialog extends StatefulWidget {
  final Accessory accessory;

  const ItemShareDialog({
    super.key,
    required this.accessory,
  });

  @override
  State<ItemShareDialog> createState() => _ItemShareDialogState();
}

class _ItemShareDialogState extends State<ItemShareDialog> {
  bool _loading = true;
  bool _submitting = false;
  String? _errorMessage;

  List<dynamic> _availableUsers = [];
  List<dynamic> _sharedUsers = [];

  int? _selectedUserId;
  final TextEditingController _customEmailController = TextEditingController();
  bool _useCustomEmail = false;

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

  Map<String, String> get _authHeaders {
    String token = Settings.getValue<String>(endpointUser, defaultValue: '')!;
    if (token.isEmpty) {
      try {
        token = html.window.localStorage['ENDPOINT_USER'] ?? '';
      } catch (_) {}
    }
    return {
      'Content-Type': 'application/json',
      if (token.isNotEmpty)
        'Authorization': token.trim().startsWith('Bearer ') ? token.trim() : 'Bearer ${token.trim()}',
    };
  }

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  @override
  void dispose() {
    _customEmailController.dispose();
    super.dispose();
  }

  Future<void> _fetchData() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final key = widget.accessory.hashedPublicKey;
      final encodedKey = Uri.encodeComponent(key);

      final usersFuture = http.get(
        Uri.parse('$_baseUrl/api/devices/available-users'),
        headers: _authHeaders,
      );
      final sharedFuture = http.get(
        Uri.parse('$_baseUrl/api/devices/shared-with?hashed_adv_key=$encodedKey'),
        headers: _authHeaders,
      );

      final results = await Future.wait([usersFuture, sharedFuture]);
      final usersRes = results[0];
      final sharedRes = results[1];

      if (usersRes.statusCode == 200 && sharedRes.statusCode == 200) {
        final List<dynamic> users = jsonDecode(usersRes.body);
        final List<dynamic> shared = jsonDecode(sharedRes.body);

        setState(() {
          _availableUsers = users;
          _sharedUsers = shared;
          _loading = false;
          if (_availableUsers.isNotEmpty) {
            _selectedUserId = _availableUsers.first['id'];
          }
        });
      } else {
        setState(() {
          _errorMessage = 'Không thể tải thông tin chia sẻ từ máy chủ';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Lỗi kết nối máy chủ: $e';
        _loading = false;
      });
    }
  }

  Future<void> _shareDevice() async {
    String? targetEmail;
    int? targetId;

    if (_useCustomEmail || _availableUsers.isEmpty) {
      targetEmail = _customEmailController.text.trim();
      if (targetEmail.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vui lòng nhập email người thân muốn chia sẻ')),
        );
        return;
      }
    } else {
      targetId = _selectedUserId;
      if (targetId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vui lòng chọn người dùng để chia sẻ')),
        );
        return;
      }
    }

    setState(() => _submitting = true);

    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/api/devices/share'),
        headers: _authHeaders,
        body: jsonEncode({
          'hashed_adv_key': widget.accessory.hashedPublicKey,
          if (targetId != null) 'target_user_id': targetId,
          if (targetEmail != null) 'target_email': targetEmail,
        }),
      );

      final data = jsonDecode(res.body);
      if (res.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(data['message'] ?? 'Đã chia sẻ thiết bị thành công!'),
              backgroundColor: Colors.teal.shade800,
            ),
          );
          _customEmailController.clear();
        }
        await _fetchData();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(data['detail'] ?? 'Chia sẻ thiết bị thất bại'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _unshareDevice(int targetDeviceId, String email) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hủy chia sẻ Tag'),
        content: Text('Bạn có chắc muốn dừng chia sẻ Tag này với $email?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Dừng chia sẻ'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _submitting = true);

    try {
      final res = await http.delete(
        Uri.parse('$_baseUrl/api/devices/shared-with/$targetDeviceId'),
        headers: _authHeaders,
      );

      if (res.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Đã hủy chia sẻ với $email')),
          );
        }
        await _fetchData();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Hủy chia sẻ thất bại'), backgroundColor: Colors.redAccent),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi kết nối: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      title: Row(
        children: [
          const Icon(Icons.share, color: Colors.teal),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Chia sẻ "${widget.accessory.name}"',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: _loading
            ? const SizedBox(
                height: 180,
                child: Center(child: CircularProgressIndicator()),
              )
            : _errorMessage != null
                ? SizedBox(
                    height: 180,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.refresh),
                            label: const Text('Thử lại'),
                            onPressed: _fetchData,
                          ),
                        ],
                      ),
                    ),
                  )
                : SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Chia sẻ vị trí Tag này cho người thân có tài khoản trên hệ thống FindMy:',
                          style: TextStyle(fontSize: 13, color: Colors.grey),
                        ),
                        const SizedBox(height: 16),

                        // Option to toggle between dropdown and manual email
                        if (_availableUsers.isNotEmpty) ...[
                          Row(
                            children: [
                              ChoiceChip(
                                label: const Text('Chọn tài khoản'),
                                selected: !_useCustomEmail,
                                onSelected: (sel) {
                                  if (sel) setState(() => _useCustomEmail = false);
                                },
                              ),
                              const SizedBox(width: 8),
                              ChoiceChip(
                                label: const Text('Nhập Email khác'),
                                selected: _useCustomEmail,
                                onSelected: (sel) {
                                  if (sel) setState(() => _useCustomEmail = true);
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                        ],

                        if (!_useCustomEmail && _availableUsers.isNotEmpty) ...[
                          DropdownButtonFormField<int>(
                            value: _selectedUserId,
                            decoration: const InputDecoration(
                              labelText: 'Người thân',
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            ),
                            items: _availableUsers.map<DropdownMenuItem<int>>((u) {
                              return DropdownMenuItem<int>(
                                value: u['id'],
                                child: Text('${u['email']} (${u['name'] ?? 'User'})'),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() => _selectedUserId = val);
                              }
                            },
                          ),
                        ] else ...[
                          TextField(
                            controller: _customEmailController,
                            keyboardType: TextInputType.emailAddress,
                            decoration: const InputDecoration(
                              labelText: 'Email người thân',
                              hintText: 'nguoithan@gmail.com',
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              prefixIcon: Icon(Icons.email_outlined),
                            ),
                          ),
                        ],

                        const SizedBox(height: 14),

                        Align(
                          alignment: Alignment.centerRight,
                          child: ElevatedButton.icon(
                            onPressed: _submitting ? null : _shareDevice,
                            icon: _submitting
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Icon(Icons.person_add, size: 18),
                            label: const Text('Chia sẻ ngay'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.teal,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),

                        const SizedBox(height: 18),
                        const Divider(),
                        const SizedBox(height: 8),

                        Row(
                          children: [
                            const Icon(Icons.people_outline, size: 18, color: Colors.teal),
                            const SizedBox(width: 6),
                            Text(
                              'Đang chia sẻ với (${_sharedUsers.length})',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),

                        if (_sharedUsers.isEmpty)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.grey.withAlpha(25),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Center(
                              child: Text(
                                'Tag này chưa được chia sẻ với ai.',
                                style: TextStyle(color: Colors.grey, fontSize: 13),
                              ),
                            ),
                          )
                        else
                          Column(
                            children: _sharedUsers.map<Widget>((su) {
                              return Card(
                                margin: const EdgeInsets.only(bottom: 6),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  side: BorderSide(color: Colors.grey.withAlpha(50)),
                                ),
                                child: ListTile(
                                  dense: true,
                                  leading: CircleAvatar(
                                    radius: 16,
                                    backgroundColor: Colors.teal.shade100,
                                    child: Text(
                                      (su['name'] != null && su['name'].toString().isNotEmpty)
                                          ? su['name'].toString().substring(0, 1).toUpperCase()
                                          : 'U',
                                      style: TextStyle(color: Colors.teal.shade900, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  title: Text(
                                    su['email'] ?? '',
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                  ),
                                  subtitle: su['name'] != null && su['name'].toString().isNotEmpty
                                      ? Text(su['name'], style: const TextStyle(fontSize: 11))
                                      : null,
                                  trailing: IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                                    tooltip: 'Dừng chia sẻ',
                                    onPressed: _submitting ? null : () => _unshareDevice(su['device_id'], su['email']),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                      ],
                    ),
                  ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Đóng'),
        ),
      ],
    );
  }
}
