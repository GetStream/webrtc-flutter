package io.getstream.webrtc.flutter;

import android.content.Context;
import android.util.Log;

import androidx.annotation.NonNull;
import androidx.lifecycle.DefaultLifecycleObserver;
import androidx.lifecycle.Lifecycle;
import androidx.lifecycle.LifecycleOwner;

import io.getstream.webrtc.flutter.audio.AudioProcessingFactoryProvider;
import io.getstream.webrtc.flutter.audio.AudioProcessingController;
import io.getstream.webrtc.flutter.audio.AudioSwitchManager;
import io.getstream.webrtc.flutter.utils.AnyThreadSink;
import io.getstream.webrtc.flutter.utils.ConstraintsMap;

import org.webrtc.ExternalAudioProcessingFactory;
import org.webrtc.MediaStreamTrack;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.embedding.engine.plugins.lifecycle.HiddenLifecycleReference;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.view.TextureRegistry;

/**
 * FlutterWebRTCPlugin
 */
public class FlutterWebRTCPlugin implements FlutterPlugin, ActivityAware, EventChannel.StreamHandler {

    static public final String TAG = "FlutterWebRTCPlugin";

    private MethodChannel methodChannel;
    private MethodCallHandlerImpl methodCallHandler;
    private LifeCycleObserver observer;
    private Lifecycle lifecycle;
    private EventChannel eventChannel;

    // eventSink is static because FlutterWebRTCPlugin can be instantiated multiple times
    // but the onListen(Object, EventChannel.EventSink) event only fires once for the first
    // FlutterWebRTCPlugin instance, so for the next instances eventSink will be == null
    public static EventChannel.EventSink eventSink;

    public FlutterWebRTCPlugin() {
        if (sharedSingleton == null) {
            sharedSingleton = this;
        } else {
            Log.w(TAG, "Warning - Multiple plugin instances detected. Keeping existing singleton.");
        }
    }

    public static FlutterWebRTCPlugin sharedSingleton;

    public void setAudioProcessingFactoryProvider(AudioProcessingFactoryProvider provider) {
        methodCallHandler.audioProcessingFactoryProvider = provider;
    }

    public AudioProcessingFactoryProvider getAudioProcessingFactoryProvider() {
        return methodCallHandler.audioProcessingFactoryProvider;
    }

    public MediaStreamTrack getTrackForId(String trackId, String peerConnectionId) {
        return methodCallHandler.getTrackForId(trackId, peerConnectionId);
    }

    public LocalTrack getLocalTrack(String trackId) {
        return methodCallHandler.getLocalTrack(trackId);
    }

    public MediaStreamTrack getRemoteTrack(String trackId) {
        return methodCallHandler.getRemoteTrack(trackId);
    }

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        startListening(binding.getApplicationContext(), binding.getBinaryMessenger(),
                binding.getTextureRegistry());
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        stopListening();
    }

    @Override
    public void onAttachedToActivity(@NonNull ActivityPluginBinding binding) {
        methodCallHandler.setActivity(binding.getActivity());
        // Also set Activity on AudioSwitchManager for setVolumeControlStream support
        if (AudioSwitchManager.instance != null) {
            AudioSwitchManager.instance.setActivity(binding.getActivity());
        }
        this.observer = new LifeCycleObserver();
        this.lifecycle = ((HiddenLifecycleReference) binding.getLifecycle()).getLifecycle();
        this.lifecycle.addObserver(this.observer);
    }

    @Override
    public void onDetachedFromActivityForConfigChanges() {
        methodCallHandler.setActivity(null);
        if (AudioSwitchManager.instance != null) {
            AudioSwitchManager.instance.setActivity(null);
        }
    }

    @Override
    public void onReattachedToActivityForConfigChanges(@NonNull ActivityPluginBinding binding) {
        methodCallHandler.setActivity(binding.getActivity());
        if (AudioSwitchManager.instance != null) {
            AudioSwitchManager.instance.setActivity(binding.getActivity());
        }
    }

    @Override
    public void onDetachedFromActivity() {
        methodCallHandler.setActivity(null);
        if (AudioSwitchManager.instance != null) {
            AudioSwitchManager.instance.setActivity(null);
        }
        if (this.observer != null && this.lifecycle != null) {
            this.lifecycle.removeObserver(this.observer);
        }
        this.observer = null;
        this.lifecycle = null;
    }

    private void startListening(final Context context, BinaryMessenger messenger,
                                TextureRegistry textureRegistry) {
        if (AudioSwitchManager.instance == null) {
            AudioSwitchManager.instance = new AudioSwitchManager(context);
        }

        methodCallHandler = new MethodCallHandlerImpl(context, messenger, textureRegistry);
        methodChannel = new MethodChannel(messenger, "FlutterWebRTC.Method");
        methodChannel.setMethodCallHandler(methodCallHandler);
        eventChannel = new EventChannel( messenger,"FlutterWebRTC.Event");
        eventChannel.setStreamHandler(this);
        AudioSwitchManager.instance.audioDeviceChangeListener = (devices, currentDevice) -> {
            Log.w(TAG, "audioFocusChangeListener " + devices+ " " + currentDevice);
            ConstraintsMap params = new ConstraintsMap();
            params.putString("event", "onDeviceChange");
            sendEvent(params.toMap());
            return null;
        };
    }

    private void stopListening() {
        methodCallHandler.dispose();
        methodCallHandler = null;
        methodChannel.setMethodCallHandler(null);
        eventChannel.setStreamHandler(null);
        if (AudioSwitchManager.instance != null) {
            Log.d(TAG, "Stopping the audio manager...");
            AudioSwitchManager.instance.stop();
        }
    }

    @Override
    public void onListen(Object arguments, EventChannel.EventSink events) {
        eventSink = new AnyThreadSink(events);
    }
    @Override
    public void onCancel(Object arguments) {
        eventSink = null;
    }

    public void sendEvent(Object event) {
        if(eventSink != null) {
            eventSink.success(event);
        }
    }

    /**
     * Restarts the camera when the host activity comes back to the foreground.
     *
     * <p>This used to also implement {@link Application.ActivityLifecycleCallbacks}
     * and restart the camera from {@code onActivityResumed} as well. Nothing
     * ever registered it as an activity callback — the static {@code
     * application} field was never assigned — yet {@code onDetachedFromActivity}
     * unregistered it, so the two halves were asymmetric and the class was one
     * line away from restarting the camera twice per foreground. Only the
     * lifecycle-observer half is kept.
     */
    private class LifeCycleObserver implements DefaultLifecycleObserver {

        @Override
        public void onResume(LifecycleOwner owner) {
            if (null != methodCallHandler) {
                methodCallHandler.reStartCamera();
            }
        }
    }
}
