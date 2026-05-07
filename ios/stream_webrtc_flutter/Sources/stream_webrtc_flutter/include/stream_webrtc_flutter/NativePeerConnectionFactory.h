#import <Foundation/Foundation.h>
#import <StreamWebRTC/StreamWebRTC.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Encapsulates a per-call RTCPeerConnectionFactory together with the
 * RTCAudioDeviceModule it owns.
 */
@interface NativePeerConnectionFactory : NSObject

/** Id used by Dart-side callers to address this factory. */
@property(nonatomic, copy, readonly) NSString* factoryId;

/** The factory that builds peer connections + tracks. */
@property(nonatomic, strong, readonly, nullable) RTCPeerConnectionFactory* factory;

/**
 * The factory's own ADM. Not owned by this class — the underlying factory owns it.
 */
@property(nonatomic, strong, readonly, nullable) RTCAudioDeviceModule* audioDeviceModule;

/** Snapshot of the appleAudioConfiguration used to build this factory. */
@property(nonatomic, copy, readonly, nullable) NSDictionary* audioConfigSnapshot;

/** Whether voice-processing was bypassed at build time. */
@property(nonatomic, assign, readonly) BOOL bypassVoiceProcessing;

/**
 * Peer-connection ids whose PC was created against this factory.
 */
@property(nonatomic, strong, readonly) NSMutableSet<NSString*>* ownedPcIds;

@property(nonatomic, assign, readonly) BOOL isDisposed;

- (instancetype)initWithFactoryId:(NSString*)factoryId
            bypassVoiceProcessing:(BOOL)bypassVoiceProcessing
                networkIgnoreMask:(NSArray<NSString*>*)networkIgnoreMask
            audioProcessingModule:(RTCDefaultAudioProcessingModule*)apm
          appleAudioConfiguration:(nullable NSDictionary*)appleAudioConfiguration
                      admObserver:(nullable id<RTCAudioDeviceModuleDelegate>)admObserver;

/**
 * Releases the factory and its ADM.
 */
- (void)dispose;

@end

NS_ASSUME_NONNULL_END
