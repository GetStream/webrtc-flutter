#if TARGET_OS_OSX

#import <Foundation/Foundation.h>

/// Captures system audio using ScreenCaptureKit (macOS 13.0+).
/// Audio is stored in an internal ring buffer as mono float32 samples
/// normalized to [-1.0, 1.0], and can be read on-demand by a mixer.
API_AVAILABLE(macos(13.0))
@interface ScreenAudioCapturer : NSObject

@property(nonatomic, readonly) BOOL isCapturing;

/// Start capturing system audio via ScreenCaptureKit.
/// Capture starts asynchronously; audio becomes available shortly after.
/// @param excludeCurrentProcess If YES, excludes audio from the current app
///        to avoid echo from remote WebRTC peer audio playback.
- (void)startCaptureWithExcludeCurrentProcess:(BOOL)excludeCurrentProcess;

/// Stop capturing system audio and clear the internal buffer.
- (void)stopCapture;

/// Read mono float32 audio frames from the internal ring buffer.
/// Values are normalized in the range [-1.0, 1.0].
/// @param buffer Output buffer to write frames into.
/// @param frameCount Number of frames requested.
/// @return The number of frames actually read (may be less than requested
///         if not enough audio is buffered).
- (NSInteger)readFrames:(float* _Nonnull)buffer count:(NSInteger)frameCount;

@end

#endif
