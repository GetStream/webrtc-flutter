package io.getstream.webrtc.flutter.videoEffects;

import io.getstream.webrtc.SurfaceTextureHelper;
import io.getstream.webrtc.VideoFrame;
import io.getstream.webrtc.VideoProcessor;
import io.getstream.webrtc.VideoSink;

import java.util.List;

/**
 * Lightweight abstraction for an object that can receive video frames, process and add effects in
 * them, and pass them on to another object.
 */
public class VideoEffectProcessor implements VideoProcessor {
    private VideoSink mSink;
    final private SurfaceTextureHelper textureHelper;
    final private List<VideoFrameProcessor> videoFrameProcessors;

    public VideoEffectProcessor(List<VideoFrameProcessor> processors, SurfaceTextureHelper textureHelper) {
        this.textureHelper = textureHelper;
        this.videoFrameProcessors = processors;
    }

    @Override
    public void onCapturerStarted(boolean success) {

    }

    @Override
    public void onCapturerStopped() {

    }

    @Override
    public void setSink(VideoSink sink) {
        mSink = sink;
    }

    /**
     * Called just after the frame is captured.
     * Will process the VideoFrame with the help of VideoFrameProcessor and send the processed
     * VideoFrame back to webrtc using onFrame method in VideoSink.
     * @param frame raw VideoFrame received from webrtc.
     */
    @Override
    public void onFrameCaptured(VideoFrame frame) {
        frame.retain();
        VideoFrame outputFrame = frame;

        for (VideoFrameProcessor processor : this.videoFrameProcessors) {
            outputFrame = processor.process(outputFrame, textureHelper);
        }

        mSink.onFrame(outputFrame);
        outputFrame.release();
        frame.release();
    }
}