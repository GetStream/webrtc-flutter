#import <Foundation/Foundation.h>
#if TARGET_OS_IPHONE
#import <StreamWebRTC/StreamWebRTC.h>
#elif TARGET_OS_MAC
#import <WebRTC/WebRTC.h>
#endif
#import "AudioProcessingAdapter.h"

@interface AudioManager : NSObject

@property(nonatomic, strong) RTCDefaultAudioProcessingModule* _Nonnull audioProcessingModule;

@property(nonatomic, strong) AudioProcessingAdapter* _Nonnull capturePostProcessingAdapter;

@property(nonatomic, strong) AudioProcessingAdapter* _Nonnull renderPreProcessingAdapter;

+ (_Nonnull instancetype)sharedInstance;

- (void)addLocalAudioRenderer:(nonnull id<RTCAudioRenderer>)renderer;

- (void)removeLocalAudioRenderer:(nonnull id<RTCAudioRenderer>)renderer;

@end
