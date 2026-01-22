#import "SystemAudioCapturer.h"

API_AVAILABLE(macos(13.0))
@interface SystemAudioCapturer ()

@property (nonatomic, strong, nullable) SCStream *stream;
@property (nonatomic, strong, nullable) SCContentFilter *contentFilter;
@property (nonatomic, strong) dispatch_queue_t captureQueue;
@property (nonatomic, assign) BOOL isCapturing;

@end

API_AVAILABLE(macos(13.0))
@implementation SystemAudioCapturer

+ (BOOL)isSupported {
    if (@available(macOS 13.0, *)) {
        return YES;
    }
    return NO;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _captureQueue = dispatch_queue_create("io.getstream.webrtc.systemaudio", DISPATCH_QUEUE_SERIAL);
        _isCapturing = NO;
    }
    return self;
}

- (void)startCaptureWithCompletion:(void (^)(NSError * _Nullable))completion {
    if (self.isCapturing) {
        if (completion) {
            completion(nil);
        }
        return;
    }
    
    // Get shareable content to create a filter for system audio capture
    [SCShareableContent getShareableContentWithCompletionHandler:^(SCShareableContent * _Nullable shareableContent, NSError * _Nullable error) {
        if (error) {
            NSLog(@"SystemAudioCapturer: Failed to get shareable content: %@", error);
            if (completion) {
                completion(error);
            }
            return;
        }
        
        if (shareableContent.displays.count == 0) {
            NSError *noDisplayError = [NSError errorWithDomain:@"SystemAudioCapturer"
                                                          code:-1
                                                      userInfo:@{NSLocalizedDescriptionKey: @"No displays available"}];
            NSLog(@"SystemAudioCapturer: No displays available");
            if (completion) {
                completion(noDisplayError);
            }
            return;
        }
        
        // Use the main display for audio capture
        SCDisplay *mainDisplay = shareableContent.displays.firstObject;
        
        // Create a content filter that excludes all windows (we only want audio)
        // We need to capture from a display but we'll only use the audio
        self.contentFilter = [[SCContentFilter alloc] initWithDisplay:mainDisplay
                                                     excludingWindows:@[]];
        
        // Configure stream for audio-only capture
        SCStreamConfiguration *config = [[SCStreamConfiguration alloc] init];
        config.capturesAudio = YES;
        config.excludesCurrentProcessAudio = YES; // Don't capture our own audio
        config.sampleRate = 48000;
        config.channelCount = 2;
        
        // Minimize video capture overhead since we only need audio
        config.width = 2;
        config.height = 2;
        config.minimumFrameInterval = CMTimeMake(1, 1); // 1 FPS minimum
        config.showsCursor = NO;
        
        // Create the stream
        self.stream = [[SCStream alloc] initWithFilter:self.contentFilter
                                         configuration:config
                                              delegate:self];
        
        NSError *addOutputError = nil;
        
        // Add audio output
        BOOL audioAdded = [self.stream addStreamOutput:self
                                                  type:SCStreamOutputTypeAudio
                                    sampleHandlerQueue:self.captureQueue
                                                 error:&addOutputError];
        
        if (!audioAdded || addOutputError) {
            NSLog(@"SystemAudioCapturer: Failed to add audio output: %@", addOutputError);
            if (completion) {
                completion(addOutputError);
            }
            return;
        }
        
        // Start capture
        [self.stream startCaptureWithCompletionHandler:^(NSError * _Nullable startError) {
            if (startError) {
                NSLog(@"SystemAudioCapturer: Failed to start capture: %@", startError);
                self.stream = nil;
                self.contentFilter = nil;
            } else {
                self.isCapturing = YES;
                NSLog(@"SystemAudioCapturer: Started capturing system audio");
            }
            if (completion) {
                completion(startError);
            }
        }];
    }];
}

- (void)stopCapture {
    if (!self.isCapturing || !self.stream) {
        return;
    }
    
    self.isCapturing = NO;
    
    [self.stream stopCaptureWithCompletionHandler:^(NSError * _Nullable error) {
        if (error) {
            NSLog(@"SystemAudioCapturer: Error stopping capture: %@", error);
        } else {
            NSLog(@"SystemAudioCapturer: Stopped capturing system audio");
        }
    }];
    
    self.stream = nil;
    self.contentFilter = nil;
}

#pragma mark - SCStreamDelegate

- (void)stream:(SCStream *)stream didStopWithError:(NSError *)error {
    NSLog(@"SystemAudioCapturer: Stream stopped with error: %@", error);
    self.isCapturing = NO;
    self.stream = nil;
    self.contentFilter = nil;
}

#pragma mark - SCStreamOutput

- (void)stream:(SCStream *)stream didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer ofType:(SCStreamOutputType)type {
    if (type == SCStreamOutputTypeAudio && self.delegate) {
        [self.delegate systemAudioCapturer:self didCaptureAudioBuffer:sampleBuffer];
    }
    // Ignore video frames - we only care about audio
}

- (void)dealloc {
    [self stopCapture];
}

@end
