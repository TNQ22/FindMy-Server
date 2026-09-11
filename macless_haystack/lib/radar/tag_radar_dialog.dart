import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../accessory/accessory_icon_model.dart';
import '../accessory/accessory_model.dart';
import 'ble_radar_service.dart';

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
  bool _isScanning = false;
  bool _hapticEnabled = true;
  String _statusMessage = 'Sẵn sàng quét sóng...';
  Timer? _staleTimer;

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
          'Rada Bluetooth yêu cầu truy cập phần cứng di động (Android / iOS).';
    }
  }

  @override
  void dispose() {
    _staleTimer?.cancel();
    _subscription?.cancel();
    _radarAnimController.dispose();
    _radarService.dispose();
    try {
      WakelockPlus.disable();
    } catch (_) {}
    super.dispose();
  }

  Future<void> _startRadar() async {
    try {
      await WakelockPlus.enable();
    } catch (_) {}

    setState(() {
      _isScanning = true;
      _statusMessage = 'Đang dò sóng Bluetooth của tag...';
    });

    _radarAnimController.repeat();

    _subscription?.cancel();
    _subscription = _radarService.scanStream.listen((result) {
      if (!mounted) return;

      if (_hapticEnabled) {
        if (result.rssi >= -60) {
          HapticFeedback.heavyImpact();
        } else if (result.rssi >= -75) {
          HapticFeedback.mediumImpact();
        } else {
          HapticFeedback.selectionClick();
        }
      }

      setState(() {
        _latestResult = result;
        _statusMessage = 'Đã bắt được tín hiệu!';
      });

      // Reset stale timer: if no packet received within 10 seconds, warn user
      _staleTimer?.cancel();
      _staleTimer = Timer(const Duration(seconds: 10), () {
        if (mounted && _isScanning) {
          setState(() {
            _statusMessage = 'Đang chờ gói tin mới từ tag...';
          });
        }
      });
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
    }
  }

  Future<void> _stopRadar() async {
    await _radarService.stopScanning();
    _staleTimer?.cancel();
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
                        child: Row(
                          children: [
                            Icon(Icons.info_outline, color: Colors.amber.shade800),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                'Tính năng quét sóng Bluetooth lân cận cần truy cập phần cứng chip Bluetooth, hiện chỉ hoạt động trên ứng dụng Android (.apk) hoặc iOS.',
                                style: TextStyle(fontSize: 13),
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
                                  signalPercent:
                                      _latestResult?.signalPercentage ?? 0,
                                  radarColor: _latestResult?.proximityColor ?? tagColor,
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
                              color: tagColor,
                              boxShadow: [
                                BoxShadow(
                                  color: (_latestResult?.proximityColor ?? tagColor)
                                      .withValues(alpha: 0.4),
                                  blurRadius: 18,
                                  spreadRadius: 4,
                                ),
                              ],
                            ),
                            child: Icon(
                              iconData,
                              color: Colors.white,
                              size: 40,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ── Signal Gauge / RSSI Value ─────────────────────────
                    if (_latestResult != null) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.sensors,
                            color: _latestResult!.proximityColor,
                            size: 24,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${_latestResult!.rssi} dBm',
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                              color: _latestResult!.proximityColor,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: _latestResult!.proximityColor
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: _latestResult!.proximityColor),
                            ),
                            child: Text(
                              '${_latestResult!.signalPercentage.round()}%',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: _latestResult!.proximityColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _latestResult!.proximityLabel,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: _latestResult!.proximityColor,
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
                            if (_latestResult!.hardwareBatteryStatus != null)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
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
                                padding: const EdgeInsets.symmetric(vertical: 4),
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
                  // Haptic feedback toggle
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      setState(() {
                        _hapticEnabled = !_hapticEnabled;
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      child: Row(
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
                              fontSize: 13,
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
                      backgroundColor:
                          _isScanning ? Colors.red.shade700 : Colors.teal.shade700,
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

  _RadarWavePainter({
    required this.animationValue,
    required this.isScanning,
    required this.signalPercent,
    required this.radarColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    // Background concentric circles
    final gridPaint = Paint()
      ..color = radarColor.withValues(alpha: 0.12)
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
      for (int i = 0; i < 3; i++) {
        final waveVal = (animationValue + (i * 0.33)) % 1.0;
        final waveRadius = 40.0 + waveVal * (maxRadius - 40.0);
        final waveAlpha = ((1.0 - waveVal) * 0.6).clamp(0.0, 1.0);

        final wavePaint = Paint()
          ..color = radarColor.withValues(alpha: waveAlpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0;

        canvas.drawCircle(center, waveRadius, wavePaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RadarWavePainter oldDelegate) {
    return oldDelegate.animationValue != animationValue ||
        oldDelegate.isScanning != isScanning ||
        oldDelegate.signalPercent != signalPercent ||
        oldDelegate.radarColor != radarColor;
  }
}
