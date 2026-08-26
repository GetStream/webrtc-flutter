#import "include/stream_webrtc_flutter/CameraSystemPressureObserver.h"

#if TARGET_OS_IPHONE

/// Frame-rate ceilings per pressure level, and how long to wait before acting.
///
/// Values match `CameraSystemPressureHandler` in `stream-video-swift`.
static const NSInteger kFairMaxFps = 24;
static const NSInteger kSeriousMaxFps = 15;
static const NSInteger kCriticalMaxFps = 10;
static const NSInteger kShutdownMaxFps = 5;

static const NSTimeInterval kDowngradeDelay = 3.0;
static const NSTimeInterval kCriticalDowngradeDelay = 1.0;
static const NSTimeInterval kUpgradeDelay = 10.0;

/// Resolution tiers. Higher is worse.
typedef NS_ENUM(NSInteger, CameraQualityTier) {
  CameraQualityTierBase = 0,    // x1.0
  CameraQualityTierMedium = 1,  // x0.75
  CameraQualityTierLow = 2,     // x0.5
};

static NSString* PressureLevelName(AVCaptureSystemPressureLevel level) {
  if ([level isEqualToString:AVCaptureSystemPressureLevelNominal]) return @"nominal";
  if ([level isEqualToString:AVCaptureSystemPressureLevelFair]) return @"fair";
  if ([level isEqualToString:AVCaptureSystemPressureLevelSerious]) return @"serious";
  if ([level isEqualToString:AVCaptureSystemPressureLevelCritical]) return @"critical";
  if ([level isEqualToString:AVCaptureSystemPressureLevelShutdown]) return @"shutdown";
  return @"unknown";
}

static void* kSystemPressureContext = &kSystemPressureContext;

@implementation CameraSystemPressureObserver {
  AVCaptureDevice* _observedDevice;
  AVCaptureSystemPressureLevel _currentLevel;
  CameraQualityTier _currentTier;

  NSInteger _baselineWidth;
  NSInteger _baselineHeight;
  NSInteger _baselineFps;

  /// Last configuration actually handed to the delegate, so an unchanged tier
  /// does not churn the capture session.
  NSInteger _appliedWidth;
  NSInteger _appliedHeight;
  NSInteger _appliedFps;

  dispatch_block_t _pendingTransition;
}

- (instancetype)init {
  self = [super init];
  if (self) {
    _currentLevel = AVCaptureSystemPressureLevelNominal;
    _currentTier = CameraQualityTierBase;
  }
  return self;
}

- (void)dealloc {
  [self stop];
}

- (NSString*)currentPressureLevel {
  return PressureLevelName(_currentLevel);
}

#pragma mark - Lifecycle

- (void)startObservingDevice:(AVCaptureDevice*)device
               baselineWidth:(NSInteger)baselineWidth
              baselineHeight:(NSInteger)baselineHeight
                 baselineFps:(NSInteger)baselineFps {
  if (device == nil) {
    return;
  }

  [self detachFromDevice];

  _baselineWidth = baselineWidth;
  _baselineHeight = baselineHeight;
  _baselineFps = baselineFps;

  // The new device starts at its own configuration, so forget what we applied
  // to the old one — the first event must re-apply unconditionally.
  _appliedWidth = 0;
  _appliedHeight = 0;
  _appliedFps = 0;
  _currentTier = CameraQualityTierBase;

  _observedDevice = device;
  [device addObserver:self
           forKeyPath:@"systemPressureState"
              options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew
              context:kSystemPressureContext];
}

- (void)updateBaselineWidth:(NSInteger)baselineWidth
                     height:(NSInteger)baselineHeight
                        fps:(NSInteger)baselineFps {
  _baselineWidth = baselineWidth;
  _baselineHeight = baselineHeight;
  _baselineFps = baselineFps;
  _appliedWidth = baselineWidth;
  _appliedHeight = baselineHeight;
  _appliedFps = baselineFps;
}

- (void)stop {
  [self cancelPendingTransition];
  [self detachFromDevice];
}

- (void)detachFromDevice {
  if (_observedDevice == nil) {
    return;
  }
  @try {
    [_observedDevice removeObserver:self
                         forKeyPath:@"systemPressureState"
                            context:kSystemPressureContext];
  } @catch (NSException* exception) {
    // Not registered — nothing to do.
  }
  _observedDevice = nil;
}

#pragma mark - KVO

