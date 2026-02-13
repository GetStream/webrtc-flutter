import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../utils.dart';

class IosAudioManagement {
  /// Ensure audio session (iOS only).
  static Future<void> ensureAudioSession() async {
    if (kIsWeb || !WebRTC.platformIsIOS) return;
    await WebRTC.invokeMethod('ensureAudioSession');
  }

  /// Set whether stereo playout is preferred (iOS only).
  ///
  /// When enabled, the native layer sets `prefersStereoPlayout` on the ADM,
  /// bypasses voice processing, sets mute mode to input mixer, and monitors
  /// audio route changes to refresh stereo playout state.
  static Future<void> setStereoPlayoutPreferred(bool preferred) async {
    if (kIsWeb || !WebRTC.platformIsIOS) return;

    try {
      await WebRTC.invokeMethod(
        'setStereoPlayoutPreferred',
        <String, dynamic>{'preferred': preferred},
      );
    } on PlatformException catch (e) {
      throw 'Unable to set stereo playout preferred: ${e.message}';
    }
  }

  /// Returns whether stereo playout is currently enabled on the ADM (iOS only).
  static Future<bool> isStereoPlayoutEnabled() async {
    if (kIsWeb || !WebRTC.platformIsIOS) return false;

    try {
      final result = await WebRTC.invokeMethod(
        'isStereoPlayoutEnabled',
        <String, dynamic>{},
      );
      return result as bool;
    } on PlatformException catch (e) {
      throw 'Unable to get isStereoPlayoutEnabled: ${e.message}';
    }
  }

  /// Refreshes the stereo playout state on the ADM (iOS only).
  static Future<void> refreshStereoPlayoutState() async {
    if (kIsWeb || !WebRTC.platformIsIOS) return;

    try {
      await WebRTC.invokeMethod(
        'refreshStereoPlayoutState',
        <String, dynamic>{},
      );
    } on PlatformException catch (e) {
      throw 'Unable to refresh stereo playout state: ${e.message}';
    }
  }

  /// Trigger the iOS audio route selection UI (iOS only).
  static Future<void> triggerAudioRouteSelectionUI() async {
    if (WebRTC.platformIsIOS) {
      return await WebRTC.invokeMethod(
        'triggeriOSAudioRouteSelectionUI',
      );
    } else {
      throw Exception('triggerAudioRouteSelectionUI is only supported for iOS');
    }
  }

  /// Enable or disable iOS multitasking camera access (iOS only).
  static Future<bool> enableMultitaskingCameraAccess(bool enable) async {
    if (WebRTC.platformIsIOS) {
      return await WebRTC.invokeMethod(
        'enableIOSMultitaskingCameraAccess',
        <String, dynamic>{'enable': enable},
      );
    } else {
      throw Exception(
          'enableMultitaskingCameraAccess is only supported for iOS');
    }
  }
}
