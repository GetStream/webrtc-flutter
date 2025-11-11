#ifdef __cplusplus
#if TARGET_OS_IPHONE
#import "StreamWebRTC/RTCAudioSource.h"
#elif TARGET_OS_MAC
#import "WebRTC/RTCAudioSource.h"
#endif
#include "media_stream_interface.h"

@interface RTCAudioSource ()

/**
 * The AudioSourceInterface object passed to this RTCAudioSource during
 * construction.
 */
@property(nonatomic, readonly) rtc::scoped_refptr<webrtc::AudioSourceInterface> nativeAudioSource;

@end
#endif
