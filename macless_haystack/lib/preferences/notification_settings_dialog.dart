import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:macless_haystack/preferences/user_preferences_model.dart';
import 'package:universal_html/html.dart' as html;

class NotificationSettingsDialog extends StatefulWidget {
  final String? userEmail;

  const NotificationSettingsDialog({super.key, this.userEmail});

  @override
  State<NotificationSettingsDialog> createState() => _NotificationSettingsDialogState();
}

class _NotificationSettingsDialogState extends State<NotificationSettingsDialog> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Form controllers
  final _emailRecipientController = TextEditingController();
  final _tgTokenController = TextEditingController();
  final _tgChatIdController = TextEditingController();
  final _discordUrlController = TextEditingController();
  final _webhookUrlController = TextEditingController();

  // Switches
  bool _emailEnabled = true;
  bool _tgEnabled = false;
  bool _discordEnabled = false;
  bool _webhookEnabled = false;

  bool _loading = true;
  bool _saving = false;
  String? _testingChannel;

  @override
  void initState() {
    super.initState();
    _emailRecipientController.text = widget.userEmail ?? '';
    _tabController = TabController(length: 4, vsync: this);
    _loadCurrentSettings();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _emailRecipientController.dispose();
    _tgTokenController.dispose();
    _tgChatIdController.dispose();
    _discordUrlController.dispose();
    _webhookUrlController.dispose();
    super.dispose();
  }

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

  Map<String, String> get _headers {
    Map<String, String> headers = {'Content-Type': 'application/json'};
    String token = Settings.getValue<String>(endpointUser, defaultValue: '')!;
    if (token.trim().isNotEmpty) {
      headers['Authorization'] = token.trim().startsWith('Bearer ') ? token.trim() : 'Bearer ${token.trim()}';
    }
    return headers;
  }

  Future<void> _loadCurrentSettings() async {
    setState(() => _loading = true);
    try {
      final res = await http.get(Uri.parse('$_baseUrl/api/auth/me'), headers: _headers);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['settings_json'] != null && data['settings_json'].toString().trim().isNotEmpty) {
          final sMap = jsonDecode(data['settings_json']);
          setState(() {
            _emailEnabled = sMap['email_alerts_enabled'] ?? true;
            if (sMap['custom_alert_email'] != null && sMap['custom_alert_email'].toString().trim().isNotEmpty) {
              _emailRecipientController.text = sMap['custom_alert_email'].toString().trim();
            }
            _tgEnabled = sMap['telegram_alerts_enabled'] ?? false;
            _tgTokenController.text = sMap['telegram_bot_token'] ?? '';
            _tgChatIdController.text = sMap['telegram_chat_id'] ?? '';
            _discordEnabled = sMap['discord_alerts_enabled'] ?? false;
            _discordUrlController.text = sMap['discord_webhook_url'] ?? '';
            _webhookEnabled = sMap['webhook_alerts_enabled'] ?? false;
            _webhookUrlController.text = sMap['webhook_url'] ?? '';
          });
        }
      }
    } catch (e) {
      debugPrint("Error loading settings: $e");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _saving = true);
    try {
      // First fetch current full settings_json to not overwrite unrelated keys
      Map<String, dynamic> currentMap = {};
      try {
        final resMe = await http.get(Uri.parse('$_baseUrl/api/auth/me'), headers: _headers);
        if (resMe.statusCode == 200) {
          final data = jsonDecode(resMe.body);
          if (data['settings_json'] != null) {
            currentMap = jsonDecode(data['settings_json']);
          }
        }
      } catch (_) {}

      currentMap['email_alerts_enabled'] = _emailEnabled;
      currentMap['custom_alert_email'] = _emailRecipientController.text.trim();
      currentMap['telegram_alerts_enabled'] = _tgEnabled;
      currentMap['telegram_bot_token'] = _tgTokenController.text.trim();
      currentMap['telegram_chat_id'] = _tgChatIdController.text.trim();
      currentMap['discord_alerts_enabled'] = _discordEnabled;
      currentMap['discord_webhook_url'] = _discordUrlController.text.trim();
      currentMap['webhook_alerts_enabled'] = _webhookEnabled;
      currentMap['webhook_url'] = _webhookUrlController.text.trim();

      // Update local storage
      await Settings.setValue<bool>(emailAlertsEnabledKey, _emailEnabled);

      // Save to server
      final res = await http.post(
        Uri.parse('$_baseUrl/api/auth/settings'),
        headers: _headers,
        body: jsonEncode({'settings_json': jsonEncode(currentMap)}),
      );

      if (res.statusCode == 200 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text('Đã lưu cấu hình thông báo thành công!'),
              ],
            ),
            backgroundColor: Color(0xFF00695C), // Colors.teal.shade800
          ),
        );
        Navigator.pop(context, true);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lưu thất bại: ${res.body}'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi kết nối: $e'), backgroundColor: Colors.red.shade700),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _testChannel(String channel, Map<String, dynamic> config) async {
    setState(() => _testingChannel = channel);
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/api/auth/test-channel'),
        headers: _headers,
        body: jsonEncode({
          'channel': channel,
          'config': config,
        }),
      );

      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(data['message'] ?? 'Gửi thử nghiệm thành công!')),
              ],
            ),
            backgroundColor: const Color(0xFF00695C), // Colors.teal.shade800
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(data['detail'] ?? 'Lỗi khi gửi thử nghiệm.')),
              ],
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi kiểm tra: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _testingChannel = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 680),
        child: Column(
          children: [
            // Top Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
                    child: const Icon(Icons.notifications_active, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Cài Đặt Thông Báo & Webhook',
                          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Cấu hình nhận thông báo và cảnh báo qua đa kênh',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
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

            // Tab Bar
            Container(
              color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.4),
              child: TabBar(
                controller: _tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelColor: Colors.teal,
                unselectedLabelColor: Colors.grey.shade600,
                indicatorColor: Colors.teal,
                indicatorWeight: 3,
                tabs: const [
                  Tab(icon: Icon(Icons.discord, size: 20), text: 'Discord'),
                  Tab(icon: Icon(Icons.email, size: 20), text: 'Email'),
                  Tab(icon: Icon(Icons.telegram, size: 20), text: 'Telegram'),
                  Tab(icon: Icon(Icons.webhook, size: 20), text: 'Webhook / Zalo'),
                ],
              ),
            ),

            // Tab Views Content
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: Colors.teal))
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildDiscordTab(),
                        _buildEmailTab(),
                        _buildTelegramTab(),
                        _buildWebhookTab(),
                      ],
                    ),
            ),

            const Divider(height: 1),

            // Bottom Actions
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Hủy'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.save, size: 18),
                    label: Text(_saving ? 'Đang lưu...' : 'Lưu Cấu Hình'),
                    onPressed: _saving ? null : _saveSettings,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 1. Telegram Tab
  Widget _buildTelegramTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Bật thông báo qua Telegram', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text('Gửi tin nhắn tức thời qua Telegram Bot cá nhân / nhóm chat'),
            value: _tgEnabled,
            activeColor: Colors.teal,
            onChanged: (val) => setState(() => _tgEnabled = val),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _tgTokenController,
            decoration: InputDecoration(
              labelText: 'Telegram Bot Token',
              hintText: 'VD: 123456789:ABCdefGhIJKlmNoPQRsTUVwxyZ',
              prefixIcon: const Icon(Icons.vpn_key_outlined, color: Colors.teal),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Colors.teal, width: 2)),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              isDense: true,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _tgChatIdController,
            decoration: InputDecoration(
              labelText: 'Telegram Chat ID (hoặc Group ID)',
              hintText: 'VD: 987654321 hoặc -100123456789',
              prefixIcon: const Icon(Icons.chat_bubble_outline, color: Colors.teal),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Colors.teal, width: 2)),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              isDense: true,
            ),
          ),
          const SizedBox(height: 16),
          // Test button
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.teal,
                side: const BorderSide(color: Colors.teal),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: _testingChannel == 'telegram'
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.teal),
                    )
                  : const Icon(Icons.send, size: 16),
              label: const Text('Gửi Thử Nghiệm Telegram'),
              onPressed: _testingChannel != null
                  ? null
                  : () {
                      _testChannel('telegram', {
                        'telegram_bot_token': _tgTokenController.text.trim(),
                        'telegram_chat_id': _tgChatIdController.text.trim(),
                      });
                    },
            ),
          ),
          const SizedBox(height: 16),
          // Quick instruction card
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.teal.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.teal.withOpacity(0.3)),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: Colors.teal),
                    SizedBox(width: 6),
                    Text(
                      'Cách lấy Token & Chat ID trong 1 phút:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.teal),
                    ),
                  ],
                ),
                SizedBox(height: 6),
                Text('1. Mở Telegram, tìm bot @BotFather và gửi lệnh /newbot để tạo bot & lấy Token.', style: TextStyle(fontSize: 11)),
                Text('2. Bấm vào link bot vừa tạo và bấm nút START.', style: TextStyle(fontSize: 11)),
                Text('3. Tìm bot @userinfobot và bấm START để lấy ID số của bạn (Chat ID).', style: TextStyle(fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 2. Discord Tab
  Widget _buildDiscordTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Bật thông báo qua Discord', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text('Gửi tin nhắn Rich Embed đến kênh Discord qua Webhook'),
            value: _discordEnabled,
            activeColor: Colors.teal,
            onChanged: (val) => setState(() => _discordEnabled = val),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _discordUrlController,
            decoration: InputDecoration(
              labelText: 'Discord Webhook URL',
              hintText: 'https://discord.com/api/webhooks/...',
              prefixIcon: const Icon(Icons.link, color: Colors.teal),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Colors.teal, width: 2)),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              isDense: true,
            ),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.teal,
                side: const BorderSide(color: Colors.teal),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: _testingChannel == 'discord'
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.teal),
                    )
                  : const Icon(Icons.send, size: 16),
              label: const Text('Gửi Thử Nghiệm Discord'),
              onPressed: _testingChannel != null
                  ? null
                  : () {
                      _testChannel('discord', {
                        'discord_webhook_url': _discordUrlController.text.trim(),
                      });
                    },
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.teal.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.teal.withOpacity(0.3)),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: Colors.teal),
                    SizedBox(width: 6),
                    Text(
                      'Cách lấy Webhook URL trên Discord:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.teal),
                    ),
                  ],
                ),
                SizedBox(height: 6),
                Text('1. Vào Server Settings hoặc Channel Settings của Discord.', style: TextStyle(fontSize: 11)),
                Text('2. Chọn Integrations > Webhooks > New Webhook.', style: TextStyle(fontSize: 11)),
                Text('3. Bấm Copy Webhook URL và dán vào ô trên.', style: TextStyle(fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 3. Custom Webhook Tab (Zalo / Automation)
  Widget _buildWebhookTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Bật Custom Webhook (HTTP POST)', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text('Gửi JSON payload đến Server riêng, Zalo Bot Bridge, n8n hoặc Home Assistant'),
            value: _webhookEnabled,
            activeColor: Colors.teal,
            onChanged: (val) => setState(() => _webhookEnabled = val),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _webhookUrlController,
            decoration: InputDecoration(
              labelText: 'Custom Webhook URL',
              hintText: 'https://your-server.com/api/webhook hoặc https://n8n.domain.com/...',
              prefixIcon: const Icon(Icons.http, color: Colors.teal),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Colors.teal, width: 2)),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              isDense: true,
            ),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.teal,
                side: const BorderSide(color: Colors.teal),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: _testingChannel == 'webhook'
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.teal),
                    )
                  : const Icon(Icons.send, size: 16),
              label: const Text('Gửi Thử Nghiệm Webhook'),
              onPressed: _testingChannel != null
                  ? null
                  : () {
                      _testChannel('webhook', {
                        'webhook_url': _webhookUrlController.text.trim(),
                      });
                    },
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.teal.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.teal.withOpacity(0.3)),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: Colors.teal),
                    SizedBox(width: 6),
                    Text(
                      'Tích hợp Zalo / Home Assistant qua Webhook:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.teal),
                    ),
                  ],
                ),
                SizedBox(height: 6),
                Text('• Server sẽ gửi POST JSON chứa thông tin chi tiết sự kiện (event, device_name, battery_status, message, timestamp).', style: TextStyle(fontSize: 11)),
                Text('• Bạn có thể dùng Webhook này để kết nối với Zalo OA Webhook, Node-RED hoặc n8n để chuyển tiếp thông báo tức thì.', style: TextStyle(fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 4. Email Tab
  Widget _buildEmailTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Bật thông báo qua Email', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text('Gửi email thông báo và cảnh báo từ hệ thống'),
            value: _emailEnabled,
            activeColor: Colors.teal,
            onChanged: (val) => setState(() => _emailEnabled = val),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _emailRecipientController,
            decoration: InputDecoration(
              labelText: 'Địa chỉ Email nhận thông báo',
              hintText: 'VD: your-email@gmail.com',
              prefixIcon: const Icon(Icons.email_outlined, color: Colors.teal),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Colors.teal, width: 2)),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              isDense: true,
            ),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.teal,
                side: const BorderSide(color: Colors.teal),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: _testingChannel == 'email'
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.teal),
                    )
                  : const Icon(Icons.send, size: 16),
              label: const Text('Gửi Email Thử Nghiệm'),
              onPressed: _testingChannel != null
                  ? null
                  : () {
                      _testChannel('email', {
                        'recipient_email': _emailRecipientController.text.trim(),
                      });
                    },
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.teal.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.teal.withOpacity(0.3)),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: Colors.teal),
                    SizedBox(width: 6),
                    Text(
                      'Lưu ý cấu hình Email:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.teal),
                    ),
                  ],
                ),
                SizedBox(height: 6),
                Text('• Email này sẽ tự động nhận các thông báo và cảnh báo từ hệ thống.', style: TextStyle(fontSize: 11)),
                Text('• Nếu không thấy email trong Hộp thư đến, vui lòng kiểm tra mục Thư rác (Spam / Junk).', style: TextStyle(fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
