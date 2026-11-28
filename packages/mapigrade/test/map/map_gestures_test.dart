import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mapigrade/src/map/camera.dart';
import 'package:mapigrade/src/map/gestures/map_gesture_adapter.dart';
import 'package:mapigrade/src/map/gestures/mapigrade_gestures.dart';
import 'package:mapigrade/src/map/mapigrade_map.dart';
import 'package:mapigrade/src/texture/map_texture_controller.dart';

import 'fake_map_controller.dart';
import 'test_matrix.dart';

// A fake recognizer: a lift without movement is a tap, and a tap within
// 300 ms of the last is also a double tap, as mln-rs reports them.
class FakeRecognizer {
  FakeRecognizer(this.map) {
    map.onGesture = _handle;
  }

  final FakeMapController map;
  final _moved = <int>{};
  double? _lastTapMs;
  List<GestureEvent> Function(GestureInput input)? extraEvents;

  GestureResult _handle(GestureInput input, double time) {
    final events = <GestureEvent>[...?extraEvents?.call(input)];
    switch (input.type) {
      case GestureInputType.pointerDown:
        _moved.remove(input.pointerId);
      case GestureInputType.pointerMove:
        _moved.add(input.pointerId);
      case GestureInputType.pointerUp when !_moved.contains(input.pointerId):
        events.add(
          GestureEvent(
            type: GestureEventType.tap,
            pointerId: input.pointerId,
            position: input.position,
          ),
        );
        final last = _lastTapMs;
        if (last != null && time - last < 300) {
          events.add(
            GestureEvent(
              type: GestureEventType.doubleTap,
              pointerId: input.pointerId,
              position: input.position,
            ),
          );
          _lastTapMs = null;
        } else {
          _lastTapMs = time;
        }
    }
    return GestureResult(handled: true, events: events);
  }
}

