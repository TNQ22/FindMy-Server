import 'dart:async';
import '../accessory/accessory_model.dart';
import 'ble_radar_service.dart';

/// Stub implementation of BleRadarService for Web and unsupported platforms.
class BleRadarService {
  static bool get isSupported => false;

  final Accessory accessory;
  BleRadarService({required this.accessory});

  Stream<RadarScanResult> get scanStream => const Stream.empty();

  bool get isScanning => false;

  Future<bool> startScanning() async {
    return false;
  }

  Future<void> stopScanning() async {}

  void dispose() {}
}
