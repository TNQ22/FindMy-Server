import 'dart:convert';
import 'dart:js' as js;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:macless_haystack/preferences/user_preferences_model.dart';
import 'package:macless_haystack/preferences/auth_state.dart';
import 'package:macless_haystack/preferences/google_auth_dialog.dart';
import 'package:universal_html/html.dart' as html;

class LoginPage extends StatefulWidget {
  final VoidCallback onLoginSuccess;
  final bool sessionExpired;
  const LoginPage({super.key, required this.onLoginSuccess, this.sessionExpired = false});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _loading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _checkRedirectToken();
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

  void _triggerGoogleLogin() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    final clientId = await _getOrFetchClientId();
    if (clientId == null || clientId.isEmpty) {
      setState(() {
        _loading = false;
        _errorMessage = 'Chưa thiết lập GOOGLE_CLIENT_ID trên hệ thống!';
      });
      return;
    }

    try {
      js.context.callMethod('triggerGooglePopupLogin', [
        clientId,
        js.allowInterop((token) {
          if (token != null) {
            _verifyAndLoginToken(token.toString());
          } else {
            setState(() {
              _loading = false;
            });
          }
        })
      ]);
    } catch (e) {
      setState(() {
        _loading = false;
        _errorMessage = 'Không thể khởi chạy Google Login: $e';
      });
    }
  }

  Future<void> _verifyAndLoginToken(String rawToken) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/api/auth/google'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'id_token': rawToken}),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final jwtToken = data['access_token'];

        // Use AuthState as single source of truth
        if (mounted) {
          await Provider.of<AuthState>(context, listen: false).onLoginSuccess(jwtToken);
          widget.onLoginSuccess();
        }
      } else {
        final data = jsonDecode(res.body);
        setState(() {
          _errorMessage = 'Đăng nhập thất bại: ${data['detail'] ?? res.body}';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Lỗi xác thực: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 40.0),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.teal.withOpacity(0.12),
                  blurRadius: 30,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.4),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
              border: Border.all(color: Colors.teal.withOpacity(0.35)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.teal.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.location_on_rounded,
                    color: Colors.teal,
                    size: 56,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'FindMy Server',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Hệ thống định vị thiết bị Apple FindMy 24/7',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.grey.shade400,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 32),
                // Show session-expired banner if redirected from a 401
                if (widget.sessionExpired) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.withOpacity(0.5)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.access_time_rounded, color: Colors.orange, size: 18),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.',
                            style: TextStyle(color: Colors.orange, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.redAccent.withOpacity(0.5)),
                    ),
                    child: Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
                if (_loading) ...[
                  const CircularProgressIndicator(color: Colors.teal),
                  const SizedBox(height: 16),
                  Text(
                    'Đang xác thực tài khoản...',
                    style: TextStyle(color: Colors.grey.shade300, fontSize: 13),
                  ),
                ] else ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black87,
                        elevation: 4,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.account_circle, color: Colors.red, size: 24),
                      label: const Text(
                        'Đăng nhập bằng Google',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onPressed: _triggerGoogleLogin,
                    ),
                  ),
                ],
                const SizedBox(height: 28),
                Text(
                  'Ứng dụng yêu cầu đăng nhập tài khoản Google để bảo mật dữ liệu và phân quyền thiết bị.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.grey.shade500,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
