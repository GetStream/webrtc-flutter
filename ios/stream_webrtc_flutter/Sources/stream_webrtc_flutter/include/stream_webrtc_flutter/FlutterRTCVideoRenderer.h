#import "FlutterWebRTCPlugin.h"

#import <StreamWebRTC/RTCMediaStream.h>
#import <StreamWebRTC/RTCVideoFrame.h>
#import <StreamWebRTC/RTCVideoRenderer.h>
#import <StreamWebRTC/RTCVideoTrack.h>

@interface FlutterRTCVideoRenderer
    : NSObject <FlutterTexture, RTCVideoRenderer, FlutterStreamHandler>

/**
 * The {@link RTCVideoTrack}, if any, which this instance renders.
 */
@property(nonatomic, strong) RTCVideoTrack* videoTrack;
@property(nonatomic) int64_t textureId;
@property(nonatomic, weak) id<FlutterTextureRegistry> registry;
@property(nonatomic, strong) FlutterEventSink eventSink;

- (instancetype)initWithTextureRegistry:(id<FlutterTextureRegistry>)registry
                              messenger:(NSObject<FlutterBinaryMessenger>*)messenger;

- (void)dispose;

@end

@interface FlutterWebRTCPlugin (FlutterVideoRendererManager)

- (FlutterRTCVideoRenderer*)createWithTextureRegistry:(id<FlutterTextureRegistry>)registry
                                            messenger:(NSObject<FlutterBinaryMessenger>*)messenger;

- (void)rendererSetSrcObject:(FlutterRTCVideoRenderer*)renderer stream:(RTCVideoTrack*)videoTrack;

@end
