import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:macless_haystack/preferences/user_preferences_model.dart';
import 'package:macless_haystack/preferences/auth_state.dart';
import 'package:macless_haystack/preferences/google_auth_dialog.dart';
import 'package:macless_haystack/preferences/app_download_dialog.dart';
import '../util/web_interop.dart';
import '../util/server_url.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:file_picker/file_picker.dart';

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
  String? _statusMessage;
  Timer? _pollTimer;
  String? _activeSessionId;

  @override
  void initState() {
    super.initState();
    _checkRedirectToken();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  void _checkRedirectToken() {
    try {
      final token = WebInterop.getRedirectToken();
      if (token != null && token.isNotEmpty) {
        _verifyAndLoginToken(token);
      }
    } catch (_) {}
  }

  String get _baseUrl => getServerBaseUrl();

  bool get _isConfiguredServer {
    String configured = Settings.getValue<String>(endpointUrl, defaultValue: '')!.trim();
    return configured.isNotEmpty && !configured.contains('localhost');
  }

  Future<String?> _getOrFetchClientId() async {
    try {
      final res = await http.get(Uri.parse('$_baseUrl/api/config')).timeout(const Duration(seconds: 4));
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

    return null;
  }

  void _triggerGoogleLogin() async {
    setState(() {
      _errorMessage = null;
    });

    // If running on mobile (or no window origin) and server URL is localhost/empty, guide user first
    if (!kIsWeb && !_isConfiguredServer) {
      _showServerConfigDialog(promptReason: 'Vui lòng thiết lập Địa chỉ máy chủ (Server URL) trước khi đăng nhập Google trên điện thoại.');
      return;
    }

    setState(() {
      _loading = true;
      _statusMessage = 'Đang kiểm tra kết nối máy chủ...';
    });

    if (kIsWeb) {
      final clientId = await _getOrFetchClientId();
      if (clientId == null || clientId.isEmpty) {
        setState(() {
          _loading = false;
          _errorMessage = 'Chưa thiết lập GOOGLE_CLIENT_ID trên hệ thống!';
        });
        return;
      }

      try {
        WebInterop.triggerGooglePopupLogin(clientId, (token) {
          _verifyAndLoginToken(token);
        });
      } catch (e) {
        setState(() {
          _loading = false;
          _errorMessage = 'Không thể khởi chạy Google Login: $e';
        });
      }
    } else {
      // Mobile flow: Web session handshake
      _startMobileGoogleLogin();
    }
  }

  Future<void> _startMobileGoogleLogin() async {
    _pollTimer?.cancel();
    setState(() {
      _statusMessage = 'Đang tạo phiên đăng nhập Google...';
    });

    try {
      final createRes = await http.post(
        Uri.parse('$_baseUrl/api/auth/session/create'),
      ).timeout(const Duration(seconds: 5));

      if (createRes.statusCode != 200) {
        setState(() {
          _loading = false;
          _errorMessage = 'Máy chủ chưa hỗ trợ tự động mở trình duyệt (Mã lỗi ${createRes.statusCode}). Vui lòng dùng tính năng "Đăng nhập bằng Token" bên dưới hoặc cập nhật máy chủ.';
        });
        return;
      }

      final data = jsonDecode(createRes.body);
      final sid = data['session_id'];
      _activeSessionId = sid;

      final loginUrl = '$_baseUrl/api/auth/mobile-login?session=$sid';
      final uri = Uri.parse(loginUrl);

      setState(() {
        _statusMessage = 'Đang mở trình duyệt để đăng nhập Google...\nSau khi đăng nhập xong trên web, app sẽ tự động kết nối!';
      });

      bool launched = false;
      if (await canLaunchUrl(uri)) {
        launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      }

      if (!launched) {
        setState(() {
          _loading = false;
          _errorMessage = 'Không thể mở trình duyệt điện thoại. Hãy thử sao chép liên kết này mở trên Chrome:\n$loginUrl';
        });
        return;
      }

      // Start polling for token
      int elapsedSeconds = 0;
      _pollTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
        elapsedSeconds += 2;
        if (elapsedSeconds > 180) {
          timer.cancel();
          if (mounted) {
            setState(() {
              _loading = false;
              _errorMessage = 'Hết thời gian chờ đăng nhập (3 phút). Vui lòng thử lại.';
            });
          }
          return;
        }

        try {
          final pollRes = await http.get(
            Uri.parse('$_baseUrl/api/auth/session/$sid/poll'),
          ).timeout(const Duration(seconds: 3));

          if (pollRes.statusCode == 200) {
            final pollData = jsonDecode(pollRes.body);
            if (pollData['authenticated'] == true && pollData['access_token'] != null) {
              timer.cancel();
              final jwtToken = pollData['access_token'];
              if (mounted) {
                setState(() {
                  _statusMessage = 'Đăng nhập Google thành công! Đang vào hệ thống...';
                });
                await Provider.of<AuthState>(context, listen: false).onLoginSuccess(jwtToken);
                widget.onLoginSuccess();
              }
            }
          }
        } catch (_) {}
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _errorMessage = 'Lỗi kết nối tới máy chủ: $e\nVui lòng kiểm tra lại Địa chỉ máy chủ (Server URL).';
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

  void _cancelMobileAuth() {
    _pollTimer?.cancel();
    setState(() {
      _loading = false;
      _statusMessage = null;
    });
  }

  void _showServerConfigDialog({String? promptReason}) {
    final currentUrl = Settings.getValue<String>(endpointUrl, defaultValue: 'https://findmy.tnq.io.vn')!;
    final controller = TextEditingController(text: currentUrl.isEmpty ? 'https://findmy.tnq.io.vn' : currentUrl);
    String? pingStatus;
    bool pinging = false;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.dns, color: Colors.teal),
                SizedBox(width: 8),
                Text('Cấu hình Địa chỉ Máy chủ', style: TextStyle(fontSize: 18)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (promptReason != null) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange.withOpacity(0.4)),
                      ),
                      child: Text(
                        promptReason,
                        style: const TextStyle(color: Colors.orange, fontSize: 13),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  const Text(
                    'Nhập địa chỉ IP hoặc tên miền của FindMy Server (kèm cổng, ví dụ: http://192.168.1.15:6176 hoặc https://findmy.domain.com):',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    decoration: const InputDecoration(
                      labelText: 'Server URL',
                      hintText: 'http://192.168.1.xxx:6176',
                      prefixIcon: Icon(Icons.link),
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.url,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade700),
                        onPressed: pinging
                            ? null
                            : () async {
                                setDialogState(() {
                                  pinging = true;
                                  pingStatus = 'Đang kiểm tra kết nối...';
                                });
                                String target = controller.text.trim();
                                if (target.endsWith('/')) {
                                  target = target.substring(0, target.length - 1);
                                }
                                try {
                                  final res = await http.get(Uri.parse('$target/api/config')).timeout(const Duration(seconds: 4));
                                  if (res.statusCode == 200) {
                                    setDialogState(() {
                                      pinging = false;
                                      pingStatus = '✅ Kết nối máy chủ thành công!';
                                    });
                                  } else {
                                    setDialogState(() {
                                      pinging = false;
                                      pingStatus = '⚠️ Máy chủ trả về mã: ${res.statusCode}';
                                    });
                                  }
                                } catch (e) {
                                  setDialogState(() {
                                    pinging = false;
                                    pingStatus = '❌ Không thể kết nối: $e';
                                  });
                                }
                              },
                        icon: pinging
                            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.network_check, color: Colors.white, size: 16),
                        label: const Text('Kiểm tra', style: TextStyle(color: Colors.white, fontSize: 13)),
                      ),
                    ],
                  ),
                  if (pingStatus != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      pingStatus!,
                      style: TextStyle(
                        fontSize: 12,
                        color: pingStatus!.startsWith('✅') ? Colors.green : Colors.redAccent,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('Hủy'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                onPressed: () async {
                  String val = controller.text.trim();
                  if (val.endsWith('/')) {
                    val = val.substring(0, val.length - 1);
                  }
                  await Settings.setValue<String>(endpointUrl, val);
                  if (context.mounted) {
                    Navigator.pop(dialogCtx);
                    setState(() {
                      _errorMessage = null;
                    });
                  }
                },
                child: const Text('Lưu máy chủ', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showQrOrTokenLoginDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) => _QrTokenLoginDialog(
        baseUrl: _baseUrl,
        onQrScanned: (raw) => _handleScannedQr(raw),
        onTokenLogin: (rawToken, {String? targetBaseUrl}) =>
            _loginWithJwtToken(rawToken, targetBaseUrl: targetBaseUrl),
      ),
    );
  }

  Future<void> _loginWithJwtToken(String rawToken, {String? targetBaseUrl}) async {
    final baseUrl = targetBaseUrl ?? _baseUrl;
    setState(() {
      _loading = true;
      _statusMessage = 'Đang xác thực thông tin đăng nhập...';
      _errorMessage = null;
    });

    String bearer = rawToken.startsWith('Bearer ') ? rawToken : 'Bearer $rawToken';
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/api/auth/me'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': bearer,
        },
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        if (mounted) {
          await Provider.of<AuthState>(context, listen: false).onLoginSuccess(bearer);
          widget.onLoginSuccess();
        }
      } else {
        if (mounted) {
          setState(() {
            _loading = false;
            _errorMessage = 'Mã đăng nhập không hợp lệ hoặc đã hết hạn (Mã phản hồi ${res.statusCode}).';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _errorMessage = 'Lỗi kết nối máy chủ ($baseUrl): $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _handleScannedQr(String raw) async {
    String tokenToLogin = raw;
    String effectiveBaseUrl = _baseUrl;
    try {
      if (raw.startsWith('{') && raw.endsWith('}')) {
        final map = jsonDecode(raw);
        if (map['server'] != null && map['server'].toString().trim().isNotEmpty) {
          String s = map['server'].toString().trim();
          if (s.endsWith('/')) s = s.substring(0, s.length - 1);
          await Settings.setValue<String>(endpointUrl, s);
          effectiveBaseUrl = s;
          if (mounted) setState(() {});
        }
        if (map['token'] != null && map['token'].toString().trim().isNotEmpty) {
          tokenToLogin = map['token'].toString().trim();
        }
      }
    } catch (_) {}

    await _loginWithJwtToken(tokenToLogin, targetBaseUrl: effectiveBaseUrl);
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
            padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 36.0),
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
                    size: 52,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'FindMy Server',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Hệ thống định vị thiết bị Apple FindMy 24/7',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.grey.shade400,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 24),

                // Server URL indicator bar (only visible on mobile/desktop, hidden on Web)
                if (!kIsWeb) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.25),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _isConfiguredServer ? Colors.teal.withOpacity(0.5) : Colors.orange.withOpacity(0.5),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _isConfiguredServer ? Icons.cloud_done : Icons.warning_amber_rounded,
                          color: _isConfiguredServer ? Colors.tealAccent : Colors.orange,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _isConfiguredServer ? 'Máy chủ kết nối:' : 'Chưa cấu hình máy chủ:',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: _isConfiguredServer ? Colors.grey.shade400 : Colors.orange.shade300,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                _baseUrl,
                                style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'monospace'),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.settings, size: 18, color: Colors.tealAccent),
                          tooltip: 'Đổi máy chủ',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () => _showServerConfigDialog(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

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
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.teal.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.teal.withOpacity(0.3)),
                    ),
                    child: Column(
                      children: [
                        const CircularProgressIndicator(color: Colors.teal),
                        const SizedBox(height: 14),
                        Text(
                          _statusMessage ?? 'Đang xác thực tài khoản...',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey.shade200, fontSize: 13),
                        ),
                        const SizedBox(height: 12),
                        TextButton.icon(
                          onPressed: _cancelMobileAuth,
                          icon: const Icon(Icons.close, size: 16, color: Colors.grey),
                          label: const Text('Hủy', style: TextStyle(color: Colors.grey, fontSize: 13)),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black87,
                        elevation: 4,
                        padding: const EdgeInsets.symmetric(vertical: 15),
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
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal.shade700,
                        foregroundColor: Colors.white,
                        elevation: 2,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.qr_code_scanner, size: 20),
                      label: const Text(
                        'Quét mã QR / Nhập Token',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      onPressed: _showQrOrTokenLoginDialog,
                    ),
                  ),
                ],

                // Download Android App (APK) button with QR & Link - Chỉ hiện trên bản Web
                if (kIsWeb) ...[
                  const SizedBox(height: 20),
                  const Divider(color: Colors.white12, height: 1),
                  const SizedBox(height: 16),
                  InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => AppDownloadDialog.show(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 14),
                      decoration: BoxDecoration(
                        color: Colors.teal.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.teal.withOpacity(0.4)),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.android, size: 19, color: Colors.greenAccent),
                          SizedBox(width: 8),
                          Text(
                            'Tải ứng dụng Android (APK)',
                            style: TextStyle(
                              color: Colors.tealAccent,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(width: 6),
                          Icon(Icons.qr_code, size: 16, color: Colors.tealAccent),
                        ],
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 16),
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

