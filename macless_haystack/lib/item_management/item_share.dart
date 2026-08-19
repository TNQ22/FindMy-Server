import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:http/http.dart' as http;
import 'package:macless_haystack/dashboard/app_toast.dart';
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
      tooltip: 'Chia sẻ với người khác',
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
        AppToast.showText(
          context,
          'Vui lòng nhập email người thân muốn chia sẻ',
          icon: Icons.warning_amber_rounded,
          backgroundColor: Colors.amber.shade900,
        );
        return;
      }
    } else {
      targetId = _selectedUserId;
      if (targetId == null) {
        AppToast.showText(
          context,
          'Vui lòng chọn người dùng để chia sẻ',
          icon: Icons.warning_amber_rounded,
          backgroundColor: Colors.amber.shade900,
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
          AppToast.showText(
            context,
            data['message'] ?? 'Đã chia sẻ thiết bị thành công!',
            icon: Icons.check_circle,
            backgroundColor: Colors.teal.shade800,
          );
          _customEmailController.clear();
        }
        await _fetchData();
      } else {
        if (mounted) {
          AppToast.showText(
            context,
            data['detail'] ?? 'Chia sẻ thiết bị thất bại',
            icon: Icons.error_outline,
            backgroundColor: Colors.redAccent,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        AppToast.showText(
          context,
          'Lỗi: $e',
          icon: Icons.error_outline,
          backgroundColor: Colors.redAccent,
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Hủy chia sẻ Tag'),
        content: Text('Bạn có chắc muốn dừng chia sẻ Tag này với $email?'),
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
          AppToast.showText(
            context,
            'Đã hủy chia sẻ với $email',
            icon: Icons.check_circle,
            backgroundColor: Colors.teal.shade800,
          );
        }
        await _fetchData();
      } else {
        final data = jsonDecode(res.body);
        if (mounted) {
          AppToast.showText(
            context,
            data['detail'] ?? 'Hủy chia sẻ thất bại',
            icon: Icons.error_outline,
            backgroundColor: Colors.redAccent,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        AppToast.showText(
          context,
          'Lỗi kết nối: $e',
          icon: Icons.error_outline,
          backgroundColor: Colors.redAccent,
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _transferOwnership(int targetUserId, String targetEmail) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.workspace_premium, color: Colors.amber, size: 24),
            SizedBox(width: 8),
            Text('Trao quyền Sở hữu Tag', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Bạn có chắc chắn muốn trao toàn bộ quyền Chủ sở hữu Tag "${widget.accessory.name}" cho tài khoản $targetEmail không?\n\nSau khi trao quyền, tài khoản này sẽ trở thành Chủ sở hữu chính của Tag.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber.shade800,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.check, size: 16),
            label: const Text('Xác nhận trao quyền'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _submitting = true);

    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/api/devices/transfer-ownership'),
        headers: _authHeaders,
        body: jsonEncode({
          'hashed_adv_key': widget.accessory.hashedPublicKey,
          'target_user_id': targetUserId,
        }),
      );

      final data = jsonDecode(res.body);
      if (res.statusCode == 200) {
        if (mounted) {
          AppToast.showText(
            context,
            data['message'] ?? 'Đã chuyển giao quyền Chủ sở hữu thành công!',
            icon: Icons.check_circle,
            backgroundColor: Colors.teal.shade800,
          );
        }
        await _fetchData();
      } else {
        if (mounted) {
          AppToast.showText(
            context,
            data['detail'] ?? 'Chuyển giao quyền sở hữu thất bại',
            icon: Icons.error_outline,
            backgroundColor: Colors.redAccent,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        AppToast.showText(
          context,
          'Lỗi: $e',
          icon: Icons.error_outline,
          backgroundColor: Colors.redAccent,
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final isMobile = mediaQuery.size.width < 600;
    final bool isCurrentOwner = !_sharedUsers.any((u) => u['is_owner'] == true);

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
          maxHeight: mediaQuery.size.height * 0.88,
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
                    child: const Icon(Icons.share, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Chia Sẻ "${widget.accessory.name}"',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: isMobile ? 16 : 18,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Chia sẻ quyền theo dõi vị trí với người khác',
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

            // Sub Tab Bar (Giống tab con trong cài đặt thông báo)
            Container(
              color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.35),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => setState(() => _useCustomEmail = false),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: !_useCustomEmail ? Colors.teal : Colors.transparent,
                              width: 3,
                            ),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.people_alt_outlined,
                              size: 18,
                              color: !_useCustomEmail ? Colors.teal : Colors.grey.shade600,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Chọn tài khoản',
                              style: TextStyle(
                                color: !_useCustomEmail ? Colors.teal : Colors.grey.shade600,
                                fontWeight: !_useCustomEmail ? FontWeight.bold : FontWeight.normal,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: InkWell(
                      onTap: () => setState(() => _useCustomEmail = true),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: _useCustomEmail ? Colors.teal : Colors.transparent,
                              width: 3,
                            ),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.alternate_email,
                              size: 18,
                              color: _useCustomEmail ? Colors.teal : Colors.grey.shade600,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Nhập Email khác',
                              style: TextStyle(
                                color: _useCustomEmail ? Colors.teal : Colors.grey.shade600,
                                fontWeight: _useCustomEmail ? FontWeight.bold : FontWeight.normal,
                                fontSize: 13,
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

            // Content
            Flexible(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: isMobile ? 14 : 20,
                  vertical: 14,
                ),
                child: _loading
                    ? const SizedBox(
                        height: 180,
                        child: Center(child: CircularProgressIndicator(color: Colors.teal)),
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
                                  'Chia sẻ vị trí Tag này cho tài khoản khác trên hệ thống FindMy:',
                                  style: TextStyle(fontSize: 13, color: Colors.grey),
                                ),
                                const SizedBox(height: 14),

                                if (!_useCustomEmail && _availableUsers.isNotEmpty) ...[
                                  DropdownButtonFormField<int>(
                                    value: _selectedUserId,
                                    decoration: const InputDecoration(
                                      labelText: 'Chia sẻ với',
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
                                      labelText: 'Chia sẻ với (Email)',
                                      hintText: 'nguoidung@gmail.com',
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

                                const SizedBox(height: 16),
                                const Divider(),
                                const SizedBox(height: 8),

                                Row(
                                  children: [
                                    const Icon(Icons.people_outline, size: 18, color: Colors.teal),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Danh sách người dùng liên kết (${_sharedUsers.length})',
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
                                      final bool isOwner = su['is_owner'] == true;

                                      return Card(
                                        margin: const EdgeInsets.only(bottom: 8),
                                        elevation: 0.5,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(10),
                                          side: BorderSide(
                                            color: isOwner ? Colors.amber.shade300 : Colors.grey.withAlpha(50),
                                            width: isOwner ? 1.5 : 1.0,
                                          ),
                                        ),
                                        child: ListTile(
                                          dense: true,
                                          leading: CircleAvatar(
                                            radius: 16,
                                            backgroundColor: isOwner ? Colors.amber.shade100 : Colors.teal.shade100,
                                            child: Icon(
                                              isOwner ? Icons.workspace_premium : Icons.person,
                                              size: 18,
                                              color: isOwner ? Colors.amber.shade900 : Colors.teal.shade900,
                                            ),
                                          ),
                                          title: Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  su['email'] ?? '',
                                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              if (isOwner)
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: Colors.amber.shade100,
                                                    borderRadius: BorderRadius.circular(6),
                                                    border: Border.all(color: Colors.amber.shade400),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Icon(Icons.star, size: 12, color: Colors.amber.shade900),
                                                      const SizedBox(width: 4),
                                                      Text(
                                                        'Chủ sở hữu',
                                                        style: TextStyle(
                                                          fontSize: 10,
                                                          fontWeight: FontWeight.bold,
                                                          color: Colors.amber.shade900,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                            ],
                                          ),
                                          subtitle: su['name'] != null && su['name'].toString().isNotEmpty
                                              ? Text(su['name'], style: const TextStyle(fontSize: 11))
                                              : null,
                                          trailing: isOwner
                                              ? null
                                              : (isCurrentOwner
                                                  ? Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        IconButton(
                                                          icon: const Icon(Icons.workspace_premium_outlined, color: Colors.amber, size: 20),
                                                          tooltip: 'Trao quyền Chủ sở hữu',
                                                          onPressed: _submitting ? null : () => _transferOwnership(su['user_id'], su['email']),
                                                        ),
                                                        IconButton(
                                                          icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                                                          tooltip: 'Hủy chia sẻ',
                                                          onPressed: _submitting ? null : () => _unshareDevice(su['device_id'], su['email']),
                                                        ),
                                                      ],
                                                    )
                                                  : null),
                                        ),
                                      );
                                    }).toList(),
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
