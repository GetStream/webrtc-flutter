#import <Foundation/Foundation.h>
#import <WebRTC/WebRTC.h>
#import "AudioProcessingAdapter.h"
#import "SystemAudioCapturer.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * SystemAudioMixer captures system audio and mixes it with the microphone audio stream.
 * It conforms to ExternalAudioProcessingDelegate to intercept microphone audio
 * and mix in system audio samples captured via ScreenCaptureKit.
 * Requires macOS 13.0 or later for system audio capture via ScreenCaptureKit.
 */
API_AVAILABLE(macos(13.0))
@interface SystemAudioMixer : NSObject <ExternalAudioProcessingDelegate, SystemAudioCapturerDelegate>

@property (nonatomic, readonly) BOOL isCapturing;

+ (BOOL)isSupported;

/**
 * Start capturing and mixing system audio.
 * System audio will be mixed into the microphone audio stream.
 */
- (void)startWithCompletion:(void (^_Nullable)(NSError * _Nullable error))completion;

/**
 * Stop capturing system audio.
 */
- (void)stop;

/**
 * Set the mix volume for system audio (0.0 - 1.0).
 * Default is 1.0.
 */
@property (nonatomic, assign) float systemAudioVolume;

/**
 * Set the mix volume for microphone audio (0.0 - 1.0).
 * Default is 1.0.
 */
@property (nonatomic, assign) float microphoneVolume;

@end

NS_ASSUME_NONNULL_END