class _QrTokenLoginDialog extends StatefulWidget {
  final String baseUrl;
  final Function(String rawQr) onQrScanned;
  final Future<void> Function(String rawToken, {String? targetBaseUrl}) onTokenLogin;

  const _QrTokenLoginDialog({
    required this.baseUrl,
    required this.onQrScanned,
    required this.onTokenLogin,
  });

  @override
  State<_QrTokenLoginDialog> createState() => _QrTokenLoginDialogState();
}

class _QrTokenLoginDialogState extends State<_QrTokenLoginDialog> {
  int _selectedTab = 0; // 0: Quét QR, 1: Nhập Token
  final MobileScannerController _scannerController = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
  );
  bool _detected = false;
  bool _analyzingImage = false;
  bool _torchOn = false;
  String? _qrError;

  final TextEditingController _tokenController = TextEditingController();
  bool _validatingToken = false;
  String? _tokenError;

  @override
  void dispose() {
    _scannerController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _pickImageAndAnalyze() async {
    try {
      setState(() {
        _analyzingImage = true;
        _qrError = null;
      });

      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
      );

      if (result == null || result.files.isEmpty) {
        if (mounted) setState(() => _analyzingImage = false);
        return;
      }

      final path = result.files.first.path;
      if (path == null || path.isEmpty) {
        if (mounted) {
          setState(() {
            _analyzingImage = false;
            _qrError = 'Không thể đọc đường dẫn ảnh trên thiết bị này.';
          });
        }
        return;
      }

      final BarcodeCapture? capture = await _scannerController.analyzeImage(path);
      if (capture != null && capture.barcodes.isNotEmpty) {
        for (final barcode in capture.barcodes) {
          final raw = barcode.rawValue;
          if (raw != null && raw.trim().isNotEmpty) {
            _detected = true;
            if (mounted) {
              Navigator.pop(context);
              widget.onQrScanned(raw.trim());
            }
            return;
          }
        }
      }

      if (mounted) {
        setState(() {
          _analyzingImage = false;
          _qrError = 'Không tìm thấy mã QR trong ảnh. Vui lòng chọn ảnh khác hoặc chuyển sang Nhập Token.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _analyzingImage = false;
          _qrError = 'Không thể quét ảnh: $e';
        });
      }
    }
  }

  Future<void> _submitToken() async {
    final raw = _tokenController.text.trim();
    if (raw.isEmpty) {
      setState(() => _tokenError = 'Vui lòng nhập mã Token.');
      return;
    }
    setState(() {
      _validatingToken = true;
      _tokenError = null;
    });

    String bearer = raw.startsWith('Bearer ') ? raw : 'Bearer $raw';
    try {
      final res = await http.get(
        Uri.parse('${widget.baseUrl}/api/auth/me'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': bearer,
        },
      ).timeout(const Duration(seconds: 6));

      if (res.statusCode == 200) {
        if (mounted) {
          Navigator.pop(context);
          await widget.onTokenLogin(bearer, targetBaseUrl: widget.baseUrl);
        }
      } else {
        if (mounted) {
          setState(() {
            _validatingToken = false;
            _tokenError = 'Token không hợp lệ hoặc đã hết hạn (Mã: ${res.statusCode}).';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _validatingToken = false;
          _tokenError = 'Lỗi kết nối máy chủ: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      titlePadding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
      title: Row(
        children: [
          Icon(
            _selectedTab == 0 ? Icons.qr_code_scanner : Icons.vpn_key,
            color: Colors.teal,
            size: 22,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _selectedTab == 0 ? 'Quét mã QR đăng nhập' : 'Đăng nhập bằng Token',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            tooltip: 'Đóng',
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      content: SizedBox(
        width: 330,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Tab toggle bar
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.all(3),
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => setState(() => _selectedTab = 0),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: _selectedTab == 0 ? Colors.teal : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.camera_alt, size: 16, color: _selectedTab == 0 ? Colors.white : Colors.grey),
                              const SizedBox(width: 6),
                              Text(
                                'Quét mã QR',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: _selectedTab == 0 ? Colors.white : Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => setState(() => _selectedTab = 1),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: _selectedTab == 1 ? Colors.teal : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.vpn_key, size: 16, color: _selectedTab == 1 ? Colors.white : Colors.grey),
                              const SizedBox(width: 6),
                              Text(
                                'Nhập Token',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: _selectedTab == 1 ? Colors.white : Colors.grey,
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

              const SizedBox(height: 14),

              // Tab 0: QR Scanner & Pick Image
              if (_selectedTab == 0) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: double.infinity,
                    height: 250,
                    color: Colors.black,
                    child: Stack(
                      children: [
                        MobileScanner(
                          controller: _scannerController,
                          onDetect: (capture) {
                            if (_detected) return;
                            for (final barcode in capture.barcodes) {
                              final raw = barcode.rawValue;
                              if (raw != null && raw.trim().isNotEmpty) {
                                _detected = true;
                                Navigator.pop(context);
                                widget.onQrScanned(raw.trim());
                                break;
                              }
                            }
                          },
                        ),
                        Center(
                          child: Container(
                            width: 175,
                            height: 175,
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.tealAccent, width: 2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                        // Quick controls: Flash & Switch camera
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Row(
                            children: [
                              Container(
                                decoration: const BoxDecoration(
                                  color: Colors.black45,
                                  shape: BoxShape.circle,
                                ),
                                child: IconButton(
                                  icon: Icon(
                                    _torchOn ? Icons.flash_on : Icons.flash_off,
                                    color: _torchOn ? Colors.amber : Colors.white,
                                    size: 20,
                                  ),
                                  onPressed: () {
                                    _scannerController.toggleTorch();
                                    setState(() => _torchOn = !_torchOn);
                                  },
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                decoration: const BoxDecoration(
                                  color: Colors.black45,
                                  shape: BoxShape.circle,
                                ),
                                child: IconButton(
                                  icon: const Icon(Icons.cameraswitch, color: Colors.white, size: 20),
                                  onPressed: () => _scannerController.switchCamera(),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // Button pick image from gallery / files
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal.shade700,
                      foregroundColor: Colors.white,
                      elevation: 2,
                      padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: _analyzingImage
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.photo_library, size: 18, color: Colors.white),
                    label: Text(
                      _analyzingImage ? 'Đang đọc mã QR từ ảnh...' : 'Chọn ảnh mã QR từ thiết bị',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    onPressed: _analyzingImage ? null : _pickImageAndAnalyze,
                  ),
                ),

                if (_qrError != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.redAccent.withOpacity(0.4)),
                    ),
                    child: Text(
                      _qrError!,
                      style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],

                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => setState(() => _selectedTab = 1),
                  child: Text(
                    'Không thể dùng camera? Bấm để Nhập Token',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],

              // Tab 1: Token Login
              if (_selectedTab == 1) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.teal.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.dns, size: 14, color: Colors.teal),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Máy chủ: ${widget.baseUrl}',
                          style: const TextStyle(fontSize: 12, color: Colors.teal, fontWeight: FontWeight.w500),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Nếu bạn đã đăng nhập trên Web / máy tính khác, vào Menu góc phải -> Sao chép Token và dán vào đây:',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _tokenController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: 'JWT Token hoặc Bearer Key',
                    hintText: 'eyJhbGciOi...',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.paste),
                      tooltip: 'Dán từ bộ nhớ tạm',
                      onPressed: () async {
                        final data = await Clipboard.getData('text/plain');
                        if (data?.text != null) {
                          setState(() {
                            _tokenController.text = data!.text!.trim();
                          });
                        }
                      },
                    ),
                  ),
                ),
                if (_tokenError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _tokenError!,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _validatingToken ? null : _submitToken,
                    child: _validatingToken
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Xác nhận đăng nhập', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 6),
                TextButton(
                  onPressed: () => setState(() => _selectedTab = 0),
                  child: Text(
                    'Quay lại Quét mã QR',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
