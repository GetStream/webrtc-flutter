package io.getstream.webrtc.flutter;

import android.content.Context;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.os.PowerManager;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.annotation.RequiresApi;

/**
 * Steps camera capture down as the device heats up, and back up as it recovers.
 *
 * <p>Without this the camera captures at its initial configuration from the
 * first frame to the last regardless of device pressure, and the whole cost of
 * thermal recovery lands on the encoder. Mirrors the tiers the iOS side derives
 * from {@code AVCaptureDevice.systemPressureState}.
 *
 * <p>Transitions are debounced so a device hovering at a threshold cannot flap
 * the capture format: 3 s before stepping down, 1 s when already at
 * {@code THERMAL_STATUS_CRITICAL} or worse where waiting is itself a cost, and
 * 10 s before stepping back up. Every status change cancels any pending
 * transition, so a step-down scheduled before the device cooled off never lands
 * afterwards.
 *
 * <p>Requires API 29 ({@code PowerManager.addThermalStatusListener}); a no-op
 * below that.
 */
public class CameraThermalThrottle {

    public interface Listener {
        /** Applies a capture configuration. Always called on the main thread. */
        void onThermalCaptureTarget(int width, int height, int fps, @NonNull String status);

        /**
         * The configuration the camera is currently running at, as
         * {@code {width, height, fps}}, or null when no camera is running.
         *
         * <p>Used to pick up a baseline the first time throttling has something
         * to act on, so the throttle does not have to be told about every
         * camera that opens.
         */
        @Nullable
        int[] currentCaptureConfiguration();
    }

    private static final String TAG = "CameraThermalThrottle";

    private static final int MODERATE_MAX_FPS = 24;
    private static final int SEVERE_MAX_FPS = 15;
    private static final int CRITICAL_MAX_FPS = 10;
    private static final int SHUTDOWN_MAX_FPS = 5;

    private static final long DOWNGRADE_DELAY_MS = 3000L;
    private static final long CRITICAL_DOWNGRADE_DELAY_MS = 1000L;
    private static final long UPGRADE_DELAY_MS = 10000L;

    /** Resolution tiers; higher is worse. */
    private static final int TIER_BASE = 0;    // x1.0
    private static final int TIER_MEDIUM = 1;  // x0.75
    private static final int TIER_LOW = 2;     // x0.5

    private final Context context;
    private final Handler mainHandler = new Handler(Looper.getMainLooper());

    @Nullable
    private Listener listener;
    @Nullable
    private PowerManager powerManager;
    @Nullable
    private PowerManager.OnThermalStatusChangedListener thermalListener;
    @Nullable
    private Runnable pendingTransition;

    private boolean enabled;
    private int currentStatus = PowerManager.THERMAL_STATUS_NONE;
    private int currentTier = TIER_BASE;

    private int baselineWidth;
    private int baselineHeight;
    private int baselineFps;

    // Last configuration handed to the listener, so an unchanged target does not
    // churn the capture session.
    private int appliedWidth;
    private int appliedHeight;
    private int appliedFps;

    public CameraThermalThrottle(Context context) {
        this.context = context.getApplicationContext();
    }

    public void setListener(@Nullable Listener listener) {
        this.listener = listener;
    }

    public boolean isEnabled() {
        return enabled;
    }

    /** Whether the platform exposes a thermal signal at all. */
    public static boolean isSupported() {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q;
    }

    /**
     * Enables or disables throttling.
     *
     * @return whether throttling is active afterwards.
     */
    public boolean setEnabled(boolean enabled) {
        if (!isSupported()) {
            return false;
        }
        if (this.enabled == enabled) {
            return this.enabled;
        }

        this.enabled = enabled;
        if (enabled) {
            registerListener();
        } else {
            unregisterListener();
        }
        return this.enabled;
    }

    /**
     * Sets the capture configuration the tiers scale down from.
     *
     * <p>Call whenever capture is (re)configured for a reason unrelated to
     * thermals, so later step-downs scale from the current target.
     */
    public void setBaseline(int width, int height, int fps) {
        baselineWidth = width;
        baselineHeight = height;
        baselineFps = fps;
        appliedWidth = width;
        appliedHeight = height;
        appliedFps = fps;
    }

    public void stop() {
        setEnabled(false);
        cancelPendingTransition();
        baselineWidth = 0;
        baselineHeight = 0;
        baselineFps = 0;
    }

    @RequiresApi(api = Build.VERSION_CODES.Q)
    private void registerListener() {
        if (powerManager == null) {
            powerManager = (PowerManager) context.getSystemService(Context.POWER_SERVICE);
        }
        if (powerManager == null) {
            enabled = false;
            return;
        }

        thermalListener = status -> mainHandler.post(() -> handleStatus(status));
        powerManager.addThermalStatusListener(thermalListener);
        // addThermalStatusListener does not deliver the current value.
        handleStatus(powerManager.getCurrentThermalStatus());
    }

