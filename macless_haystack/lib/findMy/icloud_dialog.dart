import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:macless_haystack/preferences/user_preferences_model.dart';
import 'package:universal_html/html.dart' as html;

class ICloudManagementDialog extends StatefulWidget {
  const ICloudManagementDialog({super.key});

  @override
  State<ICloudManagementDialog> createState() => _ICloudManagementDialogState();
}

class _ICloudManagementDialogState extends State<ICloudManagementDialog> {
  final _appleIdController = TextEditingController();
  final _passwordController = TextEditingController();
  final _otpController = TextEditingController();

  bool _loading = false;
  bool _showLoginForm = false;
  String? _statusMessage;
  String? _currentAppleId;
  String _loginState = "LOGGED_OUT";
  List<String> _twoFactorMethods = [];
  List<dynamic> _accounts = [];
  int _selectedMethodIndex = 0;

  @override
  void initState() {
    super.initState();
    _fetchStatus();
  }

  String get _baseUrl {
    try {
      String origin = html.window.location.origin;
      if (origin.startsWith('http')) {
        return origin;
      }
    } catch (_) {}
    String configuredUrl = Settings.getValue<String>(endpointUrl, defaultValue: '')!;
    if (configuredUrl.endsWith('/')) {
      configuredUrl = configuredUrl.substring(0, configuredUrl.length - 1);
    }
    return configuredUrl.isEmpty ? 'http://localhost:6176' : configuredUrl;
  }

  Map<String, String> get _headers {
    Map<String, String> headers = {'Content-Type': 'application/json'};
    String user = Settings.getValue<String>(endpointUser, defaultValue: '')!;
    String pass = Settings.getValue<String>(endpointPass, defaultValue: '')!;
    if (user.trim().isNotEmpty) {
      if (user.trim().startsWith('Bearer ')) {
        headers['Authorization'] = user.trim();
      } else {
        headers['Authorization'] = 'Basic ${base64.encode(utf8.encode("$user:$pass"))}';
      }
    }
    return headers;
  }

