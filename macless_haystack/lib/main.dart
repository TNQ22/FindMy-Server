import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:universal_html/html.dart' as html;
import 'package:macless_haystack/dashboard/dashboard.dart';
import 'package:provider/provider.dart';
import 'package:macless_haystack/accessory/accessory_registry.dart';
import 'package:macless_haystack/location/location_model.dart';
import 'package:macless_haystack/preferences/user_preferences_model.dart';
import 'package:macless_haystack/preferences/google_auth_dialog.dart';
import 'package:macless_haystack/preferences/auth_state.dart';
import 'package:macless_haystack/splashscreen.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:macless_haystack/preferences/login_page.dart';

void main() {
  Settings.init();
  initializeDateFormatting();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // AuthState must be first so other providers can depend on it
        ChangeNotifierProvider(create: (ctx) => AuthState()),
        ChangeNotifierProvider(create: (ctx) {
          final registry = AccessoryRegistry();
          return registry;
        }),
        ChangeNotifierProvider(create: (ctx) => UserPreferences()),
        ChangeNotifierProvider(create: (ctx) => LocationModel()),
      ],
      child: MaterialApp(
        title: 'FindMy Server',
        theme: ThemeData(primarySwatch: Colors.blue),
        darkTheme: ThemeData.dark(),
        home: const AppLayout(),
      ),
    );
  }
}

class AppLayout extends StatefulWidget {
  const AppLayout({super.key});

  @override
  State<AppLayout> createState() => _AppLayoutState();
}

class _AppLayoutState extends State<AppLayout> {
  @override
  initState() {
    super.initState();

    _initAppConfig().then((_) {
      if (mounted) {
        final authState = Provider.of<AuthState>(context, listen: false);
        final accessoryRegistry = Provider.of<AccessoryRegistry>(context, listen: false);

        // Wire 401 handler: any 401 in AccessoryRegistry triggers AuthState logout
        accessoryRegistry.onUnauthorized = () {
          authState.onUnauthorized();
        };

        if (authState.isLoggedIn) {
          accessoryRegistry.loadAccessories();
        }
      }
    });
  }

  Future<void> _initAppConfig() async {
    try {
      String origin = html.window.location.origin;
      String baseUrl = origin.startsWith('http') ? origin : 'http://localhost:6176';
      final res = await http.get(Uri.parse('$baseUrl/api/config'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['google_client_id'] != null && data['google_client_id'].toString().isNotEmpty) {
          await Settings.setValue<String>(googleClientIdKey, data['google_client_id'].toString());
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    precacheImage(const AssetImage('assets/OpenHaystackIcon.png'), context);
    super.didChangeDependencies();
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthState>();
    bool isInitialized = context.watch<UserPreferences>().initialized;
    bool isLoading = context.watch<AccessoryRegistry>().loading;

    if (!isInitialized || isLoading) {
      return const Splashscreen();
    }

    // Not logged in OR session expired → show LoginPage
    if (!authState.isLoggedIn) {
      return LoginPage(
        // Show a banner if session was auto-expired due to 401
        sessionExpired: authState.sessionExpired,
        onLoginSuccess: () {
          // After login, reload accessories
          Provider.of<AccessoryRegistry>(context, listen: false).loadAccessories();
        },
      );
    }

    return const Dashboard();
  }
}
