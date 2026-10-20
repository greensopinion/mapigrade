package com.greensopinion.flutter_mapigrade

import android.app.Activity
import android.app.Application
import android.content.ComponentCallbacks2
import android.content.Context
import android.content.res.Configuration
import android.os.Build
import android.os.Bundle
import android.util.Log
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry

/**
 * Loads the plugin's native library, which Dart calls through @Native bindings, and passes it the
 * texture registry and the application context (design D54). Rendering pauses while the Flutter
 * activity is stopped, and the maps release their image readers then (D137 of the
 * android-layer-children-alignment change). The renderers release cached resources under memory
 * pressure (D55).
 *
 * Each engine that attaches the plugin has its own instance. The native library keeps the engine's
 * texture registry under a token, which the instance gives to Dart on the channel
 * `flutter_mapigrade`, and the maps that Dart in that engine creates register with that registry.
 * When the engine detaches the plugin, the native library releases those maps (designs D153, D154
 * and D157 of the multiple-flutter-engines change).
 *
 * When the process can't load the native library, for example on a device without an arm64 ABI,
 * the plugin logs a warning and calls no native function for the life of the process (D85).
 */
class MapigradePlugin : FlutterPlugin, ActivityAware {
    private var applicationContext: Context? = null
    private var activity: Activity? = null
    private var channel: MethodChannel? = null

    // The token of this instance's engine, or 0 if the native library isn't loaded.
    private var token = 0L

    private val activityCallbacks =
        object : Application.ActivityLifecycleCallbacks {
            override fun onActivityStarted(started: Activity) {
                if (libraryLoaded && started === activity) {
                    nativeSetReadersReleased(false)
                    nativeSetPaused(false)
                }
            }

            override fun onActivityStopped(stopped: Activity) {
                if (libraryLoaded && stopped === activity) {
                    nativeSetPaused(true)
                    nativeSetReadersReleased(true)
                }
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
                if (libraryLoaded && level >= ComponentCallbacks2.TRIM_MEMORY_BACKGROUND) {
                    nativeReduceMemoryUse()
                }
            }

            @Deprecated("Deprecated in Java")
            override fun onLowMemory() {
                if (libraryLoaded) nativeReduceMemoryUse()
            }

            override fun onConfigurationChanged(configuration: Configuration) {}
        }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        if (!loadLibrary()) return
        val context = binding.applicationContext
        applicationContext = context
        token = nativeInit(binding.textureRegistry, context, context.cacheDir.absolutePath)
        context.registerComponentCallbacks(memoryCallbacks)
        // The channel belongs to this engine, so Dart in this engine receives this engine's token
        // (design D154).
        channel =
            MethodChannel(binding.binaryMessenger, CHANNEL).apply {
                setMethodCallHandler { call, result ->
                    if (call.method == "engineToken") result.success(token)
                    else result.notImplemented()
                }
            }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        applicationContext?.unregisterComponentCallbacks(memoryCallbacks)
        applicationContext = null
        if (token != 0L) {
            nativeDetach(token)
            token = 0L
        }
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        if (!libraryLoaded) return
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

    private external fun nativeInit(
        registry: TextureRegistry,
        context: Context,
        cacheDir: String,
    ): Long

    private external fun nativeDetach(token: Long)

    private external fun nativeSetPaused(paused: Boolean)

    private external fun nativeReduceMemoryUse()

    private external fun nativeSetReadersReleased(released: Boolean)

    companion object {
        private const val LIBRARY = "flutter_mapigrade"
        private const val CHANNEL = "flutter_mapigrade"

        // The result of the first load in this process, or null before it. The result applies to
        // the process, so a second engine doesn't load the library again.
        private var loadResult: Boolean? = null

        /** Whether the process loaded the native library. */
        private val libraryLoaded: Boolean
            get() = loadResult == true

        private fun loadLibrary(): Boolean {
            loadResult?.let { return it }
            val loaded =
                try {
                    System.loadLibrary(LIBRARY)
                    true
                } catch (e: UnsatisfiedLinkError) {
                    Log.w(
                        "flutter_mapigrade",
                        "lib$LIBRARY.so isn't available for this device's ABIs " +
                            "(${Build.SUPPORTED_ABIS.joinToString()}); MapigradeLayer.isSupported " +
                            "is false",
                        e,
                    )
                    false
                }
            loadResult = loaded
            return loaded
        }
    }
}
