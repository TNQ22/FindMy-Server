import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:universal_html/html.dart' as html;
import 'package:flutter_settings_screens/flutter_settings_screens.dart';

import 'package:macless_haystack/accessory/accessory_registry.dart';
import 'package:macless_haystack/findMy/icloud_dialog.dart';
import 'package:macless_haystack/preferences/user_preferences_model.dart';
import 'package:macless_haystack/location/location_model.dart';
import 'package:macless_haystack/preferences/auth_state.dart';
import 'package:macless_haystack/admin/admin_page.dart';

class UserAvatarMenu extends StatefulWidget {
  const UserAvatarMenu({super.key});

  @override
  State<UserAvatarMenu> createState() => _UserAvatarMenuState();
}

class _UserAvatarMenuState extends State<UserAvatarMenu> {
  String? _userName;
  String? _userEmail;
  String? _userPicture;
  bool _isAdmin = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchUserInfo();
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

  Future<void> _saveSettingsToServer(Map<String, dynamic> settingsMap) async {
    final token = Settings.getValue<String>(endpointUser, defaultValue: '')!;
    if (token.trim().isEmpty) return;

    try {
      await http.post(
        Uri.parse('$_baseUrl/api/auth/settings'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': token.trim().startsWith('Bearer ') ? token.trim() : 'Bearer ${token.trim()}',
        },
        body: jsonEncode({'settings_json': jsonEncode(settingsMap)}),
      );
    } catch (_) {}
  }

