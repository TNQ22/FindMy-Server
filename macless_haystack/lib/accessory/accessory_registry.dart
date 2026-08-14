import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logger/logger.dart';
import 'package:macless_haystack/accessory/accessory_battery.dart';
import 'package:macless_haystack/accessory/accessory_model.dart';
import 'package:latlong2/latlong.dart';
import 'package:macless_haystack/findMy/find_my_controller.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:macless_haystack/preferences/user_preferences_model.dart';
import 'package:http/http.dart' as http;
import 'package:universal_html/html.dart' as html;

const accessoryStorageKey = 'ACCESSORIES';
const historyStorageKey = 'HISTORY';

/// Represents a single decrypted location entry returned by the backend API.
class LocationHistoryEntry {
  final double latitude;
  final double longitude;
  final int? accuracy;
  final String? batteryStatus;
  final DateTime timestamp;

  LocationHistoryEntry({
    required this.latitude,
    required this.longitude,
    this.accuracy,
    this.batteryStatus,
    required this.timestamp,
  });

  factory LocationHistoryEntry.fromJson(Map<String, dynamic> json) {
    return LocationHistoryEntry(
      latitude:      (json['latitude']  as num).toDouble(),
      longitude:     (json['longitude'] as num).toDouble(),
      accuracy:      json['accuracy'] as int?,
      batteryStatus: json['battery_status'] as String?,
      timestamp:     DateTime.fromMillisecondsSinceEpoch(
          json['timestamp_ms'] as int, isUtc: true),
    );
  }
}

/// Result of a manual sync request (POST /api/sync/now).
class SyncResult {
  final int newReports;
  final int decrypted;
  final List<String> updatedDevices;

  SyncResult({required this.newReports, required this.decrypted, required this.updatedDevices});

  factory SyncResult.fromJson(Map<String, dynamic> json) {
    return SyncResult(
      newReports:     json['new_reports'] as int? ?? 0,
      decrypted:      json['decrypted']   as int? ?? 0,
      updatedDevices: List<String>.from(json['updated_devices'] as List? ?? []),
    );
  }
}

class AccessoryRegistry extends ChangeNotifier {
  var _storage = const FlutterSecureStorage();
  List<Accessory> _accessories = [];
  bool loading = false;
  bool initialLoadFinished = false;

  /// Called when a 401 Unauthorized response is received.
  VoidCallback? onUnauthorized;

  var logger = Logger(
    printer: PrettyPrinter(methodCount: 0),
  );

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

