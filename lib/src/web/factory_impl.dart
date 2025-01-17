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
