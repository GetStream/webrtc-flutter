#import "include/stream_webrtc_flutter/CameraUtils.h"

/// The frame rate used when a caller supplies no `frameRate` constraint.
///
/// Without this, `selectFpsForFormat:targetFps:` returned 0 for a
/// constraint-less `getUserMedia`, which produced an invalid `CMTimeMake(1, 0)`
/// frame duration and left the capture rate up to whatever the format happened
/// to default to.
static const NSInteger kDefaultTargetFps = 30;

static inline int32_t FormatArea(AVCaptureDeviceFormat* format) {
  CMVideoDimensions dimension = CMVideoFormatDescriptionGetDimensions(format.formatDescription);
  return dimension.width * dimension.height;
}

static BOOL FormatSupportsFrameRate(AVCaptureDeviceFormat* format, NSInteger fps) {
  if (fps <= 0) {
    return YES;
  }
  for (AVFrameRateRange* range in format.videoSupportedFrameRateRanges) {
    if (fps >= (NSInteger)floor(range.minFrameRate) &&
        fps <= (NSInteger)ceil(range.maxFrameRate)) {
      return YES;
    }
  }
  return NO;
}

@implementation FlutterWebRTCPlugin (CameraUtils)


- (AVCaptureDevice*)currentDevice {
  if (!self.videoCapturer) {
    return nil;
  }
  if (self.videoCapturer.captureSession.inputs.count == 0) {
    return nil;
  }
  AVCaptureDeviceInput* deviceInput = [self.videoCapturer.captureSession.inputs objectAtIndex:0];
  return deviceInput.device;
}

- (void)mediaStreamTrackHasTorch:(RTCMediaStreamTrack*)track result:(FlutterResult)result {
  NSLog(@"Not supported on macOS. Can't check torch");
  result(@NO);
}

- (void)mediaStreamTrackSetTorch:(RTCMediaStreamTrack*)track
                           torch:(BOOL)torch
                          result:(FlutterResult)result {
  AVCaptureDevice* device = [self currentDevice];
  if (!device) {
    NSLog(@"Video capturer is null. Can't set torch");
    result([FlutterError errorWithCode:@"mediaStreamTrackSetTorchFailed"
                               message:@"device is nil"
                               details:nil]);
    return;
  }

  if (![device isTorchModeSupported:AVCaptureTorchModeOn]) {
    NSLog(@"Current capture device does not support torch. Can't set torch");
    result([FlutterError errorWithCode:@"mediaStreamTrackSetTorchFailed"
                               message:@"device does not support torch"
                               details:nil]);
    return;
  }

  NSError* error;
  if ([device lockForConfiguration:&error] == NO) {
    NSLog(@"Failed to aquire configuration lock. %@", error.localizedDescription);
    result([FlutterError errorWithCode:@"mediaStreamTrackSetTorchFailed"
                               message:error.localizedDescription
                               details:nil]);
    return;
  }

  device.torchMode = torch ? AVCaptureTorchModeOn : AVCaptureTorchModeOff;
  [device unlockForConfiguration];

  result(nil);
}

- (void)mediaStreamTrackSetZoom:(RTCMediaStreamTrack*)track
                      zoomLevel:(double)zoomLevel
                         result:(FlutterResult)result {
  NSLog(@"Not supported on macOS. Can't set zoom");
  result([FlutterError errorWithCode:@"mediaStreamTrackSetZoomFailed"
                             message:@"Not supported on macOS"
                             details:nil]);
}

- (void)applyFocusMode:(NSString*)focusMode onDevice:(AVCaptureDevice*)captureDevice {
}

- (void)mediaStreamTrackSetFocusMode:(nonnull RTCMediaStreamTrack*)track
                           focusMode:(nonnull NSString*)focusMode
                              result:(nonnull FlutterResult)result {
  NSLog(@"Not supported on macOS. Can't focusMode");
  result([FlutterError errorWithCode:@"mediaStreamTrackSetFocusModeFailed"
                             message:@"Not supported on macOS"
                             details:nil]);
}

- (void)mediaStreamTrackSetFocusPoint:(nonnull RTCMediaStreamTrack*)track
                           focusPoint:(nonnull NSDictionary*)focusPoint
                               result:(nonnull FlutterResult)result {
  NSLog(@"Not supported on macOS. Can't focusPoint");
  result([FlutterError errorWithCode:@"mediaStreamTrackSetFocusPointFailed"
                             message:@"Not supported on macOS"
                             details:nil]);
}

- (void)applyExposureMode:(NSString*)exposureMode onDevice:(AVCaptureDevice*)captureDevice {
}

- (void)mediaStreamTrackSetExposureMode:(nonnull RTCMediaStreamTrack*)track
                           exposureMode:(nonnull NSString*)exposureMode
                                 result:(nonnull FlutterResult)result {
  NSLog(@"Not supported on macOS. Can't exposureMode");
  result([FlutterError errorWithCode:@"mediaStreamTrackSetExposureModeFailed"
                             message:@"Not supported on macOS"
                             details:nil]);
}

