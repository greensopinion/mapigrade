import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'flyover.dart';

/// The state of a [FlyoverPlayer].
enum FlyoverPhase {
  stopped,

  /// The pass that loads the tiles before the run.
  warmingUp,
  playing,
}

/// Plays a [Flyover] on a [MapController]: on each tick it moves the camera
/// to the flyover's camera at the time since the start (design D118). Stop
/// it on any input on the map (design D119); the camera stays where it is.
class FlyoverPlayer extends ChangeNotifier {
  FlyoverPlayer({required TickerProvider vsync, required this.controller}) {
    _ticker = vsync.createTicker(_tick);
  }

  final MapController controller;
  late final Ticker _ticker;
  Flyover? _flyover;
  FlyoverPhase _phase = FlyoverPhase.stopped;

  /// The ticker's elapsed time at the start of the current pass.
  Duration _passStart = Duration.zero;

  /// Where the rider is while the flyover follows a route, otherwise null.
  /// Updated on every tick, separately from the other state, so that only the
  /// rider's marker rebuilds.
  final rider = ValueNotifier<LatLng?>(null);

  FlyoverPhase get phase => _phase;

  bool get isActive => _phase != FlyoverPhase.stopped;

  /// The stage the flyover shows, or null when stopped.
  int? get stage => _stage;
  int? _stage;

  /// Plays [flyover] from the start; with [warmUp], plays it once first.
  void play(Flyover flyover, {required bool warmUp}) {
    _ticker.stop();
    _flyover = flyover;
    _passStart = Duration.zero;
    _phase = warmUp ? FlyoverPhase.warmingUp : FlyoverPhase.playing;
    _stage = null;
    _ticker.start();
    notifyListeners();
  }

  /// Stops the flyover, and leaves the camera where it is.
  void stop() {
    if (!isActive) return;
    _ticker.stop();
    _flyover = null;
    _phase = FlyoverPhase.stopped;
    _stage = null;
    rider.value = null;
    notifyListeners();
  }

  void _tick(Duration elapsed) {
    final flyover = _flyover!;
    var t = elapsed - _passStart;
    if (t >= flyover.duration && _phase == FlyoverPhase.warmingUp) {
      // The run starts again from the start of the first stage.
      _passStart = elapsed;
      _phase = FlyoverPhase.playing;
      t = Duration.zero;
      notifyListeners();
    }
    final camera = flyover.cameraAt(t);
    // Its source is MapEventSource.mapController, so it doesn't stop the
    // flyover.
    controller.moveAndRotate(camera.center, camera.zoom, camera.rotation);
    rider.value = flyover.riderAt(t);
    final stage = flyover.segmentAt(t).stage;
    if (stage != _stage) {
      _stage = stage;
      notifyListeners();
    }
    if (t >= flyover.duration) stop();
  }

  @override
  void dispose() {
    _ticker.dispose();
    rider.dispose();
    super.dispose();
  }
}
