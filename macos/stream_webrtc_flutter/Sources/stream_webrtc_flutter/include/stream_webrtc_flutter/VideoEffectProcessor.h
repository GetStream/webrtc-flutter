#import <StreamWebRTC/RTCVideoSource.h>
#import "VideoFrameProcessor.h"
#import "VideoProcessingAdapter.h"

@interface VideoEffectProcessor : NSObject <RTCVideoCapturerDelegate, ExternalVideoProcessingDelegate>

@property(nonatomic, strong) NSArray<NSObject<VideoFrameProcessorDelegate>*>* videoFrameProcessors;
@property(nonatomic, strong) RTCVideoSource* videoSource;

- (instancetype)initWithProcessors:
                    (NSArray<NSObject<VideoFrameProcessorDelegate>*>*)videoFrameProcessors
                       videoSource:(RTCVideoSource*)videoSource;

@end