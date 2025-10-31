#import "VideoEffectProcessor.h"
#if TARGET_OS_IPHONE
#import <StreamWebRTC/RTCVideoCapturer.h>
#elif TARGET_OS_MAC
#import <WebRTC/RTCVideoCapturer.h>
#endif

@implementation VideoEffectProcessor
- (instancetype)initWithProcessors:
                    (NSArray<NSObject<VideoFrameProcessorDelegate>*>*)videoFrameProcessors
                       videoSource:(RTCVideoSource*)videoSource {
  self = [super init];
  _videoFrameProcessors = videoFrameProcessors;
  _videoSource = videoSource;
  return self;
}
- (void)capturer:(nonnull RTCVideoCapturer*)capturer
    didCaptureVideoFrame:(nonnull RTCVideoFrame*)frame {
  RTCVideoFrame* processedFrame = frame;
  for (NSObject<VideoFrameProcessorDelegate>* processor in _videoFrameProcessors) {
    processedFrame = [processor capturer:capturer didCaptureVideoFrame:processedFrame];
  }
  [self.videoSource capturer:capturer didCaptureVideoFrame:processedFrame];
}
@end