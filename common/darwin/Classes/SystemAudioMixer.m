#import "SystemAudioMixer.h"
#import <Accelerate/Accelerate.h>
#import <os/lock.h>

// Ring buffer size - enough for ~100ms of audio at 48kHz stereo
static const NSUInteger kRingBufferCapacity = 48000 * 2 * sizeof(float) / 10;

API_AVAILABLE(macos(13.0))
@interface SystemAudioMixer ()

@property (nonatomic, strong, nullable) SystemAudioCapturer *capturer;
@property (nonatomic, assign) BOOL isCapturing;

// Ring buffer for system audio samples
@property (nonatomic, assign) float *ringBuffer;
@property (nonatomic, assign) NSUInteger ringBufferWriteIndex;
@property (nonatomic, assign) NSUInteger ringBufferReadIndex;
@property (nonatomic, assign) NSUInteger ringBufferAvailable;
@property (nonatomic, assign) os_unfair_lock ringBufferLock;

// Audio format info from WebRTC
@property (nonatomic, assign) size_t sampleRate;
@property (nonatomic, assign) size_t channels;

// Resampling state (system audio is 48kHz, WebRTC might be different)
@property (nonatomic, assign) BOOL needsResampling;

@end

API_AVAILABLE(macos(13.0))
@implementation SystemAudioMixer

+ (BOOL)isSupported {
    return [SystemAudioCapturer isSupported];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _systemAudioVolume = 1.0f;
        _microphoneVolume = 1.0f;
        _isCapturing = NO;
        _ringBufferLock = OS_UNFAIR_LOCK_INIT;
        _ringBuffer = (float *)calloc(kRingBufferCapacity / sizeof(float), sizeof(float));
        _ringBufferWriteIndex = 0;
        _ringBufferReadIndex = 0;
        _ringBufferAvailable = 0;
        _sampleRate = 48000;
        _channels = 2;
        _needsResampling = NO;
    }
    return self;
}

- (void)dealloc {
    [self stop];
    if (_ringBuffer) {
        free(_ringBuffer);
        _ringBuffer = NULL;
    }
}

- (void)startWithCompletion:(void (^)(NSError * _Nullable))completion {
    if (self.isCapturing) {
        if (completion) {
            completion(nil);
        }
        return;
    }
    
    self.capturer = [[SystemAudioCapturer alloc] init];
    self.capturer.delegate = self;
    
    [self.capturer startCaptureWithCompletion:^(NSError * _Nullable error) {
        if (!error) {
            self.isCapturing = YES;
            NSLog(@"SystemAudioMixer: Started");
        } else {
            NSLog(@"SystemAudioMixer: Failed to start: %@", error);
            self.capturer = nil;
        }
        if (completion) {
            completion(error);
        }
    }];
}

- (void)stop {
    if (!self.isCapturing) {
        return;
    }
    
    self.isCapturing = NO;
    [self.capturer stopCapture];
    self.capturer = nil;
    
    // Clear ring buffer
    os_unfair_lock_lock(&_ringBufferLock);
    _ringBufferWriteIndex = 0;
    _ringBufferReadIndex = 0;
    _ringBufferAvailable = 0;
    os_unfair_lock_unlock(&_ringBufferLock);
    
    NSLog(@"SystemAudioMixer: Stopped");
}

#pragma mark - SystemAudioCapturerDelegate

- (void)systemAudioCapturer:(id)capturer didCaptureAudioBuffer:(CMSampleBufferRef)sampleBuffer {
    if (!self.isCapturing) {
        return;
    }
    
    // Get audio buffer list
    CMBlockBufferRef blockBuffer = NULL;
    
    // AudioBufferList has a variable-length array - allocate space for stereo (2 buffers)
    // sizeof(AudioBufferList) includes 1 AudioBuffer, add 1 more for stereo
    size_t bufferListSize = sizeof(AudioBufferList) + sizeof(AudioBuffer);
    AudioBufferList *audioBufferList = (AudioBufferList *)malloc(bufferListSize);
    if (!audioBufferList) {
        NSLog(@"SystemAudioMixer: Failed to allocate audio buffer list");
        return;
    }
    
    size_t blockBufferOffset = 0;
    
    OSStatus status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
        sampleBuffer,
        &blockBufferOffset,
        audioBufferList,
        bufferListSize,
        NULL,
        NULL,
        kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
        &blockBuffer
    );
    
    if (status != noErr) {
        NSLog(@"SystemAudioMixer: Failed to get audio buffer list: %d", (int)status);
        free(audioBufferList);
        return;
    }
    
    // Get format description
    CMFormatDescriptionRef formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer);
    const AudioStreamBasicDescription *asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc);
    
    if (!asbd) {
        CFRelease(blockBuffer);
        free(audioBufferList);
        return;
    }
    
    // Process each buffer
    for (UInt32 i = 0; i < audioBufferList->mNumberBuffers; i++) {
        AudioBuffer buffer = audioBufferList->mBuffers[i];
        
        if (buffer.mData && buffer.mDataByteSize > 0) {
            [self writeSystemAudioToRingBuffer:(float *)buffer.mData
                                   sampleCount:buffer.mDataByteSize / sizeof(float)
                                    sampleRate:(size_t)asbd->mSampleRate
                                      channels:(size_t)asbd->mChannelsPerFrame];
        }
    }
    
    CFRelease(blockBuffer);
    free(audioBufferList);
}

