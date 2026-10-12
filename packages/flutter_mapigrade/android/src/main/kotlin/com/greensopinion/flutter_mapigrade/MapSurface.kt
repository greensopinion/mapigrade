package com.greensopinion.flutter_mapigrade

import android.view.Surface
import io.flutter.view.TextureRegistry

/**
 * The Flutter SurfaceProducer of one map (design D51). Native code creates it, resizes it and
 * releases it on the main thread, and receives the producer's callbacks for the native render
 * target at address [target].
 *
 * The producer resets in the background: Flutter removes its surface when the activity stops or
 * under memory pressure, and provides it again when the activity resumes.
 */
internal class MapSurface(registry: TextureRegistry, private val target: Long) :
    TextureRegistry.SurfaceProducer.Callback {
    private val producer =
        registry.createSurfaceProducer(TextureRegistry.SurfaceLifecycle.resetInBackground)

    // Whether resize() has set a size. Before that, the map has no surface to replace.
    private var sized = false

    init {
        producer.setCallback(this)
    }

    fun id(): Long = producer.id()

    /** Sets the size of the buffers and returns the surface to render into at that size. */
    fun resize(width: Int, height: Int): Surface {
        producer.setSize(width, height)
        sized = true
        return producer.surface
    }

    fun release() {
        producer.setCallback(null)
        producer.release()
    }

    override fun onSurfaceAvailable() {
        if (sized) nativeSurfaceAvailable(target, producer.surface)
    }

    override fun onSurfaceCleanup() {
        nativeSurfaceCleanup(target)
    }

    private external fun nativeSurfaceAvailable(target: Long, surface: Surface)

    private external fun nativeSurfaceCleanup(target: Long)
}
