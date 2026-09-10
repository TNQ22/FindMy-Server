import 'dart:js' as js;
import 'package:universal_html/html.dart' as html;

class WebInterop {
  static String? get windowOrigin {
    try {
      final orig = html.window.location.origin;
      if (orig != null && orig.isNotEmpty) {
        return orig;
      }
    } catch (_) {}
    return null;
  }

  static String? getRedirectToken() {
    try {
      final token = js.context['googleOAuthTokenFromRedirect'];
      if (token != null && token.toString().isNotEmpty) {
        js.context['googleOAuthTokenFromRedirect'] = null;
        return token.toString();
      }
    } catch (_) {}
    return null;
  }

  static void triggerGooglePopupLogin(String clientId, void Function(String) onToken) {
    try {
      js.context.callMethod('triggerGooglePopupLogin', [
        clientId,
        js.allowInterop((token) {
          if (token != null) {
            onToken(token.toString());
          }
        })
      ]);
    } catch (_) {}
  }

  static void googleSignOut() {
    try {
      js.context.callMethod('googleSignOut');
    } catch (_) {}
  }

  static void getWebDeviceLocation(void Function(double lat, double lng) onLocation) {
    try {
      js.context.callMethod('getWebDeviceLocation', [
        js.allowInterop((lat, lng) {
          if (lat != null && lng != null) {
            onLocation((lat as num).toDouble(), (lng as num).toDouble());
          }
        })
      ]);
    } catch (_) {}
  }

  static void stopWebDeviceLocation() {
    try {
      js.context.callMethod('stopWebDeviceLocation');
    } catch (_) {}
  }
}