- (void)mediaStreamTrackSetExposurePoint:(nonnull RTCMediaStreamTrack*)track
                           exposurePoint:(nonnull NSDictionary*)exposurePoint
                                  result:(nonnull FlutterResult)result {
  NSLog(@"Not supported on macOS. Can't exposurePoint");
  result([FlutterError errorWithCode:@"mediaStreamTrackSetExposurePointFailed"
                             message:@"Not supported on macOS"
                             details:nil]);
}

- (void)mediaStreamTrackSwitchCamera:(RTCMediaStreamTrack*)track result:(FlutterResult)result {
  NSString* trackId = track.trackId;
  NSMutableDictionary* captureState = self.videoCaptureState[trackId];

  if (!self.videoCapturer) {
    NSLog(@"Video capturer is null. Can't switch camera");
    result([FlutterError errorWithCode:@"Error while switching camera"
                               message:@"Video capturer not found"
                               details:nil]);
    return;
  }

  // Stop the running session before reconfiguring it for a different device, so
  // two AVCaptureSessions can never be live at once. iOS already did this.
  [self.videoCapturer stopCapture];

  BOOL usingFrontCamera;
  NSInteger targetWidth;
  NSInteger targetHeight;
  NSInteger targetFps;

  if (captureState) {
    // Use per-track state
    usingFrontCamera = [captureState[@"usingFrontCamera"] boolValue];
    targetWidth = [captureState[@"targetWidth"] integerValue];
    targetHeight = [captureState[@"targetHeight"] integerValue];
    targetFps = [captureState[@"targetFps"] integerValue];
  } else {
    // Use global state for backward compatibility
    usingFrontCamera = self._usingFrontCamera;
    targetWidth = self._lastTargetWidth;
    targetHeight = self._lastTargetHeight;
    targetFps = self._lastTargetFps;
  }

  usingFrontCamera = !usingFrontCamera;
  AVCaptureDevicePosition position =
      usingFrontCamera ? AVCaptureDevicePositionFront : AVCaptureDevicePositionBack;
  AVCaptureDevice* videoDevice = [self findDeviceForPosition:position];
  if (videoDevice == nil) {
    NSLog(@"No capture device found for the requested position. Can't switch camera");
    result([FlutterError errorWithCode:@"Error while switching camera"
                               message:@"No capture device found"
                               details:nil]);
    return;
  }

  AVCaptureDeviceFormat* selectedFormat = [self selectFormatForDevice:videoDevice
                                                          targetWidth:targetWidth
                                                         targetHeight:targetHeight
                                                            targetFps:targetFps];
  if (selectedFormat == nil) {
    NSLog(@"No capture format found for the requested target. Can't switch camera");
    result([FlutterError errorWithCode:@"Error while switching camera"
                               message:@"No capture format found"
                               details:nil]);
    return;
  }

  NSInteger selectedFps = [self selectFpsForFormat:selectedFormat targetFps:targetFps];

  // The new device starts at its format default, so the frame-rate cap has to be
  // re-applied here. Without this a camera flip silently discards whatever cap
  // getUserMedia (or the system-pressure throttle) had put in place.
  [self applyFixedFrameRate:selectedFps toDevice:videoDevice];

  [self.videoCapturer startCaptureWithDevice:videoDevice
                                      format:selectedFormat
                                         fps:selectedFps
                           completionHandler:^(NSError* error) {
                             if (error != nil) {
                               result([FlutterError errorWithCode:@"Error while switching camera"
                                                          message:@"Error while switching camera"
                                                          details:error]);
                             } else {
                               // Update per-track state
                               if (captureState) {
                                 captureState[@"usingFrontCamera"] = @(usingFrontCamera);
                                 captureState[@"targetFps"] = @(selectedFps);
                               }
                               // Update global state for backward compatibility
                               self._usingFrontCamera = usingFrontCamera;
                               self._lastTargetFps = selectedFps;
                               result([NSNumber numberWithBool:usingFrontCamera]);
                             }
                           }];
}

