#if TARGET_OS_OSX

#import "ScreenAudioMixer.h"
#import "ScreenAudioCapturer.h"

#import <WebRTC/WebRTC.h>

static const size_t kCaptureSampleRate = 48000;

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
  if (!_capturer || !_capturer.isCapturing) return;

  NSInteger frames = audioBuffer.frames;
  NSInteger channels = audioBuffer.channels;

  if (frames <= 0 || channels <= 0) return;

  // The ring buffer stores audio at kCaptureSampleRate (48kHz). WebRTC asks for
  // `frames` samples at _sampleRateHz. Read the number of 48kHz frames that
  // cover the same time duration, then resample down to the WebRTC frame count.
  NSInteger captureFrames = (NSInteger)((int64_t)frames * kCaptureSampleRate / _sampleRateHz);
  if (captureFrames <= 0) return;

  if (_mixBufferCapacity < captureFrames) {
    if (_mixBuffer) free(_mixBuffer);
    _mixBuffer = (float*)calloc(captureFrames, sizeof(float));
    _mixBufferCapacity = captureFrames;
  }

  NSInteger framesRead = [_capturer readFrames:_mixBuffer count:captureFrames];
  if (framesRead <= 0) return;

  // Resample from capture rate to WebRTC rate via linear interpolation, then mix.
  // The RTCAudioBuffer stores float values in int16 range (approx -32768 to 32767).
  double step = (double)framesRead / (double)frames;

  for (NSInteger ch = 0; ch < channels; ch++) {
    float* channelBuffer = [audioBuffer rawBufferForChannel:(int)ch];

    for (NSInteger i = 0; i < frames; i++) {
      double srcPos = i * step;
      NSInteger idx = (NSInteger)srcPos;
      float frac = (float)(srcPos - idx);
      float s0 = _mixBuffer[idx];
      float s1 = (idx + 1 < framesRead) ? _mixBuffer[idx + 1] : s0;
      float resampled = s0 + frac * (s1 - s0);

      float systemSample = resampled * 32767.0f;
      float mixed = channelBuffer[i] + systemSample;

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
