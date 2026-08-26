import 'dart:math';

import 'package:webrtc_interface/webrtc_interface.dart';

import 'utils.dart';

enum CameraFocusMode { auto, locked }

enum CameraExposureMode { auto, locked }

/// The capture format the camera is running at after a reconfiguration.
class CameraCaptureFormat {
  const CameraCaptureFormat({
    required this.width,
    required this.height,
    required this.fps,
  });

  factory CameraCaptureFormat.fromMap(Map<dynamic, dynamic> map) {
    return CameraCaptureFormat(
      width: (map['width'] as num?)?.toInt() ?? 0,
      height: (map['height'] as num?)?.toInt() ?? 0,
      fps: (map['fps'] as num?)?.toInt() ?? 0,
    );
  }

  /// The width of the format the device actually selected, which may be larger
  /// than what was requested.
  final int width;

  /// The height of the format the device actually selected.
  final int height;

  /// The frame rate applied, clamped to what the selected format supports.
  final int fps;

  @override
  String toString() => 'CameraCaptureFormat(${width}x$height@$fps)';
}

/// How hard the device is currently being pushed thermally.
///
/// Mirrors `AVCaptureDevice.SystemPressureState.Level` on iOS and
/// `PowerManager` thermal status on Android.
enum CameraPressureLevel {
  nominal,
  fair,
  serious,
  critical,
  shutdown,
  unknown;

  static CameraPressureLevel fromName(String? name) {
    return CameraPressureLevel.values.firstWhere(
      (level) => level.name == name,
      orElse: () => CameraPressureLevel.unknown,
    );
  }
}

/// Emitted when thermal pressure causes the camera to be reconfigured.
class CameraSystemPressureEvent {
  const CameraSystemPressureEvent({
    required this.level,
    required this.width,
    required this.height,
    required this.fps,
    this.trackId,
  });

  factory CameraSystemPressureEvent.fromMap(Map<dynamic, dynamic> map) {
    return CameraSystemPressureEvent(
      level: CameraPressureLevel.fromName(map['level'] as String?),
      width: (map['width'] as num?)?.toInt() ?? 0,
      height: (map['height'] as num?)?.toInt() ?? 0,
      fps: (map['fps'] as num?)?.toInt() ?? 0,
      trackId: map['trackId'] as String?,
    );
  }

  final CameraPressureLevel level;

  /// The capture dimensions applied in response to [level].
  final int width;
  final int height;

  /// The frame rate applied in response to [level].
  final int fps;

  final String? trackId;

  @override
  String toString() =>
      'CameraSystemPressureEvent(${level.name}, ${width}x$height@$fps)';
}

class CameraUtils {
  static Future<void> setZoom(
      MediaStreamTrack videoTrack, double zoomLevel) async {
    if (WebRTC.platformIsAndroid || WebRTC.platformIsIOS) {
      await WebRTC.invokeMethod(
        'mediaStreamTrackSetZoom',
        <String, dynamic>{'trackId': videoTrack.id, 'zoomLevel': zoomLevel},
      );
    } else {
      throw Exception('setZoom only support for mobile devices!');
    }
  }

  /// Set the exposure point for the camera, focusMode can be:
  /// 'auto', 'locked'
  static Future<void> setFocusMode(
      MediaStreamTrack videoTrack, CameraFocusMode focusMode) async {
    if (WebRTC.platformIsAndroid || WebRTC.platformIsIOS) {
      await WebRTC.invokeMethod(
        'mediaStreamTrackSetFocusMode',
        <String, dynamic>{
          'trackId': videoTrack.id,
          'focusMode': focusMode.name,
        },
      );
    } else {
      throw Exception('setFocusMode only support for mobile devices!');
    }
  }

