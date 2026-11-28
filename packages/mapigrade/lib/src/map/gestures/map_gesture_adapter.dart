import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../texture/map_texture_controller.dart';
import '../mapigrade_frame.dart';
import 'mapigrade_gestures.dart';

/// The FFI's gesture recognizer, as the adapter calls it.
abstract interface class GestureSink {
  /// Passes [input] at [timeMs].
  GestureResult handle(GestureInput input, double timeMs);

  /// Ticks at [timeMs].
  GestureResult tick(double timeMs);
}

/// `MLN_GESTURE_MODE_ROTATE`.
const int gestureModeRotate = 1;

/// `MLN_GESTURE_MODE_BOX_ZOOM`.
const int gestureModeBoxZoom = 2;

/// `MLN_GESTURE_MODE_ZOOM_OUT`.
const int gestureModeZoomOut = 4;

/// The logical pixels of scrolling of one mouse wheel detent on macOS, where
/// Flutter multiplies a wheel's line delta by 20.
const double wheelDetentPixels = 20;

/// The recognizer's options for [gestures] on [platform] (design D240): on
/// iOS and macOS friction with a half-life of 346 ms, as UIScrollView's
/// normal deceleration, and on Android the curve model with Android's fling
/// defaults.
NativeGestureOptions nativeGestureOptions(
  MapigradeGestures gestures,
  TargetPlatform platform,
) => NativeGestureOptions(
  pan: gestures.pan,
  zoom: gestures.zoom,
  rotate: gestures.rotate,
  pitch: gestures.pitch,
  glides: gestures.glides,
  snapToNorth: gestures.snapToNorth,
  doubleTapZoom: gestures.doubleTapZoom && gestures.zoom ? 1 : 0,
  twoFingerTapZoom: gestures.twoFingerTapZoom && gestures.zoom ? -1 : 0,
  momentumModel: platform == TargetPlatform.android ? 1 : 0,
  halfLifeMs: 346,
);

/// What a [MapArenaRecognizer] asks of its adapter.
abstract interface class MapArenaDelegate {
  /// Whether the map takes a one-pointer drag of [event]'s pointer.
  bool takesDrag(PointerEvent event);

  /// Whether the map takes a gesture of two or more pointers.
  bool get takesMultiPointer;

  /// An event of a pointer that the map won, in order.
  void forward(PointerEvent event);

  /// The map lost [pointer] after it won it.
  void lost(int pointer, PointerEvent? last);
}

/// A member of Flutter's gesture arena for the pointers that hit the map
/// (design D238). It keeps each pointer's events until it wins or loses the
/// pointer, and forwards them to the delegate in order when it wins. It
/// accepts a pointer that moves past the pan slop when the map takes the
/// drag, and every pointer when a second one goes down, and never on a
/// pointer's lift, so that a deeper recognizer, such as a marker's tap, wins
/// a tap.
class MapArenaRecognizer extends OneSequenceGestureRecognizer {
  /// A recognizer that reports to [delegate].
  MapArenaRecognizer({required this.delegate, super.debugOwner});

  /// The adapter.
  final MapArenaDelegate delegate;

  final _kept = <int, List<PointerEvent>>{};
  final _won = <int>{};
  final _down = <int, Offset>{};
  final _last = <int, PointerEvent>{};

  @override
  bool isPointerAllowed(PointerDownEvent event) =>
      // A middle button means nothing to the map.
      event.buttons != kMiddleMouseButton && super.isPointerAllowed(event);

  @override
  void addAllowedPointer(PointerDownEvent event) {
    startTrackingPointer(event.pointer, event.transform);
    // The pointer route delivers the down event to handleEvent next.
    _kept[event.pointer] = [];
    _down[event.pointer] = event.localPosition;
    _last[event.pointer] = event;
    if (_down.length >= 2 && delegate.takesMultiPointer) {
      for (final pointer in _down.keys.toList()) {
        if (!_won.contains(pointer)) resolvePointer(pointer, .accepted);
      }
    }
  }

