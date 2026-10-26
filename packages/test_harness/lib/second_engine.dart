// A second Flutter engine for the tests of the spec requirement "Multiple
// Flutter engines" (design D159 of the multiple-flutter-engines change).
//
// The native code of the test harness answers the channel
// `mapigrade_test/engines` on each platform. In the first engine, `start`
// starts a second engine that registers every plugin and runs
// [secondEngineMain], and `destroy` destroys it. In the second engine,
// `options` returns the options that `start` received, and `report` sends its
// argument to the first engine as a `report` call.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_mapigrade/src/testing.dart';

const enginesChannel = MethodChannel('mapigrade_test/engines');

/// The entry point of the second engine. Android and iOS run it from this
/// library. macOS looks the entry point up in the root library, so there the
/// test file declares an entry point with this name that calls this function,
/// and runs with `flutter drive`: under `flutter test` the root library is a
/// generated file.
@pragma('vm:entry-point')
Future<void> secondEngineMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('secondEngineMain: started');
  final options =
      await enginesChannel.invokeMapMethod<String, Object?>('options') ?? {};
  if (options['createMap'] != true) {
    await _report({'event': 'started'});
    return;
  }
  try {
    final controller = await MapTextureController.create(
      pixelRatio: 2,
      maxPitch: 85,
    );
    final loaded = controller.events.firstWhere((e) => e is StyleLoaded);
    // The second engine displays no view, so no frame is displayed; the
    // first rendered frame shows that the map renders.
    final frame = controller.readyFrames.first;
    controller.resize(const Size(400, 300), 2);
    controller.loadStyleJson(
      jsonEncode({
        'version': 8,
        'sources': {},
        'layers': [
          {
            'id': 'background',
            'type': 'background',
            'paint': {'background-color': '#00ff00'},
          },
        ],
      }),
    );
    await loaded.timeout(const Duration(seconds: 20));
    await frame.timeout(const Duration(seconds: 20));
    // The map stays undisposed, so that destroying the engine has to release
    // it.
    debugPrint('secondEngineMain: created a map');
    await _report({'event': 'mapCreated'});
  } catch (e) {
    debugPrint('secondEngineMain: failed to create a map: $e');
    await _report({'event': 'failed', 'error': '$e'});
  }
}

Future<void> _report(Map<String, Object?> report) =>
    enginesChannel.invokeMethod<void>('report', report);

/// Starts and destroys the second engine from the first engine.
class SecondEngine {
  SecondEngine() {
    enginesChannel.setMethodCallHandler((call) async {
      if (call.method == 'report') {
        final report = Map<String, Object?>.from(call.arguments as Map);
        debugPrint('second engine report: $report');
        _reports.add(report);
      }
    });
  }

  final _reports = StreamController<Map<String, Object?>>.broadcast();

  /// The reports of the second engine.
  Stream<Map<String, Object?>> get reports => _reports.stream;

  /// Starts the second engine, which creates a map without disposing it if
  /// [createMap], and waits for its report.
  Future<Map<String, Object?>> start({bool createMap = false}) async {
    final report = reports.first.timeout(const Duration(seconds: 60));
    await enginesChannel.invokeMethod<void>('start', {'createMap': createMap});
    return report;
  }

  /// Destroys the second engine.
  Future<void> destroy() => enginesChannel.invokeMethod<void>('destroy');

  void close() {
    enginesChannel.setMethodCallHandler(null);
    _reports.close();
  }
}
