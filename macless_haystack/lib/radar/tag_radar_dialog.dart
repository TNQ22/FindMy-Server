import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../accessory/accessory_icon_model.dart';
import '../accessory/accessory_model.dart';
import '../preferences/app_download_dialog.dart';
import 'ble_radar_service.dart';
import 'radar_vibrator.dart';

/// Interactive Radar Proximity Dialog for finding a FindMy tag using BLE RSSI.
class TagRadarDialog extends StatefulWidget {
  final Accessory accessory;

  const TagRadarDialog({
    super.key,
    required this.accessory,
  });

  @override
  State<TagRadarDialog> createState() => _TagRadarDialogState();
}

class _TagRadarDialogState extends State<TagRadarDialog>
    with SingleTickerProviderStateMixin {
  late final BleRadarService _radarService;
  StreamSubscription<RadarScanResult>? _subscription;
  late AnimationController _radarAnimController;

  RadarScanResult? _latestResult;
  double? _smoothedRssi;
  DateTime? _lastPacketTime;
  bool _isSignalLost = false;
  bool _hasDiscoveredOnce = false;
  DateTime? _discoveryAlertUntil;

  bool _isScanning = false;
  bool _hapticEnabled = true;
  String _statusMessage = 'Sẵn sàng quét sóng...';

  Timer? _freshnessTimer;
  Timer? _hapticTimer;

  @override
  void initState() {
    super.initState();
    _radarService = BleRadarService(accessory: widget.accessory);

    _radarAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );

    if (BleRadarService.isSupported) {
      _startRadar();
    } else {
      _statusMessage =
          'Rada Bluetooth yêu cầu truy cập phần cứng di động (ứng dụng Android .apk).';
    }
  }

  @override
  void dispose() {
    _stopAllHaptics();
    _freshnessTimer?.cancel();
    _subscription?.cancel();
    _radarAnimController.dispose();
    _radarService.dispose();
    try {
      WakelockPlus.disable();
    } catch (_) {}
    super.dispose();
  }

  /// Distance tier helper for haptic scheduling and display.
  /// 0: < 1m (dưới 1 mét)
  /// 1: 1 - 3m
  /// 2: 3 - 7m
  /// 3: > 7m
  int _getDistanceTier(double? rssi) {
    if (rssi == null) return -1;
    if (rssi >= -52) return 0;
    if (rssi >= -65) return 1;
    if (rssi >= -80) return 2;
    return 3;
  }

  /// Current smoothed or raw RSSI integer.
  int? get _currentRssi => _smoothedRssi?.round() ?? _latestResult?.rssi;

  /// Approximate signal strength percentage from 0% to 100%.
  double get _signalPercentage {
    if (_isSignalLost || _currentRssi == null) return 0.0;
    final r = _currentRssi!;
    if (r <= -100) return 5.0;
    if (r >= -35) return 100.0;
    return ((r + 100) / 65.0 * 100.0).clamp(5.0, 100.0);
  }

  /// Human-readable proximity label reflecting distance bands.
  String get _proximityLabel {
    if (_isSignalLost) return 'Mất tín hiệu (Ngoài vùng quét)';
    final r = _currentRssi;
    if (r == null) return 'Đang dò tìm...';
    if (r >= -52) {
      return 'Rất gần (dưới 1 mét)';
    } else if (r >= -65) {
      return 'Đang ở gần (1 - 3 mét)';
    } else if (r >= -80) {
      return 'Đang đến gần (3 - 7 mét)';
    } else if (r >= -90) {
      return 'Ở xa (7 - 15 mét)';
    } else {
      return 'Tín hiệu rất yếu (> 15 mét)';
    }
  }

  /// Color corresponding to proximity level.
  Color get _proximityColor {
    if (_isSignalLost) return Colors.orange;
    final r = _currentRssi;
    if (r == null) return widget.accessory.color;
    if (r >= -52) {
      return Colors.greenAccent.shade700;
    } else if (r >= -65) {
      return Colors.lightGreen;
    } else if (r >= -80) {
      return Colors.amber;
    } else if (r >= -90) {
      return Colors.orangeAccent;
    } else {
      return Colors.redAccent;
    }
  }

  void _cancelHapticTimer() {
    _hapticTimer?.cancel();
    _hapticTimer = null;
  }

  void _stopAllHaptics() {
    _cancelHapticTimer();
    RadarVibrator.cancel();
  }

  /// Schedules smooth periodic hardware vibration pulses based on current distance:
  /// - Under 1m (RSSI >= -52): continuous rapid pulses (260ms vib, 80ms rest -> 340ms total)
  /// - 1 - 3m (-65 <= RSSI < -52): rhythmic pulse (180ms vib, 520ms rest -> 700ms total)
  /// - 3 - 7m (-80 <= RSSI < -65): sparse long pulse (120ms vib, 1480ms rest -> 1600ms total)
  /// - > 7m or signal lost: stopped
  void _scheduleNextHapticPulse() {
    _cancelHapticTimer();

    if (!_hapticEnabled || !_isScanning || _isSignalLost || _smoothedRssi == null) {
      return;
    }

    final isAlerting = _discoveryAlertUntil != null &&
        DateTime.now().isBefore(_discoveryAlertUntil!);
    if (isAlerting) return;

    final double rssi = _smoothedRssi!;
    if (rssi < -80) {
      // Out of range (> 7m) -> silent
      return;
    }

    final Duration delay;
    final int vibDuration;

    if (rssi >= -52) {
      // Dưới 1 mét: Rung liên tục / nhịp dồn dập (260ms motor pulse, 80ms rest)
      delay = const Duration(milliseconds: 340);
      vibDuration = 260;
    } else if (rssi >= -65) {
      // 1 - 3 mét: Rung nhịp đều đặn (180ms heartbeat pulse, 520ms rest)
      delay = const Duration(milliseconds: 700);
      vibDuration = 180;
    } else {
      // 3 - 7 mét: Xung ngắt quãng lâu hơn để dễ phân biệt (120ms pulse, 1480ms rest)
      delay = const Duration(milliseconds: 1600);
      vibDuration = 120;
    }

    // Trigger hardware vibration without premature cancellation
    RadarVibrator.vibrate(vibDuration);

    // Schedule next cycle
    _hapticTimer = Timer(delay, () {
      if (!mounted || !_hapticEnabled || !_isScanning || _isSignalLost) {
        return;
      }
      _scheduleNextHapticPulse();
    });
  }

  /// Ticker running every 1 second to detect signal drop and refresh freshness.
  void _startFreshnessTimer() {
    _freshnessTimer?.cancel();
    _freshnessTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || !_isScanning) return;

      if (_lastPacketTime != null) {
        final secondsAgo =
            DateTime.now().difference(_lastPacketTime!).inSeconds;

        // Tolerant timeout: BLE tags often broadcast every 3 to 8 seconds.
        // Wait 16s before declaring lost to tolerate dropped packets.
        if (secondsAgo >= 16) {
          if (!_isSignalLost) {
            setState(() {
              _isSignalLost = true;
              _statusMessage = 'Mất tín hiệu (Ngoài vùng quét)...';
            });
            _stopAllHaptics();
            // Automatically kick the BLE scanner to wake up hardware
            _radarService.restartScanning();
          } else {
            setState(() {});
          }
        } else {
          // Still active or in waiting window, refresh UI seconds counter
          setState(() {});
        }
      }
    });
  }

  Future<void> _startRadar() async {
    try {
      await WakelockPlus.enable();
    } catch (_) {}

    setState(() {
      _isScanning = true;
      _isSignalLost = false;
      _hasDiscoveredOnce = false;
      _discoveryAlertUntil = null;
      _statusMessage = 'Đang dò sóng Bluetooth của tag...';
    });

    _radarAnimController.repeat();
    _startFreshnessTimer();

    _subscription?.cancel();
    _subscription = _radarService.scanStream.listen((result) {
      if (!mounted) return;

      final now = DateTime.now();
      _lastPacketTime = now;

      final wasLost = _isSignalLost;
      final isFirstDiscovery = !_hasDiscoveredOnce || wasLost;
      _hasDiscoveredOnce = true;
      _isSignalLost = false;

      final oldTier = _getDistanceTier(_smoothedRssi);

      if (wasLost || _smoothedRssi == null) {
        _smoothedRssi = result.rssi.toDouble();
      } else {
        // Exponential moving average (EMA) to prevent RSSI jitter
        _smoothedRssi = (_smoothedRssi! * 0.6) + (result.rssi * 0.4);
      }

      setState(() {
        _latestResult = result;
        _statusMessage = 'Đã bắt được tín hiệu!';
      });

      if (_hapticEnabled) {
        if (isFirstDiscovery) {
          // Discovery alert requested: 1s long vibration followed by 3 rapid beats
          _cancelHapticTimer();
          RadarVibrator.vibrateDiscovery();
          _discoveryAlertUntil =
              DateTime.now().add(const Duration(milliseconds: 1800));

          // After discovery alert finishes, resume distance-based continuous/rhythmic loop
          _hapticTimer = Timer(const Duration(milliseconds: 1850), () {
            if (mounted && _hapticEnabled && _isScanning && !_isSignalLost) {
              _scheduleNextHapticPulse();
            }
          });
        } else {
          final isAlerting = _discoveryAlertUntil != null &&
              DateTime.now().isBefore(_discoveryAlertUntil!);
          if (!isAlerting) {
            final newTier = _getDistanceTier(_smoothedRssi);
            if (_hapticTimer == null || oldTier != newTier) {
              _scheduleNextHapticPulse();
            }
          }
        }
      }
    });

    final success = await _radarService.startScanning();
    if (!success && mounted) {
      try {
        await WakelockPlus.disable();
      } catch (_) {}
      setState(() {
        _isScanning = false;
        _statusMessage =
            'Không thể khởi động Bluetooth. Vui lòng kiểm tra quyền và bật Bluetooth trên máy.';
      });
      _radarAnimController.stop();
      _stopAllHaptics();
      _freshnessTimer?.cancel();
    }
  }

  Future<void> _stopRadar() async {
    await _radarService.stopScanning();
    _stopAllHaptics();
    _freshnessTimer?.cancel();
    _freshnessTimer = null;
    try {
      await WakelockPlus.disable();
    } catch (_) {}
    if (mounted) {
      setState(() {
        _isScanning = false;
        _statusMessage = 'Đã dừng dò sóng.';
      });
      _radarAnimController.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tagColor = widget.accessory.color;
    final iconData = widget.accessory.icon;

    final secondsAgo = _lastPacketTime != null
        ? DateTime.now().difference(_lastPacketTime!).inSeconds
        : null;

    final activeColor = _isSignalLost ? Colors.orange : _proximityColor;

    return Dialog(
      backgroundColor: isDark ? const Color(0xFF1E1E2C) : Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 720),
        child: Column(
          children: [
            // ─── Header ──────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: isDark ? Colors.white12 : Colors.black12,
                  ),
                ),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: tagColor.withValues(alpha: 0.2),
                    child: Icon(iconData, color: tagColor, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.accessory.name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'Rada Dò Sóng Lân Cận',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // ─── Main Content ─────────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    if (!BleRadarService.isSupported) ...[
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.amber.shade700),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Icon(Icons.info_outline, color: Colors.amber.shade800),
                                const SizedBox(width: 12),
                                const Expanded(
                                  child: Text(
                                    'Tính năng quét sóng Bluetooth lân cận cần truy cập chip Bluetooth phần cứng, hiện chỉ hoạt động trên ứng dụng Android (.apk). Trình duyệt Web không có quyền quét sóng nền.',
                                    style: TextStyle(fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.teal.shade700,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10)),
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 10, horizontal: 16),
                                ),
                                icon: const Icon(Icons.android,
                                    size: 19, color: Colors.greenAccent),
                                label: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'Tải ứng dụng Android (APK)',
                                      style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold),
                                    ),
                                    SizedBox(width: 8),
                                    Icon(Icons.qr_code,
                                        size: 16, color: Colors.tealAccent),
                                  ],
                                ),
                                onPressed: () =>
                                    AppDownloadDialog.show(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],

                    // ── Animated Radar Waves Circle ──────────────────────
                    SizedBox(
                      height: 240,
                      width: 240,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Radar Waves Painter
                          AnimatedBuilder(
                            animation: _radarAnimController,
                            builder: (context, child) {
                              return CustomPaint(
                                size: const Size(240, 240),
                                painter: _RadarWavePainter(
                                  animationValue: _radarAnimController.value,
                                  isScanning: _isScanning,
                                  signalPercent: _signalPercentage,
                                  radarColor: activeColor,
                                  isSignalLost: _isSignalLost,
                                ),
                              );
                            },
                          ),

                          // Center Tag Circle
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _isSignalLost
                                  ? (isDark
                                      ? Colors.grey.shade800
                                      : Colors.grey.shade400)
                                  : tagColor,
                              boxShadow: [
                                BoxShadow(
                                  color: (_isSignalLost
                                          ? Colors.orange.withValues(alpha: 0.25)
                                          : activeColor.withValues(alpha: 0.4)),
                                  blurRadius: _isSignalLost ? 8 : 18,
                                  spreadRadius: _isSignalLost ? 1 : 4,
                                ),
                              ],
                            ),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Icon(
                                  iconData,
                                  color: _isSignalLost
                                      ? Colors.white70
                                      : Colors.white,
                                  size: 40,
                                ),
                                if (_isSignalLost)
                                  Positioned(
                                    bottom: 12,
                                    right: 12,
                                    child: Container(
                                      padding: const EdgeInsets.all(3),
                                      decoration: const BoxDecoration(
                                        color: Colors.deepOrange,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.warning_amber_rounded,
                                        size: 14,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ── Signal Gauge / RSSI Value ─────────────────────────
                    if (_latestResult != null && !_isSignalLost) ...[
                      // Active live signal state
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.sensors,
                            color: activeColor,
                            size: 24,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${_currentRssi} dBm',
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                              color: activeColor,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: activeColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: activeColor),
                            ),
                            child: Text(
                              '${_signalPercentage.round()}%',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: activeColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _proximityLabel,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: activeColor,
                        ),
                      ),
                      const SizedBox(height: 6),
                      // Freshness indicator
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: secondsAgo != null && secondsAgo <= 5
                                  ? Colors.greenAccent
                                  : Colors.amberAccent,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            secondsAgo == null || secondsAgo <= 1
                                ? 'Tín hiệu thời gian thực'
                                : secondsAgo <= 5
                                    ? 'Cập nhật ${secondsAgo}s trước'
                                    : 'Đang đợi gói tin mới (${secondsAgo}s)...',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white60 : Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ] else if (_latestResult != null && _isSignalLost) ...[
                      // Lost signal state (clearly communicates out-of-range)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.sensors_off,
                            color: Colors.orangeAccent,
                            size: 24,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            '-- dBm',
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.orangeAccent),
                            ),
                            child: const Text(
                              'Mất sóng',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Colors.orangeAccent,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Mất tín hiệu (Ngoài vùng quét)',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.orangeAccent,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        secondsAgo != null
                            ? 'Lần cuối bắt được: ${secondsAgo}s trước (${_latestResult!.rssi} dBm)'
                            : 'Không nhận được gói tin mới từ tag',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                      ),
                    ] else ...[
                      Text(
                        _statusMessage,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark ? Colors.white70 : Colors.black87,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],

                    const SizedBox(height: 20),

                    // ── Details Box (Battery, MAC, Mode) ──────────────────
                    if (_latestResult != null) ...[
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.05)
                              : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          children: [
                            // Status row
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Row(
                                    children: [
                                      Icon(Icons.wifi_tethering,
                                          size: 18, color: Colors.teal),
                                      SizedBox(width: 8),
                                      Text('Trạng thái kết nối:',
                                          style: TextStyle(fontSize: 13)),
                                    ],
                                  ),
                                  Text(
                                    _isSignalLost
                                        ? 'Mất sóng (Đang tìm lại...)'
                                        : 'Đang kết nối trực tiếp',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: _isSignalLost
                                          ? Colors.orangeAccent
                                          : Colors.greenAccent.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (_latestResult!.hardwareBatteryStatus != null)
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 4),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Row(
                                      children: [
                                        Icon(Icons.battery_charging_full,
                                            size: 18, color: Colors.teal),
                                        SizedBox(width: 8),
                                        Text('Pin phần cứng:',
                                            style: TextStyle(fontSize: 13)),
                                      ],
                                    ),
                                    Text(
                                      _latestResult!.hardwareBatteryStatus!,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            if (_latestResult!.deviceMac != null)
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 4),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Row(
                                      children: [
                                        Icon(Icons.bluetooth,
                                            size: 18, color: Colors.blue),
                                        SizedBox(width: 8),
                                        Text('Địa chỉ BLE:',
                                            style: TextStyle(fontSize: 13)),
                                      ],
                                    ),
                                    Text(
                                      _latestResult!.deviceMac!,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontFamily: 'monospace',
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // ─── Sticky Footer Controls ───────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF262638) : Colors.grey.shade50,
                border: Border(
                  top: BorderSide(
                    color: isDark ? Colors.white12 : Colors.black12,
                  ),
                ),
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(24),
                ),
              ),
              child: Row(
                children: [
                  // Haptic feedback toggle (clean and compact: icon + 'Rung')
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      setState(() {
                        _hapticEnabled = !_hapticEnabled;
                      });
                      if (!_hapticEnabled) {
                        _stopAllHaptics();
                      } else {
                        _scheduleNextHapticPulse();
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _hapticEnabled
                                ? Icons.vibration
                                : Icons.phonelink_erase,
                            size: 20,
                            color: _hapticEnabled
                                ? Colors.tealAccent.shade400
                                : Colors.grey,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Rung',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: _hapticEnabled
                                  ? (isDark ? Colors.white : Colors.black)
                                  : Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const Spacer(),

                  // Quick Refresh Button (Làm mới Bluetooth nếu đơ)
                  if (_isScanning) ...[
                    IconButton(
                      tooltip: 'Làm mới bộ quét Bluetooth',
                      icon: const Icon(Icons.refresh, size: 22),
                      onPressed: () async {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Đang làm mới bộ quét Bluetooth...'),
                            duration: Duration(seconds: 1),
                          ),
                        );
                        await _radarService.restartScanning();
                      },
                    ),
                    const SizedBox(width: 6),
                  ],

                  // Scan / Stop button
                  ElevatedButton.icon(
                    onPressed: BleRadarService.isSupported
                        ? () {
                            if (_isScanning) {
                              _stopRadar();
                            } else {
                              _startRadar();
                            }
                          }
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isScanning
                          ? Colors.red.shade700
                          : Colors.teal.shade700,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                    ),
                    icon: Icon(_isScanning ? Icons.stop : Icons.radar),
                    label: Text(
                      _isScanning ? 'Dừng quét' : 'Bắt đầu dò',
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Custom painter for the pulsing radar waves.
class _RadarWavePainter extends CustomPainter {
  final double animationValue;
  final bool isScanning;
  final double signalPercent;
  final Color radarColor;
  final bool isSignalLost;

  _RadarWavePainter({
    required this.animationValue,
    required this.isScanning,
    required this.signalPercent,
    required this.radarColor,
    this.isSignalLost = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    // Background concentric circles
    final gridColor = isSignalLost
        ? Colors.grey.withValues(alpha: 0.15)
        : radarColor.withValues(alpha: 0.12);

    final gridPaint = Paint()
      ..color = gridColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    for (int i = 1; i <= 3; i++) {
      canvas.drawCircle(center, maxRadius * (i / 3.0), gridPaint);
    }

    // Crosshairs
    canvas.drawLine(
      Offset(center.dx, 0),
      Offset(center.dx, size.height),
      gridPaint,
    );
    canvas.drawLine(
      Offset(0, center.dy),
      Offset(size.width, center.dy),
      gridPaint,
    );

    // Animated pulsing wave rings when scanning
    if (isScanning) {
      final activeColor = isSignalLost
          ? Colors.orangeAccent.withValues(alpha: 0.4)
          : radarColor;

      for (int i = 0; i < 3; i++) {
        final waveVal = (animationValue + (i * 0.33)) % 1.0;
        final waveRadius = 40.0 + waveVal * (maxRadius - 40.0);
        final waveAlpha =
            ((1.0 - waveVal) * (isSignalLost ? 0.3 : 0.6)).clamp(0.0, 1.0);

        final wavePaint = Paint()
          ..color = activeColor.withValues(alpha: waveAlpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = isSignalLost ? 1.5 : 2.0;

        canvas.drawCircle(center, waveRadius, wavePaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RadarWavePainter oldDelegate) {
    return oldDelegate.animationValue != animationValue ||
        oldDelegate.isScanning != isScanning ||
        oldDelegate.signalPercent != signalPercent ||
        oldDelegate.radarColor != radarColor ||
        oldDelegate.isSignalLost != isSignalLost;
  }
}
