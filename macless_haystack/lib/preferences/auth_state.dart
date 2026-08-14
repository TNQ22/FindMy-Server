import 'package:flutter/foundation.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:macless_haystack/preferences/user_preferences_model.dart';
import 'package:universal_html/html.dart' as html;

/// Single source of truth for authentication state across the app.
/// Any component that detects a 401 should call [onUnauthorized] to
/// trigger a global logout and redirect to the LoginPage.
class AuthState extends ChangeNotifier {
  bool _isLoggedIn = false;
  bool _sessionExpired = false;

  bool get isLoggedIn => _isLoggedIn;
  bool get sessionExpired => _sessionExpired;

  AuthState() {
    _checkInitialToken();
  }

  void _checkInitialToken() {
    final token = Settings.getValue<String>(endpointUser, defaultValue: '')!;
    _isLoggedIn = token.trim().isNotEmpty;
  }

  /// Call this after a successful login to set the JWT token.
  Future<void> onLoginSuccess(String jwtToken) async {
    final bearerToken = jwtToken.startsWith('Bearer ') ? jwtToken : 'Bearer $jwtToken';
    await Settings.setValue<String>(endpointUser, bearerToken);
    _isLoggedIn = true;
    _sessionExpired = false;
    notifyListeners();
  }

  /// Call this when the user actively logs out.
  Future<void> logout() async {
    await Settings.setValue<String>(endpointUser, '');
    try {
      html.window.localStorage.remove('ENDPOINT_USER');
    } catch (_) {}
    _isLoggedIn = false;
    _sessionExpired = false;
    notifyListeners();
  }

  /// Call this from anywhere (ReportsFetcher, AccessoryRegistry, etc.)
  /// when a 401 Unauthorized response is received.
  /// This clears the token and redirects the user to the LoginPage.
  Future<void> onUnauthorized() async {
    await Settings.setValue<String>(endpointUser, '');
    try {
      html.window.localStorage.remove('ENDPOINT_USER');
    } catch (_) {}
    _isLoggedIn = false;
    _sessionExpired = true;
    notifyListeners();
  }

  /// Get the current bearer token.
  String get bearerToken {
    return Settings.getValue<String>(endpointUser, defaultValue: '')!;
  }
}
