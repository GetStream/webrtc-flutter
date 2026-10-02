package org.webrtc;

import androidx.annotation.Nullable;

import java.util.ArrayList;
import java.util.List;

/**
 * Picks the camera capture format for a requested size.
 *
 * <p>libwebrtc's camera sessions choose the supported size with the smallest
 * {@code |width - requested.width| + |height - requested.height|}
 * ({@link CameraEnumerationAndroid#getClosestSupportedSize}). That rule ignores the aspect ratio,
 * so a camera that offers a 2:1 format next to its 16:9 ones answers a 2560x1440 request with
 * 2560x1280 (difference 160) rather than 1920x1080 (difference 1000). Pixel phones do exactly
 * this, and the encoder then publishes a 1280x2560 portrait frame nobody asked for.
 *
 * <p>This selector keeps the requested aspect ratio first: among the supported sizes whose aspect
 * ratio is within {@link #ASPECT_TOLERANCE} of the request it picks libwebrtc's closest size, so an
 * exact match still wins and the behaviour is unchanged for cameras without odd formats. When no
 * size has the requested aspect ratio it falls back to the sizes with the nearest aspect ratio,
 * then to the closest size among those. The caller passes the chosen size to
 * {@code startCapture}, where libwebrtc's own rule then finds it at difference 0.
 */
public final class CaptureSizeSelector {
    /** Relative aspect-ratio difference that still counts as "the same aspect ratio". */
    static final double ASPECT_TOLERANCE = 0.02;

    private CaptureSizeSelector() {}

    /**
     * The capture format to open for a {@code width}x{@code height} request, or null when
     * there are no sizes to choose from. Sizes and the request are compared orientation-free
     * (long edge over short edge), since camera formats are listed in sensor space.
     */
    @Nullable
    public static Size select(@Nullable List<Size> sizes, int width, int height) {
        if (sizes == null || sizes.isEmpty()) return null;
        if (width <= 0 || height <= 0) {
            return CameraEnumerationAndroid.getClosestSupportedSize(sizes, width, height);
        }

        final double wanted = aspect(width, height);
        List<Size> candidates = new ArrayList<>();
        double bestDeviation = Double.MAX_VALUE;
        for (Size size : sizes) {
            if (size.width <= 0 || size.height <= 0) continue;
            double deviation = Math.abs(aspect(size.width, size.height) - wanted) / wanted;
            if (deviation <= ASPECT_TOLERANCE) {
                if (bestDeviation > ASPECT_TOLERANCE) candidates.clear();
                bestDeviation = Math.min(bestDeviation, deviation);
                candidates.add(size);
            } else if (candidates.isEmpty() || bestDeviation > ASPECT_TOLERANCE) {
                // No size with the requested aspect ratio seen yet: keep the nearest ones.
                if (deviation < bestDeviation - 1e-9) {
                    candidates.clear();
                    bestDeviation = deviation;
                    candidates.add(size);
                } else if (Math.abs(deviation - bestDeviation) <= 1e-9) {
                    candidates.add(size);
                }
            }
        }
        if (candidates.isEmpty()) return CameraEnumerationAndroid.getClosestSupportedSize(sizes, width, height);
        return CameraEnumerationAndroid.getClosestSupportedSize(candidates, width, height);
    }

    /** The distinct sizes of the given formats, in first-seen order; formats repeat per frame-rate range. */
    public static List<Size> distinctSizes(@Nullable List<CameraEnumerationAndroid.CaptureFormat> formats) {
        List<Size> sizes = new ArrayList<>();
        if (formats == null) return sizes;
        for (CameraEnumerationAndroid.CaptureFormat format : formats) {
            Size size = new Size(format.width, format.height);
            if (!sizes.contains(size)) sizes.add(size);
        }
        return sizes;
    }

    /** "WxH, WxH, ..." for a log line, or "none". */
    public static String describe(@Nullable List<Size> sizes) {
        if (sizes == null || sizes.isEmpty()) return "none";
        StringBuilder sb = new StringBuilder();
        for (Size size : sizes) {
            if (sb.length() > 0) sb.append(", ");
            sb.append(size.width).append('x').append(size.height);
        }
        return sb.toString();
    }

    static double aspect(int width, int height) {
        return (double) Math.max(width, height) / Math.min(width, height);
    }
}
