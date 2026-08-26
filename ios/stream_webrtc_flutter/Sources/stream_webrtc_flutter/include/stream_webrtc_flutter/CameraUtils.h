#import <Foundation/Foundation.h>
#import "FlutterWebRTCPlugin.h"

@interface FlutterWebRTCPlugin (CameraUtils)

- (void)mediaStreamTrackHasTorch:(nonnull RTCMediaStreamTrack*)track result:(nonnull FlutterResult)result;

- (void)mediaStreamTrackSetTorch:(nonnull RTCMediaStreamTrack*)track
                           torch:(BOOL)torch
                          result:(nonnull FlutterResult)result;

- (void)mediaStreamTrackSetZoom:(nonnull RTCMediaStreamTrack*)track
                           zoomLevel:(double)zoomLevel
                          result:(nonnull FlutterResult)result;

- (void)mediaStreamTrackSetFocusMode:(nonnull RTCMediaStreamTrack*)track
                           focusMode:(nonnull NSString*)focusMode
                          result:(nonnull FlutterResult)result;

- (void)mediaStreamTrackSetFocusPoint:(nonnull RTCMediaStreamTrack*)track
                           focusPoint:(nonnull NSDictionary*)focusPoint
                          result:(nonnull FlutterResult)result;

- (void)mediaStreamTrackSetExposureMode:(nonnull RTCMediaStreamTrack*)track
                           exposureMode:(nonnull NSString*)exposureMode
                          result:(nonnull FlutterResult)result;

- (void)mediaStreamTrackSetExposurePoint:(nonnull RTCMediaStreamTrack*)track
                           exposurePoint:(nonnull NSDictionary*)exposurePoint
                            result:(nonnull FlutterResult)result;

- (void)mediaStreamTrackSwitchCamera:(nonnull RTCMediaStreamTrack*)track result:(nonnull FlutterResult)result;

- (NSInteger)selectFpsForFormat:(nullable AVCaptureDeviceFormat*)format targetFps:(NSInteger)targetFps;

- (nullable AVCaptureDeviceFormat*)selectFormatForDevice:(nullable AVCaptureDevice*)device
                                    targetWidth:(NSInteger)targetWidth
                                   targetHeight:(NSInteger)targetHeight;

- (nullable AVCaptureDeviceFormat*)selectFormatForDevice:(nullable AVCaptureDevice*)device
                                    targetWidth:(NSInteger)targetWidth
                                   targetHeight:(NSInteger)targetHeight
                                       targetFps:(NSInteger)targetFps;

- (void)applyFixedFrameRate:(NSInteger)fps toDevice:(nullable AVCaptureDevice*)device;

- (void)setCaptureFormatForTrack:(nullable NSString*)trackId
                           width:(NSInteger)width
                          height:(NSInteger)height
                             fps:(NSInteger)fps
                          result:(nullable FlutterResult)result;

- (void)adaptOutputFormatForTrack:(nullable NSString*)trackId
                            width:(NSInteger)width
                           height:(NSInteger)height
                              fps:(NSInteger)fps;

/// Enables or disables camera throttling under device thermal pressure.
///
/// A no-op on macOS, where `AVCaptureDevice.systemPressureState` does not exist.
- (void)setCameraSystemPressureMonitoringEnabled:(BOOL)enabled;

- (BOOL)isCameraSystemPressureMonitoringEnabled;

- (void)startCameraSystemPressureMonitoringForDevice:(nullable AVCaptureDevice*)device
                                             trackId:(nullable NSString*)trackId
                                               width:(NSInteger)width
                                              height:(NSInteger)height
                                                 fps:(NSInteger)fps;

/// Re-bases the throttle after capture was reconfigured for an unrelated reason
/// (an SFU quality change, say), so later step-downs scale from the new target.
- (void)updateCameraSystemPressureBaselineWidth:(NSInteger)width
                                         height:(NSInteger)height
                                            fps:(NSInteger)fps;

- (void)stopCameraSystemPressureMonitoring;

- (nullable AVCaptureDevice*)findDeviceForPosition:(AVCaptureDevicePosition)position;


@end
