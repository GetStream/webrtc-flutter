#import <Flutter/Flutter.h>
#import <StreamWebRTC/StreamWebRTC.h>

@interface FlutterRTCFrameCapturer : NSObject <RTCVideoRenderer>

- (instancetype)initWithTrack:(RTCVideoTrack*)track
                       toPath:(NSString*)path
                       result:(FlutterResult)result;

+ (CVPixelBufferRef)convertToCVPixelBuffer:(RTCVideoFrame*)frame;

@end
