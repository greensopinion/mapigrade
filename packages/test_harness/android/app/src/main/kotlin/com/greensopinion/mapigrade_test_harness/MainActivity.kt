package com.greensopinion.mapigrade_test_harness

import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // A second engine for integration_test/engines_test.dart, and the options it receives
    // (design D159 of the multiple-flutter-engines change).
    private var secondEngine: FlutterEngine? = null
    private var secondEngineOptions: Any? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ENGINES_CHANNEL)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    if (secondEngine != null) {
                        result.error("started", "the second engine is already running", null)
                        return@setMethodCallHandler
                    }
                    secondEngineOptions = call.arguments
                    // The engine registers every plugin of the app.
                    val engine = FlutterEngine(applicationContext)
                    MethodChannel(engine.dartExecutor.binaryMessenger, ENGINES_CHANNEL)
                        .setMethodCallHandler { secondCall, secondResult ->
                            when (secondCall.method) {
                                "options" -> secondResult.success(secondEngineOptions)
                                "report" -> {
                                    channel.invokeMethod("report", secondCall.arguments)
                                    secondResult.success(null)
                                }
                                else -> secondResult.notImplemented()
                            }
                        }
                    engine.dartExecutor.executeDartEntrypoint(
                        DartExecutor.DartEntrypoint(
                            FlutterInjector.instance().flutterLoader().findAppBundlePath(),
                            SECOND_ENGINE_LIBRARY,
                            "secondEngineMain",
                        )
                    )
                    secondEngine = engine
                    result.success(null)
                }
                "destroy" -> {
                    secondEngine?.destroy()
                    secondEngine = null
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private companion object {
        const val ENGINES_CHANNEL = "mapigrade_test/engines"
        const val SECOND_ENGINE_LIBRARY = "package:test_harness/second_engine.dart"
    }
}
