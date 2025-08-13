package io.getstream.webrtc.flutter.audio;

import android.content.Context;
import android.media.AudioAttributes;
import android.media.AudioFocusRequest;
import android.media.AudioManager;
import android.os.Build;
import android.telephony.PhoneStateListener;
import android.telephony.TelephonyCallback;
import android.telephony.TelephonyManager;
import android.util.Log;

import io.getstream.webrtc.flutter.utils.ConstraintsMap;

public class AudioFocusManager {
    private static final String TAG = "AudioFocusManager";
    
    public enum InterruptionSource {
        AUDIO_FOCUS_ONLY,
        TELEPHONY_ONLY,
        AUDIO_FOCUS_AND_TELEPHONY
    }
    
    private AudioManager audioManager;
    private TelephonyManager telephonyManager;

    private PhoneStateListener phoneStateListener;
    private AudioFocusChangeListener focusChangeListener;

    private TelephonyCallback telephonyCallback;
    private AudioFocusRequest audioFocusRequest;
    
    private InterruptionSource interruptionSource;
    private Context context;
    
    private Integer focusUsageType; // AudioAttributes.USAGE_*
    private Integer focusContentType; // AudioAttributes.CONTENT_TYPE_*
    
    public interface AudioFocusChangeListener {
        void onInterruptionStart();
        void onInterruptionEnd();
    }
    
    public AudioFocusManager(Context context) {
        this(context, InterruptionSource.AUDIO_FOCUS_AND_TELEPHONY, null, null);
    }
    
    public AudioFocusManager(Context context, InterruptionSource interruptionSource) {
        this(context, interruptionSource, null, null);
    }
    
    public AudioFocusManager(Context context, InterruptionSource interruptionSource, Integer usageType, Integer contentType) {
        this.context = context;
        this.interruptionSource = interruptionSource;
        this.focusUsageType = usageType;
        this.focusContentType = contentType;
        
        if (interruptionSource == InterruptionSource.AUDIO_FOCUS_ONLY || 
            interruptionSource == InterruptionSource.AUDIO_FOCUS_AND_TELEPHONY) {
            audioManager = (AudioManager) context.getSystemService(Context.AUDIO_SERVICE);
        }
        
        if (interruptionSource == InterruptionSource.TELEPHONY_ONLY || 
            interruptionSource == InterruptionSource.AUDIO_FOCUS_AND_TELEPHONY) {
            telephonyManager = (TelephonyManager) context.getSystemService(Context.TELEPHONY_SERVICE);
        }
    }
    
    public void setAudioFocusChangeListener(AudioFocusChangeListener listener) {
        this.focusChangeListener = listener;
        
        if (listener != null) {
            startMonitoring();
        } else {
            stopMonitoring();
        }
    }
    
    public void startMonitoring() {
        if (interruptionSource == InterruptionSource.AUDIO_FOCUS_ONLY || 
            interruptionSource == InterruptionSource.AUDIO_FOCUS_AND_TELEPHONY) {
            requestAudioFocusInternal();
        }
        
        if (interruptionSource == InterruptionSource.TELEPHONY_ONLY || 
            interruptionSource == InterruptionSource.AUDIO_FOCUS_AND_TELEPHONY) {
            registerTelephonyListener();
        }
    }
    
    public void stopMonitoring() {
        if (interruptionSource == InterruptionSource.AUDIO_FOCUS_ONLY || 
            interruptionSource == InterruptionSource.AUDIO_FOCUS_AND_TELEPHONY) {
            abandonAudioFocusInternal();
        }
        
        if (interruptionSource == InterruptionSource.TELEPHONY_ONLY || 
            interruptionSource == InterruptionSource.AUDIO_FOCUS_AND_TELEPHONY) {
            unregisterTelephonyListener();
        }
    }
    
    private void requestAudioFocusInternal() {
        if (audioManager == null) {
            Log.w(TAG, "AudioManager is null, cannot request audio focus");
            return;
        }
        
        AudioManager.OnAudioFocusChangeListener onAudioFocusChangeListener = focusChange -> {
            switch (focusChange) {
                case AudioManager.AUDIOFOCUS_LOSS:
                case AudioManager.AUDIOFOCUS_LOSS_TRANSIENT:
                    Log.d(TAG, "Audio focus lost");
                    if (focusChangeListener != null) {
                        focusChangeListener.onInterruptionStart();
                    }
                    break;
                case AudioManager.AUDIOFOCUS_GAIN:
                    Log.d(TAG, "Audio focus gained");
                    if (focusChangeListener != null) {
                        focusChangeListener.onInterruptionEnd();
                    }
                    break;
            }
        };
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            AudioAttributes audioAttributes = new AudioAttributes.Builder()
                    .setUsage(focusUsageType != null ? focusUsageType : AudioAttributes.USAGE_VOICE_COMMUNICATION)
                    .setContentType(focusContentType != null ? focusContentType : AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build();
                    
            audioFocusRequest = new AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                    .setAudioAttributes(audioAttributes)
                    .setOnAudioFocusChangeListener(onAudioFocusChangeListener)
                    .build();
                    
            audioManager.requestAudioFocus(audioFocusRequest);
        } else {
            int streamType = inferPreOStreamType(focusUsageType, focusContentType);
            audioManager.requestAudioFocus(onAudioFocusChangeListener,
                    streamType,
                    AudioManager.AUDIOFOCUS_GAIN);
        }
    }
    
