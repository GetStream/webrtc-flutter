#if TARGET_OS_IPHONE
#import "AudioUtils.h"
#import <AVFoundation/AVFoundation.h>

@implementation AudioUtils

+ (void)ensureAudioSessionWithRecording:(BOOL)recording {
  RTCAudioSession* session = [RTCAudioSession sharedInstance];
  // we also need to set default WebRTC audio configuration, since it may be activated after
  // this method is called
  RTCAudioSessionConfiguration* config = [RTCAudioSessionConfiguration webRTCConfiguration];
  // require audio session to be either PlayAndRecord or MultiRoute
  if (recording && session.category != AVAudioSessionCategoryPlayAndRecord &&
      session.category != AVAudioSessionCategoryMultiRoute) {
    config.category = AVAudioSessionCategoryPlayAndRecord;
    config.categoryOptions = AVAudioSessionCategoryOptionAllowBluetooth |
                             AVAudioSessionCategoryOptionAllowBluetoothA2DP |
                             AVAudioSessionCategoryOptionAllowAirPlay;

    [session lockForConfiguration];
    NSError* error = nil;
    bool success = [session setCategory:config.category
                            withOptions:config.categoryOptions
                                  error:&error];
    if (!success)
      NSLog(@"ensureAudioSessionWithRecording[true]: setCategory failed due to: %@", error);
    success = [session setMode:config.mode error:&error];
    if (!success)
      NSLog(@"ensureAudioSessionWithRecording[true]: setMode failed due to: %@", error);
    [session unlockForConfiguration];
  } else if (!recording && (session.category == AVAudioSessionCategoryAmbient ||
                            session.category == AVAudioSessionCategorySoloAmbient)) {
    config.mode = AVAudioSessionModeDefault;
    [session lockForConfiguration];
    NSError* error = nil;
    bool success = [session setMode:config.mode error:&error];
    if (!success)
      NSLog(@"ensureAudioSessionWithRecording[false]: setMode failed due to: %@", error);
    [session unlockForConfiguration];
  }
}

+ (BOOL)selectAudioInput:(AVAudioSessionPort)type {
  RTCAudioSession* rtcSession = [RTCAudioSession sharedInstance];
  AVAudioSessionPortDescription* inputPort = nil;
  for (AVAudioSessionPortDescription* port in rtcSession.session.availableInputs) {
    if ([port.portType isEqualToString:type]) {
      inputPort = port;
      break;
    }
  }
  if (inputPort != nil) {
    NSError* errOut = nil;
    [rtcSession lockForConfiguration];
    [rtcSession setPreferredInput:inputPort error:&errOut];
    [rtcSession unlockForConfiguration];
    if (errOut != nil) {
      return NO;
    }
    return YES;
  }
  return NO;
}

+ (void)setSpeakerphoneOn:(BOOL)enable {
  RTCAudioSession* session = [RTCAudioSession sharedInstance];
  RTCAudioSessionConfiguration* config = [RTCAudioSessionConfiguration webRTCConfiguration];

  if (enable && config.category != AVAudioSessionCategoryPlayAndRecord) {
    NSLog(@"setSpeakerphoneOn: Category option 'defaultToSpeaker' is only applicable with category "
          @"'playAndRecord', ignore.");
    return;
  }

  [session lockForConfiguration];
  NSError* error = nil;
  if (!enable) {
    [session setMode:config.mode error:&error];
    BOOL success = [session setCategory:config.category
                            withOptions:AVAudioSessionCategoryOptionAllowAirPlay |
                                        AVAudioSessionCategoryOptionAllowBluetoothA2DP |
                                        AVAudioSessionCategoryOptionAllowBluetooth
                                  error:&error];

    success = [session.session overrideOutputAudioPort:kAudioSessionOverrideAudioRoute_None
                                                 error:&error];
    if (!success)
      NSLog(@"setSpeakerphoneOn: Port override failed due to: %@", error);
  } else {
    [session setMode:config.mode error:&error];
    BOOL success = [session setCategory:config.category
                            withOptions:AVAudioSessionCategoryOptionDefaultToSpeaker |
                                        AVAudioSessionCategoryOptionAllowAirPlay |
                                        AVAudioSessionCategoryOptionAllowBluetoothA2DP |
                                        AVAudioSessionCategoryOptionAllowBluetooth
                                  error:&error];

    success = [session overrideOutputAudioPort:kAudioSessionProperty_OverrideAudioRoute
                                         error:&error];
    if (!success)
      NSLog(@"setSpeakerphoneOn: Port override failed due to: %@", error);
  }
  [session unlockForConfiguration];
}

+ (void)setSpeakerphoneOnButPreferBluetooth {
  RTCAudioSession* session = [RTCAudioSession sharedInstance];
  RTCAudioSessionConfiguration* config = [RTCAudioSessionConfiguration webRTCConfiguration];
  [session lockForConfiguration];
  NSError* error = nil;
  [session setMode:config.mode error:&error];
  BOOL success = [session setCategory:config.category
                          withOptions:AVAudioSessionCategoryOptionAllowAirPlay |
                                      AVAudioSessionCategoryOptionAllowBluetoothA2DP |
                                      AVAudioSessionCategoryOptionAllowBluetooth |
                                      AVAudioSessionCategoryOptionDefaultToSpeaker
                                error:&error];

  success = [session overrideOutputAudioPort:kAudioSessionOverrideAudioRoute_None error:&error];
  if (!success)
    NSLog(@"setSpeakerphoneOnButPreferBluetooth: Port override failed due to: %@", error);

  success = [session setActive:YES error:&error];
  if (!success)
    NSLog(@"setSpeakerphoneOnButPreferBluetooth: Audio session override failed: %@", error);
  else
    NSLog(@"AudioSession override with bluetooth preference via "
          @"setSpeakerphoneOnButPreferBluetooth successfull ");
  [session unlockForConfiguration];
}

