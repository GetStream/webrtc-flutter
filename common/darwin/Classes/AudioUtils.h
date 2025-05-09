#if TARGET_OS_IPHONE

#import <StreamWebRTC/StreamWebRTC.h>

@interface AudioUtils : NSObject
+ (void)ensureAudioSessionWithRecording:(BOOL)recording;
// needed for wired headphones to use headphone mic
+ (BOOL)selectAudioInput:(AVAudioSessionPort)type;
+ (void)setSpeakerphoneOn:(BOOL)enable;
+ (void)setSpeakerphoneOnButPreferBluetooth;
+ (void)deactiveRtcAudioSession;
+ (void) setAppleAudioConfiguration:(NSDictionary*)configuration;
@end

#endif