    private void unregisterListener() {
        if (powerManager != null && thermalListener != null
                && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            powerManager.removeThermalStatusListener(thermalListener);
        }
        thermalListener = null;
        cancelPendingTransition();
        currentStatus = PowerManager.THERMAL_STATUS_NONE;
        currentTier = TIER_BASE;
    }

    private void handleStatus(int status) {
        currentStatus = status;

        final int targetTier = tierForStatus(status);

        // Always drop a pending transition: the device may have cooled off
        // before a scheduled downgrade fired, and applying it then would be a
        // step backwards.
        cancelPendingTransition();

        if (targetTier == currentTier) {
            applyCurrentTarget();
            return;
        }

        final long delay = delayForTransition(targetTier);
        final Runnable transition = () -> {
            pendingTransition = null;
            currentTier = targetTier;
            applyCurrentTarget();
        };
        pendingTransition = transition;
        mainHandler.postDelayed(transition, delay);
    }

    private void cancelPendingTransition() {
        if (pendingTransition != null) {
            mainHandler.removeCallbacks(pendingTransition);
            pendingTransition = null;
        }
    }

    private int tierForStatus(int status) {
        if (status >= PowerManager.THERMAL_STATUS_CRITICAL) {
            return TIER_LOW;
        }
        if (status >= PowerManager.THERMAL_STATUS_SEVERE) {
            return TIER_MEDIUM;
        }
        return TIER_BASE;
    }

    private int fpsForStatus(int status) {
        if (status >= PowerManager.THERMAL_STATUS_SHUTDOWN) {
            return Math.min(baselineFps, SHUTDOWN_MAX_FPS);
        }
        if (status >= PowerManager.THERMAL_STATUS_CRITICAL) {
            return Math.min(baselineFps, CRITICAL_MAX_FPS);
        }
        if (status >= PowerManager.THERMAL_STATUS_SEVERE) {
            return Math.min(baselineFps, SEVERE_MAX_FPS);
        }
        if (status >= PowerManager.THERMAL_STATUS_MODERATE) {
            return Math.min(baselineFps, MODERATE_MAX_FPS);
        }
        return baselineFps;
    }

    private long delayForTransition(int targetTier) {
        if (targetTier > currentTier) {
            // Getting worse. Under critical pressure the wait is itself a cost.
            return currentStatus >= PowerManager.THERMAL_STATUS_CRITICAL
                    ? CRITICAL_DOWNGRADE_DELAY_MS
                    : DOWNGRADE_DELAY_MS;
        }
        // Recovering. Wait longer, so a brief dip does not immediately undo a
        // step-down that is still doing its job.
        return UPGRADE_DELAY_MS;
    }

    private void applyCurrentTarget() {
        final Listener listener = this.listener;
        if (listener == null) {
            return;
        }

        if (baselineWidth <= 0 || baselineHeight <= 0) {
            final int[] current = listener.currentCaptureConfiguration();
            if (current == null || current.length < 3) {
                return;
            }
            setBaseline(current[0], current[1], current[2]);
        }

        final double scale;
        switch (currentTier) {
            case TIER_MEDIUM:
                scale = 0.75;
                break;
            case TIER_LOW:
                scale = 0.5;
                break;
            default:
                scale = 1.0;
                break;
        }

        // Encoders want even dimensions.
        final int width = Math.max(2, ((int) (baselineWidth * scale)) & ~1);
        final int height = Math.max(2, ((int) (baselineHeight * scale)) & ~1);
        final int fps = Math.max(1, fpsForStatus(currentStatus));

        if (width == appliedWidth && height == appliedHeight && fps == appliedFps) {
            return;
        }

        appliedWidth = width;
        appliedHeight = height;
        appliedFps = fps;

        listener.onThermalCaptureTarget(width, height, fps, statusName(currentStatus));
    }

    /** The status as a lowercase name, matching the iOS pressure levels. */
    static String statusName(int status) {
        switch (status) {
            case PowerManager.THERMAL_STATUS_NONE:
                return "nominal";
            case PowerManager.THERMAL_STATUS_LIGHT:
                return "fair";
            case PowerManager.THERMAL_STATUS_MODERATE:
                return "fair";
            case PowerManager.THERMAL_STATUS_SEVERE:
                return "serious";
            case PowerManager.THERMAL_STATUS_CRITICAL:
                return "critical";
            case PowerManager.THERMAL_STATUS_EMERGENCY:
            case PowerManager.THERMAL_STATUS_SHUTDOWN:
                return "shutdown";
            default:
                return "unknown";
        }
    }
}