    private int inferPreOStreamType(Integer usageType, Integer contentType) {
        if (usageType != null) {
            if (usageType == AudioAttributes.USAGE_MEDIA
                    || usageType == AudioAttributes.USAGE_GAME
                    || usageType == AudioAttributes.USAGE_ASSISTANT) {
                return AudioManager.STREAM_MUSIC;
            }
            if (usageType == AudioAttributes.USAGE_VOICE_COMMUNICATION
                    || usageType == AudioAttributes.USAGE_VOICE_COMMUNICATION_SIGNALLING) {
                return AudioManager.STREAM_VOICE_CALL;
            }
            if (usageType == AudioAttributes.USAGE_NOTIFICATION
                    || usageType == AudioAttributes.USAGE_NOTIFICATION_RINGTONE
                    || usageType == AudioAttributes.USAGE_NOTIFICATION_COMMUNICATION_REQUEST) {
                return AudioManager.STREAM_NOTIFICATION;
            }
            if (usageType == AudioAttributes.USAGE_ALARM) {
                return AudioManager.STREAM_ALARM;
            }
        }
        if (contentType != null) {
            if (contentType == AudioAttributes.CONTENT_TYPE_MUSIC
                    || contentType == AudioAttributes.CONTENT_TYPE_MOVIE) {
                return AudioManager.STREAM_MUSIC;
            }
            if (contentType == AudioAttributes.CONTENT_TYPE_SPEECH) {
                return AudioManager.STREAM_VOICE_CALL;
            }
        }
        return AudioManager.STREAM_MUSIC;
    }
    
    private void registerTelephonyListener() {
        if (telephonyManager == null) {
            Log.w(TAG, "TelephonyManager is null, cannot register telephony listener");
            return;
        }
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // Use TelephonyCallback for Android 12+ (API 31+)
            class CallStateCallback extends TelephonyCallback implements TelephonyCallback.CallStateListener {
                @Override
                public void onCallStateChanged(int state) {
                    handleCallStateChange(state);
                }
            }
            telephonyCallback = new CallStateCallback();
            telephonyManager.registerTelephonyCallback(context.getMainExecutor(), telephonyCallback);
        } else {
            // Use PhoneStateListener for older Android versions
            phoneStateListener = new PhoneStateListener() {
                @Override
                public void onCallStateChanged(int state, String phoneNumber) {
                    handleCallStateChange(state);
                }
            };
            telephonyManager.listen(phoneStateListener, PhoneStateListener.LISTEN_CALL_STATE);
        }
    }
    
    private void handleCallStateChange(int state) {
        if (focusChangeListener == null) {
            return;
        }
        
        switch (state) {
            case TelephonyManager.CALL_STATE_RINGING:
            case TelephonyManager.CALL_STATE_OFFHOOK:
                Log.d(TAG, "Phone call interruption began");
                focusChangeListener.onInterruptionStart();
                break;
            case TelephonyManager.CALL_STATE_IDLE:
                Log.d(TAG, "Phone call interruption ended");
                focusChangeListener.onInterruptionEnd();
                break;
        }
    }
    
    private void abandonAudioFocusInternal() {
        if (audioManager == null) {
            return;
        }
        
        int result;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && audioFocusRequest != null) {
            result = audioManager.abandonAudioFocusRequest(audioFocusRequest);
        } else {
            result = audioManager.abandonAudioFocus(null);
        }
    }
    
    private void unregisterTelephonyListener() {
        if (telephonyManager == null) {
            return;
        }
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && telephonyCallback != null) {
            telephonyManager.unregisterTelephonyCallback(telephonyCallback);
            telephonyCallback = null;
        } else if (phoneStateListener != null) {
            telephonyManager.listen(phoneStateListener, PhoneStateListener.LISTEN_NONE);
            phoneStateListener = null;
        }
    }
} 