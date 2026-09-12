import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Provides hardware vibration with native Android MethodChannel and fallback to HapticFeedback.
class RadarVibrator {
  static const MethodChannel _channel =
      MethodChannel('de.dchristl.headlesshaystack/vibrate');

  static bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Vibrates for [durationMs] milliseconds with full hardware motor power.
  static Future<void> vibrate(int durationMs) async {
    if (_isAndroid) {
      try {
        await _channel.invokeMethod('vibrate', {'duration': durationMs});
        return;
      } catch (_) {}
    }
    // Fallback for Web/iOS/Desktop
    try {
      if (durationMs > 200) {
        await HapticFeedback.heavyImpact();
      } else if (durationMs > 100) {
        await HapticFeedback.mediumImpact();
      } else {
        await HapticFeedback.lightImpact();
      }
    } catch (_) {}
  }

  /// Plays a custom vibration pattern (timings in ms: [delay0, vib0, delay1, vib1, ...]).
  static Future<void> vibratePattern(List<int> pattern) async {
    if (_isAndroid) {
      try {
        await _channel.invokeMethod('vibratePattern', {'pattern': pattern});
        return;
      } catch (_) {}
    }
    // Fallback
    try {
      await HapticFeedback.heavyImpact();
    } catch (_) {}
  }

  /// Discovery Alert: Triggered when tag is first detected (or rediscovered after lost).
  /// Pattern: 1s long strong vibration + short pause + 3 rapid beats:
  /// [0ms wait, 1000ms vib, 150ms wait, 120ms vib, 100ms wait, 120ms vib, 100ms wait, 120ms vib]
  static Future<void> vibrateDiscovery() async {
    await vibratePattern([0, 1000, 150, 120, 100, 120, 100, 120]);
  }

  /// Cancels any ongoing vibration immediately.
  static Future<void> cancel() async {
    if (_isAndroid) {
      try {
        await _channel.invokeMethod('cancel');
        return;
      } catch (_) {}
    }
  }
}