  Future<void> _fetchStatus() async {
    setState(() {
      _loading = true;
      _statusMessage = null;
    });

    try {
      final res = await http.get(Uri.parse('$_baseUrl/api/icloud/status'), headers: _headers);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _currentAppleId = data['apple_id'];
          _loginState = data['login_state'] ?? 'LOGGED_OUT';
          _twoFactorMethods = List<String>.from(data['two_factor_methods'] ?? []);
          _accounts = data['accounts'] ?? [];
          if (_accounts.isEmpty) {
            _showLoginForm = true;
          }
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = "Lỗi kết nối Server: $e";
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _login() async {
    if (_appleIdController.text.trim().isEmpty || _passwordController.text.trim().isEmpty) {
      setState(() {
        _statusMessage = "Vui lòng nhập đầy đủ Apple ID và Mật khẩu!";
      });
      return;
    }

    setState(() {
      _loading = true;
      _statusMessage = null;
    });

    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/api/icloud/login'),
        headers: _headers,
        body: jsonEncode({
          'apple_id': _appleIdController.text.trim(),
          'password': _passwordController.text.trim(),
        }),
      );

      final data = jsonDecode(res.body);
      if (res.statusCode == 200) {
        setState(() {
          _currentAppleId = data['apple_id'];
          _loginState = data['login_state'] ?? 'LOGGED_OUT';
          _twoFactorMethods = List<String>.from(data['two_factor_methods'] ?? []);
          _accounts = data['accounts'] ?? [];
          _statusMessage = _loginState.contains("REQUIRE_2FA")
              ? "Apple yêu cầu xác thực 2FA. Vui lòng chọn phương thức bên dưới."
              : "Đăng nhập thành công!";
          if (!_loginState.contains("REQUIRE_2FA")) {
            _showLoginForm = false;
            _appleIdController.clear();
            _passwordController.clear();
          }
        });
      } else {
        setState(() {
          _statusMessage = "Đăng nhập thất bại: ${data['detail'] ?? res.body}";
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = "Lỗi request: $e";
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _request2FACode() async {
    setState(() {
      _loading = true;
      _statusMessage = null;
    });

    try {
      String targetEmail = _appleIdController.text.trim().isNotEmpty ? _appleIdController.text.trim() : (_currentAppleId ?? "");
      final res = await http.post(
        Uri.parse('$_baseUrl/api/icloud/2fa/request'),
        headers: _headers,
        body: jsonEncode({
          'method_index': _selectedMethodIndex,
          'apple_id': targetEmail,
        }),
      );

      final data = jsonDecode(res.body);
      if (res.statusCode == 200) {
        setState(() {
          _statusMessage = "Đã yêu cầu gửi mã OTP! Vui lòng kiểm tra thiết bị/SMS.";
        });
      } else {
        setState(() {
          _statusMessage = "Yêu cầu mã thất bại: ${data['detail'] ?? res.body}";
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = "Lỗi request: $e";
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _submit2FA() async {
    if (_otpController.text.trim().isEmpty) {
      setState(() {
        _statusMessage = "Vui lòng nhập mã OTP 6 chữ số!";
      });
      return;
    }

    setState(() {
      _loading = true;
      _statusMessage = null;
    });

    try {
      String targetEmail = _appleIdController.text.trim().isNotEmpty ? _appleIdController.text.trim() : (_currentAppleId ?? "");
      final res = await http.post(
        Uri.parse('$_baseUrl/api/icloud/2fa'),
        headers: _headers,
        body: jsonEncode({
          'code': _otpController.text.trim(),
          'method_index': _selectedMethodIndex,
          'apple_id': targetEmail,
        }),
      );

      final data = jsonDecode(res.body);
      if (res.statusCode == 200) {
        setState(() {
          _loginState = data['login_state'] ?? 'LOGGED_IN';
          _twoFactorMethods = [];
          _accounts = data['accounts'] ?? [];
          _statusMessage = "Xác thực 2FA thành công!";
          _showLoginForm = false;
          _otpController.clear();
        });
      } else {
        setState(() {
          _statusMessage = "Xác thực 2FA thất bại: ${data['detail'] ?? res.body}";
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = "Lỗi request: $e";
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _deleteAccount(int accountId) async {
    setState(() {
      _loading = true;
      _statusMessage = null;
    });

    try {
      final res = await http.delete(
        Uri.parse('$_baseUrl/api/icloud/accounts/$accountId'),
        headers: _headers,
      );

      final data = jsonDecode(res.body);
      if (res.statusCode == 200) {
        setState(() {
          _accounts = data['accounts'] ?? [];
          _currentAppleId = data['apple_id'];
          _loginState = data['login_state'] ?? 'LOGGED_OUT';
          _statusMessage = "Đã đăng xuất tài khoản thành công!";
        });
      } else {
        setState(() {
          _statusMessage = data['detail'] ?? "Không thể đăng xuất tài khoản này.";
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = "Lỗi request: $e";
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isRequire2FA = _loginState.contains("REQUIRE_2FA");
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
          maxWidth: 500,
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
                    child: const Icon(Icons.cloud_sync, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Quản Lý Shared iCloud',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: isMobile ? 16 : 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Tự động tải và đồng bộ vị trí thiết bị FindMy',
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
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: isMobile ? 10 : 16, vertical: 12),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
              if (_loading) const LinearProgressIndicator(),
              if (_statusMessage != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.teal.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _statusMessage!,
                    style: const TextStyle(color: Colors.teal, fontSize: 13),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              const Text(
                'Danh sách tài khoản trong Shared Pool:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 6),
              if (_accounts.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.0),
                  child: Text(
                    'Chưa có tài khoản iCloud nào trong Pool. Thêm ngay bên dưới để bắt đầu tự động tải vị trí.',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _accounts.length,
                  itemBuilder: (context, index) {
                    final item = _accounts[index];
                    final bool isOwner = item['is_owner'] ?? false;
                    final String displayEmail = item['apple_id'] ?? item['masked_apple_id'] ?? '';
                    final int accId = item['id'];
                    final int fetchCount = item['fetch_count'] ?? 0;
                    final String loginStateStr = item['login_state'] ?? 'LOGGED_OUT';
                    final bool isReq2FA = loginStateStr.contains('REQUIRE_2FA');

                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      elevation: 1.5,
                      color: isReq2FA ? Colors.amber.withOpacity(0.08) : null,
                      child: ListTile(
                        onTap: isReq2FA
                            ? () {
                                setState(() {
                                  _appleIdController.text = displayEmail;
                                  _passwordController.clear();
                                  _showLoginForm = true;
                                  _loginState = 'LOGGED_OUT';
                                });
                              }
                            : null,
                        leading: Icon(
                          isReq2FA ? Icons.warning_amber_rounded : Icons.account_circle,
                          color: isReq2FA ? Colors.amber.shade800 : (isOwner ? Colors.teal : Colors.teal.shade700),
                        ),
                        title: Text(
                          displayEmail,
                          style: TextStyle(
                            fontWeight: isOwner ? FontWeight.bold : FontWeight.normal,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          isReq2FA
                              ? '⚠️ Cần xác thực lại 2FA (Bấm để đăng nhập lại)'
                              : (isOwner
                                  ? 'Tài khoản đang hoạt động • $fetchCount fetches'
                                  : 'Tài khoản chia sẻ • Email đã che • $fetchCount fetches'),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: isReq2FA ? FontWeight.bold : FontWeight.normal,
                            color: isReq2FA ? Colors.amber.shade900 : Colors.grey,
                          ),
                        ),
                        trailing: isOwner
                            ? IconButton(
                                icon: const Icon(Icons.logout, color: Colors.redAccent, size: 20),
                                tooltip: 'Đăng xuất tài khoản này',
                                onPressed: _loading ? null : () => _deleteAccount(accId),
                              )
                            : Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.teal.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Text('Shared Pool', style: TextStyle(fontSize: 10, color: Colors.teal)),
                              ),
                      ),
                    );
                  },
                ),
              const SizedBox(height: 12),
              Center(
                child: OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      _showLoginForm = !_showLoginForm;
                    });
                  },
                  icon: Icon(_showLoginForm ? Icons.remove : Icons.add),
                  label: Text(_showLoginForm ? 'Ẩn form thêm tài khoản' : 'Thêm tài khoản iCloud mới'),
                ),
              ),
              if (_showLoginForm) ...[
                const Divider(height: 24),
                if (!isRequire2FA) ...[
                  const Text('Thêm tài khoản Apple ID mới:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _appleIdController,
                    decoration: const InputDecoration(
                      labelText: 'Apple ID (Email)',
                      prefixIcon: Icon(Icons.email),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Mật khẩu Apple ID',
                      prefixIcon: Icon(Icons.lock),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _loading ? null : _login,
                    icon: const Icon(Icons.cloud_upload),
                    label: const Text('Đăng nhập & Thêm vào Pool'),
                  ),
                ] else ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          '📧 Tài khoản: ${_appleIdController.text.isNotEmpty ? _appleIdController.text : (_currentAppleId ?? "")}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _loginState = 'LOGGED_OUT';
                          });
                        },
                        child: const Text('Đổi tài khoản', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '🔒 Xác thực 2 yếu tố (2FA)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.amber),
                  ),
                  const SizedBox(height: 6),
                  if (_twoFactorMethods.isNotEmpty) ...[
                    const Text('Chọn phương thức nhận mã OTP:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    DropdownButton<int>(
                      value: _selectedMethodIndex < _twoFactorMethods.length ? _selectedMethodIndex : 0,
                      isExpanded: true,
                      items: List.generate(_twoFactorMethods.length, (index) {
                        return DropdownMenuItem(
                          value: index,
                          child: Text(_twoFactorMethods[index], style: const TextStyle(fontSize: 12)),
                        );
                      }),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _selectedMethodIndex = val;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 6),
                    OutlinedButton.icon(
                      onPressed: _loading ? null : _request2FACode,
                      icon: const Icon(Icons.send_to_mobile, size: 16),
                      label: const Text('Gửi / Yêu cầu gửi lại mã OTP'),
                    ),
                    const SizedBox(height: 10),
                  ],
                  TextField(
                    controller: _otpController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Mã OTP 6 chữ số',
                      hintText: 'Nhập mã 6 số từ iPhone / SMS',
                      prefixIcon: Icon(Icons.pin),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber.shade700,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _loading ? null : _submit2FA,
                      icon: const Icon(Icons.verified_user),
                      label: const Text('XÁC NHẬN MÃ 2FA'),
                    ),
                  ),
                ],
              ],
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
