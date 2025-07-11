import '../android_interruption_source.dart';
import '../desktop_capturer.dart';

export 'package:dart_webrtc/dart_webrtc.dart'
    hide videoRenderer, MediaDevices, MediaRecorder;

DesktopCapturer get desktopCapturer => throw UnimplementedError();

Future<void> setVideoEffects(
  String trackId, {
  required List<String> names,
}) async {
  throw UnimplementedError('setVideoEffects() is not supported on web');
}

Future<void> handleCallInterruptionCallbacks(
  void Function()? onInterruptionStart,
  void Function()? onInterruptionEnd, {
  AndroidInterruptionSource? androidInterruptionSource,
}) {
  throw UnimplementedError(
      'handleCallInterruptionCallbacks() is not supported on web');
}
