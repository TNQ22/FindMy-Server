class WebInterop {
  static String? get windowOrigin => null;

  static String? getRedirectToken() => null;

  static void triggerGooglePopupLogin(String clientId, void Function(String) onToken) {}

  static void googleSignOut() {}

  static void getWebDeviceLocation(void Function(double lat, double lng) onLocation) {}

  static void stopWebDeviceLocation() {}
}
