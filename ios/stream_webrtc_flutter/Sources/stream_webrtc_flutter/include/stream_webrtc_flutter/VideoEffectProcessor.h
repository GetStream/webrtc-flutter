#if TARGET_OS_IPHONE
#import <StreamWebRTC/RTCVideoSource.h>
#elif TARGET_OS_MAC
#import <WebRTC/RTCVideoSource.h>
#endif

#import "VideoFrameProcessor.h"

@interface VideoEffectProcessor : NSObject <RTCVideoCapturerDelegate>

@property(nonatomic, strong) NSArray<NSObject<VideoFrameProcessorDelegate>*>* videoFrameProcessors;
@property(nonatomic, strong) RTCVideoSource* videoSource;

- (instancetype)initWithProcessors:
                    (NSArray<NSObject<VideoFrameProcessorDelegate>*>*)videoFrameProcessors
                       videoSource:(RTCVideoSource*)videoSource;

@end