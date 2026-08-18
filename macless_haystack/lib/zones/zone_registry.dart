import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:universal_html/html.dart' as html;

import 'package:macless_haystack/preferences/user_preferences_model.dart';
import 'package:macless_haystack/zones/zone_model.dart';

class ZoneRegistry extends ChangeNotifier {
  List<ZoneItem> _zones = [];
  List<ZoneAlertItem> _alerts = [];
  int _totalAlerts = 0;
  bool _loading = false;
  bool _showZonesOnMap = true;
  ZoneItem? _focusedZone;
  ZoneItem? _highlightedZone;

  List<ZoneItem> get zones => List.unmodifiable(_zones);
  List<ZoneAlertItem> get alerts => List.unmodifiable(_alerts);
  int get totalAlerts => _totalAlerts;
  bool get loading => _loading;
  bool get showZonesOnMap => _showZonesOnMap;
  ZoneItem? get focusedZone => _focusedZone;
  ZoneItem? get highlightedZone => _highlightedZone;

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
    try {
      String token = Settings.getValue<String>(endpointUser, defaultValue: '')!;
      if (token.isEmpty) {
        token = html.window.localStorage['ENDPOINT_USER'] ?? '';
      }
      if (token.isNotEmpty) {
        headers['Authorization'] =
            token.startsWith('Bearer ') ? token : 'Bearer $token';
      }
    } catch (_) {}
    return headers;
  }

  static const String _prefShowZones = 'SHOW_ZONES_ON_MAP';

  ZoneRegistry() {
    _loadPreferences();
  }

  void _loadPreferences() {
    try {
      final val = Settings.getValue<bool>(_prefShowZones, defaultValue: true);
      _showZonesOnMap = val ?? true;
    } catch (_) {
      try {
        final raw = html.window.localStorage[_prefShowZones];
        if (raw != null) {
          _showZonesOnMap = raw == 'true';
        }
      } catch (_) {}
    }
  }

  void toggleShowZonesOnMap(bool val) {
    _showZonesOnMap = val;
    try {
      Settings.setValue<bool>(_prefShowZones, val);
    } catch (_) {}
    try {
      html.window.localStorage[_prefShowZones] = val.toString();
    } catch (_) {}
    notifyListeners();
  }

  void focusZone(ZoneItem? zone) {
    _focusedZone = zone;
    _highlightedZone = zone;
    notifyListeners();
  }

  void clearFocusedCamera() {
    _focusedZone = null;
  }

  void clearHighlightedZone() {
    if (_highlightedZone != null) {
      _highlightedZone = null;
      notifyListeners();
    }
  }

  Future<void> fetchZones() async {
    _loading = true;
    notifyListeners();

    try {
      final res = await http.get(Uri.parse('$_baseUrl/api/zones/'), headers: _headers);
      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body);
        _zones = list.map((item) => ZoneItem.fromJson(item as Map<String, dynamic>)).toList();
      }
    } catch (e) {
      debugPrint('Error fetching zones: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<bool> createZone({
    required String name,
    required double latitude,
    required double longitude,
    required double radius,
    required bool alertOnExit,
    required bool alertOnEnter,
    required int cooldownMinutes,
    required bool isActive,
    String shapeType = 'circle',
    List<LatLng>? polygonPoints,
    List<int>? deviceIds,
    List<String>? hashedAdvKeys,
  }) async {
    try {
      final payload = {
        'name': name.trim(),
        'latitude': latitude,
        'longitude': longitude,
        'radius': radius,
        'shape_type': shapeType,
        'polygon_points': polygonPoints != null
            ? polygonPoints.map((p) => {'lat': p.latitude, 'lon': p.longitude}).toList()
            : null,
        'alert_on_exit': alertOnExit,
        'alert_on_enter': alertOnEnter,
        'cooldown_minutes': cooldownMinutes,
        'is_active': isActive,
        'device_ids': deviceIds ?? [],
        'hashed_adv_keys': hashedAdvKeys ?? [],
      };

      final res = await http.post(
        Uri.parse('$_baseUrl/api/zones/'),
        headers: _headers,
        body: jsonEncode(payload),
      );

      if (res.statusCode == 201) {
        await fetchZones();
        return true;
      }
    } catch (e) {
      debugPrint('Error creating zone: $e');
    }
    return false;
  }

  Future<bool> updateZone({
    required int zoneId,
    String? name,
    double? latitude,
    double? longitude,
    double? radius,
    String? shapeType,
    List<LatLng>? polygonPoints,
    bool? alertOnExit,
    bool? alertOnEnter,
    int? cooldownMinutes,
    bool? isActive,
    List<int>? deviceIds,
    List<String>? hashedAdvKeys,
  }) async {
    try {
      final Map<String, dynamic> payload = {};
      if (name != null) payload['name'] = name.trim();
      if (latitude != null) payload['latitude'] = latitude;
      if (longitude != null) payload['longitude'] = longitude;
      if (radius != null) payload['radius'] = radius;
      if (shapeType != null) payload['shape_type'] = shapeType;
      if (polygonPoints != null) {
        payload['polygon_points'] = polygonPoints.map((p) => {'lat': p.latitude, 'lon': p.longitude}).toList();
      }
      if (alertOnExit != null) payload['alert_on_exit'] = alertOnExit;
      if (alertOnEnter != null) payload['alert_on_enter'] = alertOnEnter;
      if (cooldownMinutes != null) payload['cooldown_minutes'] = cooldownMinutes;
      if (isActive != null) payload['is_active'] = isActive;
      if (deviceIds != null) payload['device_ids'] = deviceIds;
      if (hashedAdvKeys != null) payload['hashed_adv_keys'] = hashedAdvKeys;

      final res = await http.put(
        Uri.parse('$_baseUrl/api/zones/$zoneId'),
        headers: _headers,
        body: jsonEncode(payload),
      );

      if (res.statusCode == 200) {
        await fetchZones();
        return true;
      }
    } catch (e) {
      debugPrint('Error updating zone: $e');
    }
    return false;
  }

  Future<bool> deleteZone(int zoneId) async {
    try {
      final res = await http.delete(
        Uri.parse('$_baseUrl/api/zones/$zoneId'),
        headers: _headers,
      );

      if (res.statusCode == 200) {
        _zones.removeWhere((z) => z.id == zoneId);
        notifyListeners();
        return true;
      }
    } catch (e) {
      debugPrint('Error deleting zone: $e');
    }
    return false;
  }

  Future<void> fetchAlerts({int limit = 50, int offset = 0, int? zoneId, int? deviceId}) async {
    try {
      var uri = Uri.parse('$_baseUrl/api/zones/alerts/history?limit=$limit&offset=$offset');
      if (zoneId != null) {
        uri = Uri.parse('$uri&zone_id=$zoneId');
      }
      if (deviceId != null) {
        uri = Uri.parse('$uri&device_id=$deviceId');
      }

      final res = await http.get(uri, headers: _headers);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        _totalAlerts = data['total'] as int? ?? 0;
        final List list = data['items'] as List? ?? [];
        _alerts = list.map((item) => ZoneAlertItem.fromJson(item as Map<String, dynamic>)).toList();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error fetching alerts: $e');
    }
  }

  Future<bool> deleteAlert(int alertId) async {
    try {
      final res = await http.delete(
        Uri.parse('$_baseUrl/api/zones/alerts/$alertId'),
        headers: _headers,
      );

      if (res.statusCode == 200) {
        _alerts.removeWhere((a) => a.id == alertId);
        _totalAlerts = (_totalAlerts - 1).clamp(0, 999999);
        notifyListeners();
        return true;
      }
    } catch (e) {
      debugPrint('Error deleting alert: $e');
    }
    return false;
  }

  Future<bool> clearAllAlerts() async {
    try {
      final res = await http.delete(
        Uri.parse('$_baseUrl/api/zones/alerts'),
        headers: _headers,
      );

      if (res.statusCode == 200) {
        _alerts.clear();
        _totalAlerts = 0;
        notifyListeners();
        return true;
      }
    } catch (e) {
      debugPrint('Error clearing alerts: $e');
    }
    return false;
  }
}
