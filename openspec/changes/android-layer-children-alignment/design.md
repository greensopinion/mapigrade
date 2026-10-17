## Context

See proposal.md for the motivation. The current state on Android:

- `AndroidSurfaceTarget` (`android/src/main/cpp/map_texture_android.cpp`) renders through an EGL window surface on the `Surface` of one `SurfaceProducer`, created with `SurfaceLifecycle.resetInBackground` (D51, D54). It has one display slot. `map_texture_select` does nothing, and `RenderIntoSurface` sends a frame-displayed event with no display time after each render (D128). Renders are paced to one per display refresh interval, and the window surface uses swap interval 0, so a swap never waits for Flutter's main thread (D53).
- The layer chooses frames only when `textureIds.length > 1`, and otherwise draws its children at the live camera (`map_texture_layer.dart`).
- Flutter 3.47.5 implements `SurfaceProducer` as `ImageReaderSurfaceProducer` (`FlutterRenderer.java`). Its `ImageReader` listener runs on the main looper. Each reader queues up to two images, and the raster thread takes the oldest queued image each time it paints the texture. The producer closes an image after the raster thread has taken three later images.
- `TextureRegistry.createImageTexture()` returns an `ImageTextureEntry`. `pushImage(image)` replaces the entry's pending image, closes the replaced one and schedules an engine frame. The raster thread takes the pending image when it paints the texture (`ImageExternalTexture::ProcessFrame`), and keeps drawing it until it takes another. The engine never closes an image it took, so the caller closes it. The entry is registered with `resetOnBackground` false, so Flutter keeps the last image when its GPU context is destroyed.
- Flutter's frame pipeline holds two layer trees: a Dart build starts only after the raster thread has finished the build before the previous one.

## Goals / Non-Goals

**Goals:**
- The slot protocol of layer-children-alignment on Android, with the same C ABI and Dart API, so that the layer has no platform branch.
- A swap never waits for the main thread, and the map thread never calls into Java (D53, D54).

**Non-Goals:**
- An exact signal that Flutter has finished with an image. Flutter provides none for image textures.
- A copy option on Android. Every map still renders directly into the displayed buffers.

## Decisions

### D130. A plugin-owned `ImageReader` and an image texture replace the `SurfaceProducer`

