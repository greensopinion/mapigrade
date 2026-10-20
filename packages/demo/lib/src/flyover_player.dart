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

  /// After the warm-up pass, at the flyover's start until [FlyoverPlayer.start]
  /// (design D145).
  waiting,
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

  /// The length of the warm-up pass.
  Duration _warmUp = Duration.zero;
  bool _waitAfterWarmUp = false;

  /// Where the rider is while the flyover follows a route, otherwise null.
  /// Updated on every tick, separately from the other state, so that only the
  /// rider's marker rebuilds.
  final rider = ValueNotifier<LatLng?>(null);

  FlyoverPhase get phase => _phase;

  bool get isActive => _phase != FlyoverPhase.stopped;

  /// The stage the flyover shows, or null when stopped.
  int? get stage => _stage;
  int? _stage;

  /// Plays [flyover] from the start. With [warmUp], first plays a warm-up
  /// pass from the start to [warmUp], or to the end if that is earlier. With
  /// [waitAfterWarmUp], it then waits at the start until [start] is called.
  void play(Flyover flyover, {Duration? warmUp, bool waitAfterWarmUp = false}) {
    _ticker.stop();
    _flyover = flyover;
    _warmUp = warmUp == null || warmUp > flyover.duration
        ? flyover.duration
        : warmUp;
    _waitAfterWarmUp = waitAfterWarmUp;
    _passStart = Duration.zero;
    _phase = warmUp != null ? FlyoverPhase.warmingUp : FlyoverPhase.playing;
    _stage = null;
    _ticker.start();
    notifyListeners();
  }

  /// Starts the run when the player is [FlyoverPhase.waiting].
  void start() {
    if (_phase != FlyoverPhase.waiting) return;
    _passStart = Duration.zero;
    _phase = FlyoverPhase.playing;
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
    if (t >= _warmUp && _phase == FlyoverPhase.warmingUp) {
      if (_waitAfterWarmUp) {
        _wait(flyover);
        return;
      }
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

  /// Holds the camera at the flyover's start, without the rider; [start]
  /// restarts the ticker, so the run's time starts from 0.
  void _wait(Flyover flyover) {
    _ticker.stop();
    _phase = FlyoverPhase.waiting;
    final camera = flyover.cameraAt(Duration.zero);
    controller.moveAndRotate(camera.center, camera.zoom, camera.rotation);
    rider.value = null;
    _stage = flyover.segmentAt(Duration.zero).stage;
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker.dispose();
    rider.dispose();
    super.dispose();
  }
}