  Future<void> _fetchUserInfo() async {
    final token = Settings.getValue<String>(endpointUser, defaultValue: '')!;
    if (token.trim().isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/api/auth/me'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': token.trim().startsWith('Bearer ') ? token.trim() : 'Bearer ${token.trim()}',
        },
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['settings_json'] != null && data['settings_json'].toString().trim().isNotEmpty) {
          try {
            final sMap = jsonDecode(data['settings_json']);
            if (sMap['number_of_days'] != null) {
              await Settings.setValue<int>(numberOfDaysToFetch, (sMap['number_of_days'] as num).toInt());
            }
            if (sMap['fetch_on_startup'] != null) {
              await Settings.setValue<bool>(fetchLocationOnStartupKey, sMap['fetch_on_startup'] == true);
            }
            if (sMap['email_alerts_enabled'] != null) {
              await Settings.setValue<bool>(emailAlertsEnabledKey, sMap['email_alerts_enabled'] == true);
            }
            if (sMap['location_access_wanted'] != null) {
              bool wantLoc = sMap['location_access_wanted'] == true;
              await Settings.setValue<bool>(locationAccessWantedKey, wantLoc);
              if (mounted) {
                var userPrefs = Provider.of<UserPreferences>(context, listen: false);
                var locationModel = Provider.of<LocationModel>(context, listen: false);
                await userPrefs.setLocationPreference(wantLoc);
                if (wantLoc) {
                  locationModel.requestLocationUpdates();
                } else {
                  locationModel.cancelLocationUpdates();
                }
              }
            }
          } catch (_) {}
        }
        if (mounted) {
          setState(() {
            _userName = data['name'];
            _userEmail = data['email'];
            _userPicture = data['picture'];
            _isAdmin = data['is_admin'] == true;
            _loading = false;
          });
        }
      } else {
        if (mounted) setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showProfilePopup(BuildContext context) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black38,
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (ctx, anim1, anim2) {
        return const SizedBox.shrink();
      },
      transitionBuilder: (ctx, anim1, anim2, child) {
        final curve = CurvedAnimation(parent: anim1, curve: Curves.easeOutBack);
        return ScaleTransition(
          scale: curve,
          alignment: const Alignment(0.9, -0.9), // Top-right popup anchor
          child: StatefulBuilder(
            builder: (dialogContext, setDialogState) {
              bool showLocation = Settings.getValue<bool>(locationAccessWantedKey, defaultValue: true)!;
              bool emailAlertsEnabled = Settings.getValue<bool>(emailAlertsEnabledKey, defaultValue: true)!;

              return AlertDialog(
                alignment: Alignment.topRight,
                insetPadding: const EdgeInsets.only(top: 60, right: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                contentPadding: const EdgeInsets.all(20),
                content: SizedBox(
                  width: 330,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Avatar Header
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 28,
                              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                              backgroundImage: (_userPicture != null && _userPicture!.isNotEmpty)
                                  ? NetworkImage(_userPicture!)
                                  : null,
                              child: (_userPicture == null || _userPicture!.isEmpty)
                                  ? Text(
                                      (_userName != null && _userName!.isNotEmpty)
                                          ? _userName![0].toUpperCase()
                                          : 'G',
                                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _userName ?? 'Tài khoản Google',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _userEmail ?? 'Chưa đăng nhập',
                                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.green.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.check_circle, size: 12, color: Colors.green),
                                        SizedBox(width: 4),
                                        Text(
                                          'Google Verified',
                                          style: TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        const Divider(height: 1),
                        const SizedBox(height: 12),

                        // Section 1: Quick Core Links
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.cloud_outlined, color: Colors.blue, size: 20),
                          ),
                          title: const Text('Shared iCloud', style: TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: const Text('Quản lý danh sách tài khoản iCloud', style: TextStyle(fontSize: 11)),
                          trailing: const Icon(Icons.chevron_right, size: 18),
                          onTap: () {
                            Navigator.pop(ctx);
                            showDialog(
                              context: context,
                              builder: (c) => const ICloudManagementDialog(),
                            );
                          },
                        ),

                        const SizedBox(height: 8),

                        if (_isAdmin) ...[
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.admin_panel_settings, color: Colors.orange, size: 20),
                            ),
                            title: const Text('Trang Quản trị', style: TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: const Text('Quản lý User & Thiết bị hệ thống', style: TextStyle(fontSize: 11)),
                            trailing: const Icon(Icons.chevron_right, size: 18),
                            onTap: () async {
                              Navigator.pop(ctx);
                              await Navigator.push(
                                context,
                                MaterialPageRoute(builder: (context) => const AdminPage()),
                              );
                              // Refresh devices automatically after closing Admin Page
                              if (context.mounted) {
                                Provider.of<AccessoryRegistry>(context, listen: false).syncWithBackendServer();
                                Provider.of<LocationModel>(context, listen: false).requestLocationUpdates();
                              }
                            },
                          ),
                          const SizedBox(height: 8),
                        ],
                        const Divider(height: 1),
                        const SizedBox(height: 8),

                        // Section 2: Quick Settings Directly In Avatar Menu!
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'THIẾT LẬP NHANH',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey),
                          ),
                        ),
                        const SizedBox(height: 6),

                        // Setting 1: Show this device's location
                        SwitchListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          secondary: const Icon(Icons.my_location, size: 20, color: Colors.teal),
                          title: const Text('Show this device\'s location', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                          subtitle: const Text('Định vị vị trí thiết bị này trên bản đồ', style: TextStyle(fontSize: 11)),
                          value: showLocation,
                          onChanged: (val) async {
                            var userPrefs = Provider.of<UserPreferences>(context, listen: false);
                            await userPrefs.setLocationPreference(val);
                            setDialogState(() {});
                            var locationModel = Provider.of<LocationModel>(context, listen: false);
                            if (val) {
                              locationModel.requestLocationUpdates();
                            } else {
                              locationModel.cancelLocationUpdates();
                            }
                            _saveSettingsToServer({
                              'number_of_days': Settings.getValue<int>(numberOfDaysToFetch, defaultValue: 30),
                              'location_access_wanted': val,
                              'email_alerts_enabled': Settings.getValue<bool>(emailAlertsEnabledKey, defaultValue: true),
                            });
                          },
                        ),


                        // Setting 2: Email Alerts
                        SwitchListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          secondary: const Icon(Icons.email, size: 20, color: Colors.blue),
                          title: const Text('Nhận cảnh báo qua Email', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                          subtitle: const Text('Gửi email khi pin Thấp / Rất thấp', style: TextStyle(fontSize: 11)),
                          value: emailAlertsEnabled,
                          onChanged: (val) async {
                            await Settings.setValue<bool>(emailAlertsEnabledKey, val);
                            setDialogState(() {
                              emailAlertsEnabled = val;
                            });
                            _saveSettingsToServer({
                              'number_of_days': Settings.getValue<int>(numberOfDaysToFetch, defaultValue: 30),
                              'location_access_wanted': Settings.getValue<bool>(locationAccessWantedKey, defaultValue: true),
                              'email_alerts_enabled': val,
                            });
                          },
                        ),
                        
                        Align(
                          alignment: Alignment.centerRight,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue.withOpacity(0.1),
                              foregroundColor: Colors.blue,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                            icon: const Icon(Icons.send, size: 16),
                            label: const Text('Gửi Email Test', style: TextStyle(fontSize: 12)),
                            onPressed: () async {
                              // Send test email
                              final token = Settings.getValue<String>(endpointUser, defaultValue: '')!;
                              try {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đang gửi...')));
                                final res = await http.post(
                                  Uri.parse('$_baseUrl/api/auth/test-email'),
                                  headers: {
                                    'Content-Type': 'application/json',
                                    'Authorization': token.trim().startsWith('Bearer ') ? token.trim() : 'Bearer ${token.trim()}',
                                  },
                                );
                                if (res.statusCode == 200 && context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã gửi Email Test thành công! Vui lòng kiểm tra hộp thư.')));
                                } else if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lỗi gửi email! Kiểm tra log backend.')));
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lỗi kết nối máy chủ!')));
                                }
                              }
                            },
                          ),
                        ),

                        const SizedBox(height: 12),
                        const Divider(height: 1),
                        const SizedBox(height: 16),

                        // Logout Button
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red.shade50,
                              foregroundColor: Colors.red.shade700,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: const Icon(Icons.logout, size: 18),
                            label: const Text('Đăng xuất Google', style: TextStyle(fontWeight: FontWeight.bold)),
                            onPressed: () async {
                              Navigator.pop(ctx);
                              await Provider.of<AuthState>(context, listen: false).logout();
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: GestureDetector(
        onTap: () => _showProfilePopup(context),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Tooltip(
            message: _userName ?? 'Tài khoản Google',
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [Colors.blue.shade400, Colors.purple.shade400],
                    ),
                  ),
                  child: CircleAvatar(
                    radius: 18,
                    backgroundColor: Theme.of(context).colorScheme.surface,
                    backgroundImage: (_userPicture != null && _userPicture!.isNotEmpty)
                        ? NetworkImage(_userPicture!)
                        : null,
                    child: (_userPicture == null || _userPicture!.isEmpty)
                        ? Text(
                            (_userName != null && _userName!.isNotEmpty)
                                ? _userName![0].toUpperCase()
                                : 'G',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          )
                        : null,
                  ),
                ),
                Positioned(
                  right: 0,
                  bottom: 4,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                      border: Border.all(color: Theme.of(context).colorScheme.surface, width: 1.5),
                    ),
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
