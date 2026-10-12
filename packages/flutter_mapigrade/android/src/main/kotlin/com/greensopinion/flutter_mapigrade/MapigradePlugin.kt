package com.greensopinion.flutter_mapigrade

import android.app.Activity
import android.app.Application
import android.content.ComponentCallbacks2
import android.content.Context
import android.content.res.Configuration
import android.os.Bundle
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.embedding.engine.renderer.FlutterRenderer
import io.flutter.view.TextureRegistry

/**
 * Loads the plugin's native library, which Dart calls through @Native bindings, and passes it the
 * texture registry and the application context (design D54). Rendering pauses while the Flutter
 * activity is stopped, and the renderers release cached resources under memory pressure (D55).
 *
 * The plugin supports one Flutter engine per process, as on macOS and iOS.
 */
class MapigradePlugin : FlutterPlugin, ActivityAware {
    private var applicationContext: Context? = null
    private var activity: Activity? = null

    private val activityCallbacks =
        object : Application.ActivityLifecycleCallbacks {
            override fun onActivityStarted(started: Activity) {
                if (started === activity) nativeSetPaused(false)
            }

            override fun onActivityStopped(stopped: Activity) {
                if (stopped === activity) nativeSetPaused(true)
            }

            override fun onActivityCreated(created: Activity, state: Bundle?) {}

            override fun onActivityResumed(resumed: Activity) {}

            override fun onActivityPaused(paused: Activity) {}

            override fun onActivitySaveInstanceState(saved: Activity, state: Bundle) {}

            override fun onActivityDestroyed(destroyed: Activity) {}
        }

    private val memoryCallbacks =
        object : ComponentCallbacks2 {
            override fun onTrimMemory(level: Int) {
                @Suppress("DEPRECATION")
                if (level >= ComponentCallbacks2.TRIM_MEMORY_BACKGROUND) nativeReduceMemoryUse()
            }

            @Deprecated("Deprecated in Java")
            override fun onLowMemory() {
                nativeReduceMemoryUse()
            }

            override fun onConfigurationChanged(configuration: Configuration) {}
        }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        System.loadLibrary("flutter_mapigrade")
        val context = binding.applicationContext
        applicationContext = context
        renderer = binding.flutterEngine.renderer
        nativeInit(binding.textureRegistry, context, context.cacheDir.absolutePath)
        context.registerComponentCallbacks(memoryCallbacks)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext?.unregisterComponentCallbacks(memoryCallbacks)
        applicationContext = null
        renderer = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        val attached = binding.activity
        activity = attached
        attached.application.registerActivityLifecycleCallbacks(activityCallbacks)
        // An activity that isn't started yet, or is already stopped, gets no stop callback
        // before its next start, so rendering pauses here; the start callback resumes it.
        val started =
            (attached as? LifecycleOwner)?.lifecycle?.currentState?.isAtLeast(Lifecycle.State.STARTED)
                ?: true
        if (!started) nativeSetPaused(true)
    }

    override fun onDetachedFromActivity() {
        activity?.application?.unregisterActivityLifecycleCallbacks(activityCallbacks)
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        onDetachedFromActivity()
    }

    private external fun nativeInit(registry: TextureRegistry, context: Context, cacheDir: String)

    private external fun nativeSetPaused(paused: Boolean)

    private external fun nativeReduceMemoryUse()

    companion object {
        private var renderer: FlutterRenderer? = null

        /**
         * For tests (map_texture_trim_surfaces_for_testing): makes Flutter remove the surfaces of
         * the surface producers, as FlutterActivity does when it stops, or provide them again, as
         * it does when it resumes. Called on the main thread.
         */
        @JvmStatic
        fun trimSurfacesForTesting(restore: Boolean) {
            val renderer = renderer ?: return
            if (restore) {
                renderer.restoreSurfaceProducers()
            } else {
                @Suppress("DEPRECATION")
                renderer.onTrimMemory(ComponentCallbacks2.TRIM_MEMORY_BACKGROUND)
            }
        }
    }
}
