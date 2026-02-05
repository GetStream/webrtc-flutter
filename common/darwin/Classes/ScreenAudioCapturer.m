#if TARGET_OS_OSX

#import "ScreenAudioCapturer.h"

#import <ScreenCaptureKit/ScreenCaptureKit.h>
#import <CoreMedia/CoreMedia.h>
#import <os/lock.h>

/// Ring buffer capacity: 2 seconds of audio at 48kHz mono.
static const NSInteger kRingBufferCapacityFrames = 48000 * 2;

/// Target sample rate to request from ScreenCaptureKit.
static const NSInteger kTargetSampleRate = 48000;

/// Target channel count (mono) to request from ScreenCaptureKit.
static const NSInteger kTargetChannelCount = 1;

API_AVAILABLE(macos(13.0))
@interface ScreenAudioCapturer () <SCStreamDelegate, SCStreamOutput>
@end

API_AVAILABLE(macos(13.0))
@implementation ScreenAudioCapturer {
  SCStream* _stream;
  dispatch_queue_t _audioQueue;

  // Ring buffer storing mono float32 samples normalized to [-1.0, 1.0].
  float* _ringBuffer;
  NSInteger _ringBufferCapacity;
  NSInteger _writePos;
  NSInteger _availableFrames;
  os_unfair_lock _lock;

  BOOL _isCapturing;
}

- (instancetype)init {
  self = [super init];
  if (self) {
    _audioQueue = dispatch_queue_create("io.getstream.webrtc.screenAudioCapture",
                                        DISPATCH_QUEUE_SERIAL);
    _ringBufferCapacity = kRingBufferCapacityFrames;
    _ringBuffer = (float*)calloc(_ringBufferCapacity, sizeof(float));
    _writePos = 0;
    _availableFrames = 0;
    _lock = OS_UNFAIR_LOCK_INIT;
    _isCapturing = NO;
  }
  return self;
}

- (void)dealloc {
  [self stopCapture];
  if (_ringBuffer) {
    free(_ringBuffer);
    _ringBuffer = NULL;
  }
}

- (BOOL)isCapturing {
  return _isCapturing;
}

- (void)startCaptureWithExcludeCurrentProcess:(BOOL)excludeCurrentProcess {
  if (_isCapturing) {
    NSLog(@"ScreenAudioCapturer: Already capturing");
    return;
  }

  __weak typeof(self) weakSelf = self;

  [SCShareableContent getShareableContentWithCompletionHandler:^(SCShareableContent* content,
                                                                  NSError* error) {
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (!strongSelf) return;

    if (error) {
      NSLog(@"ScreenAudioCapturer: Failed to get shareable content: %@", error);
      return;
    }

    SCDisplay* mainDisplay = content.displays.firstObject;
    if (!mainDisplay) {
      NSLog(@"ScreenAudioCapturer: No display found");
      return;
    }

    SCContentFilter* filter =
        [[SCContentFilter alloc] initWithDisplay:mainDisplay
                           excludingApplications:@[]
                                exceptingWindows:@[]];

    SCStreamConfiguration* config = [[SCStreamConfiguration alloc] init];

    // Enable audio capture.
    config.capturesAudio = YES;
    config.excludesCurrentProcessAudio = excludeCurrentProcess;
    config.sampleRate = kTargetSampleRate;
    config.channelCount = kTargetChannelCount;

    // Minimal video configuration to reduce overhead.
    // ScreenCaptureKit requires video; we configure it to be as cheap as possible.
    config.width = 2;
    config.height = 2;
    config.minimumFrameInterval = CMTimeMake(1, 1);  // 1 FPS
    config.showsCursor = NO;

    strongSelf->_stream = [[SCStream alloc] initWithFilter:filter
                                             configuration:config
                                                  delegate:strongSelf];

    NSError* addOutputError = nil;
    [strongSelf->_stream addStreamOutput:strongSelf
                                    type:SCStreamOutputTypeAudio
                      sampleHandlerQueue:strongSelf->_audioQueue
                                   error:&addOutputError];
    if (addOutputError) {
      NSLog(@"ScreenAudioCapturer: Failed to add audio output: %@", addOutputError);
      strongSelf->_stream = nil;
      return;
    }

    [strongSelf->_stream startCaptureWithCompletionHandler:^(NSError* startError) {
      __strong typeof(weakSelf) innerSelf = weakSelf;
      if (!innerSelf) return;

      if (startError) {
        NSLog(@"ScreenAudioCapturer: Failed to start capture: %@", startError);
        innerSelf->_stream = nil;
        return;
      }
      NSLog(@"ScreenAudioCapturer: Started system audio capture");
      innerSelf->_isCapturing = YES;
    }];
  }];
}

- (void)stopCapture {
  if (!_isCapturing && !_stream) return;
  _isCapturing = NO;

  if (_stream) {
    [_stream stopCaptureWithCompletionHandler:^(NSError* error) {
      if (error) {
        NSLog(@"ScreenAudioCapturer: Error stopping capture: %@", error);
      } else {
        NSLog(@"ScreenAudioCapturer: Stopped system audio capture");
      }
    }];
    _stream = nil;
  }

  // Clear the ring buffer.
  os_unfair_lock_lock(&_lock);
  _writePos = 0;
  _availableFrames = 0;
  memset(_ringBuffer, 0, _ringBufferCapacity * sizeof(float));
  os_unfair_lock_unlock(&_lock);
}