- (void)writeSystemAudioToRingBuffer:(float *)samples
                         sampleCount:(NSUInteger)sampleCount
                          sampleRate:(size_t)sampleRate
                            channels:(size_t)channels {
    if (!samples || sampleCount == 0) {
        return;
    }
    
    os_unfair_lock_lock(&_ringBufferLock);
    
    NSUInteger bufferCapacity = kRingBufferCapacity / sizeof(float);
    
    for (NSUInteger i = 0; i < sampleCount; i++) {
        // Apply volume
        _ringBuffer[_ringBufferWriteIndex] = samples[i] * _systemAudioVolume;
        _ringBufferWriteIndex = (_ringBufferWriteIndex + 1) % bufferCapacity;
        
        // Update available samples (overwrite old data if buffer is full)
        if (_ringBufferAvailable < bufferCapacity) {
            _ringBufferAvailable++;
        } else {
            // Buffer overflow - advance read index
            _ringBufferReadIndex = (_ringBufferReadIndex + 1) % bufferCapacity;
        }
    }
    
    os_unfair_lock_unlock(&_ringBufferLock);
}

- (NSUInteger)readSystemAudioFromRingBuffer:(float *)outputBuffer
                                sampleCount:(NSUInteger)sampleCount {
    os_unfair_lock_lock(&_ringBufferLock);
    
    NSUInteger bufferCapacity = kRingBufferCapacity / sizeof(float);
    NSUInteger samplesToRead = MIN(sampleCount, _ringBufferAvailable);
    
    for (NSUInteger i = 0; i < samplesToRead; i++) {
        outputBuffer[i] = _ringBuffer[_ringBufferReadIndex];
        _ringBufferReadIndex = (_ringBufferReadIndex + 1) % bufferCapacity;
    }
    
    _ringBufferAvailable -= samplesToRead;
    
    // Zero-fill remaining samples if we don't have enough
    for (NSUInteger i = samplesToRead; i < sampleCount; i++) {
        outputBuffer[i] = 0.0f;
    }
    
    os_unfair_lock_unlock(&_ringBufferLock);
    
    return samplesToRead;
}

#pragma mark - ExternalAudioProcessingDelegate

- (void)audioProcessingInitializeWithSampleRate:(size_t)sampleRateHz channels:(size_t)channels {
    self.sampleRate = sampleRateHz;
    self.channels = channels;
    self.needsResampling = (sampleRateHz != 48000);
    
    NSLog(@"SystemAudioMixer: Initialized with sample rate: %zu, channels: %zu", sampleRateHz, channels);
}

- (void)audioProcessingProcess:(RTCAudioBuffer *)audioBuffer {
    if (!self.isCapturing) {
        return;
    }
    
    NSUInteger frameCount = (NSUInteger)audioBuffer.frames;
    NSUInteger channelCount = (NSUInteger)audioBuffer.channels;
    
    // Allocate temporary buffer for system audio
    NSUInteger totalSamples = frameCount * channelCount;
    float *systemAudioTemp = (float *)calloc(totalSamples, sizeof(float));
    
    if (!systemAudioTemp) {
        return;
    }
    
    // Read system audio from ring buffer
    [self readSystemAudioFromRingBuffer:systemAudioTemp sampleCount:totalSamples];
    
    // Mix system audio into each channel of the microphone audio
    for (NSUInteger ch = 0; ch < channelCount; ch++) {
        float *micBuffer = [audioBuffer rawBufferForChannel:(int)ch];
        
        if (!micBuffer) {
            continue;
        }
        
        // Mix samples
        for (NSUInteger frame = 0; frame < frameCount; frame++) {
            // Get system audio sample (interleaved or per-channel based on format)
            float systemSample = 0.0f;
            NSUInteger systemIndex = frame * channelCount + ch;
            if (systemIndex < totalSamples) {
                systemSample = systemAudioTemp[systemIndex];
            }
            
            // Mix: micBuffer already contains mic audio, add system audio
            // Apply volume controls
            float micSample = micBuffer[frame] * _microphoneVolume;
            float mixedSample = micSample + systemSample;
            
            // Soft clip to prevent harsh distortion
            if (mixedSample > 1.0f) {
                mixedSample = 1.0f - (1.0f / (mixedSample + 1.0f));
            } else if (mixedSample < -1.0f) {
                mixedSample = -1.0f + (1.0f / (-mixedSample + 1.0f));
            }
            
            micBuffer[frame] = mixedSample;
        }
    }
    
    free(systemAudioTemp);
}

- (void)audioProcessingRelease {
    NSLog(@"SystemAudioMixer: Released");
    [self stop];
}

@end
