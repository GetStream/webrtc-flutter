package io.getstream.webrtc.video;

import androidx.annotation.Nullable;

import io.getstream.webrtc.flutter.SimulcastVideoEncoderFactoryWrapper;

import io.getstream.webrtc.EglBase;
import io.getstream.webrtc.SoftwareVideoEncoderFactory;
import io.getstream.webrtc.VideoCodecInfo;
import io.getstream.webrtc.VideoEncoder;
import io.getstream.webrtc.VideoEncoderFactory;

import java.util.ArrayList;
import java.util.List;

public class CustomVideoEncoderFactory implements VideoEncoderFactory {
    private SoftwareVideoEncoderFactory softwareVideoEncoderFactory = new SoftwareVideoEncoderFactory();
    private SimulcastVideoEncoderFactoryWrapper simulcastVideoEncoderFactoryWrapper;

    private boolean forceSWCodec  = false;

    private List<String> forceSWCodecs = new ArrayList<>();

    public CustomVideoEncoderFactory(EglBase.Context sharedContext,
                                     boolean enableIntelVp8Encoder,
                                     boolean enableH264HighProfile) {
        this.simulcastVideoEncoderFactoryWrapper = new SimulcastVideoEncoderFactoryWrapper(sharedContext, enableIntelVp8Encoder, enableH264HighProfile);
    }

    public void setForceSWCodec(boolean forceSWCodec) {
        this.forceSWCodec = forceSWCodec;
    }

    public void setForceSWCodecList(List<String> forceSWCodecs) {
        this.forceSWCodecs = forceSWCodecs;
    }

    @Nullable
    @Override
    public VideoEncoder createEncoder(VideoCodecInfo videoCodecInfo) {
        if(forceSWCodec) {
            return softwareVideoEncoderFactory.createEncoder(videoCodecInfo);
        }

        if(!forceSWCodecs.isEmpty()) {
            if(forceSWCodecs.contains(videoCodecInfo.name)) {
                return softwareVideoEncoderFactory.createEncoder(videoCodecInfo);
            }
        }

        return simulcastVideoEncoderFactoryWrapper.createEncoder(videoCodecInfo);
    }

    @Override
    public VideoCodecInfo[] getSupportedCodecs() {
        if(forceSWCodec && forceSWCodecs.isEmpty()) {
            return softwareVideoEncoderFactory.getSupportedCodecs();
        }
        return simulcastVideoEncoderFactoryWrapper.getSupportedCodecs();
    }
}