  static Future<void> setFocusPoint(
      MediaStreamTrack videoTrack, Point<double>? point) async {
    if (WebRTC.platformIsAndroid || WebRTC.platformIsIOS) {
      await WebRTC.invokeMethod(
        'mediaStreamTrackSetFocusPoint',
        <String, dynamic>{
          'trackId': videoTrack.id,
          'focusPoint': {
            'reset': point == null,
            'x': point?.x,
            'y': point?.y,
          },
        },
      );
    } else {
      throw Exception('setFocusPoint only support for mobile devices!');
    }
  }

  static Future<void> setExposureMode(
      MediaStreamTrack videoTrack, CameraExposureMode exposureMode) async {
    if (WebRTC.platformIsAndroid || WebRTC.platformIsIOS) {
      await WebRTC.invokeMethod(
        'mediaStreamTrackSetExposureMode',
        <String, dynamic>{
          'trackId': videoTrack.id,
          'exposureMode': exposureMode.name,
        },
      );
    } else {
      throw Exception('setExposureMode only support for mobile devices!');
    }
  }

  static Future<void> setExposurePoint(
      MediaStreamTrack videoTrack, Point<double>? point) async {
    if (WebRTC.platformIsAndroid || WebRTC.platformIsIOS) {
      await WebRTC.invokeMethod(
        'mediaStreamTrackSetExposurePoint',
        <String, dynamic>{
          'trackId': videoTrack.id,
          'exposurePoint': {
            'reset': point == null,
            'x': point?.x,
            'y': point?.y,
          },
        },
      );
    } else {
      throw Exception('setExposurePoint only support for mobile devices!');
    }
  }

  /// Reconfigures the running capture session to [width] x [height] at [fps].
  ///
  /// The camera keeps running: no track is recreated and no `getUserMedia`
  /// round trip happens, so this is cheap enough to call whenever the needed
  /// resolution changes during a call.
  ///
  /// [width] and [height] are a target, not a guarantee — the device picks the
  /// closest format it can actually run, and the returned
  /// [CameraCaptureFormat] reports what it settled on. The video source is
  /// additionally capped to the requested size, so the encoder never receives
  /// more than was asked for.
  static Future<CameraCaptureFormat?> setCaptureFormat(
    MediaStreamTrack videoTrack, {
    required int width,
    required int height,
    required int fps,
  }) async {
    if (!WebRTC.platformIsAndroid && !WebRTC.platformIsIOS) {
      throw Exception('setCaptureFormat only supported for mobile devices!');
    }

    final result = await WebRTC.invokeMethod(
      'mediaStreamTrackSetCaptureFormat',
      <String, dynamic>{
        'trackId': videoTrack.id,
        'width': width,
        'height': height,
        'fps': fps,
      },
    );

    if (result is Map) return CameraCaptureFormat.fromMap(result);
    return null;
  }

  /// Enables or disables throttling the camera as the device heats up.
  ///
  /// When enabled, the plugin watches the platform's thermal signal and steps
  /// capture frame rate and resolution down as pressure rises, restoring them
  /// as it recovers. Transitions are debounced so pressure hovering at a
  /// boundary cannot flap the capture format.
  ///
  /// Returns whether monitoring is active afterwards — `false` on platforms
  /// that expose no thermal signal.
  static Future<bool> setSystemPressureMonitoringEnabled(bool enabled) async {
    if (!WebRTC.platformIsAndroid && !WebRTC.platformIsIOS) return false;

    final result = await WebRTC.invokeMethod(
      'setCameraSystemPressureMonitoringEnabled',
      <String, dynamic>{'enabled': enabled},
    );
    return result as bool? ?? false;
  }

  /// Whether camera thermal throttling is currently active.
  static Future<bool> isSystemPressureMonitoringEnabled() async {
    if (!WebRTC.platformIsAndroid && !WebRTC.platformIsIOS) return false;

    final result = await WebRTC.invokeMethod(
      'isCameraSystemPressureMonitoringEnabled',
    );
    return result as bool? ?? false;
  }
}
