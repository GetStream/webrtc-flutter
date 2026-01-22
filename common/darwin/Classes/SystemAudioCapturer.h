#import <Foundation/Foundation.h>
#import <ScreenCaptureKit/ScreenCaptureKit.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

API_AVAILABLE(macos(13.0))
@protocol SystemAudioCapturerDelegate <NSObject>
- (void)systemAudioCapturer:(id)capturer didCaptureAudioBuffer:(CMSampleBufferRef)sampleBuffer;
@end

API_AVAILABLE(macos(13.0))
@interface SystemAudioCapturer : NSObject <SCStreamDelegate, SCStreamOutput>

@property (nonatomic, weak, nullable) id<SystemAudioCapturerDelegate> delegate;
@property (nonatomic, readonly) BOOL isCapturing;

+ (BOOL)isSupported;

- (void)startCaptureWithCompletion:(void (^)(NSError * _Nullable error))completion;
- (void)stopCapture;

@end

NS_ASSUME_NONNULL_END
