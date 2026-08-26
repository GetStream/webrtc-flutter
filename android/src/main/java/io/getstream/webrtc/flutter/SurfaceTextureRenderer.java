package io.getstream.webrtc.flutter;

import android.graphics.SurfaceTexture;
import android.view.Surface;

import org.webrtc.EglBase;
import org.webrtc.EglRenderer;
import org.webrtc.GlRectDrawer;
import org.webrtc.RendererCommon;
import org.webrtc.ThreadUtils;
import org.webrtc.VideoFrame;

import java.util.concurrent.CountDownLatch;

import io.flutter.view.TextureRegistry;
import io.getstream.webrtc.flutter.utils.EglUtils;

/**
 * Display the video stream on a Surface.
 * renderFrame() is asynchronous to avoid blocking the calling thread.
 * This class is thread safe and handles access from potentially three different threads:
 * Interaction from the main app in init, release and setMirror.
 * Interaction from C++ rtc::VideoSinkInterface in renderFrame.
 * Interaction from SurfaceHolder lifecycle in surfaceCreated, surfaceChanged, and surfaceDestroyed.
 */
public class SurfaceTextureRenderer extends EglRenderer {
  // Callback for reporting renderer events. Read-only after initilization so no lock required.
  private RendererCommon.RendererEvents rendererEvents;
  private final Object layoutLock = new Object();
  private boolean isRenderingPaused;
  private boolean isFirstFrameRendered;
  private int rotatedFrameWidth;
  private int rotatedFrameHeight;
  private int frameRotation;

  /**
   * In order to render something, you must first call init().
   */
  public SurfaceTextureRenderer(String name) {
    super(name);
  }

  public void init(final EglBase.Context sharedContext,
      RendererCommon.RendererEvents rendererEvents) {
    init(sharedContext, rendererEvents, EglUtils.getConfigAttributes(), new GlRectDrawer());
  }

  /**
   * Initialize this class, sharing resources with |sharedContext|. The custom |drawer| will be used
   * for drawing frames on the EGLSurface. This class is responsible for calling release() on
   * |drawer|. It is allowed to call init() to reinitialize the renderer after a previous
   * init()/release() cycle.
   */
  public void init(final EglBase.Context sharedContext,
                   RendererCommon.RendererEvents rendererEvents, final int[] configAttributes,
                   RendererCommon.GlDrawer drawer) {
    ThreadUtils.checkIsOnMainThread();
    this.rendererEvents = rendererEvents;
    synchronized (layoutLock) {
      isFirstFrameRendered = false;
      rotatedFrameWidth = 0;
      rotatedFrameHeight = 0;
      frameRotation = -1;
    }
    super.init(sharedContext, configAttributes, drawer);
  }
  @Override
  public void init(final EglBase.Context sharedContext, final int[] configAttributes,
                   RendererCommon.GlDrawer drawer) {
    init(sharedContext, null /* rendererEvents */, configAttributes, drawer);
  }
  /**
   * Limit render framerate.
   *
   * @param fps Limit render framerate to this value, or use Float.POSITIVE_INFINITY to disable fps
   *            reduction.
   */
  @Override
  public void setFpsReduction(float fps) {
    synchronized (layoutLock) {
      isRenderingPaused = fps == 0f;
    }
    super.setFpsReduction(fps);
  }
  @Override
  public void disableFpsReduction() {
    synchronized (layoutLock) {
      isRenderingPaused = false;
    }
    super.disableFpsReduction();
  }
  @Override
  public void pauseVideo() {
    synchronized (layoutLock) {
      isRenderingPaused = true;
    }
    super.pauseVideo();
  }
  /**
   * The size of the widget this renderer draws into, in physical pixels, or 0
   * when unknown.
   *
   * <p>Sizing the texture to the stream instead of the widget means a 1080p
   * remote in a 120px thumbnail allocates a full 1080p texture, pays a full-res
   * draw every frame, and leaves the downscale to Flutter's compositor. Capping
   * at the widget size makes the GL draw do the downscale once.
   */
  private int viewWidth;
  private int viewHeight;

  /**
   * Sets the size of the widget this renderer draws into, in physical pixels.
   *
   * <p>Pass 0 for either dimension to go back to sizing the texture to the
   * incoming stream.
   */
  public void setViewSize(int width, int height) {
    final int targetWidth;
    final int targetHeight;
    synchronized (layoutLock) {
      if (viewWidth == width && viewHeight == height) {
        return;
      }
      viewWidth = Math.max(0, width);
      viewHeight = Math.max(0, height);
      targetWidth = rotatedFrameWidth;
      targetHeight = rotatedFrameHeight;
    }

    // Re-size against the last known frame so the change takes effect without
    // waiting for the stream resolution to happen to change.
    if (targetWidth > 0 && targetHeight > 0) {
      synchronized (surfaceLock) {
        if (surface != null) {
          resizeSurface(targetWidth, targetHeight);
        }
      }
    }
  }

