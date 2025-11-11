#if TARGET_OS_IPHONE
#import <StreamWebRTC/StreamWebRTC.h>
#elif TARGET_OS_MAC
#import <WebRTC/WebRTC.h>
#endif

#if TARGET_OS_IPHONE
#import <Flutter/Flutter.h>
#elif TARGET_OS_OSX
#import <FlutterMacOS/FlutterMacOS.h>
#endif

@interface FlutterRTCFrameCapturer : NSObject <RTCVideoRenderer>

- (instancetype)initWithTrack:(RTCVideoTrack*)track
                       toPath:(NSString*)path
                       result:(FlutterResult)result;

+ (CVPixelBufferRef)convertToCVPixelBuffer:(RTCVideoFrame*)frame;

@end
