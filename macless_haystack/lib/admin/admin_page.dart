import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:macless_haystack/preferences/auth_state.dart';
import 'package:macless_haystack/admin/admin_add_tag_dialog.dart';
import 'package:macless_haystack/preferences/user_preferences_model.dart';
import 'package:universal_html/html.dart' as html;
import 'package:file_picker/file_picker.dart';

class AdminPage extends StatefulWidget {
  const AdminPage({super.key});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
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
  
  List<dynamic> _users = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchUsers();
  }

  Future<void> _fetchUsers() async {
    setState(() => _loading = true);
    final token = Settings.getValue<String>(endpointUser, defaultValue: '')!;
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/api/admin/users'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': token.trim().startsWith('Bearer ') ? token.trim() : 'Bearer ${token.trim()}',
        },
      );
      if (res.statusCode == 200) {
        setState(() {
          _users = jsonDecode(res.body);
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
        _showError('Không thể tải danh sách người dùng (Lỗi ${res.statusCode})');
      }
    } catch (e) {
      setState(() => _loading = false);
      _showError('Lỗi kết nối máy chủ');
    }
  }

  Future<void> _deleteUser(int userId, String email) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa Người dùng'),
        content: Text('Bạn có chắc chắn muốn xóa toàn bộ dữ liệu của $email?\nHành động này không thể hoàn tác.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final token = Settings.getValue<String>(endpointUser, defaultValue: '')!;
    try {
      final res = await http.delete(
        Uri.parse('$_baseUrl/api/admin/users/$userId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': token.trim().startsWith('Bearer ') ? token.trim() : 'Bearer ${token.trim()}',
        },
      );
      if (res.statusCode == 200) {
        _fetchUsers();
      } else {
        _showError('Xóa thất bại (Lỗi ${res.statusCode})');
      }
    } catch (e) {
      _showError('Lỗi kết nối');
    }
  }

  Future<void> _changeRole(int userId, bool makeAdmin) async {
    setState(() => _loading = true);
    final token = Settings.getValue<String>(endpointUser, defaultValue: '')!;
    try {
      final res = await http.put(
        Uri.parse('$_baseUrl/api/admin/users/$userId/role'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': token.trim().startsWith('Bearer ') ? token.trim() : 'Bearer ${token.trim()}',
        },
        body: jsonEncode({'is_admin': makeAdmin}),
      );
      if (res.statusCode == 200) {
        _fetchUsers();
      } else {
        setState(() => _loading = false);
        final data = jsonDecode(res.body);
        _showError(data['detail'] ?? 'Cập nhật quyền thất bại');
      }
    } catch (e) {
      setState(() => _loading = false);
      _showError('Lỗi kết nối');
    }
  }

  void _showError(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
    }
  }

  void _showSuccess(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.teal.shade800));
    }
  }

  Future<void> _importTags(int userId) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json', 'keys'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      if (file.bytes == null) {
        _showError('Không thể đọc dữ liệu file');
        return;
      }

      final content = utf8.decode(file.bytes!);
      final dynamic parsed = jsonDecode(content);
      List<dynamic> keysToImport = [];

      if (parsed is List) {
        keysToImport = parsed;
      } else if (parsed is Map && parsed.containsKey('keys') && parsed['keys'] is List) {
        keysToImport = parsed['keys'];
      } else {
        _showError('Định dạng JSON không hợp lệ');
        return;
      }

      if (keysToImport.isEmpty) {
        _showError('Không tìm thấy tag nào trong file');
        return;
      }

      setState(() => _loading = true);
      int successCount = 0;
      int failCount = 0;
      final token = Settings.getValue<String>(endpointUser, defaultValue: '')!;

      for (var k in keysToImport) {
        final name = k['name']?.toString() ?? 'Imported Tag';
        final privKey = k['privateKey']?.toString() ?? '';

        if (privKey.isEmpty) continue;

        try {
          final res = await http.post(
            Uri.parse('$_baseUrl/api/admin/users/$userId/devices'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': token.trim().startsWith('Bearer ') ? token.trim() : 'Bearer ${token.trim()}',
            },
            body: jsonEncode({
              'name': name,
              'private_key_b64': privKey,
            }),
          );
          if (res.statusCode == 200) {
            successCount++;
          } else {
            failCount++;
          }
        } catch (_) {
          failCount++;
        }
      }

      _fetchUsers(); // also resets loading
      _showSuccess('Nhập thành công $successCount tags' + (failCount > 0 ? ', $failCount thất bại' : ''));

    } catch (e) {
      if (mounted) setState(() => _loading = false);
      _showError('Lỗi đọc file: ${e.toString()}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trang Quản trị'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchUsers,
          )
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetchUsers,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _users.length,
                itemBuilder: (context, index) {
                  final u = _users[index];
                  final bool isAdmin = u['is_admin'] == true;
                  return Card(
                    elevation: 2,
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundImage: u['picture'] != null ? NetworkImage(u['picture']) : null,
                        child: u['picture'] == null ? const Icon(Icons.person) : null,
                      ),
                      title: Row(
                        children: [
                          Expanded(child: Text(u['email'], style: const TextStyle(fontWeight: FontWeight.bold))),
                          if (isAdmin)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: Colors.orange, borderRadius: BorderRadius.circular(4)),
                              child: const Text('ADMIN', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                            )
                        ],
                      ),
                      subtitle: Text('Tên: ${u['name']} \nSố Tag: ${u['device_count']}'),
                      isThreeLine: true,
                      trailing: PopupMenuButton<String>(
                        onSelected: (val) {
                          if (val == 'add_tag') {
                            showDialog(
                              context: context,
                              builder: (_) => AdminAddTagDialog(userId: u['id'], userEmail: u['email']),
                            ).then((value) {
                              if (value == true) _fetchUsers();
                            });
                          } else if (val == 'delete') {
                            _deleteUser(u['id'], u['email']);
                          } else if (val == 'promote') {
                            _changeRole(u['id'], true);
                          } else if (val == 'demote') {
                            _changeRole(u['id'], false);
                          } else if (val == 'import') {
                            _importTags(u['id']);
                          } else if (val == 'share_tags') {
                            showDialog(
                              context: context,
                              builder: (_) => AdminShareTagsDialog(
                                userId: u['id'],
                                userEmail: u['email'],
                                allUsers: _users,
                              ),
                            ).then((_) => _fetchUsers());
                          }
                        },
                        itemBuilder: (BuildContext context) => [
                          const PopupMenuItem(
                            value: 'add_tag',
                            child: Row(children: [Icon(Icons.add_link, color: Colors.teal, size: 20), SizedBox(width: 8), Text('Thêm Tag')]),
                          ),
                          const PopupMenuItem(
                            value: 'import',
                            child: Row(children: [Icon(Icons.file_upload, color: Colors.green, size: 20), SizedBox(width: 8), Text('Import từ File')]),
                          ),
                          const PopupMenuItem(
                            value: 'share_tags',
                            child: Row(children: [Icon(Icons.share, color: Colors.teal, size: 20), SizedBox(width: 8), Text('Quản lý & Share Tag')]),
                          ),
                          if (!isAdmin)
                            const PopupMenuItem(
                              value: 'promote',
                              child: Row(children: [Icon(Icons.admin_panel_settings, color: Colors.orange, size: 20), SizedBox(width: 8), Text('Thăng quyền Admin')]),
                            ),
                          if (isAdmin)
                            const PopupMenuItem(
                              value: 'demote',
                              child: Row(children: [Icon(Icons.person, color: Colors.grey, size: 20), SizedBox(width: 8), Text('Hủy quyền Admin')]),
                            ),
                          if (!isAdmin)
                            const PopupMenuItem(
                              value: 'delete',
                              child: Row(children: [Icon(Icons.delete, color: Colors.red, size: 20), SizedBox(width: 8), Text('Xóa')]),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}

class AdminShareTagsDialog extends StatefulWidget {
  final int userId;
  final String userEmail;
  final List<dynamic> allUsers;

  const AdminShareTagsDialog({
    super.key,
    required this.userId,
    required this.userEmail,
    required this.allUsers,
  });

  @override
  State<AdminShareTagsDialog> createState() => _AdminShareTagsDialogState();
}

class _AdminShareTagsDialogState extends State<AdminShareTagsDialog> {
  List<dynamic> _userDevices = [];
  bool _loading = true;
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

  @override
  void initState() {
    super.initState();
    _fetchUserDevices();
  }

  Future<void> _fetchUserDevices() async {
    setState(() => _loading = true);
    final token = Settings.getValue<String>(endpointUser, defaultValue: '')!;
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/api/admin/users/${widget.userId}/devices'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': token.trim().startsWith('Bearer ') ? token.trim() : 'Bearer ${token.trim()}',
        },
      );
      if (res.statusCode == 200) {
        setState(() {
          _userDevices = jsonDecode(res.body);
          _loading = false;
        });
      } else {
        setState(() {
          _error = 'Không thể tải danh sách Tag';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Lỗi kết nối máy chủ';
        _loading = false;
      });
    }
  }

  Future<void> _shareDeviceToTargetUser(dynamic device, int targetUserId, String targetUserEmail) async {
    final token = Settings.getValue<String>(endpointUser, defaultValue: '')!;
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/api/admin/share-device'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': token.trim().startsWith('Bearer ') ? token.trim() : 'Bearer ${token.trim()}',
        },
        body: jsonEncode({
          'device_id': device['id'],
          'target_user_id': targetUserId,
        }),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(data['message'] ?? 'Đã chia sẻ Tag thành công!')),
          );
        }
        _fetchUserDevices();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Lỗi khi chia sẻ Tag')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lỗi kết nối máy chủ')),
        );
      }
    }
  }

  Future<void> _unshareDevice(int targetDeviceId, String targetUserEmail) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hủy Chia Sẻ Tag'),
        content: Text('Bạn có chắc chắn muốn hủy chia sẻ Tag này đối với $targetUserEmail?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Hủy Share'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final token = Settings.getValue<String>(endpointUser, defaultValue: '')!;
    try {
      final res = await http.delete(
        Uri.parse('$_baseUrl/api/admin/devices/$targetDeviceId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': token.trim().startsWith('Bearer ') ? token.trim() : 'Bearer ${token.trim()}',
        },
      );
      if (res.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Đã hủy chia sẻ với $targetUserEmail')),
          );
        }
        _fetchUserDevices();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Hủy chia sẻ thất bại')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lỗi kết nối máy chủ')),
        );
      }
    }
  }

  void _showSharePicker(dynamic device) {
    final otherUsers = widget.allUsers.where((u) => u['id'] != widget.userId).toList();
    if (otherUsers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không có người dùng khác để chia sẻ')),
      );
      return;
    }

    int? selectedTargetId = otherUsers.first['id'];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          title: Text('Chia sẻ Tag "${device['name']}"'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Chọn người dùng để chia sẻ Tag từ ${widget.userEmail}:'),
              const SizedBox(height: 12),
              DropdownButton<int>(
                value: selectedTargetId,
                isExpanded: true,
                items: otherUsers.map<DropdownMenuItem<int>>((u) {
                  return DropdownMenuItem<int>(
                    value: u['id'],
                    child: Text('${u['email']} (${u['name']})'),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setDlgState(() => selectedTargetId = val);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                if (selectedTargetId != null) {
                  final targetUser = otherUsers.firstWhere((u) => u['id'] == selectedTargetId);
                  _shareDeviceToTargetUser(device, selectedTargetId!, targetUser['email']);
                }
              },
              child: const Text('Xác nhận Share'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Danh sách Tag của ${widget.userEmail}'),
      content: SizedBox(
        width: 520,
        height: 420,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
                : _userDevices.isEmpty
                    ? const Center(child: Text('Người dùng này chưa có Tag nào'))
                    : ListView.builder(
                        itemCount: _userDevices.length,
                        itemBuilder: (context, index) {
                          final dev = _userDevices[index];
                          final List sharedWith = dev['shared_with'] ?? [];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: CircleAvatar(
                                      backgroundColor: Colors.teal.shade100,
                                      child: const Icon(Icons.pin_drop, color: Colors.teal),
                                    ),
                                    title: Text(dev['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                                    subtitle: Text('ADV Key: ${dev['hashed_adv_key'].toString().substring(0, 15)}...'),
                                    trailing: ElevatedButton.icon(
                                      icon: const Icon(Icons.share, size: 16),
                                      label: const Text('Share'),
                                      onPressed: () => _showSharePicker(dev),
                                    ),
                                  ),
                                  if (sharedWith.isNotEmpty) ...[
                                    const Divider(height: 1),
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        const Icon(Icons.people_outline, size: 16, color: Colors.teal),
                                        const SizedBox(width: 4),
                                        const Text(
                                          'Đang chia sẻ với:',
                                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.teal),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 4,
                                      children: sharedWith.map<Widget>((sw) {
                                        return Chip(
                                          avatar: const CircleAvatar(
                                            backgroundColor: Colors.teal,
                                            child: Icon(Icons.person, size: 12, color: Colors.white),
                                          ),
                                          label: Text(sw['email'], style: const TextStyle(fontSize: 12)),
                                          deleteIcon: const Icon(Icons.close, size: 14, color: Colors.red),
                                          onDeleted: () => _unshareDevice(sw['device_id'], sw['email']),
                                          visualDensity: VisualDensity.compact,
                                          padding: const EdgeInsets.all(0),
                                        );
                                      }).toList(),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Đóng'),
        ),
      ],
    );
  }
}