  @override
  void addAllowedPointerPanZoom(PointerPanZoomStartEvent event) {
    startTrackingPointer(event.pointer, event.transform);
    _kept[event.pointer] = [];
    _last[event.pointer] = event;
    // A trackpad gesture over the map is the map's.
    resolvePointer(event.pointer, .accepted);
  }

  @override
  void handleEvent(PointerEvent event) {
    final pointer = event.pointer;
    _last[pointer] = event;
    if (_won.contains(pointer)) {
      delegate.forward(event);
    } else {
      _kept[pointer]?.add(event);
      final down = _down[pointer];
      if (event is PointerMoveEvent && down != null) {
        final slop = computePanSlop(event.kind, gestureSettings);
        if ((event.localPosition - down).distance > slop) {
          final takes = _down.length >= 2
              ? delegate.takesMultiPointer
              : delegate.takesDrag(event);
          resolvePointer(pointer, takes ? .accepted : .rejected);
        }
      }
    }
    if (event is PointerUpEvent ||
        event is PointerCancelEvent ||
        event is PointerPanZoomEndEvent) {
      _down.remove(pointer);
      stopTrackingPointer(pointer);
    }
  }

  @override
  void acceptGesture(int pointer) {
    if (!_won.add(pointer)) return;
    for (final event in _kept.remove(pointer) ?? const <PointerEvent>[]) {
      delegate.forward(event);
    }
  }

  @override
  void rejectGesture(int pointer) {
    _kept.remove(pointer);
    _down.remove(pointer);
    if (_won.remove(pointer)) delegate.lost(pointer, _last[pointer]);
    _last.remove(pointer);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {}

  @override
  void stopTrackingPointer(int pointer) {
    super.stopTrackingPointer(pointer);
    // A pointer that ended stays won or kept until the arena resolves it.
    if (!_kept.containsKey(pointer)) {
      _won.remove(pointer);
      _last.remove(pointer);
    }
  }

  @override
  String get debugDescription => 'MapigradeMap';
}

/// Turns the input over a `MapigradeMap` into inputs of the FFI's gesture
/// recognizer, and its results into taps, ticks, haptic feedback and the box
/// zoom rectangle (designs D237 to D240 and D245).
class MapGestureAdapter extends StatefulWidget {
  /// An adapter around [child] that sends to [sink], once there is one.
  const MapGestureAdapter({
    super.key,
    required this.sink,
    required this.gestures,
    required this.frame,
    required this.boxZoom,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.onSecondaryTap,
    this.hapticFeedback = true,
    this.onActiveChanged,
  });

  /// The recognizer, or null before the map exists.
  final GestureSink? sink;

  /// Which gestures move the camera.
  final MapigradeGestures gestures;

  /// The frame displayed now, for the coordinates of taps.
  final MapigradeFrame? Function() frame;

  /// Set to the rectangle of a box zoom being drawn, or null.
  final ValueNotifier<Rect?> boxZoom;

  /// The map and its children.
  final Widget child;

  /// The map's tap callbacks.
  final void Function(MapigradeTap tap)? onTap;

  /// The map's long-press callback.
  final void Function(MapigradeTap tap)? onLongPress;

  /// The map's secondary-tap callback.
  final void Function(MapigradeTap tap)? onSecondaryTap;

  /// Whether notches play haptic feedback on iOS and Android.
  final bool hapticFeedback;

  /// Called when input starts or stops moving the camera: a pointer is down
  /// on the map, or the recognizer asks for ticks.
  final void Function(bool active)? onActiveChanged;

