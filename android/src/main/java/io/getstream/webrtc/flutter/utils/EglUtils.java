package io.getstream.webrtc.flutter.utils;

import android.os.Build;

import org.webrtc.EglBase;

public class EglUtils {
    /**
     * The root {@link EglBase} instance shared by the entire application for
     * the sake of reducing the utilization of system resources (such as EGL
     * contexts).
     */
    private static EglBase rootEglBase;

    /**
     * Whether renderer surfaces are configured with an alpha channel.
     *
     * <p>An alpha surface forces the system compositor to blend rather than
     * overwrite, on every frame of every video tile. Video is opaque, so that
     * cost buys nothing in the common case.
     *
     * <p>It is not free to turn off, though: an alpha config was originally
     * adopted to stop Impeller blending the background into the video texture
     * on some devices. Set this to true to get that behaviour back if the
     * artifact reappears.
     */
    private static boolean useAlphaConfig = false;

    /**
     * Selects the EGL config used for the root context and every renderer
     * surface. Must be called before the first renderer is created; changing it
     * afterwards has no effect on already-created contexts.
     */
    public static synchronized void setUseAlphaConfig(boolean enabled) {
        useAlphaConfig = enabled;
    }

    public static synchronized boolean isUsingAlphaConfig() {
        return useAlphaConfig;
    }

    /**
     * The config attributes renderer surfaces should be created with.
     */
    public static synchronized int[] getConfigAttributes() {
        return useAlphaConfig ? EglBase.CONFIG_RGBA : EglBase.CONFIG_PLAIN;
    }

    /**
     * Lazily creates and returns the one and only {@link EglBase} which will
     * serve as the root for all contexts that are needed.
     */
    public static synchronized EglBase getRootEglBase() {
        if (rootEglBase == null) {
            final int[] configAttributes = getConfigAttributes();
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP)
                rootEglBase = EglBase.createEgl10(configAttributes);
            else
                rootEglBase = EglBase.create(null, configAttributes);
        }

        return rootEglBase;
    }

    public static EglBase.Context getRootEglBaseContext() {
        EglBase eglBase = getRootEglBase();

        return eglBase == null ? null : eglBase.getEglBaseContext();
    }
}
