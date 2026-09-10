import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:logger/logger.dart';

import '../accessory/accessory_model.dart';
import '../findMy/find_my_controller.dart';
import 'ble_radar_service.dart';

/// Full Bluetooth Low Energy Radar Service for mobile and IO platforms.
class BleRadarService {
  static final Logger _logger = Logger(printer: PrettyPrinter(methodCount: 0));

  static bool get isSupported =>
      Platform.isAndroid || Platform.isIOS || Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  final Accessory accessory;
  final StreamController<RadarScanResult> _scanController =
      StreamController<RadarScanResult>.broadcast();

  StreamSubscription? _scanSubscription;
  bool _isScanning = false;
  final List<Uint8List> _targetAdvKeys = [];
  bool _keysLoaded = false;

  BleRadarService({required this.accessory});

  Stream<RadarScanResult> get scanStream => _scanController.stream;

  bool get isScanning => _isScanning;

  /// Loads the 28-byte advertisement key(s) for the accessory.
  Future<void> _loadKeys() async {
    if (_keysLoaded) return;
    _targetAdvKeys.clear();

    try {
      if (accessory.hashedPublicKey.isNotEmpty) {
        final keyPair =
            await FindMyController.getKeyPair(accessory.hashedPublicKey);
        final advKeyB64 = keyPair.getBase64AdvertisementKey();
        _targetAdvKeys.add(base64Decode(advKeyB64));
      }
    } catch (e) {
      _logger.w('Không thể tải khóa chính từ storage: $e');
    }

    // Load additional keys if available
    for (final addKey in accessory.additionalKeys) {
      try {
        if (addKey.isNotEmpty) {
          final kp = await FindMyController.importKeyPair(addKey);
          _targetAdvKeys.add(base64Decode(kp.getBase64AdvertisementKey()));
        }
      } catch (_) {}
    }

    _keysLoaded = true;
    _logger.i('BleRadar: Đã tải ${_targetAdvKeys.length} khóa mục tiêu cho "${accessory.name}"');
  }

  /// Starts scanning for nearby BLE advertisements matching this tag.
  Future<bool> startScanning() async {
    if (!isSupported) {
      _logger.w('BleRadar: Nền tảng không hỗ trợ BLE');
      return false;
    }

    try {
      await _loadKeys();
      if (_targetAdvKeys.isEmpty) {
        _logger.e('BleRadar: Không có khóa quảng bá nào cho tag này.');
        return false;
      }

      // Check Bluetooth adapter state
      if (!await FlutterBluePlus.isSupported) {
        _logger.e('BleRadar: Thiết bị không hỗ trợ Bluetooth');
        return false;
      }

      final adapterState = await FlutterBluePlus.adapterState.first;
      if (adapterState != BluetoothAdapterState.on) {
        if (Platform.isAndroid) {
          try {
            await FlutterBluePlus.turnOn();
          } catch (e) {
            _logger.w('Không thể tự động bật Bluetooth: $e');
          }
        }
      }

      _isScanning = true;

      // Cancel previous subscription if any
      await _scanSubscription?.cancel();

      _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        for (final r in results) {
          _processScanResult(r);
        }
      }, onError: (err) {
        _logger.e('BleRadar scan error: $err');
      });

      // Start BLE scan with fine location enabled on Android
      await FlutterBluePlus.startScan(
        timeout: const Duration(minutes: 15),
        androidUsesFineLocation: true,
      );

      return true;
    } catch (e) {
      _logger.e('BleRadar: Lỗi khởi động quét: $e');
      _isScanning = false;
      return false;
    }
  }

  /// Checks whether an incoming BLE advertisement matches our target keys.
  void _processScanResult(ScanResult r) {
    final mData = r.advertisementData.manufacturerData;
    // Apple Company ID is 0x004C (76 in decimal)
    final appleBytes = mData[0x004C] ?? mData[76];
    if (appleBytes == null || appleBytes.length < 3) return;

    // Offline Finding Type is 0x12
    if (appleBytes[0] != 0x12) return;

    final int ofLength = appleBytes[1];
    int? detectedStatus;
    bool isMatch = false;

    // Mode A: Separated state (Payload length 0x19 = 25 bytes)
    // Structure: [0x12, 0x19, statusByte, keyBytes(22), hint]
    if (ofLength == 0x19 && appleBytes.length >= 25) {
      detectedStatus = appleBytes[2];
      final pubKeyEnd = appleBytes.sublist(3, 25); // 22 bytes

      for (final targetKey in _targetAdvKeys) {
        if (targetKey.length >= 28) {
          final targetEnd = targetKey.sublist(6, 28); // 22 bytes
          if (_listEquals(pubKeyEnd, targetEnd)) {
            isMatch = true;
            break;
          }
        }
      }
    }
    // Mode B: Nearby state (Payload length 0x02 = 2 bytes)
    else if (ofLength == 0x02 && appleBytes.length >= 4) {
      detectedStatus = appleBytes[2];
      final macStr = r.device.remoteId.str.replaceAll(':', '').replaceAll('-', '');
      if (macStr.length >= 12) {
        try {
          final macBytes = Uint8List.fromList(List.generate(
              6, (i) => int.parse(macStr.substring(i * 2, i * 2 + 2), radix: 16)));
          final pubKeyStartMs = (appleBytes[3] << 6) & 0xC0;
          final pubKeyStartLs = macBytes[0] & 0x3F;
          final firstByte = pubKeyStartMs | pubKeyStartLs;
          final partialMatch = Uint8List.fromList([firstByte, ...macBytes.sublist(1)]);

          for (final targetKey in _targetAdvKeys) {
            if (targetKey.length >= 6 && _listEquals(partialMatch, targetKey.sublist(0, 6))) {
              isMatch = true;
              break;
            }
          }
        } catch (_) {}
      }
    }

    if (isMatch) {
      final scanResult = RadarScanResult(
        rssi: r.rssi,
        statusByte: detectedStatus,
        timestamp: DateTime.now(),
        deviceMac: r.device.remoteId.str,
      );

      if (!_scanController.isClosed) {
        _scanController.add(scanResult);
      }
    }
  }

  bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Stops BLE scanning.
  Future<void> stopScanning() async {
    _isScanning = false;
    try {
      await _scanSubscription?.cancel();
      _scanSubscription = null;
      if (await FlutterBluePlus.isScanning.first) {
        await FlutterBluePlus.stopScan();
      }
    } catch (_) {}
  }

  void dispose() {
    stopScanning();
    _scanController.close();
  }
}
