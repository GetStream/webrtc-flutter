package io.getstream.webrtc.flutter.video;

import org.webrtc.VideoCapturer;

public class VideoCapturerInfo {
    public VideoCapturer capturer;
    /**
     * Whether {@link #capturer} is currently running.
     *
     * <p>libwebrtc's capturers do not expose their state, and starting an
     * already-started capturer is not free, so track it here.
     */
    public boolean isCapturing;
    public int width;
    public int height;
    public int fps;
    public boolean isScreenCapture = false;
    public String cameraName;
}