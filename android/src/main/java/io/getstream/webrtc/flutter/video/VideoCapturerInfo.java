package io.getstream.webrtc.flutter.video;

import io.getstream.webrtc.VideoCapturer;

public class VideoCapturerInfo {
    public VideoCapturer capturer;
    public int width;
    public int height;
    public int fps;
    public boolean isScreenCapture = false;
    public String cameraName;
}