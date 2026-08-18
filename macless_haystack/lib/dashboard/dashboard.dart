import 'package:flutter/material.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:logger/logger.dart';
import 'package:macless_haystack/item_management/refresh_action.dart';
import 'package:provider/provider.dart';
import 'package:macless_haystack/accessory/accessory_registry.dart';
import 'package:macless_haystack/dashboard/accessory_map_list_vert.dart';
import 'package:macless_haystack/item_management/item_management.dart';
import 'package:macless_haystack/item_management/new_item_action.dart';
import 'package:macless_haystack/location/location_model.dart';
import 'package:macless_haystack/preferences/user_preferences_model.dart';

import '../accessory/accessory_model.dart';
import 'package:macless_haystack/preferences/user_avatar_menu.dart';

class Dashboard extends StatefulWidget {
  /// Displays the layout for the mobile view of the app.
  const Dashboard({super.key});

  @override
  State<StatefulWidget> createState() {
    return _DashboardState();
  }
}

class _DashboardState extends State<Dashboard> {
  bool _hasShownStartupToast = false;
  int _selectedIndex = 0;

  var logger = Logger(
    printer: PrettyPrinter(),
  );

  /// A list of the tabs displayed in the bottom tab bar.
  late final List<Map<String, dynamic>> _tabs = [
    {
      'title': 'My Accessories',
      'body': (ctx) => AccessoryMapListVertical(
            loadLocationUpdates: loadLocationUpdates,
            saveOrderUpdatesCallback: saveAccessories,
          ),
      'icon': Icons.place,
      'label': 'Map',
      'actionButton': (ctx) => RefreshAction(
            callback: () async {
              await loadLocationUpdates(null);
            },
          ),
    },
    {
      'title': 'My Accessories',
      'body': (ctx) => const KeyManagement(),
      'icon': Icons.style,
      'label': 'Accessories',
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
  /// Now calls the backend POST /api/sync/now which fetches from Apple + decrypts server-side.
  Future<void> loadLocationUpdates(Accessory? accessory) async {
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

      if (loginState == 'REQUIRE_2FA' || loginState == 'LoginState.REQUIRE_2FA') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.amber.shade900,
            content: const Text(
              '⚠️ Tài khoản iCloud cần xác thực 2FA. Vui lòng mở Shared iCloud để xác thực!',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        );
      } else if (loginState == 'LOGGED_OUT' || activeAccounts.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.amber.shade900,
            content: const Text(
              '⚠️ Chưa có tài khoản iCloud khả dụng. Vui lòng thêm tài khoản!',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        );
      } else {
        final newCount = result.newReports;
        final updated = result.updatedDevices;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 3),
            backgroundColor: Colors.teal.shade700,
            content: Row(
              children: [
                const Icon(Icons.refresh_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    newCount > 0
                        ? 'Đã cập nhật vị trí: $newCount báo cáo mới${updated.isNotEmpty ? " cho ${updated.join(", ")}" : ""}'
                        : 'Vị trí đã được đồng bộ (không có dữ liệu mới)',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    } catch (e, stacktrace) {
      logger.e('Error on fetching', error: e, stackTrace: stacktrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Theme.of(context).colorScheme.error,
            content: Text(
              'Lỗi đồng bộ dữ liệu. Thử lại sau. Lỗi: ${e.toString()}',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onError,
              ),
            ),
          ),
        );
      }
    }
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final accessoryRegistry = Provider.of<AccessoryRegistry>(context);

    // Trigger floating SnackBar toast once initial location fetch completes
    if (!_hasShownStartupToast && accessoryRegistry.initialLoadFinished) {
      _hasShownStartupToast = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          final count = accessoryRegistry.accessories.where((a) => a.isActive).length;
          if (count > 0) {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                duration: const Duration(seconds: 4),
                backgroundColor: Colors.teal.shade700,
                content: Row(
                  children: [
                    const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Đã nạp và cập nhật vị trí mới nhất cho $count thiết bị!',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
        }
      });
    }

    return Scaffold(
        appBar: AppBar(
          title: const Text('My Accessories'),
          actions: const <Widget>[
            UserAvatarMenu(),
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
          unselectedItemColor: Theme.of(context).brightness == Brightness.dark
              ? Colors.grey.shade500
              : Colors.grey.shade600,
          onTap: _onItemTapped,
        ),
        floatingActionButton:
            _tabs[_selectedIndex]['actionButton']?.call(context),
        floatingActionButtonLocation: FloatingActionButtonLocation.endDocked);
  }

  Future<void> saveAccessories(List<Accessory> accessories) async {
    var accessoryRegistry =
        Provider.of<AccessoryRegistry>(context, listen: false);
    accessoryRegistry.saveOrderUpdates(accessories);
  }
}
