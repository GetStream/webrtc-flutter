
#if TARGET_OS_IPHONE
#import <StreamWebRTC/RTCVideoCapturer.h>
#import <StreamWebRTC/RTCVideoFrame.h>
#elif TARGET_OS_MAC
#import <WebRTC/RTCVideoCapturer.h>
#import <WebRTC/RTCVideoFrame.h>
#endif

@protocol VideoFrameProcessorDelegate
- (RTCVideoFrame*)capturer:(RTCVideoCapturer*)capturer didCaptureVideoFrame:(RTCVideoFrame*)frame;
@end