- (NSInteger)readFrames:(float*)buffer count:(NSInteger)frameCount {
  if (!_isCapturing || frameCount <= 0) return 0;

  os_unfair_lock_lock(&_lock);

  if (_availableFrames <= 0) {
    os_unfair_lock_unlock(&_lock);
    return 0;
  }

  NSInteger framesToRead = MIN(frameCount, _availableFrames);

  // Calculate read position (oldest data first).
  NSInteger readPos = _writePos - _availableFrames;
  if (readPos < 0) readPos += _ringBufferCapacity;

  for (NSInteger i = 0; i < framesToRead; i++) {
    buffer[i] = _ringBuffer[(readPos + i) % _ringBufferCapacity];
  }

  _availableFrames -= framesToRead;

  os_unfair_lock_unlock(&_lock);
  return framesToRead;
}

#pragma mark - SCStreamOutput

- (void)stream:(SCStream*)stream
    didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
                   ofType:(SCStreamOutputType)type {
  if (type != SCStreamOutputTypeAudio) return;
  if (!CMSampleBufferIsValid(sampleBuffer)) return;
  if (!_isCapturing) return;

  CMFormatDescriptionRef formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer);
  if (!formatDesc) return;

  const AudioStreamBasicDescription* asbd =
      CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc);
  if (!asbd) return;

  NSInteger channelCount = asbd->mChannelsPerFrame;
  BOOL isFloat = (asbd->mFormatFlags & kAudioFormatFlagIsFloat) != 0;
  BOOL isNonInterleaved = (asbd->mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0;
  NSInteger frameCount = (NSInteger)CMSampleBufferGetNumSamples(sampleBuffer);

  if (frameCount <= 0) return;

  // Get the audio buffer list from the sample buffer.
  size_t bufferListSizeNeeded = 0;
  CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
      sampleBuffer, &bufferListSizeNeeded, NULL, 0, NULL, NULL, 0, NULL);

  AudioBufferList* abl = (AudioBufferList*)malloc(bufferListSizeNeeded);
  CMBlockBufferRef retainedBlockBuffer = NULL;

  OSStatus status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
      sampleBuffer, NULL, abl, bufferListSizeNeeded, NULL, NULL,
      kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment, &retainedBlockBuffer);

  if (status != noErr) {
    free(abl);
    if (retainedBlockBuffer) CFRelease(retainedBlockBuffer);
    return;
  }

  os_unfair_lock_lock(&_lock);

  if (isFloat && isNonInterleaved) {
    // Non-interleaved float32: each channel in a separate buffer.
    // Downmix to mono by averaging channels.
    for (NSInteger f = 0; f < frameCount; f++) {
      float sum = 0;
      for (UInt32 ch = 0; ch < abl->mNumberBuffers && ch < (UInt32)channelCount; ch++) {
        float* channelData = (float*)abl->mBuffers[ch].mData;
        sum += channelData[f];
      }
      float monoSample = sum / (float)channelCount;
      _ringBuffer[_writePos] = monoSample;
      _writePos = (_writePos + 1) % _ringBufferCapacity;
    }
  } else if (isFloat) {
    // Interleaved float32: channels interleaved in a single buffer.
    float* data = (float*)abl->mBuffers[0].mData;
    for (NSInteger f = 0; f < frameCount; f++) {
      float sum = 0;
      for (NSInteger ch = 0; ch < channelCount; ch++) {
        sum += data[f * channelCount + ch];
      }
      float monoSample = sum / (float)channelCount;
      _ringBuffer[_writePos] = monoSample;
      _writePos = (_writePos + 1) % _ringBufferCapacity;
    }
  } else {
    // Integer format (assume 16-bit signed PCM interleaved).
    int16_t* data = (int16_t*)abl->mBuffers[0].mData;
    for (NSInteger f = 0; f < frameCount; f++) {
      float sum = 0;
      for (NSInteger ch = 0; ch < channelCount; ch++) {
        sum += data[f * channelCount + ch] / 32768.0f;
      }
      float monoSample = sum / (float)channelCount;
      _ringBuffer[_writePos] = monoSample;
      _writePos = (_writePos + 1) % _ringBufferCapacity;
    }
  }

  _availableFrames += frameCount;
  if (_availableFrames > _ringBufferCapacity) {
    _availableFrames = _ringBufferCapacity;
  }

  os_unfair_lock_unlock(&_lock);

  free(abl);
  if (retainedBlockBuffer) CFRelease(retainedBlockBuffer);
}

#pragma mark - SCStreamDelegate

- (void)stream:(SCStream*)stream didStopWithError:(NSError*)error {
  NSLog(@"ScreenAudioCapturer: Stream stopped with error: %@", error);
  _isCapturing = NO;
}

@end

#endif
