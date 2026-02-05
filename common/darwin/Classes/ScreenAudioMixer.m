#if TARGET_OS_OSX

#import "ScreenAudioMixer.h"
#import "ScreenAudioCapturer.h"

#import <WebRTC/WebRTC.h>

API_AVAILABLE(macos(13.0))
@implementation ScreenAudioMixer {
  ScreenAudioCapturer* _capturer;
  float* _mixBuffer;
  NSInteger _mixBufferCapacity;
  size_t _sampleRateHz;
  size_t _channels;
}

- (instancetype)initWithCapturer:(ScreenAudioCapturer*)capturer {
  self = [super init];
  if (self) {
    _capturer = capturer;
    _mixBuffer = NULL;
    _mixBufferCapacity = 0;
    _sampleRateHz = 48000;
    _channels = 1;
  }
  return self;
}

- (void)dealloc {
  if (_mixBuffer) {
    free(_mixBuffer);
    _mixBuffer = NULL;
  }
}

#pragma mark - ExternalAudioProcessingDelegate

- (void)audioProcessingInitializeWithSampleRate:(size_t)sampleRateHz
                                       channels:(size_t)channels {
  _sampleRateHz = sampleRateHz;
  _channels = channels;
  NSLog(@"ScreenAudioMixer: Initialized with sampleRate=%zu, channels=%zu",
        sampleRateHz, channels);
}

- (void)audioProcessingProcess:(RTC_OBJC_TYPE(RTCAudioBuffer)*)audioBuffer {
  // [DBG] Checkpoint 3: Is the mixer being called?
  static int mixCallCount = 0;
  ++mixCallCount;

  if (!_capturer || !_capturer.isCapturing) {
    if (mixCallCount % 100 == 1) {
      NSLog(@"ScreenAudioMixer: [DBG] called #%d but capturer not ready (capturer=%p, isCapturing=%d)",
            mixCallCount, _capturer, _capturer ? _capturer.isCapturing : 0);
    }
    return;
  }

  NSInteger frames = audioBuffer.frames;
  NSInteger channels = audioBuffer.channels;

  if (frames <= 0 || channels <= 0) return;

  if (mixCallCount % 100 == 1) {
    NSLog(@"ScreenAudioMixer: [DBG] audioProcessingProcess called #%d, frames=%ld, channels=%ld",
          mixCallCount, (long)frames, (long)channels);
  }

  // Ensure our temporary mix buffer is large enough for mono frames.
  if (_mixBufferCapacity < frames) {
    if (_mixBuffer) free(_mixBuffer);
    _mixBuffer = (float*)calloc(frames, sizeof(float));
    _mixBufferCapacity = frames;
  }

  // Read mono system audio frames from the capturer.
  // The capturer delivers normalized float32 in [-1.0, 1.0].
  NSInteger framesRead = [_capturer readFrames:_mixBuffer count:frames];

  // [DBG] Checkpoint 4: What did we actually read, and what does the mic buffer look like?
  if (mixCallCount % 100 == 1) {
    float micSample = (frames > 0 && channels > 0) ? [audioBuffer rawBufferForChannel:0][0] : 0.0f;
    float sysSample = (framesRead > 0) ? _mixBuffer[0] : 0.0f;
    NSLog(@"ScreenAudioMixer: [DBG] framesRead=%ld, sysAudio[0]=%f, micAudio[0]=%f",
          (long)framesRead, sysSample, micSample);
  }

  if (framesRead <= 0) return;

  // Mix system audio into each channel of the RTCAudioBuffer.
  //
  // The RTCAudioBuffer stores float values in int16 range (approx -32768 to 32767),
  // as evidenced by the existing toPCMBuffer: conversion in AudioProcessingAdapter.
  // We convert our normalized [-1.0, 1.0] samples to that scale before mixing.
  for (NSInteger ch = 0; ch < channels; ch++) {
    float* channelBuffer = [audioBuffer rawBufferForChannel:(int)ch];

    for (NSInteger i = 0; i < framesRead; i++) {
      float systemSample = _mixBuffer[i] * 32767.0f;
      float mixed = channelBuffer[i] + systemSample;

      // Clip to int16 range to prevent overflow distortion.
      if (mixed > 32767.0f) {
        mixed = 32767.0f;
      } else if (mixed < -32768.0f) {
        mixed = -32768.0f;
      }

      channelBuffer[i] = mixed;
    }
  }
}

- (void)audioProcessingRelease {
  NSLog(@"ScreenAudioMixer: Released");
  if (_mixBuffer) {
    free(_mixBuffer);
    _mixBuffer = NULL;
    _mixBufferCapacity = 0;
  }
}

@end

#endif
