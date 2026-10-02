package org.webrtc;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNull;

import java.util.Arrays;
import java.util.Collections;
import java.util.List;

import org.junit.Test;

public class CaptureSizeSelectorTest {

    /** The front camera of a Pixel 6a as it lists its sizes: a 2:1 format next to the 16:9 and 4:3 ones. */
    private static final List<Size> PIXEL_FRONT = Arrays.asList(
            new Size(3264, 2448), new Size(2560, 1920), new Size(2560, 1280), new Size(1920, 1080),
            new Size(1600, 1200), new Size(1280, 720), new Size(640, 480), new Size(320, 240));

    @Test
    public void keepsTheRequestedAspectRatioOverASmallerEdgeDifference() {
        // libwebrtc alone would pick 2560x1280 (difference 160) for this request.
        assertEquals(new Size(1920, 1080), CaptureSizeSelector.select(PIXEL_FRONT, 2560, 1440));
    }

    @Test
    public void exactMatchStillWins() {
        assertEquals(new Size(1280, 720), CaptureSizeSelector.select(PIXEL_FRONT, 1280, 720));
        assertEquals(new Size(640, 480), CaptureSizeSelector.select(PIXEL_FRONT, 640, 480));
    }

    @Test
    public void fourByThreeRequestGetsFourByThree() {
        assertEquals(new Size(1600, 1200), CaptureSizeSelector.select(PIXEL_FRONT, 1440, 1080));
        assertEquals(new Size(2560, 1920), CaptureSizeSelector.select(PIXEL_FRONT, 2560, 1920));
    }

    @Test
    public void requestOrientationDoesNotMatter() {
        // The SDK may ask in portrait; formats are in sensor space.
        assertEquals(new Size(1920, 1080), CaptureSizeSelector.select(PIXEL_FRONT, 1440, 2560));
    }

    @Test
    public void fallsBackToTheNearestAspectRatioWhenNoneMatches() {
        List<Size> only43and21 = Arrays.asList(new Size(2560, 1920), new Size(2560, 1280), new Size(640, 480));
        // 2:1 (2.0) is nearer to 16:9 (1.78) than 4:3 (1.33) is.
        assertEquals(new Size(2560, 1280), CaptureSizeSelector.select(only43and21, 2560, 1440));
    }

    @Test
    public void unchangedForCamerasWithoutOddFormats() {
        List<Size> plain = Arrays.asList(new Size(1920, 1080), new Size(1280, 720), new Size(640, 480));
        for (Size size : plain) {
            assertEquals(size, CaptureSizeSelector.select(plain, size.width, size.height));
        }
        assertEquals(new Size(1920, 1080), CaptureSizeSelector.select(plain, 2560, 1440));
        assertEquals(
                CameraEnumerationAndroid.getClosestSupportedSize(plain, 2560, 1440),
                CaptureSizeSelector.select(plain, 2560, 1440));
    }

    @Test
    public void nullOrEmptyGivesNull() {
        assertNull(CaptureSizeSelector.select(null, 1280, 720));
        assertNull(CaptureSizeSelector.select(Collections.<Size>emptyList(), 1280, 720));
    }

    @Test
    public void distinctSizesDropsRepeatsPerFrameRateRange() {
        List<CameraEnumerationAndroid.CaptureFormat> formats = Arrays.asList(
                new CameraEnumerationAndroid.CaptureFormat(1920, 1080, 15000, 30000),
                new CameraEnumerationAndroid.CaptureFormat(1920, 1080, 30000, 30000),
                new CameraEnumerationAndroid.CaptureFormat(1280, 720, 30000, 30000));
        assertEquals(Arrays.asList(new Size(1920, 1080), new Size(1280, 720)),
                CaptureSizeSelector.distinctSizes(formats));
        assertEquals("1920x1080, 1280x720", CaptureSizeSelector.describe(CaptureSizeSelector.distinctSizes(formats)));
    }
}
