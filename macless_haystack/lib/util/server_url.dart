import 'package:flutter/foundation.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:macless_haystack/preferences/user_preferences_model.dart';
import 'package:macless_haystack/util/web_interop.dart';

/// Returns the normalized base URL of the FindMy Server.
/// - On Web: uses the current browser origin (e.g. https://findmy.domain.com).
/// - On Android / iOS / Desktop: uses the server URL configured by the user in Settings
///   (or defaults to http://localhost:6176 if not configured).
String getServerBaseUrl() {
  if (kIsWeb) {
    try {
      final origin = WebInterop.windowOrigin;
      if (origin != null && origin.startsWith('http')) {
        return origin;
      }
    } catch (_) {}
  }

  String configuredUrl = Settings.getValue<String>(endpointUrl, defaultValue: 'https://findmy.tnq.io.vn')!;
  if (configuredUrl.endsWith('/')) {
    configuredUrl = configuredUrl.substring(0, configuredUrl.length - 1);
  }
  return configuredUrl.isEmpty ? 'https://findmy.tnq.io.vn' : configuredUrl;
}
