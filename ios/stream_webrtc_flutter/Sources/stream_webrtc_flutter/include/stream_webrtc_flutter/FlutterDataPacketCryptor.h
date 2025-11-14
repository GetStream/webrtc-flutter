#import <Flutter/Flutter.h>
#import <StreamWebRTC/StreamWebRTC.h>

#import "FlutterWebRTCPlugin.h"

@interface FlutterWebRTCPlugin (DataPacketCryptor)

- (void)handleDataPacketCryptorMethodCall:(nonnull FlutterMethodCall*)call
                                   result:(nonnull FlutterResult)result;

@end
