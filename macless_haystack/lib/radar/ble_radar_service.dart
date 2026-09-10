import 'package:flutter/material.dart';

export 'ble_radar_service_stub.dart'
    if (dart.library.io) 'ble_radar_service_io.dart';

/// Represents a live BLE beacon detection event for a FindMy tag.
class RadarScanResult {
  final int rssi;
  final int? statusByte;
  final DateTime timestamp;
  final String? deviceMac;

  RadarScanResult({
    required this.rssi,
    this.statusByte,
    required this.timestamp,
    this.deviceMac,
  });

  /// Approximate signal strength percentage from 0% to 100%.
  /// -100 dBm is considered 0% (edge of detection), -35 dBm is 100% (right on top).
  double get signalPercentage {
    if (rssi <= -100) return 5.0;
    if (rssi >= -35) return 100.0;
    return ((rssi + 100) / 65.0 * 100.0).clamp(5.0, 100.0);
  }

  /// Human-readable proximity estimate based on RSSI.
  String get proximityLabel {
    if (rssi >= -50) {
      return 'Rất gần (dưới 1 mét)';
    } else if (rssi >= -65) {
      return 'Đang ở gần (1 - 3 mét)';
    } else if (rssi >= -80) {
      return 'Đang đến gần (3 - 7 mét)';
    } else if (rssi >= -90) {
      return 'Ở xa (7 - 15 mét)';
    } else {
      return 'Tín hiệu rất yếu (> 15 mét)';
    }
  }

  /// Color corresponding to proximity level.
  Color get proximityColor {
    if (rssi >= -50) {
      return Colors.greenAccent.shade700;
    } else if (rssi >= -65) {
      return Colors.lightGreen;
    } else if (rssi >= -80) {
      return Colors.amber;
    } else if (rssi >= -90) {
      return Colors.orangeAccent;
    } else {
      return Colors.redAccent;
    }
  }

  /// Hardware battery status decoded from Apple status byte (if present).
  String? get hardwareBatteryStatus {
    if (statusByte == null) return null;
    final int battBits = (statusByte! >> 6) & 0x03;
    switch (battBits) {
      case 0:
        return 'Đầy pin (Full)';
      case 1:
        return 'Pin trung bình (Medium)';
      case 2:
        return 'Pin yếu (Low)';
      case 3:
        return 'Pin rất yếu (Critical)';
      default:
        return '0x${statusByte!.toRadixString(16).padLeft(2, '0').toUpperCase()}';
    }
  }

  /// Whether the tag is separated from owner based on status byte bit 2.
  bool? get isSeparated {
    if (statusByte == null) return null;
    return (statusByte! & 0x04) != 0;
  }
}
