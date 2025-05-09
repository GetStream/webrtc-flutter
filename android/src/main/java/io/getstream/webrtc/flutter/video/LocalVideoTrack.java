package io.getstream.webrtc.flutter.video;

import androidx.annotation.Nullable;

import io.getstream.webrtc.flutter.LocalTrack;

import io.getstream.webrtc.VideoFrame;
import io.getstream.webrtc.VideoProcessor;
import io.getstream.webrtc.VideoSink;
import io.getstream.webrtc.VideoTrack;

import java.util.ArrayList;
import java.util.List;

public class LocalVideoTrack extends LocalTrack implements VideoProcessor {
    public interface ExternalVideoFrameProcessing {
        /**
         * Process a video frame.
         * @param frame
         * @return The processed video frame.
         */
        public abstract VideoFrame onFrame(VideoFrame frame);
    }

    public LocalVideoTrack(VideoTrack videoTrack) {
        super(videoTrack);
    }

    List<ExternalVideoFrameProcessing> processors = new ArrayList<>();

    public void addProcessor(ExternalVideoFrameProcessing processor) {
        synchronized (processors) {
            processors.add(processor);
        }
    }

    public void removeProcessor(ExternalVideoFrameProcessing processor) {
        synchronized (processors) {
            processors.remove(processor);
        }
    }

    private VideoSink sink = null;

    @Override
    public void setSink(@Nullable VideoSink videoSink) {
        sink = videoSink;
    }

    @Override
    public void onCapturerStarted(boolean b) {}

    @Override
    public void onCapturerStopped() {}

    @Override
    public void onFrameCaptured(VideoFrame videoFrame) {
        if (sink != null) {
            synchronized (processors) {
                for (ExternalVideoFrameProcessing processor : processors) {
                    videoFrame = processor.onFrame(videoFrame);
                }
            }
            sink.onFrame(videoFrame);
        }
    }
}
