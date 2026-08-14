import 'dart:async';
import 'dart:convert';
import 'dart:js' as js;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:macless_haystack/preferences/user_preferences_model.dart';
import 'package:macless_haystack/preferences/auth_state.dart';
import 'package:macless_haystack/accessory/accessory_registry.dart';
import 'package:universal_html/html.dart' as html;

const String googleClientIdKey = 'GOOGLE_CLIENT_ID';

class GoogleAuthDialog extends StatefulWidget {
  const GoogleAuthDialog({super.key});

  @override
  State<GoogleAuthDialog> createState() => _GoogleAuthDialogState();
}

class _GoogleAuthDialogState extends State<GoogleAuthDialog> {
  bool _loading = false;
  String? _statusMessage;
  Map<String, dynamic>? _userProfile;

  @override
  void initState() {
    super.initState();
    _checkRedirectToken();
    _fetchServerConfig();
    _fetchCurrentUser();
  }

  void _checkRedirectToken() {
    try {
      final token = js.context['googleOAuthTokenFromRedirect'];
      if (token != null && token.toString().isNotEmpty) {
        js.context['googleOAuthTokenFromRedirect'] = null;
        _verifyAndLoginToken(token.toString());
      }
    } catch (_) {}
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

  Future<String?> _getOrFetchClientId() async {
    try {
      final res = await http.get(Uri.parse('$_baseUrl/api/config'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['google_client_id'] != null && data['google_client_id'].toString().trim().isNotEmpty) {
          String serverClientId = data['google_client_id'].toString().trim();
          await Settings.setValue<String>(googleClientIdKey, serverClientId);
          return serverClientId;
        }
      }
    } catch (_) {}

    String stored = Settings.getValue<String>(googleClientIdKey, defaultValue: '')!;
    if (stored.trim().isNotEmpty) return stored.trim();

    return '17360711987-c4eqe3jk31on92okbffbsbrffc1v7u66.apps.googleusercontent.com';
  }

  Future<void> _fetchServerConfig() async {
    await _getOrFetchClientId();
  }

  String get _currentBearerToken {
    return Settings.getValue<String>(endpointUser, defaultValue: '')!;
  }

  Future<void> _fetchCurrentUser() async {
    final token = _currentBearerToken;
    if (token.isEmpty) return;

    setState(() {
      _loading = true;
    });

    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/api/auth/me'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': token.startsWith('Bearer ') ? token : 'Bearer $token',
        },
      );

      if (res.statusCode == 200) {
        setState(() {
          _userProfile = jsonDecode(res.body);
        });
      }
    } catch (e) {
      // Ignore if guest mode
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  StreamSubscription? _messageSubscription;

  @override
  void dispose() {
    _messageSubscription?.cancel();
    super.dispose();
  }

  void _triggerGoogleSignInPopUp() async {
    setState(() {
      _loading = true;
      _statusMessage = "Đang kết nối tới Google...";
    });

    final clientId = await _getOrFetchClientId();
    if (clientId == null || clientId.isEmpty) {
      setState(() {
        _loading = false;
        _statusMessage = "Chưa khai báo GOOGLE_CLIENT_ID trong file .env!";
      });
      return;
    }

    setState(() {
      _loading = false;
      _statusMessage = "Đang mở cửa sổ đăng nhập Google...";
    });

    try {
      js.context.callMethod('triggerGooglePopupLogin', [
        clientId,
        js.allowInterop((token) {
          if (token != null) {
            _verifyAndLoginToken(token.toString());
          }
        })
      ]);
    } catch (e) {
      setState(() {
        _statusMessage = "Không thể mở cửa sổ Google: $e";
      });
    }
  }

  Future<void> _verifyAndLoginToken(String rawToken) async {
    setState(() {
      _loading = true;
      _statusMessage = null;
    });

    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/api/auth/google'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'id_token': rawToken}),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final jwtToken = data['access_token'];
        final user = data['user'];

        await Provider.of<AuthState>(context, listen: false).onLoginSuccess(jwtToken);

        setState(() {
          _userProfile = user;
          _statusMessage = "Đăng nhập Google thành công!";
        });

        if (mounted) {
          Provider.of<AccessoryRegistry>(context, listen: false).loadAccessories();
        }
      } else {
        final data = jsonDecode(res.body);
        setState(() {
          _statusMessage = "Xác thực thất bại: ${data['detail'] ?? res.body}";
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = "Lỗi xác thực: $e";
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _logout() async {
    try {
      js.context.callMethod('googleSignOut');
    } catch (_) {}
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    await Provider.of<AuthState>(context, listen: false).logout();
  }

  @override
  Widget build(BuildContext context) {
    bool isLoggedIn = _userProfile != null;

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.account_circle, color: Colors.indigo),
          SizedBox(width: 8),
          Text('Tài khoản & Google Auth'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_loading) const LinearProgressIndicator(),
            if (_statusMessage != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.indigo.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _statusMessage!,
                  style: const TextStyle(color: Colors.indigo, fontSize: 13),
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (isLoggedIn) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.indigo.withOpacity(0.1),
                  border: Border.all(color: Colors.indigo),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: Colors.indigo,
                      child: Text(
                        (_userProfile!['name'] ?? _userProfile!['email'] ?? 'U')[0].toUpperCase(),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _userProfile!['name'] ?? 'Google User',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          Text(
                            _userProfile!['email'] ?? '',
                            style: const TextStyle(color: Colors.grey, fontSize: 13),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Tài khoản đang được bảo mật bằng JWT',
                            style: TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                onPressed: _loading ? null : _logout,
                icon: const Icon(Icons.logout, color: Colors.white),
                label: const Text('Đăng xuất Google', style: TextStyle(color: Colors.white)),
              ),
            ] else ...[
              const Text(
                'Đăng nhập bằng tài khoản Google để tự động đồng bộ thiết bị và phân quyền:',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 20),
              Center(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black87,
                    elevation: 3,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    side: const BorderSide(color: Colors.grey),
                  ),
                  icon: const Icon(Icons.account_circle, color: Colors.red, size: 26),
                  label: const Text(
                    'Đăng nhập bằng Google',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  onPressed: _loading ? null : _triggerGoogleSignInPopUp,
                ),
              ),
            ],
          ],
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
