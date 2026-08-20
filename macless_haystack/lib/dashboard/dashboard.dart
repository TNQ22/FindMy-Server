import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:latlong2/latlong.dart';
import 'package:logger/logger.dart';
import 'package:macless_haystack/dashboard/app_toast.dart';
import 'package:macless_haystack/item_management/refresh_action.dart';
import 'package:provider/provider.dart';
import 'package:macless_haystack/accessory/accessory_list.dart';
import 'package:macless_haystack/accessory/accessory_registry.dart';
import 'package:macless_haystack/dashboard/accessory_map_list_vert.dart';
import 'package:macless_haystack/item_management/item_management.dart';
import 'package:macless_haystack/item_management/new_item_action.dart';
import 'package:macless_haystack/location/location_model.dart';
import 'package:macless_haystack/map/map.dart';
import 'package:macless_haystack/preferences/user_preferences_model.dart';
import 'package:macless_haystack/zones/zone_management_dialog.dart';

import '../accessory/accessory_model.dart';
import 'package:macless_haystack/preferences/user_avatar_menu.dart';

class Dashboard extends StatefulWidget {
  /// Displays the layout for the app with Apple Find My style floating UI on desktop.
  const Dashboard({super.key});

  @override
  State<StatefulWidget> createState() {
    return _DashboardState();
  }
}

class _DashboardState extends State<Dashboard> {
  bool _hasShownStartupToast = false;
  int _selectedIndex = 0;
  int _desktopTab = 0; // 0: Map List, 1: Key Management
  bool _isSidebarCollapsed = false;
  bool _isSyncing = false;
  final MapController _mapController = MapController();

  var logger = Logger(
    printer: PrettyPrinter(),
  );

  /// A list of the tabs displayed in the mobile bottom tab bar.
  late final List<Map<String, dynamic>> _tabs = [
    {
      'title': 'FindMy Server',
      'body': (ctx) => AccessoryMapListVertical(
            loadLocationUpdates: loadLocationUpdates,
            saveOrderUpdatesCallback: saveAccessories,
          ),
      'icon': Icons.place,
      'label': 'Vị trí Tag',
      'actionButton': (ctx) => RefreshAction(
            callback: () async {
              await loadLocationUpdates(null);
            },
          ),
    },
    {
      'title': 'FindMy Server',
      'body': (ctx) => const KeyManagement(),
      'icon': Icons.style,
      'label': 'Quản lý Tag',
      'actionButton': (ctx) => const NewKeyAction(),
    },
  ];

  @override
  void initState() {
    super.initState();

    // Initialize models and preferences
    var userPreferences = Provider.of<UserPreferences>(context, listen: false);
    var locationModel = Provider.of<LocationModel>(context, listen: false);
    var locationPreferenceKnown =
        userPreferences.locationPreferenceKnown ?? false;
    var locationAccessWanted = userPreferences.locationAccessWanted ?? true;
    if (!locationPreferenceKnown || locationAccessWanted) {
      locationModel.requestLocationUpdates();
    }
  }

