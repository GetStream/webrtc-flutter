#import "NativePeerConnectionFactory.h"
#import "AudioUtils.h"
#import "VideoFactoriesPrivate.h"

#if TARGET_OS_IPHONE
#import <StreamWebRTC/StreamWebRTC.h>
#elif TARGET_OS_MAC
#import <WebRTC/WebRTC.h>
#endif

@implementation NativePeerConnectionFactory {
  RTCPeerConnectionFactory* _factory;
  RTCAudioDeviceModule* _audioDeviceModule;
  BOOL _disposed;
}

- (instancetype)initWithFactoryId:(NSString*)factoryId
            bypassVoiceProcessing:(BOOL)bypassVoiceProcessing
                networkIgnoreMask:(NSArray<NSString*>*)networkIgnoreMask
            audioProcessingModule:(RTCDefaultAudioProcessingModule*)apm
          appleAudioConfiguration:(NSDictionary*)appleAudioConfiguration
                      admObserver:(id<RTCAudioDeviceModuleDelegate>)admObserver {
  if (self = [super init]) {
    _factoryId = [factoryId copy];
    _bypassVoiceProcessing = bypassVoiceProcessing;
    _audioConfigSnapshot = [appleAudioConfiguration copy];
    _ownedPcIds = [NSMutableSet new];
    _ownedTrackIds = [NSMutableSet new];
    _ownedStreamIds = [NSMutableSet new];
    _disposed = NO;

    if (appleAudioConfiguration != nil) {
      [AudioUtils setAppleAudioConfiguration:appleAudioConfiguration];
    }

    VideoDecoderFactory* decoderFactory = [[VideoDecoderFactory alloc] init];
    VideoEncoderFactory* encoderFactory = [[VideoEncoderFactory alloc] init];
    VideoEncoderFactorySimulcast* simulcastFactory =
        [[VideoEncoderFactorySimulcast alloc] initWithPrimary:encoderFactory
                                                     fallback:encoderFactory];

    _factory = [[RTCPeerConnectionFactory alloc]
        initWithAudioDeviceModuleType:RTCAudioDeviceModuleTypeAudioEngine
                bypassVoiceProcessing:bypassVoiceProcessing
                       encoderFactory:simulcastFactory
                       decoderFactory:decoderFactory
                audioProcessingModule:apm];

    RTCPeerConnectionFactoryOptions* options = [[RTCPeerConnectionFactoryOptions alloc] init];
    for (NSString* adapter in networkIgnoreMask) {
      if ([@"adapterTypeEthernet" isEqualToString:adapter]) {
        options.ignoreEthernetNetworkAdapter = YES;
      } else if ([@"adapterTypeWifi" isEqualToString:adapter]) {
        options.ignoreWiFiNetworkAdapter = YES;
      } else if ([@"adapterTypeCellular" isEqualToString:adapter]) {
        options.ignoreCellularNetworkAdapter = YES;
      } else if ([@"adapterTypeVpn" isEqualToString:adapter]) {
        options.ignoreVPNNetworkAdapter = YES;
      } else if ([@"adapterTypeLoopback" isEqualToString:adapter]) {
        options.ignoreLoopbackNetworkAdapter = YES;
      } else if ([@"adapterTypeAny" isEqualToString:adapter]) {
        options.ignoreEthernetNetworkAdapter = YES;
        options.ignoreWiFiNetworkAdapter = YES;
        options.ignoreCellularNetworkAdapter = YES;
        options.ignoreVPNNetworkAdapter = YES;
        options.ignoreLoopbackNetworkAdapter = YES;
      }
    }
    [_factory setOptions:options];

    _audioDeviceModule = _factory.audioDeviceModule;
    if (admObserver != nil) {
      _audioDeviceModule.observer = admObserver;
    }

    NSLog(@"[NativePeerConnectionFactory] built id: %@ bypass: %d", factoryId,
          bypassVoiceProcessing);
  }
  return self;
}

- (void)dispose {
  if (_disposed) {
    return;
  }
  _disposed = YES;

  // Order matters: drop our reference to the ADM first so any in-flight
  // access through that handle stops before the factory destructor runs.
  if (_audioDeviceModule != nil) {
    _audioDeviceModule.observer = nil;
    _audioDeviceModule = nil;
  }
  _factory = nil;

  NSLog(@"[NativePeerConnectionFactory] disposed id: %@", _factoryId);
}

- (BOOL)isDisposed {
  return _disposed;
}

@end
