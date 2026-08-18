import 'package:latlong2/latlong.dart';

class ZoneDeviceItem {
  final int deviceId;
  final String deviceName;
  final String hashedAdvKey;
  final String lastStatus; // INSIDE, OUTSIDE, UNKNOWN
  final double? lastDistance;
  final DateTime? lastAlertTime;
  final String? lastAlertType;

  ZoneDeviceItem({
    required this.deviceId,
    required this.deviceName,
    required this.hashedAdvKey,
    this.lastStatus = 'UNKNOWN',
    this.lastDistance,
    this.lastAlertTime,
    this.lastAlertType,
  });

  factory ZoneDeviceItem.fromJson(Map<String, dynamic> json) {
    return ZoneDeviceItem(
      deviceId: json['device_id'] as int? ?? 0,
      deviceName: json['device_name'] as String? ?? '',
      hashedAdvKey: json['hashed_adv_key'] as String? ?? '',
      lastStatus: json['last_status'] as String? ?? 'UNKNOWN',
      lastDistance: (json['last_distance'] as num?)?.toDouble(),
      lastAlertTime: json['last_alert_time'] != null
          ? DateTime.tryParse(json['last_alert_time'].toString())?.toLocal()
          : null,
      lastAlertType: json['last_alert_type'] as String?,
    );
  }
}

class ZoneItem {
  final int id;
  final int userId;
  final String name;
  final double latitude;
  final double longitude;
  final double radius;
  final String shapeType; // circle, polygon
  final List<LatLng> polygonPoints;
  final bool alertOnExit;
  final bool alertOnEnter;
  final int cooldownMinutes;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final List<ZoneDeviceItem> devices;

  ZoneItem({
    required this.id,
    required this.userId,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.radius,
    this.shapeType = 'circle',
    this.polygonPoints = const [],
    this.alertOnExit = true,
    this.alertOnEnter = false,
    this.cooldownMinutes = 15,
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
    this.devices = const [],
  });

  LatLng get center => LatLng(latitude, longitude);

  factory ZoneItem.fromJson(Map<String, dynamic> json) {
    var devList = <ZoneDeviceItem>[];
    if (json['devices'] is List) {
      devList = (json['devices'] as List)
          .map((d) => ZoneDeviceItem.fromJson(d as Map<String, dynamic>))
          .toList();
    }

    var polyPts = <LatLng>[];
    if (json['polygon_points'] is List) {
      polyPts = (json['polygon_points'] as List)
          .map((p) => LatLng(
                (p['lat'] as num?)?.toDouble() ?? (p['latitude'] as num?)?.toDouble() ?? 0.0,
                (p['lon'] as num?)?.toDouble() ?? (p['longitude'] as num?)?.toDouble() ?? 0.0,
              ))
          .toList();
    }

    return ZoneItem(
      id: json['id'] as int? ?? 0,
      userId: json['user_id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
      radius: (json['radius'] as num?)?.toDouble() ?? 100.0,
      shapeType: json['shape_type'] as String? ?? 'circle',
      polygonPoints: polyPts,
      alertOnExit: json['alert_on_exit'] as bool? ?? true,
      alertOnEnter: json['alert_on_enter'] as bool? ?? false,
      cooldownMinutes: json['cooldown_minutes'] as int? ?? 15,
      isActive: json['is_active'] as bool? ?? true,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())?.toLocal()
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString())?.toLocal()
          : null,
      devices: devList,
    );
  }
}

class ZoneAlertItem {
  final int id;
  final int zoneId;
  final String zoneName;
  final int deviceId;
  final String deviceName;
  final String alertType; // EXIT, ENTER
  final double latitude;
  final double longitude;
  final double distance;
  final DateTime createdAt;

  ZoneAlertItem({
    required this.id,
    required this.zoneId,
    required this.zoneName,
    required this.deviceId,
    required this.deviceName,
    required this.alertType,
    required this.latitude,
    required this.longitude,
    required this.distance,
    required this.createdAt,
  });

  factory ZoneAlertItem.fromJson(Map<String, dynamic> json) {
    return ZoneAlertItem(
      id: json['id'] as int? ?? 0,
      zoneId: json['zone_id'] as int? ?? 0,
      zoneName: json['zone_name'] as String? ?? 'Khu vực đã xóa',
      deviceId: json['device_id'] as int? ?? 0,
      deviceName: json['device_name'] as String? ?? 'Thẻ đã xóa',
      alertType: json['alert_type'] as String? ?? 'EXIT',
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
      distance: (json['distance'] as num?)?.toDouble() ?? 0.0,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())?.toLocal() ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
