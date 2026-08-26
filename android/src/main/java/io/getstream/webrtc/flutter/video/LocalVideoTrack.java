package io.getstream.webrtc.flutter.video;

import androidx.annotation.Nullable;

import io.getstream.webrtc.flutter.LocalTrack;

import org.webrtc.VideoFrame;
import org.webrtc.VideoProcessor;
import org.webrtc.VideoSink;
import org.webrtc.VideoTrack;

import java.util.List;
import java.util.concurrent.CopyOnWriteArrayList;

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

    // Copy-on-write so onFrameCaptured, which runs for every captured frame, does
    // not have to take a monitor to read the list.
    private final List<ExternalVideoFrameProcessing> processors = new CopyOnWriteArrayList<>();

    public void addProcessor(ExternalVideoFrameProcessing processor) {
        processors.add(processor);
    }

    public void removeProcessor(ExternalVideoFrameProcessing processor) {
        processors.remove(processor);
    }

    // Written from the platform thread, read on the capture thread.
    private volatile VideoSink sink = null;

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
        final VideoSink sink = this.sink;
        if (sink == null) {
            return;
        }

        // The common case by far is an empty processor list. Skipping the loop
        // avoids allocating an iterator for every captured frame.
        if (!processors.isEmpty()) {
            for (ExternalVideoFrameProcessing processor : processors) {
                videoFrame = processor.onFrame(videoFrame);
            }
        }

        sink.onFrame(videoFrame);
    }
}