  /**
   * The texture size to use for a frame of the given rotated dimensions.
   *
   * <p>Never upscales: a stream smaller than the widget keeps its own size and
   * lets the compositor scale it up, which is cheaper than drawing more pixels
   * than the stream actually has.
   */
  private int[] targetSurfaceSize(int frameWidth, int frameHeight) {
    final int boundWidth;
    final int boundHeight;
    synchronized (layoutLock) {
      boundWidth = viewWidth;
      boundHeight = viewHeight;
    }

    if (boundWidth <= 0 || boundHeight <= 0 || frameWidth <= 0 || frameHeight <= 0) {
      return new int[] {frameWidth, frameHeight};
    }

    final float scale =
        Math.min(1f, Math.min((float) boundWidth / frameWidth, (float) boundHeight / frameHeight));

    return new int[] {
        Math.max(1, Math.round(frameWidth * scale)), Math.max(1, Math.round(frameHeight * scale))
    };
  }

  // VideoSink interface.
  @Override
  public void onFrame(VideoFrame frame) {
    final int[] size = targetSurfaceSize(frame.getRotatedWidth(), frame.getRotatedHeight());
    synchronized (surfaceLock) {
      if (surface == null) {
        producer.setSize(size[0], size[1]);
        surface = producer.getSurface();
        createEglSurface(surface);
        surfaceWidth = size[0];
        surfaceHeight = size[1];
      } else if (size[0] != surfaceWidth || size[1] != surfaceHeight) {
        resizeSurface(size[0], size[1]);
      }
    }
    updateFrameDimensionsAndReportEvents(frame);
    super.onFrame(frame);
  }

  /**
   * The size the EGL surface was last created at.
   *
   * <p>Tracked separately from the frame dimensions so the surface is only
   * recreated when the *texture* size actually changes. Once the texture is
   * capped at the widget size, a simulcast layer switch usually maps to the
   * same texture size and no longer costs a teardown.
   */
  private int surfaceWidth;
  private int surfaceHeight;

  /**
   * Recreates the EGL surface at a new size.
   *
   * <p>The producer's backing buffers are fixed-size: setSize() only takes
   * effect for a Surface obtained afterwards. Without recreating the EGL
   * surface here, a simulcast layer upgrade keeps rendering into the old
   * low-resolution buffer and the video stays blurry.
   *
   * <p>Caller must hold {@link #surfaceLock}.
   */
  private void resizeSurface(int width, int height) {
    releaseEglSurface(() -> {});
    // Clear the field before re-obtaining: if getSurface() throws, the next
    // frame takes the surface == null path and recreates cleanly rather than
    // rendering into the already-released surface.
    surface = null;
    producer.setSize(width, height);
    surface = producer.getSurface();
    createEglSurface(surface);
    surfaceWidth = width;
    surfaceHeight = height;
  }

  // Guards surface lifecycle transitions: creation/recreation happens on the
  // frame delivery thread while destruction arrives on the main thread via
  // the producer's onSurfaceCleanup callback. Serializing the two prevents a
  // frame from re-creating the EGL surface against a Surface the producer is
  // concurrently invalidating. surfaceDestroyed() blocks on the EGL release
  // while holding this lock; the latch is signaled by the EglRenderer render
  // thread, which never acquires it, so the wait cannot deadlock.
  private final Object surfaceLock = new Object();
  private Surface surface = null;

  private TextureRegistry.SurfaceProducer producer;

  public void surfaceCreated(final TextureRegistry.SurfaceProducer producer) {
    ThreadUtils.checkIsOnMainThread();
    this.producer = producer;
    this.producer.setCallback(
        new TextureRegistry.SurfaceProducer.Callback() {
          @Override
          public void onSurfaceAvailable() {
            // Do surface initialization here, and draw the current frame.
          }

          @Override
          public void onSurfaceCleanup() {
            onSurfaceCleanup();
          }
        });
  }

  public void onSurfaceCleanup() {
    ThreadUtils.checkIsOnMainThread();
    synchronized (surfaceLock) {
      final CountDownLatch completionLatch = new CountDownLatch(1);
      releaseEglSurface(completionLatch::countDown);
      ThreadUtils.awaitUninterruptibly(completionLatch);
      surface = null;
      surfaceWidth = 0;
      surfaceHeight = 0;
    }
  }

  // Update frame dimensions and report any changes to |rendererEvents|.
  private void updateFrameDimensionsAndReportEvents(VideoFrame frame) {
    synchronized (layoutLock) {
      if (isRenderingPaused) {
        return;
      }
      if (!isFirstFrameRendered) {
        isFirstFrameRendered = true;
        if (rendererEvents != null) {
          rendererEvents.onFirstFrameRendered();
        }
      }
      if (rotatedFrameWidth != frame.getRotatedWidth()
              || rotatedFrameHeight != frame.getRotatedHeight()
              || frameRotation != frame.getRotation()) {
        if (rendererEvents != null) {
          rendererEvents.onFrameResolutionChanged(
                  frame.getBuffer().getWidth(), frame.getBuffer().getHeight(), frame.getRotation());
        }
        rotatedFrameWidth = frame.getRotatedWidth();
        rotatedFrameHeight = frame.getRotatedHeight();
        frameRotation = frame.getRotation();
      }
    }
  }
}