- (void)observeValueForKeyPath:(NSString*)keyPath
                      ofObject:(id)object
                        change:(NSDictionary*)change
                       context:(void*)context {
  if (context != kSystemPressureContext) {
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    return;
  }

  AVCaptureDevice* device = _observedDevice;
  if (device == nil) {
    return;
  }

  AVCaptureSystemPressureLevel level = device.systemPressureState.level;
  dispatch_async(dispatch_get_main_queue(), ^{
    [self handlePressureLevel:level];
  });
}

- (void)handlePressureLevel:(AVCaptureSystemPressureLevel)level {
  _currentLevel = level;

  const CameraQualityTier targetTier = [self tierForLevel:level];

  // Always drop a pending transition: pressure may have recovered before the
  // scheduled downgrade fired, and applying it then would be a step backwards.
  [self cancelPendingTransition];

  // The frame-rate cap follows the level directly rather than the tier, so a
  // nominal -> fair transition still takes effect even though both map to the
  // base resolution tier.
  if (targetTier == _currentTier) {
    [self applyCurrentConfiguration];
    return;
  }

  const NSTimeInterval delay = [self delayForTransitionToTier:targetTier];

  __weak typeof(self) weakSelf = self;
  dispatch_block_t transition = dispatch_block_create(0, ^{
    typeof(self) strongSelf = weakSelf;
    if (strongSelf == nil) {
      return;
    }
    strongSelf->_currentTier = targetTier;
    [strongSelf applyCurrentConfiguration];
  });

  _pendingTransition = transition;
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                 dispatch_get_main_queue(), transition);
}

- (void)cancelPendingTransition {
  if (_pendingTransition != nil) {
    dispatch_block_cancel(_pendingTransition);
    _pendingTransition = nil;
  }
}

#pragma mark - Policy

- (CameraQualityTier)tierForLevel:(AVCaptureSystemPressureLevel)level {
  if ([level isEqualToString:AVCaptureSystemPressureLevelSerious]) {
    return CameraQualityTierMedium;
  }
  if ([level isEqualToString:AVCaptureSystemPressureLevelCritical] ||
      [level isEqualToString:AVCaptureSystemPressureLevelShutdown]) {
    return CameraQualityTierLow;
  }
  return CameraQualityTierBase;
}

- (NSInteger)targetFpsForLevel:(AVCaptureSystemPressureLevel)level {
  if ([level isEqualToString:AVCaptureSystemPressureLevelFair]) {
    return MIN(_baselineFps, kFairMaxFps);
  }
  if ([level isEqualToString:AVCaptureSystemPressureLevelSerious]) {
    return MIN(_baselineFps, kSeriousMaxFps);
  }
  if ([level isEqualToString:AVCaptureSystemPressureLevelCritical]) {
    return MIN(_baselineFps, kCriticalMaxFps);
  }
  if ([level isEqualToString:AVCaptureSystemPressureLevelShutdown]) {
    return MIN(_baselineFps, kShutdownMaxFps);
  }
  return _baselineFps;
}

- (NSTimeInterval)delayForTransitionToTier:(CameraQualityTier)targetTier {
  if (targetTier > _currentTier) {
    // Getting worse. Under critical pressure the wait is itself a cost.
    if ([_currentLevel isEqualToString:AVCaptureSystemPressureLevelCritical] ||
        [_currentLevel isEqualToString:AVCaptureSystemPressureLevelShutdown]) {
      return kCriticalDowngradeDelay;
    }
    return kDowngradeDelay;
  }
  // Recovering. Wait longer, so a brief dip does not immediately undo a
  // step-down that is still doing its job.
  return kUpgradeDelay;
}

- (void)applyCurrentConfiguration {
  if (_baselineWidth <= 0 || _baselineHeight <= 0) {
    return;
  }

  double scale;
  switch (_currentTier) {
    case CameraQualityTierMedium:
      scale = 0.75;
      break;
    case CameraQualityTierLow:
      scale = 0.5;
      break;
    case CameraQualityTierBase:
    default:
      scale = 1.0;
      break;
  }

  // Encoders want even dimensions.
  NSInteger width = MAX(2, ((NSInteger)(_baselineWidth * scale)) & ~1);
  NSInteger height = MAX(2, ((NSInteger)(_baselineHeight * scale)) & ~1);
  NSInteger fps = MAX(1, [self targetFpsForLevel:_currentLevel]);

  if (width == _appliedWidth && height == _appliedHeight && fps == _appliedFps) {
    return;
  }

  _appliedWidth = width;
  _appliedHeight = height;
  _appliedFps = fps;

  [self.delegate systemPressureRequestsCaptureWidth:width
                                             height:height
                                                fps:fps
                                      pressureLevel:PressureLevelName(_currentLevel)];
}

@end

#endif
