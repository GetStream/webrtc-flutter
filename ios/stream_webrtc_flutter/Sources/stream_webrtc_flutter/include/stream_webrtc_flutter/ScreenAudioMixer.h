#if TARGET_OS_OSX

#import <Foundation/Foundation.h>
#import "AudioProcessingAdapter.h"

@class ScreenAudioCapturer;

/// Mixes system audio (from ScreenAudioCapturer) into the microphone audio stream.
///
/// Implements ExternalAudioProcessingDelegate so it can be registered with the
/// AudioManager's capturePostProcessingAdapter. When active, each microphone
/// audio buffer is modified in-place to include mixed-in system audio.
API_AVAILABLE(macos(13.0))
@interface ScreenAudioMixer : NSObject <ExternalAudioProcessingDelegate>

/// Create a mixer that reads system audio from the given capturer.
- (nonnull instancetype)initWithCapturer:(nonnull ScreenAudioCapturer*)capturer;

@end

#endif
