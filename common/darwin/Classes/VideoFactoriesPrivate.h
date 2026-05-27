#import <Foundation/Foundation.h>

#if TARGET_OS_IPHONE
#import <StreamWebRTC/StreamWebRTC.h>
#elif TARGET_OS_MAC
#import <WebRTC/WebRTC.h>
#endif

NS_ASSUME_NONNULL_BEGIN

@interface VideoEncoderFactory : RTCDefaultVideoEncoderFactory
@end

@interface VideoDecoderFactory : RTCDefaultVideoDecoderFactory
@end

@interface VideoEncoderFactorySimulcast : RTCVideoEncoderFactorySimulcast
@end

NS_ASSUME_NONNULL_END
