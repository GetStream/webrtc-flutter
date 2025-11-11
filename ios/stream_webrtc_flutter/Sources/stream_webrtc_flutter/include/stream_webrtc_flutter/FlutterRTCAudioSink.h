#import <CoreMedia/CoreMedia.h>
#import <Foundation/Foundation.h>
#if TARGET_OS_IPHONE
#import <StreamWebRTC/StreamWebRTC.h>
#elif TARGET_OS_MAC
#import <WebRTC/WebRTC.h>
#endif

@interface FlutterRTCAudioSink : NSObject

@property(nonatomic, copy) void (^bufferCallback)(CMSampleBufferRef);
@property(nonatomic) CMAudioFormatDescriptionRef format;

- (instancetype)initWithAudioTrack:(RTCAudioTrack*)audio;

- (void)close;

@end