+ (void)deactiveRtcAudioSession {
  NSError* error = nil;
  RTCAudioSession* session = [RTCAudioSession sharedInstance];
  [session lockForConfiguration];
  if ([session isActive]) {
    BOOL success = [session setActive:NO error:&error];
    if (!success)
      NSLog(@"RTC Audio session deactive failed: %@", error);
    else
      NSLog(@"RTC AudioSession deactive is successful ");
  }
  [session unlockForConfiguration];
}

+ (AVAudioSessionMode)audioSessionModeFromString:(NSString*)mode {
  if ([@"default_" isEqualToString:mode]) {
    return AVAudioSessionModeDefault;
  } else if ([@"voicePrompt" isEqualToString:mode]) {
    return AVAudioSessionModeVoicePrompt;
  } else if ([@"videoRecording" isEqualToString:mode]) {
    return AVAudioSessionModeVideoRecording;
  } else if ([@"videoChat" isEqualToString:mode]) {
    return AVAudioSessionModeVideoChat;
  } else if ([@"voiceChat" isEqualToString:mode]) {
    return AVAudioSessionModeVoiceChat;
  } else if ([@"gameChat" isEqualToString:mode]) {
    return AVAudioSessionModeGameChat;
  } else if ([@"measurement" isEqualToString:mode]) {
    return AVAudioSessionModeMeasurement;
  } else if ([@"moviePlayback" isEqualToString:mode]) {
    return AVAudioSessionModeMoviePlayback;
  } else if ([@"spokenAudio" isEqualToString:mode]) {
    return AVAudioSessionModeSpokenAudio;
  }
  return AVAudioSessionModeDefault;
}

+ (AVAudioSessionCategory)audioSessionCategoryFromString:(NSString*)category {
  if ([@"ambient" isEqualToString:category]) {
    return AVAudioSessionCategoryAmbient;
  } else if ([@"soloAmbient" isEqualToString:category]) {
    return AVAudioSessionCategorySoloAmbient;
  } else if ([@"playback" isEqualToString:category]) {
    return AVAudioSessionCategoryPlayback;
  } else if ([@"record" isEqualToString:category]) {
    return AVAudioSessionCategoryRecord;
  } else if ([@"playAndRecord" isEqualToString:category]) {
    return AVAudioSessionCategoryPlayAndRecord;
  } else if ([@"multiRoute" isEqualToString:category]) {
    return AVAudioSessionCategoryMultiRoute;
  }
  return AVAudioSessionCategoryAmbient;
}

+ (void)setAppleAudioConfiguration:(NSDictionary*)configuration {
  RTCAudioSession* session = [RTCAudioSession sharedInstance];
  RTCAudioSessionConfiguration* config = [RTCAudioSessionConfiguration webRTCConfiguration];

  NSString* appleAudioCategory = configuration[@"appleAudioCategory"];
  NSArray* appleAudioCategoryOptions = configuration[@"appleAudioCategoryOptions"];
  NSString* appleAudioMode = configuration[@"appleAudioMode"];

  [session lockForConfiguration];

  AVAudioSessionCategoryOptions desiredOptions = 0;
  BOOL haveOptions = NO;
  if (appleAudioCategoryOptions != nil) {
    haveOptions = YES;
    for (NSString* option in appleAudioCategoryOptions) {
      if ([@"mixWithOthers" isEqualToString:option]) {
        desiredOptions |= AVAudioSessionCategoryOptionMixWithOthers;
      } else if ([@"duckOthers" isEqualToString:option]) {
        desiredOptions |= AVAudioSessionCategoryOptionDuckOthers;
      } else if ([@"allowBluetooth" isEqualToString:option]) {
        desiredOptions |= AVAudioSessionCategoryOptionAllowBluetooth;
      } else if ([@"allowBluetoothA2DP" isEqualToString:option]) {
        desiredOptions |= AVAudioSessionCategoryOptionAllowBluetoothA2DP;
      } else if ([@"allowAirPlay" isEqualToString:option]) {
        desiredOptions |= AVAudioSessionCategoryOptionAllowAirPlay;
      } else if ([@"defaultToSpeaker" isEqualToString:option]) {
        desiredOptions |= AVAudioSessionCategoryOptionDefaultToSpeaker;
      }
    }
    config.categoryOptions = desiredOptions;
  }

  AVAudioSessionCategory desiredCategory = nil;
  AVAudioSessionMode desiredMode = nil;
  if (appleAudioCategory != nil) {
    desiredCategory = [AudioUtils audioSessionCategoryFromString:appleAudioCategory];
    config.category = desiredCategory;
  }
  if (appleAudioMode != nil) {
    desiredMode = [AudioUtils audioSessionModeFromString:appleAudioMode];
    config.mode = desiredMode;
  }

  NSError* err = nil;
  if (desiredCategory != nil && desiredMode != nil && haveOptions) {
    BOOL ok = [session setCategory:desiredCategory
                              mode:desiredMode
                           options:desiredOptions
                             error:&err];
    if (!ok) {
      NSLog(@"setCategory:mode:options: failed: %@", err);
    }
  } else {
    if (desiredCategory != nil) {
      [session setCategory:desiredCategory withOptions:desiredOptions error:nil];
    }
    if (desiredMode != nil) {
      [session setMode:desiredMode error:nil];
    }
  }

  [session unlockForConfiguration];
}

@end
#endif