  @override
  State<MapGestureAdapter> createState() => MapGestureAdapterState();
}

/// The state of a [MapGestureAdapter].
class MapGestureAdapterState extends State<MapGestureAdapter>
    with SingleTickerProviderStateMixin
    implements MapArenaDelegate {
  late final Ticker _ticker = createTicker(_onTick);
  Timer? _tickTimer;
  final _focus = FocusNode(debugLabel: 'MapigradeMap');
  // The pointers down on the map that it won, and the buttons of each.
  final _pointers = <int, int>{};
  // A trackpad gesture's last cumulative scale and rotation.
  double _panZoomScale = 1;
  double _panZoomRotation = 0;
  double _lastTimeMs = 0;
  GestureNextTick _nextTick = GestureNextTick.none;
  bool _active = false;
  int _modes = 0;
  // A tap held until a double tap is ruled out (design D239).
  Timer? _tapTimer;
  MapigradeTap? _heldTap;

  @override
  void dispose() {
    _ticker.dispose();
    _tickTimer?.cancel();
    _tapTimer?.cancel();
    _focus.dispose();
    super.dispose();
  }

  bool get _holdsTaps => widget.gestures.doubleTapZoom && widget.gestures.zoom;

  @override
  bool takesDrag(PointerEvent event) {
    final g = widget.gestures;
    if (event.kind == PointerDeviceKind.mouse &&
        (event.buttons & kSecondaryMouseButton != 0 ||
            _keyModes() & gestureModeRotate != 0)) {
      return g.rotate || g.pitch;
    }
    if (_keyModes() & gestureModeBoxZoom != 0 &&
        event.kind == PointerDeviceKind.mouse) {
      return g.zoom;
    }
    return g.pan;
  }

  @override
  bool get takesMultiPointer {
    final g = widget.gestures;
    return g.pan || g.zoom || g.rotate || g.pitch;
  }

  int _keyModes() {
    final keys = HardwareKeyboard.instance;
    var modes = 0;
    if (keys.isShiftPressed) modes |= gestureModeBoxZoom | gestureModeZoomOut;
    if (keys.isControlPressed) modes |= gestureModeRotate;
    return modes;
  }

  double _time(Duration timeStamp) {
    final ms = timeStamp.inMicroseconds / 1000;
    if (ms > _lastTimeMs) _lastTimeMs = ms;
    return _lastTimeMs;
  }

  static int _id(int pointer) => pointer & 0xffffffff;

  static int _kind(PointerDeviceKind kind) => switch (kind) {
    PointerDeviceKind.mouse => 0,
    PointerDeviceKind.stylus || PointerDeviceKind.invertedStylus => 2,
    _ => 1,
  };

  void _send(GestureInput input, double timeMs) {
    final sink = widget.sink;
    if (sink == null) return;
    _apply(sink.handle(input, timeMs), timeMs);
  }

  // Sends the modes of the held keys when they changed.
  void _sendModes(double timeMs) {
    final modes = _keyModes();
    if (modes == _modes) return;
    _modes = modes;
    _send(GestureInput(type: GestureInputType.modes, modes: modes), timeMs);
  }

  @override
  void forward(PointerEvent event) {
    final time = _time(event.timeStamp);
    final id = _id(event.pointer);
    switch (event) {
      case PointerDownEvent():
        if (event.kind == PointerDeviceKind.mouse) {
          _focus.requestFocus();
          _sendModes(time);
        }
        _pointers[event.pointer] = event.buttons;
        _setActive();
        _send(
          GestureInput(
            type: GestureInputType.pointerDown,
            pointerId: id,
            pointerKind: _kind(event.kind),
            position: event.localPosition,
            modes: event.buttons & kSecondaryMouseButton != 0
                ? gestureModeRotate
                : 0,
          ),
          time,
        );
      case PointerMoveEvent():
        _send(
          GestureInput(
            type: GestureInputType.pointerMove,
            pointerId: id,
            position: event.localPosition,
          ),
          time,
        );
      case PointerUpEvent():
        if (event.kind == PointerDeviceKind.mouse) _sendModes(time);
        _send(
          GestureInput(
            type: GestureInputType.pointerUp,
            pointerId: id,
            position: event.localPosition,
          ),
          time,
        );
        _pointers.remove(event.pointer);
        _secondaryPointers.remove(id);
        _setActive();
      case PointerCancelEvent():
        _cancel(event.pointer, time);
      case PointerPanZoomStartEvent():
        _panZoomScale = 1;
        _panZoomRotation = 0;
        _pointers[event.pointer] = 0;
        _setActive();
        _send(
          GestureInput(
            type: GestureInputType.pinch,
            position: event.localPosition,
            phase: 0,
          ),
          time,
        );
      case PointerPanZoomUpdateEvent():
        if (widget.gestures.pan && event.localPanDelta != Offset.zero) {
          _send(
            GestureInput(
              type: GestureInputType.delta,
              position: event.localPosition,
              pan: event.localPanDelta,
            ),
            time,
          );
        }
        final scale = event.scale / _panZoomScale;
        final rotation = (event.rotation - _panZoomRotation) * 180 / math.pi;
        _panZoomScale = event.scale;
        _panZoomRotation = event.rotation;
        if (scale != 1 || rotation != 0) {
          _send(
            GestureInput(
              type: GestureInputType.pinch,
              position: event.localPosition,
              scale: widget.gestures.zoom ? scale : 1,
              rotation: widget.gestures.rotate ? rotation : 0,
              phase: 1,
            ),
            time,
          );
        }
      case PointerPanZoomEndEvent():
        _send(
          GestureInput(
            type: GestureInputType.pinch,
            position: event.localPosition,
            phase: 2,
          ),
          time,
        );
        _pointers.remove(event.pointer);
        _setActive();
      default:
        break;
    }
  }

  @override
  void lost(int pointer, PointerEvent? last) {
    _cancel(pointer, last == null ? _lastTimeMs : _time(last.timeStamp));
  }

  void _cancel(int pointer, double time) {
    if (_pointers.remove(pointer) == null) return;
    _send(
      GestureInput(
        type: GestureInputType.pointerCancel,
        pointerId: _id(pointer),
      ),
      time,
    );
    _setActive();
  }

  void _onSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !widget.gestures.zoom) return;
    if (event.kind == PointerDeviceKind.trackpad) return;
    // The resolver gives the event to the deepest registration only, so an
    // enclosing scrollable doesn't also scroll.
    GestureBinding.instance.pointerSignalResolver.register(event, (event) {
      final scroll = event as PointerScrollEvent;
      final time = _time(scroll.timeStamp);
      _send(
        GestureInput(
          type: GestureInputType.delta,
          position: scroll.localPosition,
          discrete: true,
          zoom: -scroll.scrollDelta.dy / wheelDetentPixels / 3,
        ),
        time,
      );
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final time = _time(event.timeStamp);
    _sendModes(time);
    if (!widget.gestures.keyboard ||
        (event is! KeyDownEvent && event is! KeyRepeatEvent)) {
      return KeyEventResult.ignored;
    }
    final g = widget.gestures;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final key = event.logicalKey;
    GestureInput? input;
    GestureInput delta({
      Offset pan = Offset.zero,
      double zoom = 0,
      double bearing = 0,
      double pitch = 0,
    }) => GestureInput(
      type: GestureInputType.delta,
      position: (context.size ?? Size.zero).center(Offset.zero),
      discrete: true,
      pan: pan,
      zoom: zoom,
      bearing: bearing,
      pitch: pitch,
    );
    if (shift && key == LogicalKeyboardKey.arrowLeft && g.rotate) {
      input = delta(bearing: -15);
    } else if (shift && key == LogicalKeyboardKey.arrowRight && g.rotate) {
      input = delta(bearing: 15);
    } else if (shift && key == LogicalKeyboardKey.arrowUp && g.pitch) {
      input = delta(pitch: 10);
    } else if (shift && key == LogicalKeyboardKey.arrowDown && g.pitch) {
      input = delta(pitch: -10);
    } else if (!shift && g.pan && key == LogicalKeyboardKey.arrowLeft) {
      input = delta(pan: const Offset(100, 0));
    } else if (!shift && g.pan && key == LogicalKeyboardKey.arrowRight) {
      input = delta(pan: const Offset(-100, 0));
    } else if (!shift && g.pan && key == LogicalKeyboardKey.arrowUp) {
      input = delta(pan: const Offset(0, 100));
    } else if (!shift && g.pan && key == LogicalKeyboardKey.arrowDown) {
      input = delta(pan: const Offset(0, -100));
    } else if (g.zoom &&
        (key == LogicalKeyboardKey.equal ||
            key == LogicalKeyboardKey.add ||
            key == LogicalKeyboardKey.numpadAdd)) {
      input = delta(zoom: 1);
    } else if (g.zoom &&
        (key == LogicalKeyboardKey.minus ||
            key == LogicalKeyboardKey.numpadSubtract)) {
      input = delta(zoom: -1);
    }
    if (input == null) return KeyEventResult.ignored;
    _send(input, time);
    return KeyEventResult.handled;
  }

  void _apply(GestureResult result, double timeMs) {
    for (final event in result.events) {
      _onGestureEvent(event, result.events);
    }
    widget.boxZoom.value = result.boxZoom;
    _nextTick = result.nextTick;
    _tickTimer?.cancel();
    _tickTimer = null;
    switch (result.nextTick) {
      case GestureNextTick.frame:
        if (!_ticker.isActive) _ticker.start();
      case GestureNextTick.at:
        if (_ticker.isActive) _ticker.stop();
        final delay = math.max(0.0, result.nextTickMs - timeMs);
        _tickTimer = Timer(
          Duration(microseconds: (delay * 1000).round()),
          () => _tick(result.nextTickMs),
        );
      case GestureNextTick.none:
        if (_ticker.isActive) _ticker.stop();
    }
    _setActive();
  }

  void _onTick(Duration _) {
    // The frame's time is on the clock of the pointer events.
    _tick(_time(SchedulerBinding.instance.currentSystemFrameTimeStamp));
  }

  void _tick(double timeMs) {
    final sink = widget.sink;
    if (sink == null || !mounted) return;
    if (timeMs > _lastTimeMs) _lastTimeMs = timeMs;
    _apply(sink.tick(_lastTimeMs), _lastTimeMs);
  }

  void _setActive() {
    final active = _pointers.isNotEmpty || _nextTick != GestureNextTick.none;
    if (active == _active) return;
    _active = active;
    widget.onActiveChanged?.call(active);
  }

  MapigradeTap _tapAt(Offset position) => MapigradeTap(
    position: position,
    coordinate: widget.frame()?.unproject(position),
  );

  void _onGestureEvent(GestureEvent event, List<GestureEvent> all) {
    switch (event.type) {
      case GestureEventType.tap:
        final tap = _tapAt(event.position);
        final secondary = _secondaryPointers.remove(event.pointerId);
        if (secondary) {
          widget.onSecondaryTap?.call(tap);
        } else if (!_holdsTaps) {
          widget.onTap?.call(tap);
        } else if (!all.any((e) => e.type == GestureEventType.doubleTap)) {
          _releaseHeldTap();
          _heldTap = tap;
          _tapTimer = Timer(kDoubleTapTimeout, _releaseHeldTap);
        }
      case GestureEventType.doubleTap:
        if (_holdsTaps) {
          _tapTimer?.cancel();
          _heldTap = null;
        }
      case GestureEventType.longPress:
        widget.onLongPress?.call(_tapAt(event.position));
      case GestureEventType.notch:
        if (widget.hapticFeedback &&
            (defaultTargetPlatform == TargetPlatform.iOS ||
                defaultTargetPlatform == TargetPlatform.android)) {
          HapticFeedback.selectionClick();
        }
    }
  }

  // The recognizer's ids of the pointers that went down with the secondary
  // button, whose taps are secondary taps.
  final _secondaryPointers = <int>{};

  void _releaseHeldTap() {
    _tapTimer?.cancel();
    _tapTimer = null;
    final tap = _heldTap;
    _heldTap = null;
    if (tap != null) widget.onTap?.call(tap);
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: _focus,
    onKeyEvent: _onKey,
    child: Listener(
      onPointerSignal: _onSignal,
      onPointerDown: (event) {
        if (event.buttons & kSecondaryMouseButton != 0) {
          _secondaryPointers.add(_id(event.pointer));
        }
      },
      child: RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: {
          MapArenaRecognizer:
              GestureRecognizerFactoryWithHandlers<MapArenaRecognizer>(
                () => MapArenaRecognizer(delegate: this, debugOwner: this),
                (_) {},
              ),
        },
        child: widget.child,
      ),
    ),
  );
}