  /// Fetches current iCloud accounts pool status.
  Future<Map<String, dynamic>> fetchICloudStatus() async {
    try {
      final res = await http.get(
          Uri.parse('$_baseUrl/api/icloud/status'), headers: _headers);
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return {};
  }

  /// A list of the user's accessories.
  UnmodifiableListView<Accessory> get accessories =>
      UnmodifiableListView(_accessories);

  /// Loads accessories from storage then syncs with backend server.
  /// Backend now provides last known location directly (no client-side decrypt).
  Future<void> loadAccessories() async {
    loading = true;
    initialLoadFinished = false;

    String? serialized;

    // 1. Read from HTML5 localStorage first
    try {
      serialized = html.window.localStorage['HAYSTACK_ACCESSORIES'];
      if (serialized == null || serialized.isEmpty) {
        serialized = html.window.localStorage['ACCESSORIES_BACKUP'];
      }
    } catch (_) {}

    // 2. Fallback to FlutterSecureStorage
    if (serialized == null || serialized.isEmpty) {
      try {
        serialized = await _storage.read(key: accessoryStorageKey);
      } catch (_) {}
    }

    if (serialized != null && serialized.isNotEmpty) {
      try {
        List accessoryJson = json.decode(serialized);
        List<Accessory> loaded = accessoryJson.map((val) {
          if (val is String) val = json.decode(val);
          return Accessory.fromJson(val as Map<String, dynamic>);
        }).toList();
        _accessories = loaded;
      } catch (e) {
        logger.e("Error decoding stored accessories: $e");
      }
    }

    // Render UI instantly from local storage
    loading = false;
    notifyListeners();

    // Sync device list + latest locations from backend in background
    await syncWithBackendServer();

    initialLoadFinished = true;
    notifyListeners();
  }

  set setStorage(FlutterSecureStorage s) {
    _storage = s;
  }

  String get _baseUrl {
    try {
      String origin = html.window.location.origin;
      if (origin.startsWith('http')) return origin;
    } catch (_) {}
    String configuredUrl =
        Settings.getValue<String>(endpointUrl, defaultValue: '')!;
    if (configuredUrl.endsWith('/')) {
      configuredUrl =
          configuredUrl.substring(0, configuredUrl.length - 1);
    }
    return configuredUrl.isEmpty ? 'http://localhost:6176' : configuredUrl;
  }

  Map<String, String> get _authHeaders {
    Map<String, String> headers = {'Content-Type': 'application/json'};
    String token =
        Settings.getValue<String>(endpointUser, defaultValue: '')!;
    if (token.trim().isNotEmpty) {
      headers['Authorization'] = token.trim().startsWith('Bearer ')
          ? token.trim()
          : 'Bearer ${token.trim()}';
    }
    return headers;
  }

  // ── Backend sync ────────────────────────────────────────────────────────────

  /// Syncs the device list from the backend, restores private keys to
  /// secure storage, and updates last-known location from server-side data.
  Future<void> syncWithBackendServer() async {
    try {
      final token =
          Settings.getValue<String>(endpointUser, defaultValue: '')!;
      if (token.trim().isEmpty) return;

      final res = await http.get(
        Uri.parse('$_baseUrl/api/devices'),
        headers: _authHeaders,
      );

      if (res.statusCode == 401) {
        onUnauthorized?.call();
        return;
      }
      if (res.statusCode == 200) {
        List data = jsonDecode(res.body);
        List<Accessory> syncedAccessories = [];
        bool updated = false;

        for (var item in data) {
          String? jsonStr = item['private_key_b64'];
          String canonicalKey = item['hashed_adv_key']?.toString() ?? '';

          Accessory? acc;
          String? rawPrivateKey;

          if (jsonStr != null && jsonStr.isNotEmpty) {
            if (jsonStr.startsWith('{')) {
              try {
                Map<String, dynamic> accJson = jsonDecode(jsonStr);
                if (canonicalKey.isNotEmpty) {
                  accJson['hashedPublicKey'] = canonicalKey;
                }
                acc = Accessory.fromJson(accJson);
                if (accJson['privateKey'] != null &&
                    accJson['privateKey'].toString().isNotEmpty) {
                  rawPrivateKey = accJson['privateKey'].toString();
                }
              } catch (_) {}
            } else {
              rawPrivateKey = jsonStr.trim();
            }
          }

          // Fall back to minimal Accessory if JSON blob was missing/malformed
          if (acc == null && canonicalKey.isNotEmpty) {
            acc = Accessory(
              id: item['id']?.toString() ?? canonicalKey,
              name: item['name']?.toString() ?? 'Unknown',
              hashedPublicKey: canonicalKey,
              datePublished: null,
              additionalKeys: [],
              hashesWithTS: {},
              lastBatteryStatus: null,
              locationHistory: [],
            );
          }
          if (acc == null) continue;

          // Save private key to secure storage (for tag import, MAC calculation & export support)
          if (rawPrivateKey != null &&
              rawPrivateKey.isNotEmpty &&
              acc.hashedPublicKey.isNotEmpty) {
            try {
              await FindMyController.savePrivateKeyToStorage(
                acc.hashedPublicKey,
                rawPrivateKey,
              );
            } catch (_) {}
          }

          // Override name from DB (authoritative)
          if (item['name'] != null && item['name'].toString().isNotEmpty) {
            acc.name = item['name'].toString();
          }

          // ── Apply server-side decrypted location ──────────────────────────
          final double? lastLat =
              item['last_lat'] != null ? (item['last_lat'] as num).toDouble() : null;
          final double? lastLon =
              item['last_lon'] != null ? (item['last_lon'] as num).toDouble() : null;
          final String? lastSeenStr = item['last_seen_at'] as String?;
          final String? lastBattery = item['last_battery'] as String?;

          if (lastLat != null && lastLon != null) {
            // Server-side location is always authoritative
            acc.lastLocation = LatLng(lastLat, lastLon);
            if (lastSeenStr != null) {
              try {
                acc.datePublished = DateTime.parse(lastSeenStr).toLocal();
              } catch (_) {}
            }
            acc.lastBatteryStatus = _parseBattery(lastBattery);
          }

          syncedAccessories.add(acc);
          updated = true;
        }

        if (updated && syncedAccessories.isNotEmpty) {
          _accessories = syncedAccessories;
          _storeAccessories();
          notifyListeners();
        }
      }
    } catch (e) {
      logger.e('Failed to sync devices from backend server: $e');
    }
  }

  /// Triggers an immediate Apple FindMy sync + decrypt on the backend.
  /// Used by the Refresh button. Returns a [SyncResult] summary.
  Future<SyncResult> triggerImmediateSync() async {
    try {
      final token =
          Settings.getValue<String>(endpointUser, defaultValue: '')!;
      if (token.trim().isEmpty) {
        return SyncResult(newReports: 0, decrypted: 0, updatedDevices: []);
      }

      final res = await http.post(
        Uri.parse('$_baseUrl/api/sync/now'),
        headers: _authHeaders,
      );

      if (res.statusCode == 401) {
        onUnauthorized?.call();
        return SyncResult(newReports: 0, decrypted: 0, updatedDevices: []);
      }

      SyncResult result = SyncResult(newReports: 0, decrypted: 0, updatedDevices: []);
      if (res.statusCode == 200) {
        result = SyncResult.fromJson(jsonDecode(res.body));
      }

      // Reload latest locations from backend after sync
      await syncWithBackendServer();
      return result;
    } catch (e) {
      logger.e('Failed to trigger immediate sync: $e');
      return SyncResult(newReports: 0, decrypted: 0, updatedDevices: []);
    }
  }

  /// Fetches the decrypted location history for a specific accessory from the backend.
  /// [fromTs] and [toTs] are unix millisecond timestamps.
  /// Pass [fromTs] = 0 for "all time".
  Future<List<LocationHistoryEntry>> loadDeviceHistory(
    String hashedPublicKey, {
    int? fromTs,
    int? toTs,
    int? days,
  }) async {
    try {
      // Find the device ID by key
      final devRes = await http.get(
        Uri.parse('$_baseUrl/api/devices'),
        headers: _authHeaders,
      );
      if (devRes.statusCode != 200) return [];

      List data = jsonDecode(devRes.body);
      var deviceItem = data.firstWhere(
        (d) => d['hashed_adv_key'] == hashedPublicKey,
        orElse: () => null,
      );
      if (deviceItem == null) return [];

      int deviceId = deviceItem['id'];

      // Build query string
      String queryStr = '';
      if (days != null) {
        queryStr = '?days=$days';
      } else if (fromTs != null) {
        queryStr = '?from_ts=$fromTs';
        if (toTs != null) queryStr += '&to_ts=$toTs';
      }

      final histRes = await http.get(
        Uri.parse('$_baseUrl/api/devices/$deviceId/locations$queryStr'),
        headers: _authHeaders,
      );

      if (histRes.statusCode != 200) return [];

      Map<String, dynamic> body = jsonDecode(histRes.body);
      List items = body['items'] ?? [];
      return items
          .map((e) => LocationHistoryEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      logger.e('Failed to load device history: $e');
      return [];
    }
  }

  // ── Device management ───────────────────────────────────────────────────────

  void addAccessory(Accessory accessory) {
    Accessory? foundOne;
    for (var acc in _accessories) {
      if (accessory.hashedPublicKey == acc.hashedPublicKey) {
        foundOne = acc;
        break;
      }
    }
    if (foundOne != null) {
      _accessories.remove(foundOne);
    }

    _accessories.add(accessory);
    _storeAccessories();
    _saveDeviceToBackend(accessory);
    notifyListeners();
  }

  void removeAccessory(Accessory accessory) {
    _accessories.remove(accessory);
    accessory.getHashedPublicKey().then((publicKey) {
      _storage.delete(key: publicKey);
    });

    _storeAccessories();
    _deleteDeviceFromBackend(accessory);
    notifyListeners();
  }

  void editAccessory(Accessory oldAccessory, Accessory newAccessory) {
    oldAccessory.update(newAccessory);
    _storeAccessories();
    _saveDeviceToBackend(oldAccessory);
    notifyListeners();
  }

  void deleteData(Accessory accessory) {
    accessory.lastBatteryStatus = null;
    accessory.lastLocation = null;
    accessory.hashesWithTS.clear();
    accessory.datePublished = DateTime(1970);
    accessory.place = Future.value(null);
    accessory.locationHistory.clear();
    _storeAccessories();
    notifyListeners();
  }

  void saveOrderUpdates(List<Accessory> newOrder) {
    final Map<Accessory, int> positionMap = {
      for (int i = 0; i < newOrder.length; i++) newOrder[i]: i,
    };
    _accessories.sort((a, b) => positionMap[a]!.compareTo(positionMap[b]!));
    _storeAccessories();
  }

  // ── Private helpers ─────────────────────────────────────────────────────────

  Future<void> _storeAccessories() async {
    try {
      List<Map<String, dynamic>> jsonList = _accessories.map((a) {
        try {
          return a.toJson();
        } catch (e) {
          logger.e('Error serializing accessory ${a.name}: $e');
          return {
            'id': a.id.isNotEmpty ? a.id : a.hashedPublicKey,
            'name': a.name,
            'hashedPublicKey': a.hashedPublicKey,
          };
        }
      }).toList();
      String jsonStr = jsonEncode(jsonList);
      try {
        html.window.localStorage['HAYSTACK_ACCESSORIES'] = jsonStr;
        html.window.localStorage['ACCESSORIES_BACKUP'] = jsonStr;
      } catch (_) {}
      try {
        await _storage.write(key: accessoryStorageKey, value: jsonStr);
      } catch (_) {}
    } catch (e) {
      logger.e('Failed to store accessories: $e');
    }
  }

  Future<void> _saveDeviceToBackend(Accessory accessory) async {
    try {
      final token =
          Settings.getValue<String>(endpointUser, defaultValue: '')!;
      if (token.trim().isEmpty) return;

      String privateKey = '';
      try {
        privateKey = await accessory.getPrivateKey();
      } catch (_) {}

      final accJson = accessory.toJson();
      if (privateKey.isNotEmpty) {
        accJson['privateKey'] = privateKey;
      }

      final body = jsonEncode({
        'name': accessory.name,
        'hashed_adv_key': accessory.hashedPublicKey,
        'private_key_b64': jsonEncode(accJson),
      });

      await http.post(
        Uri.parse('$_baseUrl/api/devices'),
        headers: _authHeaders,
        body: body,
      );
    } catch (e) {
      logger.e('Failed to push device to backend: $e');
    }
  }

  Future<void> _deleteDeviceFromBackend(Accessory accessory) async {
    try {
      final token =
          Settings.getValue<String>(endpointUser, defaultValue: '')!;
      if (token.trim().isEmpty) return;

      final res = await http.get(
        Uri.parse('$_baseUrl/api/devices'),
        headers: _authHeaders,
      );

      if (res.statusCode == 200) {
        List data = jsonDecode(res.body);
        for (var item in data) {
          if (item['hashed_adv_key'] == accessory.hashedPublicKey) {
            int devId = item['id'];
            await http.delete(
              Uri.parse('$_baseUrl/api/devices/$devId'),
              headers: _authHeaders,
            );
            break;
          }
        }
      }
    } catch (e) {
      logger.e('Failed to delete device from backend: $e');
    }
  }

  // ── Battery status helper ───────────────────────────────────────────────────
  static AccessoryBatteryStatus? _parseBattery(String? val) {
    if (val == null) return null;
    try {
      return AccessoryBatteryStatus.values.byName(val);
    } catch (_) {}
    return null;
  }
}
