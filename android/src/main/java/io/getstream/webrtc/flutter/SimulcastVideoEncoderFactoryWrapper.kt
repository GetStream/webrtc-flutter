package io.getstream.webrtc.flutter

import org.webrtc.*

/*
Copyright 2017, Lyo Kato <lyo.kato at gmail.com> (Original Author)
Copyright 2017-2021, Shiguredo Inc.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
 */
internal class SimulcastVideoEncoderFactoryWrapper(
    sharedContext: EglBase.Context?,
    enableIntelVp8Encoder: Boolean,
    enableH264HighProfile: Boolean
) : VideoEncoderFactory {

    /**
     * Factory that prioritizes software encoder.
     *
     * When the selected codec can't be handled by the software encoder,
     * it uses the hardware encoder as a fallback. However, this class is
     * primarily used to address an issue in libwebrtc, and does not have
     * purposeful usecase itself.
     *
     * To use simulcast in libwebrtc, SimulcastEncoderAdapter is used.
     * SimulcastEncoderAdapter takes in a primary and fallback encoder.
     * If HardwareVideoEncoderFactory and SoftwareVideoEncoderFactory are
     * passed in directly as primary and fallback, when H.264 is used,
     * libwebrtc will crash.
     *
     * This is because SoftwareVideoEncoderFactory does not handle H.264,
     * so [SoftwareVideoEncoderFactory.createEncoder] returns null, and
     * the libwebrtc side does not handle nulls, regardless of whether the
     * fallback is actually used or not.
     *
     * To avoid nulls, we simply pass responsibility over to the HardwareVideoEncoderFactory.
     * This results in HardwareVideoEncoderFactory being both the primary and fallback,
     * but there aren't any specific problems in doing so.
     */
    private class FallbackFactory(private val hardwareVideoEncoderFactory: VideoEncoderFactory) :
        VideoEncoderFactory {

        private val softwareVideoEncoderFactory: VideoEncoderFactory = SoftwareVideoEncoderFactory()

        override fun createEncoder(info: VideoCodecInfo): VideoEncoder? {
            val softwareEncoder = softwareVideoEncoderFactory.createEncoder(info)
            val hardwareEncoder = hardwareVideoEncoderFactory.createEncoder(info)
            return if (hardwareEncoder != null && softwareEncoder != null) {
                VideoEncoderFallback(hardwareEncoder, softwareEncoder)
            } else {
                softwareEncoder ?: hardwareEncoder
            }
        }

        override fun getSupportedCodecs(): Array<VideoCodecInfo> {
            val supportedCodecInfos: MutableList<VideoCodecInfo> = mutableListOf()
            supportedCodecInfos.addAll(softwareVideoEncoderFactory.supportedCodecs)
            supportedCodecInfos.addAll(hardwareVideoEncoderFactory.supportedCodecs)
            return supportedCodecInfos.toTypedArray()
        }

    }

    /**
     * Wraps each stream encoder and scales the frame when the resolution from
     * [initEncode] doesn't match the incoming buffer.
     *
     * Every method used to be routed through a dedicated single-thread executor
     * and then immediately blocked on with `future.get()`, which bought no
     * parallelism at all — the calling encoder thread just waited. With three
     * simulcast layers that was three extra threads, three
     * `Callable`+`FutureTask` allocations and six context switches per captured
     * frame at 30 fps, plus the same round trip for the `getEncoderInfo()` and
     * `getScalingSettings()` calls libwebrtc makes constantly. Calls now go
     * straight through to the wrapped encoder on the caller's thread.
     */
    private class StreamEncoderWrapper(private val encoder: VideoEncoder) : VideoEncoder {

        var streamSettings: VideoEncoder.Settings? = null

        override fun initEncode(
            settings: VideoEncoder.Settings,
            callback: VideoEncoder.Callback?
        ): VideoCodecStatus {
            streamSettings = settings
            return encoder.initEncode(settings, callback)
        }

        override fun release(): VideoCodecStatus = encoder.release()

        override fun encode(
            frame: VideoFrame,
            encodeInfo: VideoEncoder.EncodeInfo?
        ): VideoCodecStatus {
            val settings = streamSettings
            if (settings == null || frame.buffer.width == settings.width) {
                return encoder.encode(frame, encodeInfo)
            }

            // The incoming buffer differs from the streamSettings received in
            // initEncode(), so scale before handing it over.
            val originalBuffer = frame.buffer
            val adaptedBuffer = originalBuffer.cropAndScale(
                0, 0, originalBuffer.width, originalBuffer.height,
                settings.width, settings.height
            )
            val adaptedFrame = VideoFrame(adaptedBuffer, frame.rotation, frame.timestampNs)
            val result = encoder.encode(adaptedFrame, encodeInfo)
            adaptedBuffer.release()
            return result
        }

        override fun setRateAllocation(
            allocation: VideoEncoder.BitrateAllocation?,
            frameRate: Int
        ): VideoCodecStatus = encoder.setRateAllocation(allocation, frameRate)

        override fun getScalingSettings(): VideoEncoder.ScalingSettings = encoder.scalingSettings

        override fun getImplementationName(): String = encoder.implementationName

        override fun createNative(webrtcEnvRef: Long): Long = encoder.createNative(webrtcEnvRef)

        override fun isHardwareEncoder(): Boolean = encoder.isHardwareEncoder

        override fun setRates(rcParameters: VideoEncoder.RateControlParameters?): VideoCodecStatus =
            encoder.setRates(rcParameters)

        override fun getResolutionBitrateLimits(): Array<VideoEncoder.ResolutionBitrateLimits> =
            encoder.resolutionBitrateLimits

        override fun getEncoderInfo(): VideoEncoder.EncoderInfo = encoder.encoderInfo
    }

    private class StreamEncoderWrapperFactory(private val factory: VideoEncoderFactory) :
        VideoEncoderFactory {
        override fun createEncoder(videoCodecInfo: VideoCodecInfo?): VideoEncoder? {
            val encoder = factory.createEncoder(videoCodecInfo)
            if (encoder == null) {
                return null
            }
            if (encoder is WrappedNativeVideoEncoder) {
              return encoder
            }
            return StreamEncoderWrapper(encoder)
        }

        override fun getSupportedCodecs(): Array<VideoCodecInfo> {
            return factory.supportedCodecs
        }
    }


    private val primary: VideoEncoderFactory
    private val fallback: VideoEncoderFactory
    private val native: SimulcastVideoEncoderFactory

    init {
        val hardwareVideoEncoderFactory = HardwareVideoEncoderFactory(
            sharedContext, enableIntelVp8Encoder, enableH264HighProfile
        )
        primary = StreamEncoderWrapperFactory(hardwareVideoEncoderFactory)
        // Wrap the raw hardware factory, not `primary`: passing the already
        // wrapped factory here nested one StreamEncoderWrapper inside another,
        // so every fallback encoder paid the wrapper twice per call.
        fallback = StreamEncoderWrapperFactory(FallbackFactory(hardwareVideoEncoderFactory))
        native = SimulcastVideoEncoderFactory(primary, fallback)
    }

    override fun createEncoder(info: VideoCodecInfo?): VideoEncoder? {
        return native.createEncoder(info)
    }

    override fun getSupportedCodecs(): Array<VideoCodecInfo> {
        return native.supportedCodecs
    }

}