- (AVCaptureDevice*)findDeviceForPosition:(AVCaptureDevicePosition)position {
  if (position == AVCaptureDevicePositionUnspecified) {
    return [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
  }
  NSArray<AVCaptureDevice*>* captureDevices = [RTCCameraVideoCapturer captureDevices];
  for (AVCaptureDevice* device in captureDevices) {
    if (device.position == position) {
      return device;
    }
  }
  if (captureDevices.count > 0) {
    return captureDevices[0];
  }
  return nil;
}

- (AVCaptureDeviceFormat*)selectFormatForDevice:(AVCaptureDevice*)device
                                    targetWidth:(NSInteger)targetWidth
                                   targetHeight:(NSInteger)targetHeight {
  return [self selectFormatForDevice:device
                         targetWidth:targetWidth
                        targetHeight:targetHeight
                           targetFps:0];
}

/// Picks the capture format to run the camera at.
///
/// Formats are ranked by how much their pixel area differs from the target, and
/// then filtered in descending order of preference:
///
///   1. preferred pixel format, area at least the target, target fps in range
///   2. area at least the target, target fps in range
///   3. area at least the target
///   4. whatever is closest in area
///
/// The "at least the target" rule matters: the previous nearest-match on
/// `|dw| + |dh|` could settle on a format *smaller* than requested, so the
/// encoder silently received less than it asked for. Considering the frame rate
/// ranges matters for thermals: iPhones expose several 1280x720 variants
/// (binned and unbinned, 30/60/240-capable), and a high-speed sensor mode
/// clocked down to 30 fps by frame duration still runs a hotter readout.
- (AVCaptureDeviceFormat*)selectFormatForDevice:(AVCaptureDevice*)device
                                    targetWidth:(NSInteger)targetWidth
                                   targetHeight:(NSInteger)targetHeight
                                      targetFps:(NSInteger)targetFps {
  if (device == nil) {
    return nil;
  }

  const int32_t targetArea = (int32_t)(targetWidth * targetHeight);
  const FourCharCode preferredPixelFormat = [self.videoCapturer preferredOutputPixelFormat];

  NSMutableArray<AVCaptureDeviceFormat*>* candidates = [NSMutableArray array];
  for (AVCaptureDeviceFormat* format in
       [RTCCameraVideoCapturer supportedFormatsForDevice:device]) {    [candidates addObject:format];
  }

  if (candidates.count == 0) {
    return nil;
  }

  [candidates sortUsingComparator:^NSComparisonResult(AVCaptureDeviceFormat* lhs,
                                                      AVCaptureDeviceFormat* rhs) {
    int32_t lhsDiff = labs(FormatArea(lhs) - targetArea);
    int32_t rhsDiff = labs(FormatArea(rhs) - targetArea);
    if (lhsDiff < rhsDiff) {
      return NSOrderedAscending;
    }
    if (lhsDiff > rhsDiff) {
      return NSOrderedDescending;
    }
    return NSOrderedSame;
  }];

  for (NSInteger tier = 0; tier < 4; tier++) {
    for (AVCaptureDeviceFormat* format in candidates) {
      const BOOL matchesPixelFormat =
          CMFormatDescriptionGetMediaSubType(format.formatDescription) == preferredPixelFormat;
      const BOOL isLargeEnough = FormatArea(format) >= targetArea;
      const BOOL supportsFps = FormatSupportsFrameRate(format, targetFps);

      switch (tier) {
        case 0:
          if (matchesPixelFormat && isLargeEnough && supportsFps) return format;
          break;
        case 1:
          if (isLargeEnough && supportsFps) return format;
          break;
        case 2:
          if (isLargeEnough) return format;
          break;
        default:
          // Sorted by area difference, so the first candidate is the closest.
          return format;
      }
    }
  }

  return candidates.firstObject;
}

/// Clamps [targetFps] into what [format] can actually deliver.
///
/// Never returns 0: the result is fed to `CMTimeMake(1, fps)`, and a timescale
/// of zero is an invalid `CMTime` that `AVCaptureDevice` accepts silently and
/// then ignores.
- (NSInteger)selectFpsForFormat:(AVCaptureDeviceFormat*)format targetFps:(NSInteger)targetFps {
  const NSInteger requestedFps = targetFps > 0 ? targetFps : kDefaultTargetFps;

  if (format == nil) {
    return requestedFps;
  }

  Float64 minSupportedFramerate = DBL_MAX;
  Float64 maxSupportedFramerate = 0;
  for (AVFrameRateRange* fpsRange in format.videoSupportedFrameRateRanges) {
    minSupportedFramerate = fmin(minSupportedFramerate, fpsRange.minFrameRate);
    maxSupportedFramerate = fmax(maxSupportedFramerate, fpsRange.maxFrameRate);
  }

  if (maxSupportedFramerate <= 0) {
    return requestedFps;
  }

  const NSInteger bounded =
      (NSInteger)fmin(maxSupportedFramerate, fmax(minSupportedFramerate, (Float64)requestedFps));
  return MAX(1, bounded);
}

/// Pins the device to a fixed frame rate.
///
/// Applied as both the min and max frame duration so the camera cannot drift up
/// under good light, which is where the extra sensor readout cost comes from.
- (void)applyFixedFrameRate:(NSInteger)fps toDevice:(AVCaptureDevice*)device {
  if (device == nil || fps <= 0) {
    return;
  }

  NSError* error = nil;
  if (![device lockForConfiguration:&error]) {
    NSLog(@"Failed to acquire configuration lock to set frame rate. %@",
          error.localizedDescription);
    return;
  }

  @try {
    CMTime duration = CMTimeMake(1, (int32_t)fps);
    device.activeVideoMinFrameDuration = duration;
    device.activeVideoMaxFrameDuration = duration;
  } @catch (NSException* exception) {
    NSLog(@"Failed to set active frame rate!\n User info:%@", exception.userInfo);
  }

  [device unlockForConfiguration];
}

@end
