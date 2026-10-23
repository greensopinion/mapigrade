package com.greensopinion.flutter_mapigrade

import android.graphics.ImageFormat
import android.hardware.HardwareBuffer
import android.media.Image
import android.media.ImageReader
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import android.view.Surface
import io.flutter.view.TextureRegistry
import java.util.IdentityHashMap

/**
 * The image texture and image readers of one map. The map renders into the surface of the current
 * reader. A listener on a thread of its own acquires each image and passes it to the native render
 * target at address [target], which keeps the images of its display slots, gives the chosen one to
 * Flutter with [push] and releases each with [closeImage].
 *
 * Native code creates, resizes and releases this object on the main thread.
 */
internal class MapSurface(registry: TextureRegistry, private val target: Long) {
    private val entry = registry.createImageTexture()
    private val thread = HandlerThread("flutter_mapigrade images").apply { start() }
    private val handler = Handler(thread.looper)

    private val lock = Any()

    // Guarded by lock: the number of open images of each reader, the reader of each open image,
    // the reader the map renders into, and whether release() was called.
    private val openImages = IdentityHashMap<ImageReader, Int>()
    private val readerOf = IdentityHashMap<Image, ImageReader>()
    // Readers whose last acquisition failed because all their images were open. An image that
    // Android queued then stays queued, and the reader calls the listener again only for the next
    // frame, so closing one of the reader's images retries the acquisition.
    private val starved = IdentityHashMap<ImageReader, Boolean>()
    private var current: ImageReader? = null
    private var released = false

    fun id(): Long = entry.id()

    /**
     * Creates a reader of the given size and returns the surface to render into. The previous
     * reader is closed once it has no open image.
     */
    fun resize(width: Int, height: Int): Surface {
        val reader =
            ImageReader.newInstance(
                maxOf(width, 1),
                maxOf(height, 1),
                ImageFormat.PRIVATE,
                MAX_IMAGES,
                HardwareBuffer.USAGE_GPU_SAMPLED_IMAGE,
            )
        reader.setOnImageAvailableListener(::onImageAvailable, handler)
        synchronized(lock) {
            val previous = current
            current = reader
            openImages[reader] = 0
            previous?.let { closeReaderIfUnusedLocked(it) }
        }
        return reader.surface
    }

    /** Gives [image] to Flutter for the Flutter frame being built. */
    fun push(image: Image) {
        entry.pushImage(image)
    }

    /** Closes [image], and its reader if that is no longer current and has no open image. */
    fun closeImage(image: Image) {
        synchronized(lock) {
            image.close()
            val reader = readerOf.remove(image) ?: return
            openImages[reader] = (openImages[reader] ?: 1) - 1
            if (starved.remove(reader) != null && openImages.containsKey(reader)) {
                handler.post { onImageAvailable(reader) }
            }
            closeReaderIfUnusedLocked(reader)
        }
    }

    /**
     * Closes the readers once their images are closed, so that the map doesn't render until
     * [resize] creates a reader again.
     */
    fun releaseReaders() {
        synchronized(lock) {
            current = null
            for (reader in openImages.keys.toList()) closeReaderIfUnusedLocked(reader)
        }
    }

    /**
     * Releases the texture, the readers and their images. Returns after the listener thread has
     * stopped, so that it no longer calls the native target.
     */
    fun release() {
        synchronized(lock) { released = true }
        thread.quitSafely()
        thread.join()
        synchronized(lock) {
            for (image in readerOf.keys) image.close()
            readerOf.clear()
            for (reader in openImages.keys) reader.close()
            openImages.clear()
            current = null
        }
        entry.release()
    }

    private fun onImageAvailable(reader: ImageReader) {
        while (true) {
            val image =
                try {
                    reader.acquireNextImage()
                } catch (e: IllegalStateException) {
                    // All the reader's images are open, or it was closed.
                    synchronized(lock) {
                        val open = openImages[reader] ?: return
                        Log.w(
                            TAG,
                            "acquireNextImage failed with $open open images; retrying when one " +
                                "is closed; open frames: " +
                                readerOf.entries.filter { it.value === reader }
                                    .map { it.key.timestamp },
                        )
                        // An image closed since the attempt doesn't retry by itself.
                        if (open < MAX_IMAGES) {
                            handler.post { onImageAvailable(reader) }
                        } else {
                            starved[reader] = true
                        }
                    }
                    null
                } ?: return
            synchronized(lock) {
                if (released || !openImages.containsKey(reader)) {
                    image.close()
                    return
                }
                openImages[reader] = (openImages[reader] ?: 0) + 1
                readerOf[image] = reader
            }
            // The timestamp is the frame id, which the map thread set as the presentation time.
            if (!nativeFrameImage(target, image.timestamp, image)) closeImage(image)
        }
    }

    private fun closeReaderIfUnusedLocked(reader: ImageReader) {
        if (reader === current || (openImages[reader] ?: 0) > 0) return
        openImages.remove(reader)
        starved.remove(reader)
        reader.close()
    }

    private external fun nativeFrameImage(target: Long, frameId: Long, image: Image): Boolean

    private companion object {
        const val TAG = "flutter_mapigrade"

        // One image per display slot.
        const val MAX_IMAGES = 6
    }
}
