#if TARGET_OS_IPHONE
#import <StreamWebRTC/StreamWebRTC.h>
#elif TARGET_OS_MAC
#import <WebRTC/WebRTC.h>
#endif
#import "AudioProcessingAdapter.h"
#import "LocalTrack.h"

@interface LocalAudioTrack : NSObject <LocalTrack>

- (_Nonnull instancetype)initWithTrack:(RTCAudioTrack* _Nonnull)track;

@property(nonatomic, strong) RTCAudioTrack* _Nonnull audioTrack;

- (void)addRenderer:(_Nonnull id<RTC_OBJC_TYPE(RTCAudioRenderer)>)renderer;

- (void)removeRenderer:(_Nonnull id<RTC_OBJC_TYPE(RTCAudioRenderer)>)renderer;

- (void)addProcessing:(_Nonnull id<ExternalAudioProcessingDelegate>)processor;

- (void)removeProcessing:(_Nonnull id<ExternalAudioProcessingDelegate>)processor;

@end