`MapSurface.kt` creates an `ImageTextureEntry` and, for each physical size, an `ImageReader` (`ImageFormat.PRIVATE`, `maxImages` 6, usage `GPU_SAMPLED_IMAGE`, as Flutter's own reader uses; EGL adds the usage it renders with). The map renders through an EGL window surface on the reader's `Surface`, as it renders on the producer's surface today. When Dart chooses a frame, the plugin pushes that frame's `Image` into the entry. Flutter displays the pushed image from the next Flutter frame that it rasterizes.

Alternatives:
- One `SurfaceProducer` per slot, as the layer-children-alignment change assumed. Each producer queues images in order, so a second render into a slot before Flutter paints it would make Flutter display the older frame. Its listener runs on the main looper, where Dart events can run before it, so Dart could choose a frame that hasn't reached Flutter's queue yet. The producer also closes images on its own schedule.
- Keep one producer and give the children the live camera: the current state, which the proposal rejects.

### D131. A frame is ready when the plugin holds its image

Before each swap, the map thread sets the frame id as the buffer's presentation time (`eglPresentationTimeANDROID`). The reader's listener runs on a `HandlerThread` that the plugin owns. It acquires each image with `acquireNextImage` and calls the native target with the image's timestamp, which is the frame id. The core then publishes the frame into the slot that was rendering it and sends the frame-ready event. So when Dart learns of a frame, the plugin already holds its image, and `select` can push the image at once.

The window surface keeps swap interval 0. A queued buffer can then be replaced before the listener acquires it. When a newer frame arrives, the core frees any slot that still renders an older frame. A timestamp that matches no rendering slot is reported once as a render error, and its image is closed.

The listener can receive an image before `render_update` returns, because the swap happens inside it. The map thread therefore records the frame id in its slot before the render. An image that arrives while its slot still renders is kept, and the map thread publishes the frame when the render returns.

If an acquisition fails because all the reader's images are open, Android keeps the image queued, and calls the listener again only for the next frame, so the map would stop. The listener then retries when the plugin closes one of the reader's images, which is the only event after which the acquisition can succeed; it logs a warning with the frame ids of the open images. On the Pixel 4a (5G) this happened 4 times in one run of `map_texture_test.dart` and in none of the next three runs; the cause is unknown.

Alternative: send the frame-ready event from the map thread after the swap. Dart could then choose a frame whose image hasn't been acquired yet.

### D132. `map_texture_select` pushes the image on the main thread

`MapTexture::Select` records the choice in `BufferState`, as on macOS and iOS. When the choice is new, it calls the target, which calls `pushImage` through JNI on the main thread, where Dart's UI isolate runs. Selecting the slot chosen last again pushes nothing. Pushing the same `Image` again would make the entry close it. `Select` then sends the frame-displayed event with no display time, the first time Dart chooses a frame (spec, "Camera of each displayed frame"). `presented_frames` and the layer metrics count these events.

If two choices come before one raster, the entry closes the first image. The plugin later closes it again when its slot is freed, and `Image.close` does nothing on an image that is already closed.

### D133. Six slots, and a slot is freed after three later choices

`BufferState` gets a second release rule: a held slot becomes free when Dart has chosen three later frames. The Android target uses this rule, and the Darwin targets keep the `Present` rule (D124). At the latest, the slot's image is displayed by the raster of the build that chose the next frame. The third later choice is at least two builds after that build, and by Flutter's two-tree pipeline that raster has finished on the CPU. Flutter's own producer closes images at the same point. When a slot becomes free, the target closes its image. The thread that frees the slot closes the image: the main thread in `Select`, the listener thread when a newer frame replaces a ready frame.

`kMaxBufferCount` becomes 6, and Android uses six slots: three held (the displayed frame and the two chosen before it), one ready, one queued, whose image hasn't arrived yet, and one rendering. A seventh buffer is the one that EGL has dequeued. Each slot holds at most one acquired buffer, and the reader allows six, so a dequeue always finds a free buffer and a swap never waits. The buffer queue creates buffers only when they are needed, and keeps them until the reader is closed.

*Correction (2026-10-17):* the design first had five slots, without the queued one. On the Pixel 4a (5G), with interval pacing (D134), the map then found no free slot for 203 to 266 renders per 30 s pan; with six slots, for none.

Alternatives:
- Four later choices and seven slots, if the manual check shows tearing. That costs one more buffer.
- Release free buffers with `ImageReader.discardFreeBuffers()` when the map is idle, if the memory that the sixth and seventh buffers keep at rest matters.
- Count Dart frames instead of choices. A Dart frame that chooses no new frame doesn't displace the image Flutter displays, so frames say nothing about it.

### D134. Android keeps pacing renders by the display refresh interval

On Android the map renders once per display refresh interval, as before this change (D53), into a free slot. It doesn't wait for Dart to choose the latest frame. Dart chooses the newest ready frame in each Flutter frame, and a ready frame that Dart hasn't chosen is replaced by the next one. Publishing a frame frees the replaced slot, and wakes a render that waits for a free slot.

*Correction (2026-10-17):* the design first paced Android renders by Dart's choice, as on macOS and iOS (D124). On the Pixel 4a (5G) that halved the frame rate to 25.7 to 27.4 map frames per second: a frame reaches Dart only after its image arrives, about 10 ms after it is published, Dart chooses it in the next Flutter frame, and a render of about 12 ms then ends after the following refresh, so each frame took two refresh intervals. Rendering ahead (D19) starts only when a render takes longer than a whole refresh interval. The user chose interval pacing.

With interval pacing and six slots, the Pixel rendered as many frames as before this change, and Dart chose 50.8 to 51.7 per second, against 57.7 to 58.3 queued frames per second before it (Flutter then rasterized 1,641 to 1,713 Flutter frames in 30 s, so it showed at most 55 to 57 map frames per second). The map renders by its own clock, which drifts against the display refresh. In some Flutter frames two frames become ready and the older one is replaced, and in others none does and Flutter shows the same frame again. The user accepted this on 2026-10-17, expecting faster devices to show more frames.

Alternatives:
- Pacing by Dart's choice: rejected, see the correction.
- Start each render at a fixed point after a display refresh, from an `AChoreographer` frame callback on a thread with a looper (the alternative of D53). Each Flutter frame would then get one new frame. A later change can measure it.

### D135. The Android target keeps its kind, and gains slots

`AndroidSurfaceTarget` stays a `SurfaceRenderTarget`: the session presents through a window surface, and there is no copy and no `Present`. `SurfaceRenderTarget` gets `slot_count()` (6), `FrameAvailable(slot)` (push) and `SlotFreed(slot)` (close). `MapTexture` gets `OnFrameImage(frame_id)` for the listener. `RenderIntoSurface` acquires a free slot, records the frame id it renders, and leaves publishing to `OnFrameImage`, which marks the frame queued until then. The native target keeps a global reference to the `Image` of each slot. It sets the reference, pushes the image and closes it under the `BufferState` lock, so the three are ordered. It sets and closes references only on the listener thread and the main thread, and the map thread frees only slots without an image, so the map thread never calls into Java. Kotlin counts the open images of each reader, so that it can close a retired reader once its last image is closed. A target task, which replaces or removes the surface, frees the slots of queued frames, whose images may never arrive. `map_texture_texture_ids` returns six entries with the same id.

### D136. Resize creates a reader, and keeps the slots

`WillResize` (main thread) creates a reader of the new size and sends its window to the map thread, as `SurfaceProducer.setSize` and `getSurface` do today. The slots aren't reset. Frames of the old size stay in their slots until the release rule frees them, and Dart may still choose one, which the `Texture` widget scales to the viewport for that frame. A reader is closed when it isn't the current reader and has no open image. D126's fallback isn't needed on Android, because the entry keeps displaying the last pushed image.

### D137. The plugin releases the reader when the activity stops

In `onActivityStopped`, after pausing rendering, the plugin parks the session on the pbuffer surface, as `onSurfaceCleanup` does today (D54). It then closes every image and the reader, and resets the slots. Dart's choice of a frame from before the reset is then refused. In `onActivityStarted` it creates a reader and sends its window before it resumes rendering. `map_texture_trim_surfaces_for_testing` calls the same two steps. `nativeReduceMemoryUse` keeps releasing MapLibre's cached resources only.

Flutter released the producer's surface at every stop (D54), and its source says that Android 14 needs this. The plugin keeps that behavior.

### D138. Dart has no Android branch

The layer chooses frames on every platform. The `textureIds.length > 1` check and its comment go. The documentation of `textureIds`, `readyFrames`, `select`, `frames`, `presentedFrames`, `intervalWaits` and `maxSlotsInUse` drops the Android exceptions. The alignment benchmark still exits on Android, because Android has no display times (D58).

## Risks / Trade-offs

- [The GPU may still read an image after three later choices, if raster GPU work lags more than Flutter assumes. Then the map overwrites a displayed buffer and the map tears.] → The manual check looks for tearing during flings. If it shows up, use D133's alternative.
- [The plugin depends on details of `ImageTextureEntry` that Flutter doesn't document: the engine never closes a taken image, and `pushImage` closes the replaced image.] → An integration test fails if images leak: after 600 frames the map still renders. A Flutter upgrade reruns the integration tests on the Pixel.
- [`pushImage` logs "Dropping PlatformView Frame" at error level each time it replaces an image that Flutter hasn't taken.] → This happens only when Dart chooses two frames between two rasters. The manual check counts these log lines during a pan.
- [Renders paced by their own clock drift against the display refresh, so about 12% of rendered frames are never shown and some frames are shown twice (D134).] → Accepted by the user; a later change can align renders with the display refresh.
- [On Android below 13, Flutter doesn't wait on the image's fence, and may sample a frame that the GPU hasn't finished rendering.] → The same holds for the producer today. The reference device runs Android 14.
- [Up to seven buffers of the map's size: about 69 MB full screen on the Pixel 4a (5G).] → The memory measurement records PSS before and after.

## Migration Plan

The C ABI and Dart API don't change. Applications see children that follow the map on Android. Rollback is a revert of the change.
