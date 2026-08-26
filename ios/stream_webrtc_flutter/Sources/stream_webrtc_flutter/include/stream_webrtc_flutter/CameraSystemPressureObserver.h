#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#if TARGET_OS_IPHONE

/// The capture configuration the observer wants applied right now.
@protocol CameraSystemPressureObserverDelegate <NSObject>

/// Asks the delegate to reconfigure capture.
///
/// Always called on the main queue. [width] and [height] are already rounded to
/// even numbers; [fps] is already clamped to something the device can deliver.
- (void)systemPressureRequestsCaptureWidth:(NSInteger)width
                                    height:(NSInteger)height
                                       fps:(NSInteger)fps
                             pressureLevel:(NSString*)pressureLevel;

@end

/// Watches `AVCaptureDevice.systemPressureState` and steps capture down as the
/// device heats up, mirroring `CameraSystemPressureHandler` in
/// `stream-video-swift`.
///
/// Without this the camera captures at its initial configuration from the first
/// frame to the last regardless of device pressure, and the whole cost of
/// thermal recovery falls on the encoder.
///
/// Transitions are debounced so pressure oscillating around a boundary cannot
/// flap the capture format: 3 s before stepping down (1 s when already critical
/// or worse, where waiting is itself a cost), 10 s before stepping back up.
@interface CameraSystemPressureObserver : NSObject

@property(nonatomic, weak, nullable) id<CameraSystemPressureObserverDelegate> delegate;

/// The most recent observed pressure level, as a lowercase string.
@property(nonatomic, readonly) NSString* currentPressureLevel;

/// Starts observing [device], using the given capture configuration as the
/// baseline that the tiers scale down from.
///
/// Re-targets to the new device when called again, so a camera flip keeps the
/// throttle attached.
- (void)startObservingDevice:(AVCaptureDevice*)device
               baselineWidth:(NSInteger)baselineWidth
              baselineHeight:(NSInteger)baselineHeight
                 baselineFps:(NSInteger)baselineFps;

/// Updates the baseline without changing the observed device.
///
/// Called when capture is reconfigured for a reason unrelated to pressure (an
/// SFU quality change, say), so later throttling scales from the new target.
- (void)updateBaselineWidth:(NSInteger)baselineWidth
                     height:(NSInteger)baselineHeight
                        fps:(NSInteger)baselineFps;

/// Stops observing and cancels any pending transition.
- (void)stop;

@end

#endif

NS_ASSUME_NONNULL_END