void main() {
  late FakeMapController map;
  late FakeRecognizer recognizer;

  setUp(() {
    map = FakeMapController();
    recognizer = FakeRecognizer(map);
    debugCreateMapigradeMap = ({
      required pixelRatio,
      required httpHeaders,
      required initialCamera,
      required limits,
    }) async => map;
  });
  tearDown(() => debugCreateMapigradeMap = null);

  Widget app(Widget child) => Directionality(
    textDirection: TextDirection.ltr,
    child: MediaQuery(
      data: const MediaQueryData(size: Size(800, 800)),
      child: child,
    ),
  );

  Widget mapWidget({
    MapigradeGestures gestures = const MapigradeGestures(),
    void Function(MapigradeTap)? onTap,
    void Function(MapigradeTap)? onSecondaryTap,
    List<Widget> children = const [],
  }) => SizedBox(
    width: 400,
    height: 400,
    child: MapigradeMap(
      styleJson: '{}',
      initialCamera: const MapigradeCamera(center: LatLng(0, 0), zoom: 3),
      gestures: gestures,
      onTap: onTap,
      onSecondaryTap: onSecondaryTap,
      children: children,
    ),
  );

  Future<void> pumpMap(WidgetTester tester, Widget widget) async {
    await tester.pumpWidget(app(widget));
    await tester.pump();
  }

  List<int> types() => [for (final input in map.inputs) input.type];

  Future<void> drag(
    WidgetTester tester,
    Offset from,
    Offset by, {
    int steps = 10,
  }) async {
    final gesture = await tester.startGesture(from);
    for (var i = 1; i <= steps; ++i) {
      await gesture.moveTo(from + by * (i / steps));
    }
    await gesture.up();
    await tester.pump();
  }

  group('gesture arena', () {
    testWidgets('a marker\'s tap wins', (tester) async {
      var markerTaps = 0, mapTaps = 0;
      await pumpMap(
        tester,
        Align(
          alignment: Alignment.topLeft,
          child: mapWidget(
            onTap: (_) => mapTaps++,
            children: [
              Positioned(
                left: 100,
                top: 100,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => markerTaps++,
                  child: const SizedBox(width: 40, height: 40),
                ),
              ),
            ],
          ),
        ),
      );
      await tester.tapAt(const Offset(120, 120));
      await tester.pump(const Duration(milliseconds: 400));
      expect(markerTaps, 1);
      expect(mapTaps, 0);
      expect(map.inputs, isEmpty);
    });

    testWidgets('a vertical drag in a ListView goes to one recognizer', (
      tester,
    ) async {
      final scroll = ScrollController();
      await pumpMap(
        tester,
        ListView(
          controller: scroll,
          children: [mapWidget(), const SizedBox(height: 2000)],
        ),
      );
      await drag(tester, const Offset(200, 200), const Offset(0, -150));
      final mapMoved = map.inputs.any(
        (i) => i.type == GestureInputType.pointerMove,
      );
      final listScrolled = scroll.offset != 0;
      expect(mapMoved != listScrolled, isTrue);
    });

    testWidgets('a two-finger gesture in a list goes to the map', (
      tester,
    ) async {
      final scroll = ScrollController();
      await pumpMap(
        tester,
        ListView(
          controller: scroll,
          children: [mapWidget(), const SizedBox(height: 2000)],
        ),
      );
      final a = await tester.startGesture(const Offset(150, 200), pointer: 1);
      final b = await tester.startGesture(const Offset(250, 200), pointer: 2);
      for (var i = 1; i <= 10; ++i) {
        await a.moveBy(const Offset(0, -10));
        await b.moveBy(const Offset(0, -10));
      }
      await a.up();
      await b.up();
      await tester.pump();
      expect(scroll.offset, 0);
      final moved = {
        for (final i in map.inputs)
          if (i.type == GestureInputType.pointerMove) i.pointerId,
      };
      expect(moved, hasLength(2));
    });

    testWidgets('a disabled part releases its pointer', (tester) async {
      var outerPans = 0;
      Widget withOuter(MapigradeGestures gestures) => Align(
        alignment: Alignment.topLeft,
        child: GestureDetector(
          onPanStart: (_) => outerPans++,
          child: mapWidget(gestures: gestures),
        ),
      );
      await pumpMap(tester, withOuter(const MapigradeGestures(pan: false)));
      await drag(tester, const Offset(200, 200), const Offset(120, 0));
      expect(outerPans, 1);
      expect(map.inputs, isEmpty);
      await pumpMap(tester, withOuter(const MapigradeGestures()));
      await drag(tester, const Offset(200, 200), const Offset(120, 0));
      expect(outerPans, 1);
      expect(types().first, GestureInputType.pointerDown);
    });

    testWidgets('the kept events are replayed in order on a win', (
      tester,
    ) async {
      await pumpMap(
        tester,
        Align(
          alignment: Alignment.topLeft,
          child: GestureDetector(onPanStart: (_) {}, child: mapWidget()),
        ),
      );
      await drag(tester, const Offset(100, 100), const Offset(100, 0));
      expect(
        types().where((t) => t == GestureInputType.pointerDown),
        hasLength(1),
      );
      expect(types().first, GestureInputType.pointerDown);
      expect(map.inputs.first.position, const Offset(100, 100));
      final moves = [
        for (final i in map.inputs)
          if (i.type == GestureInputType.pointerMove) i.position.dx,
      ];
      expect(moves, [for (var i = 1; i <= 10; ++i) 100 + 10.0 * i]);
      expect(types().last, GestureInputType.pointerUp);
    });
  });

  group('desktop input', () {
    testWidgets('a trackpad pan and pinch become a delta and a pinch', (
      tester,
    ) async {
      await pumpMap(
        tester,
        Align(alignment: Alignment.topLeft, child: mapWidget()),
      );
      final pointer = TestPointer(1, PointerDeviceKind.trackpad);
      await tester.sendEventToBinding(
        pointer.panZoomStart(const Offset(200, 200)),
      );
      await tester.sendEventToBinding(
        pointer.panZoomUpdate(
          const Offset(200, 200),
          pan: const Offset(10, 5),
          scale: 1.5,
          rotation: 0.1,
        ),
      );
      await tester.sendEventToBinding(pointer.panZoomEnd());
      await tester.pump();
      expect(types(), [
        GestureInputType.pinch,
        GestureInputType.delta,
        GestureInputType.pinch,
        GestureInputType.pinch,
      ]);
      final delta = map.inputs[1];
      expect(delta.discrete, isFalse);
      expect(delta.pan, const Offset(10, 5));
      final update = map.inputs[2];
      expect(update.phase, 1);
      expect(update.scale, closeTo(1.5, 1e-9));
      expect(update.rotation, closeTo(0.1 * 180 / 3.141592653589793, 1e-9));
      expect(map.inputs.last.phase, 2);
    });

    testWidgets('a wheel detent zooms a third of a level and doesn\'t scroll '
        'an enclosing list', (tester) async {
      final scroll = ScrollController();
      await pumpMap(
        tester,
        ListView(
          controller: scroll,
          children: [mapWidget(), const SizedBox(height: 2000)],
        ),
      );
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(pointer.hover(const Offset(200, 200)));
      await tester.sendEventToBinding(
        pointer.scroll(const Offset(0, -wheelDetentPixels)),
      );
      await tester.pump();
      expect(scroll.offset, 0);
      final delta = map.inputs.single;
      expect(delta.type, GestureInputType.delta);
      expect(delta.discrete, isTrue);
      expect(delta.zoom, closeTo(1 / 3, 1e-9));
      expect(delta.position, const Offset(200, 200));
    });

    testWidgets('the right button and held keys select modes', (tester) async {
      await pumpMap(
        tester,
        Align(alignment: Alignment.topLeft, child: mapWidget()),
      );
      final right = await tester.startGesture(
        const Offset(200, 200),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await right.up();
      expect(map.inputs.first.type, GestureInputType.pointerDown);
      expect(map.inputs.first.modes, gestureModeRotate);
      expect(map.inputs.first.pointerKind, 0);
      map.inputs.clear();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      final left = await tester.startGesture(
        const Offset(200, 200),
        kind: PointerDeviceKind.mouse,
      );
      await left.up();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(map.inputs.first.type, GestureInputType.modes);
      expect(map.inputs.first.modes, gestureModeBoxZoom | gestureModeZoomOut);
    });

    testWidgets('the keyboard moves the camera once the map has focus', (
      tester,
    ) async {
      await pumpMap(
        tester,
        Align(alignment: Alignment.topLeft, child: mapWidget()),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      expect(map.inputs, isEmpty);
      final click = await tester.startGesture(
        const Offset(200, 200),
        kind: PointerDeviceKind.mouse,
      );
      await click.up();
      await tester.pump();
      map.inputs.clear();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.equal);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      final deltas = [
        for (final i in map.inputs)
          if (i.type == GestureInputType.delta) i,
      ];
      expect(deltas.map((d) => (d.pan, d.zoom, d.pitch, d.discrete)), [
        (const Offset(-100, 0), 0, 0, true),
        (Offset.zero, 1, 0, true),
        (Offset.zero, 0, 10, true),
      ]);
    });
  });

  group('taps', () {
    Future<void> tapAt(WidgetTester tester, Duration at) async {
      final gesture = await tester.createGesture();
      await gesture.down(const Offset(200, 200), timeStamp: at);
      await gesture.up(timeStamp: at + const Duration(milliseconds: 40));
    }

    testWidgets('taps 290 ms apart are a double tap and call no onTap', (
      tester,
    ) async {
      final taps = <MapigradeTap>[];
      await pumpMap(
        tester,
        Align(
          alignment: Alignment.topLeft,
          child: mapWidget(onTap: taps.add),
        ),
      );
      await tapAt(tester, Duration.zero);
      await tester.pump(const Duration(milliseconds: 290));
      await tapAt(tester, const Duration(milliseconds: 290));
      await tester.pump(const Duration(milliseconds: 400));
      expect(taps, isEmpty);
    });

    testWidgets('taps 310 ms apart call onTap twice', (tester) async {
      final taps = <MapigradeTap>[];
      await pumpMap(
        tester,
        Align(
          alignment: Alignment.topLeft,
          child: mapWidget(onTap: taps.add),
        ),
      );
      await tapAt(tester, Duration.zero);
      await tester.pump(const Duration(milliseconds: 310));
      expect(taps, hasLength(1));
      await tapAt(tester, const Duration(milliseconds: 310));
      await tester.pump(const Duration(milliseconds: 400));
      expect(taps, hasLength(2));
      expect(taps.first.position, const Offset(200, 200));
    });

    testWidgets('without double-tap zoom each tap calls onTap at once', (
      tester,
    ) async {
      final taps = <MapigradeTap>[];
      await pumpMap(
        tester,
        Align(
          alignment: Alignment.topLeft,
          child: mapWidget(
            onTap: taps.add,
            gestures: const MapigradeGestures(doubleTapZoom: false),
          ),
        ),
      );
      await tapAt(tester, Duration.zero);
      expect(taps, hasLength(1));
      await tapAt(tester, const Duration(milliseconds: 100));
      expect(taps, hasLength(2));
    });

    testWidgets('a pan calls no onTap', (tester) async {
      final taps = <MapigradeTap>[];
      await pumpMap(
        tester,
        Align(
          alignment: Alignment.topLeft,
          child: mapWidget(onTap: taps.add),
        ),
      );
      await drag(tester, const Offset(200, 200), const Offset(80, 0));
      await tester.pump(const Duration(milliseconds: 400));
      expect(taps, isEmpty);
    });

    testWidgets('a tap gives the coordinate of the displayed frame', (
      tester,
    ) async {
      final taps = <MapigradeTap>[];
      await pumpMap(
        tester,
        Align(
          alignment: Alignment.topLeft,
          child: mapWidget(
            onTap: taps.add,
            gestures: const MapigradeGestures(doubleTapZoom: false),
          ),
        ),
      );
      map.finish(
        fakeFrame(
          zoom: 3,
          pitch: 45,
          logicalSize: const Size(400, 400),
          matrix: testMatrix(
            center: const LatLng(0, 0),
            zoom: 3,
            size: const Size(400, 400),
            pitch: 45,
          ),
        ),
      );
      await tester.pump();
      await tapAt(tester, Duration.zero);
      final coordinate = taps.single.coordinate!;
      expect(coordinate.latitude, closeTo(0, 1e-9));
      expect(coordinate.longitude, closeTo(0, 1e-9));
    });

    testWidgets('a right click without a drag is a secondary tap', (
      tester,
    ) async {
      final taps = <MapigradeTap>[], secondary = <MapigradeTap>[];
      await pumpMap(
        tester,
        Align(
          alignment: Alignment.topLeft,
          child: mapWidget(onTap: taps.add, onSecondaryTap: secondary.add),
        ),
      );
      final click = await tester.startGesture(
        const Offset(200, 200),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await click.up();
      await tester.pump(const Duration(milliseconds: 400));
      expect(secondary, hasLength(1));
      expect(taps, isEmpty);
    });

    testWidgets('a notch plays feedback once', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final haptics = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            haptics.add(call.arguments as String);
          }
          return null;
        },
      );
      recognizer.extraEvents = (input) => [
        if (input.type == GestureInputType.pointerUp)
          const GestureEvent(type: GestureEventType.notch, axis: 1),
      ];
      await pumpMap(
        tester,
        Align(alignment: Alignment.topLeft, child: mapWidget()),
      );
      await drag(tester, const Offset(200, 200), const Offset(80, 0));
      expect(haptics, ['HapticFeedbackType.selectionClick']);
      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('options', () {
    test('each part maps to the recognizer\'s options', () {
      const all = MapigradeGestures();
      final options = nativeGestureOptions(all, TargetPlatform.iOS);
      expect(
        (
          options.pan,
          options.zoom,
          options.rotate,
          options.pitch,
          options.glides,
          options.snapToNorth,
          options.doubleTapZoom,
          options.twoFingerTapZoom,
        ),
        (true, true, true, true, true, true, 1, -1),
      );
      final none = nativeGestureOptions(
        const MapigradeGestures.none(),
        TargetPlatform.iOS,
      );
      expect(
        (
          none.pan,
          none.zoom,
          none.rotate,
          none.pitch,
          none.glides,
          none.snapToNorth,
          none.doubleTapZoom,
          none.twoFingerTapZoom,
        ),
        (false, false, false, false, false, false, 0, 0),
      );
      for (final (gestures, check)
          in <(MapigradeGestures, bool Function(NativeGestureOptions))>[
            (all.copyWith(pan: false), (o) => !o.pan && o.zoom),
            (all.copyWith(zoom: false), (o) => !o.zoom && o.doubleTapZoom == 0),
            (all.copyWith(rotate: false), (o) => !o.rotate && o.pitch),
            (all.copyWith(pitch: false), (o) => !o.pitch && o.rotate),
            (all.copyWith(glides: false), (o) => !o.glides),
            (all.copyWith(snapToNorth: false), (o) => !o.snapToNorth),
            (all.copyWith(doubleTapZoom: false), (o) => o.doubleTapZoom == 0),
            (
              all.copyWith(twoFingerTapZoom: false),
              (o) => o.twoFingerTapZoom == 0,
            ),
          ]) {
        expect(
          check(nativeGestureOptions(gestures, TargetPlatform.iOS)),
          isTrue,
        );
      }
    });

    test('each platform gets its momentum', () {
      for (final (platform, model) in [
        (TargetPlatform.iOS, 0),
        (TargetPlatform.macOS, 0),
        (TargetPlatform.android, 1),
      ]) {
        final options = nativeGestureOptions(
          const MapigradeGestures(),
          platform,
        );
        expect(options.momentumModel, model, reason: '$platform');
        expect(options.halfLifeMs, 346);
      }
    });

    testWidgets('the map creates its recognizer and passes new options', (
      tester,
    ) async {
      await pumpMap(tester, mapWidget());
      expect(
        map.gestureOptions.single,
        nativeGestureOptions(const MapigradeGestures(), defaultTargetPlatform),
      );
      await pumpMap(
        tester,
        mapWidget(gestures: const MapigradeGestures(rotate: false)),
      );
      expect(map.gestureOptions.last.rotate, isFalse);
    });
  });
}