  /// Fetch location updates for all accessories when user manually triggers refresh.
  Future<void> loadLocationUpdates(Accessory? accessory) async {
    if (_isSyncing) return;
    setState(() => _isSyncing = true);

    var accessoryRegistry =
        Provider.of<AccessoryRegistry>(context, listen: false);
    try {
      final result = await accessoryRegistry.triggerImmediateSync();
      if (!mounted) return;

      // Check global iCloud Pool status for precise user feedback
      var statusData = await accessoryRegistry.fetchICloudStatus();
      String loginState = (statusData['login_state'] ?? 'LOGGED_OUT').toString();
      List accounts = (statusData['accounts'] as List?) ?? [];
      var activeAccounts = accounts.where((a) => a['is_active'] == true).toList();
      bool hasLoggedInAccount = activeAccounts.any((a) => (a['login_state'] ?? '').toString() == 'LOGGED_IN');

      if (!hasLoggedInAccount && activeAccounts.isNotEmpty && activeAccounts.every((a) => (a['login_state'] ?? '').toString().contains('REQUIRE_2FA'))) {
        AppToast.showText(
          context,
          '⚠️ Tài khoản iCloud cần xác thực 2FA. Vui lòng mở Shared iCloud để xác thực!',
          backgroundColor: Colors.amber.shade900,
          duration: const Duration(seconds: 5),
        );
      } else if (!hasLoggedInAccount && (loginState == 'LOGGED_OUT' || activeAccounts.isEmpty)) {
        AppToast.showText(
          context,
          '⚠️ Chưa có tài khoản iCloud khả dụng. Vui lòng thêm tài khoản!',
          backgroundColor: Colors.amber.shade900,
          duration: const Duration(seconds: 5),
        );
      } else {
        final newCount = result.newReports;
        final updated = result.updatedDevices;
        AppToast.showText(
          context,
          newCount > 0
              ? 'Đã cập nhật vị trí: $newCount báo cáo mới${updated.isNotEmpty ? " cho ${updated.join(", ")}" : ""}'
              : 'Vị trí đã được đồng bộ (không có dữ liệu mới)',
          backgroundColor: Colors.teal.shade700,
          icon: Icons.refresh_rounded,
          duration: const Duration(seconds: 4),
        );
      }
    } catch (e, stacktrace) {
      logger.e('Error on fetching', error: e, stackTrace: stacktrace);
      if (mounted) {
        AppToast.showText(
          context,
          'Lỗi đồng bộ dữ liệu. Thử lại sau. Lỗi: ${e.toString()}',
          backgroundColor: Theme.of(context).colorScheme.error,
          duration: const Duration(seconds: 6),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  void _centerMap(LatLng point) {
    _mapController.move(point, 17);
  }

  @override
  Widget build(BuildContext context) {
    final accessoryRegistry = Provider.of<AccessoryRegistry>(context);
    final isDesktop = MediaQuery.of(context).size.width >= 720;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Trigger floating SnackBar toast once initial location fetch completes
    if (!_hasShownStartupToast && accessoryRegistry.initialLoadFinished) {
      _hasShownStartupToast = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          final count = accessoryRegistry.accessories.where((a) => a.isActive).length;
          if (count > 0) {
            AppToast.showText(
              context,
              'Đã nạp và cập nhật vị trí mới nhất cho $count thiết bị!',
              backgroundColor: Colors.teal.shade700,
              icon: Icons.check_circle_rounded,
              duration: const Duration(seconds: 4),
            );
          }
        }
      });
    }

    // ==========================================
    // 🖥️ DESKTOP LAYOUT (Apple Find My Floating UI)
    // ==========================================
    if (isDesktop) {
      final activeCount = accessoryRegistry.accessories.where((a) => a.isActive).length;

      return Scaffold(
        body: Stack(
          children: [
            // Layer 0: Fullscreen Map
            Positioned.fill(
              child: AccessoryMap(
                mapController: _mapController,
              ),
            ),

            // Layer 1: Floating User Profile Button (Top-Right)
            const Positioned(
              top: 16,
              right: 16,
              child: UserAvatarMenu(),
            ),

            // Layer 2: Floating Left Sidebar Panel (Full-height from top: 16 to bottom: 16)
            AnimatedPositioned(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              top: 16,
              left: _isSidebarCollapsed ? -410 : 16,
              bottom: 16,
              width: 380,
              child: Container(
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey.shade900.withOpacity(0.95) : Colors.white.withOpacity(0.95),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.18),
                      blurRadius: 22,
                      offset: const Offset(0, 6),
                    ),
                  ],
                  border: Border.all(
                    color: isDark ? Colors.white.withOpacity(0.12) : Colors.black.withOpacity(0.08),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Column(
                    children: [
                      // Panel Header with Sub-tabs
                      Container(
                        padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: isDark ? Colors.white12 : Colors.black.withOpacity(0.06),
                            ),
                          ),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.radar, color: Colors.teal, size: 20),
                                const SizedBox(width: 8),
                                const Text(
                                  'FindMy Server',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.teal.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '$activeCount',
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.teal),
                                  ),
                                ),
                                const Spacer(),
                                IconButton(
                                  icon: const Icon(Icons.chevron_left, size: 22),
                                  tooltip: 'Thu gọn danh sách',
                                  onPressed: () => setState(() => _isSidebarCollapsed = true),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),

                            // Sub Tab Switcher Pills
                            Container(
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: () => setState(() => _desktopTab = 0),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(vertical: 7),
                                        decoration: BoxDecoration(
                                          color: _desktopTab == 0
                                              ? (isDark ? Colors.grey.shade700 : Colors.white)
                                              : Colors.transparent,
                                          borderRadius: BorderRadius.circular(10),
                                          boxShadow: _desktopTab == 0
                                              ? [
                                                  BoxShadow(
                                                    color: Colors.black.withOpacity(0.08),
                                                    blurRadius: 4,
                                                    offset: const Offset(0, 1),
                                                  )
                                                ]
                                              : null,
                                        ),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.location_on,
                                              size: 15,
                                              color: _desktopTab == 0 ? Colors.teal : Colors.grey,
                                            ),
                                            const SizedBox(width: 5),
                                            Text(
                                              'Vị trí Tag',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: _desktopTab == 0 ? FontWeight.bold : FontWeight.normal,
                                                color: _desktopTab == 0 ? null : Colors.grey,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: () => setState(() => _desktopTab = 1),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(vertical: 7),
                                        decoration: BoxDecoration(
                                          color: _desktopTab == 1
                                              ? (isDark ? Colors.grey.shade700 : Colors.white)
                                              : Colors.transparent,
                                          borderRadius: BorderRadius.circular(10),
                                          boxShadow: _desktopTab == 1
                                              ? [
                                                  BoxShadow(
                                                    color: Colors.black.withOpacity(0.08),
                                                    blurRadius: 4,
                                                    offset: const Offset(0, 1),
                                                  )
                                                ]
                                              : null,
                                        ),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.tune,
                                              size: 15,
                                              color: _desktopTab == 1 ? Colors.teal : Colors.grey,
                                            ),
                                            const SizedBox(width: 5),
                                            Text(
                                              'Quản lý Tag',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: _desktopTab == 1 ? FontWeight.bold : FontWeight.normal,
                                                color: _desktopTab == 1 ? null : Colors.grey,
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
                          ],
                        ),
                      ),

                      // Panel Body
                      Expanded(
                        child: _desktopTab == 0
                            ? AccessoryList(
                                loadLocationUpdates: loadLocationUpdates,
                                saveOrderUpdatesCallback: saveAccessories,
                                centerOnPoint: _centerMap,
                              )
                            : const KeyManagement(),
                      ),

                      // Panel Bottom Toolbar (Nút chuyển đổi động theo tab: Làm mới khi ở Vị trí, Thêm Tag khi ở Quản lý)
                      Container(
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.grey.shade900 : Colors.grey.shade50,
                          border: Border(
                            top: BorderSide(
                              color: isDark ? Colors.white10 : Colors.black.withOpacity(0.06),
                            ),
                          ),
                        ),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.teal,
                              foregroundColor: Colors.white,
                              elevation: 1,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(vertical: 11),
                            ),
                            icon: _desktopTab == 0
                                ? (_isSyncing
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                      )
                                    : const Icon(Icons.refresh, size: 20))
                                : const Icon(Icons.add, size: 20),
                            label: Text(
                              _desktopTab == 0 ? 'Làm mới vị trí' : 'Thêm Tag mới',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            onPressed: _desktopTab == 0
                                ? (_isSyncing ? null : () => loadLocationUpdates(null))
                                : () => const NewKeyAction().showCreationSheet(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Layer 3: Floating Top-Left Button to Open List (When sidebar is collapsed)
            if (_isSidebarCollapsed)
              Positioned(
                top: 16,
                left: 16,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isDark ? Colors.grey.shade900 : Colors.white,
                    foregroundColor: Colors.teal,
                    elevation: 6,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    side: BorderSide(color: isDark ? Colors.white12 : Colors.black.withOpacity(0.08)),
                  ),
                  icon: const Icon(Icons.view_sidebar_outlined, size: 18),
                  label: const Text('Danh sách thiết bị', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  onPressed: () => setState(() {
                    _isSidebarCollapsed = false;
                    _desktopTab = 0;
                  }),
                ),
              ),

            // Layer 4: Floating Bottom-Left Action Button (When sidebar is collapsed)
            if (_isSidebarCollapsed)
              Positioned(
                bottom: 16,
                left: 16,
                child: FloatingActionButton(
                  heroTag: 'desktopCollapsedFab',
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  elevation: 6,
                  tooltip: _desktopTab == 0 ? 'Làm mới vị trí từ Apple' : 'Thêm thiết bị mới',
                  onPressed: _desktopTab == 0
                      ? (_isSyncing ? null : () => loadLocationUpdates(null))
                      : () => const NewKeyAction().showCreationSheet(context),
                  child: _desktopTab == 0
                      ? (_isSyncing
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                            )
                          : const Icon(Icons.refresh, size: 26))
                      : const Icon(Icons.add, size: 26),
                ),
              ),
          ],
        ),
      );
    }

    // ==========================================
    // 📱 MOBILE LAYOUT (Classic / Responsive)
    // ==========================================
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _tabs[_selectedIndex]['title'] as String,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: const <Widget>[
          Padding(
            padding: EdgeInsets.only(right: 12),
            child: Center(
              child: UserAvatarMenu(),
            ),
          ),
        ],
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          _tabs[0]['body'](context),
          _tabs[1]['body'](context),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: _tabs
            .map((tab) => BottomNavigationBarItem(
                  icon: Icon(tab['icon']),
                  label: tab['label'],
                ))
            .toList(),
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.teal,
        unselectedItemColor: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
        onTap: _onItemTapped,
      ),
      floatingActionButton: _tabs[_selectedIndex]['actionButton']?.call(context),
      floatingActionButtonLocation: FloatingActionButtonLocation.endDocked,
    );
  }

  Future<void> saveAccessories(List<Accessory> accessories) async {
    var accessoryRegistry =
        Provider.of<AccessoryRegistry>(context, listen: false);
    accessoryRegistry.saveOrderUpdates(accessories);
  }
}

