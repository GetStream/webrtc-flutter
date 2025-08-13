import 'dart:async';
import 'dart:io';

import 'package:webrtc_interface/webrtc_interface.dart';

import '../desktop_capturer.dart';
import 'android/audio_configuration.dart';
import 'desktop_capturer_impl.dart';
import 'frame_cryptor_impl.dart';
import 'media_recorder_impl.dart';
import 'media_stream_impl.dart';
import 'mediadevices_impl.dart';
import 'navigator_impl.dart';
import 'rtc_peerconnection_impl.dart';
import 'rtc_video_renderer_impl.dart';
import 'utils.dart';

class RTCFactoryNative extends RTCFactory {
  RTCFactoryNative._internal();

  static final RTCFactory instance = RTCFactoryNative._internal();

  Future<void> setVideoEffects(String trackId, List<String> names) async {
    await WebRTC.invokeMethod('setVideoEffects', {
      'trackId': trackId,
      'names': names,
    });
  }

  Future<void> handleCallInterruptionCallbacks(
    void Function()? onInterruptionStart,
    void Function()? onInterruptionEnd, {
    AndroidInterruptionSource androidInterruptionSource =
        AndroidInterruptionSource.audioFocusAndTelephony,
    AndroidAudioAttributesUsageType? androidAudioAttributesUsageType,
    AndroidAudioAttributesContentType? androidAudioAttributesContentType,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      throw UnimplementedError(
          'handleCallInterruptionCallbacks is only supported on Android and iOS');
    }

    await WebRTC.invokeMethod(
      'handleCallInterruptionCallbacks',
      <String, dynamic>{
        if (Platform.isAndroid)
          'androidInterruptionSource': androidInterruptionSource.name,
        if (Platform.isAndroid && androidAudioAttributesUsageType != null)
          'androidAudioAttributesUsageType':
              androidAudioAttributesUsageType.name,
        if (Platform.isAndroid && androidAudioAttributesContentType != null)
          'androidAudioAttributesContentType':
              androidAudioAttributesContentType.name,
      },
    );

    final mediaDeviceNative = mediaDevices as MediaDeviceNative;
    mediaDeviceNative.onInterruptionStart = onInterruptionStart;
    mediaDeviceNative.onInterruptionEnd = onInterruptionEnd;
  }

  @override
  Future<MediaStream> createLocalMediaStream(String label) async {
    final response = await WebRTC.invokeMethod('createLocalMediaStream');
    if (response == null) {
      throw Exception('createLocalMediaStream return null, something wrong');
    }
    return MediaStreamNative(response['streamId'], label);
  }

  @override
  Future<RTCPeerConnection> createPeerConnection(
      Map<String, dynamic> configuration,
      [Map<String, dynamic> constraints = const {}]) async {
    var defaultConstraints = <String, dynamic>{
      'mandatory': {},
      'optional': [
        {'DtlsSrtpKeyAgreement': true},
      ],
    };

    final response = await WebRTC.invokeMethod(
      'createPeerConnection',
      <String, dynamic>{
        'configuration': configuration,
        'constraints': constraints.isEmpty ? defaultConstraints : constraints
      },
    );

    String peerConnectionId = response['peerConnectionId'];
    return RTCPeerConnectionNative(peerConnectionId, configuration);
  }

  @override
  MediaRecorder mediaRecorder() {
    return MediaRecorderNative();
  }

  @override
  VideoRenderer videoRenderer() {
    return RTCVideoRenderer();
  }

  @override
  Navigator get navigator => NavigatorNative.instance;

  @override
  FrameCryptorFactory get frameCryptorFactory =>
      FrameCryptorFactoryImpl.instance;

  @override
  Future<RTCRtpCapabilities> getRtpReceiverCapabilities(String kind) async {
    final response = await WebRTC.invokeMethod(
      'getRtpReceiverCapabilities',
      <String, dynamic>{
        'kind': kind,
      },
    );
    return RTCRtpCapabilities.fromMap(response);
  }

  @override
  Future<RTCRtpCapabilities> getRtpSenderCapabilities(String kind) async {
    final response = await WebRTC.invokeMethod(
      'getRtpSenderCapabilities',
      <String, dynamic>{
        'kind': kind,
      },
    );
    return RTCRtpCapabilities.fromMap(response);
  }
}

Future<void> setVideoEffects(
  String trackId, {
  required List<String> names,
}) async {
  return (RTCFactoryNative.instance as RTCFactoryNative)
      .setVideoEffects(trackId, names);
}

Future<void> handleCallInterruptionCallbacks(
  void Function()? onInterruptionStart,
  void Function()? onInterruptionEnd, {
  AndroidInterruptionSource androidInterruptionSource =
      AndroidInterruptionSource.audioFocusAndTelephony,
  AndroidAudioAttributesUsageType? androidAudioAttributesUsageType,
  AndroidAudioAttributesContentType? androidAudioAttributesContentType,
}) {
  return (RTCFactoryNative.instance as RTCFactoryNative)
      .handleCallInterruptionCallbacks(
    onInterruptionStart,
    onInterruptionEnd,
    androidInterruptionSource: androidInterruptionSource,
    androidAudioAttributesUsageType: androidAudioAttributesUsageType,
    androidAudioAttributesContentType: androidAudioAttributesContentType,
  );
}

Future<RTCPeerConnection> createPeerConnection(
    Map<String, dynamic> configuration,
    [Map<String, dynamic> constraints = const {}]) async {
  return RTCFactoryNative.instance
      .createPeerConnection(configuration, constraints);
}

Future<MediaStream> createLocalMediaStream(String label) async {
  return RTCFactoryNative.instance.createLocalMediaStream(label);
}

Future<RTCRtpCapabilities> getRtpReceiverCapabilities(String kind) async {
  return RTCFactoryNative.instance.getRtpReceiverCapabilities(kind);
}

Future<RTCRtpCapabilities> getRtpSenderCapabilities(String kind) async {
  return RTCFactoryNative.instance.getRtpSenderCapabilities(kind);
}

MediaRecorder mediaRecorder() {
  return RTCFactoryNative.instance.mediaRecorder();
}

Navigator get navigator => RTCFactoryNative.instance.navigator;

DesktopCapturer get desktopCapturer => DesktopCapturerNative.instance;

MediaDevices get mediaDevices => MediaDeviceNative.instance;

FrameCryptorFactory get frameCryptorFactory => FrameCryptorFactoryImpl.instance;
