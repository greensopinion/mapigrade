// Polyline layer tests (polyline-layer spec; the map-layer scenario "Map
// polylines below Flutter children"; tasks 3.1 to 3.4 of the
// add-mapigrade-polyline-layer change).
//
//   cd packages/test_harness && flutter test integration_test/polyline_layer_test.dart -d macos
//
// The style is assets/polyline_style.json, built by
// tool/make_polyline_style.py. It places its features by screen position for
// a 360x280 map centered on latitude 0, longitude 0 at flutter_map zoom 12:
// water at x 270..350, y 10..100; a road along y = 140; a bridge along x =
// 100; a 3D building (fill-extrusion) at x 336..358, y 112..126; a boundary
// line, the last layer that isn't a symbol layer, along y = 275 from x =
// 300; the road name "ROAD" at (180, 140); the place name "CITY" at (240,
// 215). Its glyphs are solid blocks. The tests read pixel colors from a
// RepaintBoundary capture. The tests use a MapTextureLayer in place of the
// MapigradeLayer that builds it, to read the displayed frame.
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:flutter_mapigrade/flutter_mapigrade.dart';
import 'package:flutter_mapigrade/src/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:latlong2/latlong.dart';

// Narrower than every phone screen, so that the map has this size there too.
const _size = Size(360, 280);
const _zoom = 12.0;
const _lightStyleUrl = 'asset://assets/polyline_style.json';
const _darkStyleUrl = 'asset://assets/polyline_style_dark.json';

const _red = Color(0xFFFF0000);
const _blue = Color(0xFF0000FF);
const _green = Color(0xFF00A000);
const _black = Color(0xFF000000);

typedef _Rgb = List<int>;

bool _isRed(_Rgb c) => c[0] > 200 && c[1] < 90 && c[2] < 90;
bool _isBlue(_Rgb c) => c[2] > 200 && c[0] < 90 && c[1] < 90;
bool _isGreen(_Rgb c) => c[1] > 130 && c[0] < 90 && c[2] < 90;
bool _isDark(_Rgb c) => c.every((v) => v < 70);
bool _isBlack(_Rgb c) => c.every((v) => v < 20);
bool _isWhite(_Rgb c) => c.every((v) => v > 235);
bool _isGrey(_Rgb c) =>
    (c[0] - 128).abs() < 24 &&
    (c[1] - 128).abs() < 24 &&
    (c[2] - 128).abs() < 24;
bool _isTeal(_Rgb c) => c[0] < 60 && c[1] > 120 && c[2] > 120;
bool _isPurple(_Rgb c) => c[0] > 90 && c[1] < 60 && c[2] > 90;
bool _isOrange(_Rgb c) => c[0] > 200 && c[1] > 90 && c[1] < 170 && c[2] < 60;

/// How red a pixel is, 1 for pure red and 0 for white, grey, teal, blue and
/// purple.
double _redness(_Rgb c) => math.max(0, c[0] - math.max(c[1], c[2])) / 255;

final _rest = fm.MapCamera(
  crs: const fm.Epsg3857(),
  center: const LatLng(0, 0),
  zoom: _zoom,
  rotation: 0,
  nonRotatedSize: _size,
);

/// The coordinate that the map at rest draws at the logical position
/// ([x], [y]).
LatLng _ll(double x, double y) => _rest.screenOffsetToLatLng(Offset(x, y));

/// A solid polyline through the logical positions [xy] of the map at rest.
MapigradePolyline _route(
  List<Offset> xy, {
  Color color = _red,
  double width = 8,
  StrokeCap cap = StrokeCap.butt,
  StrokeJoin join = StrokeJoin.round,
  double borderWidth = 0,
  Color borderColor = _black,
  List<double>? dashes,
  List<Color>? gradientColors,
}) => MapigradePolyline(
  points: [for (final p in xy) _ll(p.dx, p.dy)],
  color: color,
  strokeWidth: width,
  strokeCap: cap,
  strokeJoin: join,
  borderStrokeWidth: borderWidth,
  borderColor: borderColor,
  dashes: dashes,
  gradientColors: gradientColors,
);

MapigradePolyline _horizontal(
  double y, {
  Color color = _red,
  double width = 8,
}) => _route(
  [Offset(-20, y), Offset(_size.width + 20, y)],
  color: color,
  width: width,
);

/// Two diagonal polylines that cross at ([x], [y]), the first [first] and the
/// second [second].
List<MapigradePolyline> _crossing(
  double x,
  double y,
  Color first,
  Color second,
) => [
  _route(
    [Offset(x - 40, y - 40), Offset(x + 40, y + 40)],
    color: first,
    width: 14,
  ),
  _route(
    [Offset(x - 40, y + 40), Offset(x + 40, y - 40)],
    color: second,
    width: 14,
  ),
];

Widget _polylines(
  List<MapigradePolyline> polylines, {
  LayerPlacement placement = const LayerPlacement.belowLabels(),
  Key? key,
}) => MapigradePolylineLayer(
  key: key,
  polylines: polylines,
  placement: placement,
);

class _Shot {
  _Shot(this.bytes, this.width, this.height, this.scale);

  final ByteData bytes;
  final int width;
  final int height;
  final double scale;

  /// The color at the logical position ([x], [y]).
  _Rgb rgb(num x, num y) {
    final px = (x * scale).floor().clamp(0, width - 1);
    final py = (y * scale).floor().clamp(0, height - 1);
    final o = (py * width + px) * 4;
    return [bytes.getUint8(o), bytes.getUint8(o + 1), bytes.getUint8(o + 2)];
  }
}

/// A map with its layer's callbacks, displayed in a [_app].
class _Map {
  _Map({this.center = const LatLng(0, 0), this.zoom = _zoom});

  final LatLng center;
  final double zoom;
  final boundary = GlobalKey();
  final mapController = fm.MapController();
  MapTextureController? texture;
  final errors = <LayerException>[];
  final renderEvents = <RenderError>[];
  int stylesLoaded = 0;
  int? displayedFrameId;
  fm.MapCamera? displayedCamera;

  Future<_Shot> capture([double ratio = 2]) async {
    final repaint =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    return _read(await repaint.toImage(pixelRatio: ratio), ratio);
  }
}

Future<_Shot> _read(ui.Image image, double ratio) async {
  final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  return _Shot(bytes, image.width, image.height, ratio);
}

Widget _app(
  _Map map, {
  String? styleJson,
  String? styleUrl,
  List<Widget> children = const [],
  List<Widget> flutterMapChildren = const [],
}) => MaterialApp(
  home: Align(
    alignment: Alignment.topLeft,
    child: RepaintBoundary(
      key: map.boundary,
      child: SizedBox.fromSize(
        size: _size,
        child: fm.FlutterMap(
          mapController: map.mapController,
          options: fm.MapOptions(
            initialCenter: map.center,
            initialZoom: map.zoom,
          ),
          children: [
            MapTextureLayer(
              styleJson: styleJson,
              styleUrl: styleUrl,
              onController: (texture) {
                map.texture = texture;
                texture.events.listen((e) {
                  if (e is RenderError) map.renderEvents.add(e);
                });
              },
              onStyleLoaded: () => map.stylesLoaded++,
              onError: map.errors.add,
              onChildCamera: (frameId, camera) {
                map.displayedFrameId = frameId;
                map.displayedCamera = camera;
              },
              children: children,
            ),
            ...flutterMapChildren,
          ],
        ),
      ),
    ),
  ),
);

/// Pumps until [condition] holds, for at most 20 seconds.
Future<void> _until(
  WidgetTester tester,
  FutureOr<bool> Function() condition,
  String what,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (!await condition()) {
    if (DateTime.now().isAfter(deadline)) fail('timed out waiting for $what');
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Shows the style [styleJson] or [styleUrl] with [children] and waits until
/// the map is idle and displayed.
Future<_Map> _show(
  WidgetTester tester, {
  String? styleJson,
  String? styleUrl,
  List<Widget> children = const [],
  LatLng center = const LatLng(0, 0),
  double zoom = _zoom,
}) async {
  assert((styleJson == null) != (styleUrl == null));
  await tester.pumpWidget(const SizedBox.shrink());
  final map = _Map(center: center, zoom: zoom);
  await tester.pumpWidget(
    _app(map, styleJson: styleJson, styleUrl: styleUrl, children: children),
  );
  await _until(tester, () => map.texture != null, 'the map');
  await _until(tester, () => map.stylesLoaded > 0, 'the style to load');
  await _until(
    tester,
    () => map.texture!.displayedFrame != null,
    'a displayed frame',
  );
  await Future<void>.delayed(const Duration(milliseconds: 500));
  await tester.pump();
  return map;
}

Future<void> _rebuild(
  WidgetTester tester,
  _Map map, {
  String? styleJson,
  String? styleUrl,
  List<Widget> children = const [],
  List<Widget> flutterMapChildren = const [],
}) => tester.pumpWidget(
  _app(
    map,
    styleJson: styleJson,
    styleUrl: styleUrl,
    children: children,
    flutterMapChildren: flutterMapChildren,
  ),
);

/// Returns null when [shot] is as expected, and what is wrong otherwise.
typedef _Problem = String? Function(_Shot shot);

_Problem _pixel(num x, num y, bool Function(_Rgb) test, String expected) =>
    (shot) {
      final c = shot.rgb(x, y);
      return test(c) ? null : 'the pixel at ($x, $y) is $c, not $expected';
    };

_Problem _all(List<_Problem> problems) => (shot) {
  for (final problem in problems) {
    final p = problem(shot);
    if (p != null) return p;
  }
  return null;
};

_Problem _pixels(
  List<(num, num)> positions,
  bool Function(_Rgb) test,
  String expected,
) => _all([for (final (x, y) in positions) _pixel(x, y, test, expected)]);

/// Polls until [problem] finds nothing wrong, for at most 20 seconds, then
/// checks again after the map has had time to show a later frame.
Future<_Shot> _eventually(
  WidgetTester tester,
  _Map map,
  _Problem problem,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  var shot = await map.capture();
  var found = problem(shot);
  while (found != null) {
    if (DateTime.now().isAfter(deadline)) fail(found);
    await tester.pump(const Duration(milliseconds: 100));
    shot = await map.capture();
    found = problem(shot);
  }
  await tester.pump(const Duration(milliseconds: 300));
  await Future<void>.delayed(const Duration(milliseconds: 300));
  shot = await map.capture();
  expect(problem(shot), isNull, reason: 'the map changed after it matched');
  return shot;
}

/// The logical position of a pixel of the glyph block nearest [near] whose
/// surrounding 3 by 3 logical pixels are all black, so that the glyph covers
/// it fully: a white glyph then passes [_isWhite] there, which a glyph edge
/// that is merely [_isDark] doesn't.
Offset _blockPixel(_Shot shot, Offset near) {
  Offset? best;
  for (var y = near.dy - 14; y <= near.dy + 14; y += 0.5) {
    for (var x = near.dx - 44; x <= near.dx + 44; x += 0.5) {
      var solid = true;
      for (var dy = -1.0; dy <= 1 && solid; dy += 0.5) {
        for (var dx = -1.0; dx <= 1 && solid; dx += 0.5) {
          solid = _isBlack(shot.rgb(x + dx, y + dy));
        }
      }
      if (!solid) continue;
      final p = Offset(x, y);
      if (best == null || (p - near).distance < (best - near).distance) {
        best = p;
      }
    }
  }
  if (best == null) fail('no glyph block near $near');
  return best;
}

/// The pixels of the road name and the place name, in a map shown with
/// [children], where the polylines of [children] leave the labels visible.
class _Labels {
  const _Labels(this.road, this.place);
  final Offset road;
  final Offset place;
}

Future<(_Map, _Labels)> _showWithLabels(
  WidgetTester tester,
  String styleJson,
  List<Widget> children,
) async {
  final map = await _show(tester, styleJson: styleJson);
  final shot = await _eventually(
    tester,
    map,
    _all([
      (s) => _blockPixel2(s, const Offset(180, 140))
          ? null
          : 'the road name is not drawn yet',
      (s) => _blockPixel2(s, const Offset(240, 215))
          ? null
          : 'the place name is not drawn yet',
    ]),
  );
  final labels = _Labels(
    _blockPixel(shot, const Offset(180, 140)),
    _blockPixel(shot, const Offset(240, 215)),
  );
  await _rebuild(tester, map, styleJson: styleJson, children: children);
  return (map, labels);
}

bool _blockPixel2(_Shot shot, Offset near) {
  for (var y = near.dy - 14; y <= near.dy + 14; y += 2) {
    for (var x = near.dx - 44; x <= near.dx + 44; x += 2) {
      if (_isDark(shot.rgb(x, y))) return true;
    }
  }
  return false;
}

/// The width in logical pixels of a black line on white along the row [y]
/// from [x0] to [x1]: the sum of the pixel coverages.
double _rowCoverage(_Shot shot, num y, num x0, num x1) {
  var sum = 0.0;
  for (var px = (x0 * shot.scale).floor(); px < x1 * shot.scale; px++) {
    sum += (255 - shot.rgb(px / shot.scale + 0.01, y)[0]) / 255;
  }
  return sum / shot.scale;
}

late String _lightStyle;
late String _darkStyle;

/// A capture of one Flutter frame. [frameId] and [camera] are the map frame
/// the layer displayed in it. The capture reads the map's texture when it is
/// rasterized, which can be after a later Flutter frame displayed another map
/// frame; [captureFrameId] is the map frame displayed when the capture
/// completed, so the capture shows the frame of [camera] only when it equals
/// [frameId].
typedef _Sample<T> = ({
  int index,
  Duration elapsed,
  int? frameId,
  int? captureFrameId,
  fm.MapCamera? camera,
  T value,
});

/// Calls [tick] with the elapsed time in each Flutter frame, which may change
/// the camera, and reads [measure] from a capture of every frame, until
/// [finished] returns true for the elapsed time and the samples so far.
Future<List<_Sample<T>>> _record<T>(
  _Map map, {
  required Future<T> Function(_Shot shot, fm.MapCamera? camera) measure,
  required bool Function(Duration elapsed, List<_Sample<T>> samples) finished,
  void Function(Duration elapsed)? tick,
}) async {
  final samples = <_Sample<T>>[];
  final captures = <Future<void>>[];
  final done = Completer<void>();
  Duration? first;
  var index = 0;
  void frame(Duration timestamp) {
    first ??= timestamp;
    final elapsed = timestamp - first!;
    tick?.call(elapsed);
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (done.isCompleted) return;
      final i = index++;
      final frameId = map.displayedFrameId;
      final camera = map.displayedCamera;
      captures.add(
        map.capture(1).then((shot) async {
          final captureFrameId = map.displayedFrameId;
          final value = await measure(shot, camera);
          samples.add((
            index: i,
            elapsed: elapsed,
            frameId: frameId,
            captureFrameId: captureFrameId,
            camera: camera,
            value: value,
          ));
        }),
      );
    });
    if (finished(elapsed, List.of(samples))) {
      done.complete();
    } else {
      SchedulerBinding.instance.scheduleFrameCallback(frame);
    }
  }

  SchedulerBinding.instance.scheduleFrameCallback(frame);
  SchedulerBinding.instance.scheduleFrame();
  await done.future;
  await Future.wait(captures);
  return samples..sort((a, b) => a.index.compareTo(b.index));
}

/// Whether this is the Android emulator, which renders with a software GPU
/// and so draws only a few frames per second.
Future<bool> _isAndroidEmulator() async {
  if (!Platform.isAndroid) return false;
  for (final property in ['ro.kernel.qemu', 'ro.boot.qemu']) {
    final result = await Process.run('getprop', [property]);
    if ('${result.stdout}'.trim() == '1') return true;
  }
  return false;
}

/// Logical pixels per degree of longitude at [_zoom].
final _pxPerDegree = 256 * math.pow(2, _zoom) / 360;

/// The east offset in logical pixels at [t] seconds of a pan back and forth
/// at 1,000 logical px/s between -125 and 125.
double _panOffset(double t) {
  final s = (t * 1000) % 500;
  return s < 250 ? s - 125 : 375 - s;
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  setUpAll(() async {
    _lightStyle = await rootBundle.loadString('assets/polyline_style.json');
    _darkStyle = await rootBundle.loadString('assets/polyline_style_dark.json');
  });

  group('the test style', () {
    testWidgets('renders its layers and labels', (tester) async {
      final map = await _show(tester, styleJson: _lightStyle);
      await _eventually(
        tester,
        map,
        _all([
          _pixel(5, 5, _isWhite, 'the white background'),
          _pixel(310, 50, _isBlue, 'the blue water'),
          _pixel(30, 140, _isGrey, 'the grey road'),
          _pixel(100, 30, _isTeal, 'the teal bridge'),
          _pixel(100, 140, _isTeal, 'the bridge above the road'),
          _pixel(347, 119, _isOrange, 'the orange building'),
          _pixel(330, 275, _isPurple, 'the purple boundary'),
          (s) {
            var brightest = s.rgb(240, 130);
            for (var y = 130.0; y < 150; y += 1) {
              for (var x = 240.0; x < 262; x += 1) {
                final c = s.rgb(x, y);
                if (_isWhite(c)) return null;
                if (c.reduce(math.min) > brightest.reduce(math.min)) {
                  brightest = c;
                }
              }
            }
            return 'the one-way arrow is not drawn above the road; the '
                'brightest pixel is $brightest';
          },
          (s) => _blockPixel2(s, const Offset(180, 140))
              ? null
              : 'the road name is not drawn',
          (s) => _blockPixel2(s, const Offset(240, 215))
              ? null
              : 'the place name is not drawn',
        ]),
      );
      expect(map.errors, isEmpty);
    });
  });

  group('Polyline layer in the children of the map layer', () {
    testWidgets('Route drawn by the map', (tester) async {
      final points = [
        const Offset(40, 60),
        const Offset(320, 60),
        const Offset(320, 240),
      ];
      final map = await _show(
        tester,
        styleJson: _lightStyle,
        children: [
          _polylines([_route(points, width: 6, join: StrokeJoin.miter)]),
        ],
      );
      final shot = await _eventually(
        tester,
        map,
        _pixel(180, 60, _isRed, 'red on the route'),
      );
      var minX = 1e9, maxX = -1.0, minY = 1e9, maxY = -1.0;
      for (var y = 0.0; y < _size.height; y += 0.5) {
        for (var x = 0.0; x < _size.width; x += 0.5) {
          if (!_isRed(shot.rgb(x, y))) continue;
          minX = math.min(minX, x);
          maxX = math.max(maxX, x);
          minY = math.min(minY, y);
          maxY = math.max(maxY, y);
        }
      }
      debugPrint('ROUTE extent x $minX..$maxX, y $minY..$maxY');
      expect(minX, closeTo(40, 1), reason: 'west end of the route');
      expect(maxX, closeTo(323, 1), reason: 'east side of the last segment');
      expect(minY, closeTo(57, 1), reason: 'north side of the first segment');
      expect(maxY, closeTo(240, 1), reason: 'south end of the route');
      expect(map.errors, isEmpty);
    });

    testWidgets('Polyline layer inside another widget', (tester) async {
      final notifier = ValueNotifier<int>(0);
      addTearDown(notifier.dispose);
      final map = await _show(
        tester,
        styleJson: _lightStyle,
        children: [
          ValueListenableBuilder<int>(
            valueListenable: notifier,
            builder: (_, _, _) => Padding(
              padding: const EdgeInsets.all(4),
              child: _polylines([_horizontal(190)]),
            ),
          ),
        ],
      );
      await _eventually(
        tester,
        map,
        _pixels([(30, 190), (330, 190)], _isRed, 'red on the route'),
      );
    });

    testWidgets('Polyline layer outside a map layer', (tester) async {
      final map = _Map();
      await tester.pumpWidget(
        _app(
          map,
          styleJson: _lightStyle,
          flutterMapChildren: [
            _polylines([_horizontal(190)]),
          ],
        ),
      );
      final exception = tester.takeException();
      expect(exception, isA<AssertionError>());
      expect('$exception', contains('MapigradeLayer'));
    });

    testWidgets('Polylines given before the map exists', (tester) async {
      final map = _Map();
      await tester.pumpWidget(
        _app(
          map,
          styleJson: _lightStyle,
          children: [
            _polylines([_horizontal(190)]),
          ],
        ),
      );
      await _until(tester, () => map.texture != null, 'the map');
      await _eventually(
        tester,
        map,
        _pixels([(30, 190), (330, 190)], _isRed, 'red on the route'),
      );
      expect(map.stylesLoaded, 1);
      expect(map.errors, isEmpty);
    });
  });

  group('How a polyline is drawn', () {
    testWidgets('Translucent line with a border', (tester) async {
      const color = Color(0x800000FF);
      final map = await _show(
        tester,
        styleJson: _lightStyle,
        children: [
          _polylines([
            _route(
              [const Offset(40, 245), const Offset(320, 245)],
              color: color,
              width: 10,
              borderWidth: 4,
              borderColor: _red,
            ),
          ]),
        ],
      );
      bool isMix(_Rgb c) =>
          (c[0] - 128).abs() < 30 && (c[1] - 128).abs() < 30 && c[2] > 225;
      final shot = await _eventually(tester, map, (s) {
        final mix = _count(s, 180, 225, 265, isMix);
        return mix >= 8 ? null : 'only $mix logical px of the line mix';
      });
      final classes = <String>[
        for (var y = 225.0; y < 265; y += 0.5)
          if (_isRed(shot.rgb(180, y)))
            'R'
          else if (isMix(shot.rgb(180, y)))
            'M'
          else
            '.',
      ];
      final column = classes.join();
      debugPrint('BORDER column ${column.replaceAll(RegExp(r'\.+'), '.')}');
      final firstMix = column.indexOf('M');
      final lastMix = column.lastIndexOf('M');
      expect(
        column.substring(firstMix, lastMix + 1).contains('R'),
        isFalse,
        reason: 'no red at the center of the line',
      );
      final above = column.substring(0, firstMix).split('R').length - 1;
      final below = column.substring(lastMix + 1).split('R').length - 1;
      expect(above / 2, closeTo(2, 1), reason: 'red logical px above the line');
      expect(below / 2, closeTo(2, 1), reason: 'red logical px below the line');
      expect(
        _count(shot, 180, 225, 265, isMix),
        closeTo(10, 1),
        reason: 'width of the translucent line',
      );
    });

    {
      testWidgets('Width in meters', (tester) async {
        const latitude = 45.0;
        double expectedWidth(double zoom) =>
            100 *
            256 *
            math.pow(2, zoom) /
            (40075016.686 * math.cos(latitude * math.pi / 180));
        final measured = <double, double>{};
        for (final zoom in [16.0, 18.0]) {
          final map = await _show(
            tester,
            styleJson: _lightStyle,
            center: const LatLng(latitude, 0),
            zoom: zoom,
            children: [
              _polylines([
                MapigradePolyline(
                  points: const [
                    LatLng(latitude, 0),
                    LatLng(latitude + 0.01, 0),
                  ],
                  color: _black,
                  strokeWidth: 100,
                  useStrokeWidthInMeter: true,
                  strokeCap: StrokeCap.butt,
                ),
              ]),
            ],
          );
          final shot = await _eventually(
            tester,
            map,
            (s) => _rowCoverage(s, 100, 0, 360) > 20
                ? null
                : 'the line is not drawn',
          );
          measured[zoom] = _rowCoverage(shot, 100, 0, 360);
          debugPrint(
            'METERS zoom $zoom: ${measured[zoom]!.toStringAsFixed(2)} px, '
            'expected ${expectedWidth(zoom).toStringAsFixed(2)} px',
          );
        }
        for (final zoom in [16.0, 18.0]) {
          expect(
            measured[zoom],
            closeTo(expectedWidth(zoom), expectedWidth(zoom) * 0.01),
            reason: 'width of 100 m at latitude 45, zoom $zoom',
          );
        }
        expect(
          measured[18]! / measured[16]!,
          closeTo(4, 4 * 0.01),
          reason: 'width at a zoom 2 higher',
        );
      });
    }

    testWidgets('Dashes scale with the width', (tester) async {
      // East of the bridge, 19 periods of 12 px and a last dash; x = 180 is
      // a tile boundary, where MapLibre starts the pattern again.
      const x0 = 120.0, x1 = 356.0, tileBoundary = 180.0;
      final map = await _show(
        tester,
        styleJson: _lightStyle,
        children: [
          _polylines([
            _route(
              [const Offset(x0, 265), const Offset(x1, 265)],
              width: 4,
              dashes: const [2, 1],
            ),
          ]),
        ],
      );
      double redness(_Shot s, int px) =>
          _redness(s.rgb(px / s.scale + 0.01, 265));
      final shot = await _eventually(tester, map, (s) {
        var sum = 0.0;
        for (var px = 0; px < _size.width * s.scale; px++) {
          sum += redness(s, px);
        }
        return sum / s.scale > 100 ? null : 'the dashed line is not drawn';
      });
      final first = ((x0 - 10) * shot.scale).round();
      final boundary = (tileBoundary * shot.scale).round();
      final dark = <bool>[
        for (var px = first; px < _size.width * shot.scale; px++)
          redness(shot, px) > 0.5,
      ];
      final dashes = <double>[];
      final gaps = <double>[];
      var start = 0;
      for (var i = 1; i <= dark.length; i++) {
        if (i < dark.length && dark[i] == dark[start]) continue;
        final length = (i - start) / shot.scale;
        final touchesBoundary =
            start + first <= boundary && boundary <= i + first;
        if (start > 0 && i < dark.length && !touchesBoundary) {
          (dark[start] ? dashes : gaps).add(length);
        }
        start = i;
      }
      debugPrint('DASHES $dashes gaps $gaps');
      expect(dashes.length, greaterThan(16), reason: 'number of dashes');
      for (final d in dashes) {
        expect(d, closeTo(8, 1), reason: 'dash length');
      }
      for (final g in gaps) {
        expect(g, closeTo(4, 1), reason: 'gap length');
      }
    });

    testWidgets('Gradient along a curved line', (tester) async {
      final map = await _show(
        tester,
        styleJson: _lightStyle,
        children: [
          _polylines([
            _route(
              [
                const Offset(50, 170),
                const Offset(310, 170),
                const Offset(310, 196),
                const Offset(60, 196),
              ],
              gradientColors: const [_red, _blue],
            ),
          ]),
        ],
      );
      final path = [
        const Offset(56, 170),
        const Offset(180, 170),
        const Offset(300, 170),
        const Offset(310, 183),
        const Offset(300, 196),
        const Offset(180, 196),
        const Offset(64, 196),
      ];
      final shot = await _eventually(
        tester,
        map,
        _pixel(
          56,
          170,
          (c) => c[0] > 200 && c[1] < 90,
          'red at the first point',
        ),
      );
      final colors = [for (final p in path) shot.rgb(p.dx, p.dy)];
      debugPrint('GRADIENT $colors');
      expect(colors.first[0], greaterThan(220), reason: 'red at the start');
      expect(colors.first[2], lessThan(40), reason: 'not blue at the start');
      expect(colors.last[2], greaterThan(220), reason: 'blue at the end');
      expect(colors.last[0], lessThan(40), reason: 'not red at the end');
      for (var i = 1; i < colors.length; i++) {
        expect(
          colors[i][0],
          lessThanOrEqualTo(colors[i - 1][0] + 12),
          reason: 'red decreases along the line at $i',
        );
      }
      expect(
        colors[1][0] - colors[5][0],
        greaterThan(80),
        reason:
            'positions at the same x on the way out and back differ, so the '
            'gradient follows the line',
      );
      expect(colors[3][0], closeTo(130, 50), reason: 'halfway along the line');
    });

    testWidgets('Line across the antimeridian', (tester) async {
      final map = await _show(
        tester,
        styleJson: _lightStyle,
        center: const LatLng(0, 180),
        zoom: 7,
        children: [
          _polylines([
            MapigradePolyline(
              points: const [LatLng(0, 179), LatLng(0, -179)],
              color: _red,
              strokeWidth: 6,
              strokeCap: StrokeCap.butt,
            ),
          ]),
        ],
      );
      final pxPerDegree = 256 * math.pow(2, 7) / 360;
      final half = pxPerDegree;
      final shot = await _eventually(
        tester,
        map,
        _pixels(
          [for (var dx = -80.0; dx <= 80; dx += 20) (180 + dx, 140)],
          _isRed,
          'red on the line',
        ),
      );
      expect(
        _isRed(shot.rgb(180 - half - 6, 140)),
        isFalse,
        reason: 'west of the western end, 1 degree west of 180',
      );
      expect(
        _isRed(shot.rgb(180 + half + 6, 140)),
        isFalse,
        reason: 'east of the eastern end',
      );
      var length = 0.0;
      for (var x = 0.0; x < 360; x += 0.5) {
        if (_isRed(shot.rgb(x, 140))) length += 0.5;
      }
      debugPrint(
        'ANTIMERIDIAN line length $length px, 2 degrees '
        '${2 * pxPerDegree} px',
      );
      expect(length, closeTo(2 * pxPerDegree, 3), reason: 'length of the line');
    });
  });

  group('Draw order of polylines', () {
    testWidgets('Later polyline above', (tester) async {
      final map = await _show(
        tester,
        styleJson: _lightStyle,
        children: [_polylines(_crossing(150, 200, _red, _blue))],
      );
      await _eventually(
        tester,
        map,
        _all([
          _pixel(150, 200, _isBlue, 'blue at the crossing'),
          _pixel(120, 170, _isRed, 'red away from the crossing'),
          _pixel(120, 230, _isBlue, 'blue away from the crossing'),
        ]),
      );
    });

    testWidgets('Borders in a run', (tester) async {
      final map = await _show(
        tester,
        styleJson: _lightStyle,
        children: [
          _polylines([
            _route(
              [const Offset(60, 200), const Offset(240, 200)],
              color: _red,
              width: 10,
              borderWidth: 8,
              borderColor: const Color(0xFFFFFF00),
            ),
            _route(
              [const Offset(150, 160), const Offset(150, 250)],
              color: _green,
              width: 10,
              borderWidth: 8,
              borderColor: const Color(0xFF800080),
            ),
          ]),
        ],
      );
      await _eventually(
        tester,
        map,
        _all([
          _pixel(150, 200, _isGreen, 'the second line above the first'),
          _pixel(
            156.5,
            200,
            _isRed,
            'the first line above the border of the second',
          ),
          _pixel(
            143.5,
            200,
            _isRed,
            'the first line above the border of the second',
          ),
          _pixel(
            150,
            206.5,
            _isGreen,
            'the second line above the border of the first',
          ),
          _pixel(
            150,
            193.5,
            _isGreen,
            'the second line above the border of the first',
          ),
          _pixel(
            100,
            205.5,
            (c) => c[0] > 200 && c[1] > 200 && c[2] < 90,
            'the border of the first',
          ),
          _pixel(155, 235, _isPurple, 'the border of the second'),
        ]),
      );
    });

    testWidgets('Crossings on tile boundaries follow the list order', (
      tester,
    ) async {
      // Tile boundaries of the GeoJSON tiles at the map's zoom run through
      // the center of the map: x = 180 and y = 140.
      final crossings = [
        const Offset(180, 60),
        const Offset(50, 140),
        const Offset(180, 210),
      ];
      final redOver = [
        for (final c in crossings) ..._crossing(c.dx, c.dy, _blue, _red),
      ];
      final blueOver = [
        for (final c in crossings) ..._crossing(c.dx, c.dy, _red, _blue),
      ];
      final map = await _show(
        tester,
        styleJson: _lightStyle,
        children: [_polylines(blueOver)],
      );
      _Problem around(bool Function(_Rgb) test, String color) => _pixels(
        [
          for (final c in crossings)
            for (final d in const [
              Offset(0, 0),
              Offset(-3, 0),
              Offset(3, 0),
              Offset(0, -3),
              Offset(0, 3),
            ])
              (c.dx + d.dx, c.dy + d.dy),
        ],
        test,
        '$color at a crossing on a tile boundary',
      );
      await _eventually(tester, map, around(_isBlue, 'blue'));
      await _rebuild(
        tester,
        map,
        styleJson: _lightStyle,
        children: [_polylines(redOver)],
      );
      await _eventually(tester, map, around(_isRed, 'red'));
    });

    testWidgets('Crossing at the corner of four tiles follows the list order', (
      tester,
    ) async {
      final map = await _show(
        tester,
        styleJson: _lightStyle,
        children: [
          _polylines(
            _crossing(180, 140, _red, _blue),
            placement: const LayerPlacement.top(),
          ),
        ],
      );
      await _eventually(
        tester,
        map,
        _pixels(
          [(180, 140), (177, 137), (183, 137), (177, 143), (183, 143)],
          _isBlue,
          'blue at the crossing at the tile corner',
        ),
      );
    });
  });

  group('Placement among the style\'s layers', () {
    testWidgets('Route below labels', (tester) async {
      final (map, labels) = await _showWithLabels(tester, _lightStyle, [
        _polylines([_horizontal(140, width: 12)]),
      ]);
      await _eventually(
        tester,
        map,
        _all([
          _pixel(
            labels.road.dx,
            labels.road.dy,
            _isDark,
            'the road name above the polyline',
          ),
          _pixel(30, 140, _isRed, 'the polyline over the road'),
          _pixel(300, 140, _isRed, 'the polyline over the road'),
        ]),
      );
    });

    testWidgets('Style with symbol layers between other layers', (
      tester,
    ) async {
      final (map, labels) = await _showWithLabels(tester, _lightStyle, [
        _polylines([_horizontal(140, width: 12), _horizontal(215, width: 12)]),
      ]);
      await _eventually(
        tester,
        map,
        _all([
          _pixel(100, 215, _isRed, 'the polyline above the bridge'),
          _pixel(100, 140, _isRed, 'the polyline above the bridge'),
          _pixel(250, 140, _isRed, 'the polyline above the one-way arrows'),
          _pixel(
            labels.place.dx,
            labels.place.dy,
            _isDark,
            'the place name above the polyline',
          ),
          _pixel(
            labels.road.dx,
            labels.road.dy,
            _isDark,
            'the road name above the polyline',
          ),
        ]),
      );
    });

    testWidgets('Style with 3D buildings', (tester) async {
      final lines = [_horizontal(119, width: 12), _horizontal(275, width: 12)];
      final map = await _show(
        tester,
        styleJson: _lightStyle,
        children: [_polylines(lines)],
      );
      await _eventually(
        tester,
        map,
        _all([
          _pixel(347, 119, _isOrange, 'the building above the polyline'),
          _pixel(200, 119, _isRed, 'the polyline beside the building'),
          _pixel(330, 275, _isPurple, 'the boundary above the polyline'),
          _pixel(200, 275, _isRed, 'the polyline west of the boundary'),
        ]),
      );
      await _rebuild(
        tester,
        map,
        styleJson: _lightStyle,
        children: [_polylines(lines, placement: const LayerPlacement.top())],
      );
      await _eventually(
        tester,
        map,
        _all([
          _pixel(347, 119, _isRed, 'the polyline above the building'),
          _pixel(330, 275, _isRed, 'the polyline above the boundary'),
        ]),
      );
      expect(map.errors, isEmpty);
    });

    testWidgets('Below a named layer', (tester) async {
      final map = await _show(
        tester,
        styleJson: _lightStyle,
        children: [
          _polylines([
            _vertical(300),
          ], placement: const LayerPlacement.belowLayer('water')),
        ],
      );
      await _eventually(
        tester,
        map,
        _all([
          _pixel(300, 50, _isBlue, 'the water above the polyline'),
          _pixel(300, 200, _isRed, 'the polyline on the background'),
        ]),
      );
    });

    testWidgets('A different placement is drawn at the new placement', (
      tester,
    ) async {
      final line = [_vertical(300)];
      final map = await _show(
        tester,
        styleJson: _lightStyle,
        children: [_polylines(line)],
      );
      await _eventually(
        tester,
        map,
        _all([
          _pixel(300, 50, _isRed, 'the polyline above the water'),
          _pixel(300, 140, _isRed, 'the polyline above the road'),
        ]),
      );
      await _rebuild(
        tester,
        map,
        styleJson: _lightStyle,
        children: [
          _polylines(line, placement: const LayerPlacement.belowLayer('water')),
        ],
      );
      await _eventually(
        tester,
        map,
        _all([
          _pixel(300, 50, _isBlue, 'the water above the polyline'),
          _pixel(300, 140, _isGrey, 'the road above the polyline'),
          _pixel(300, 200, _isRed, 'the polyline on the background'),
        ]),
      );
      await _rebuild(
        tester,
        map,
        styleJson: _lightStyle,
        children: [_polylines(line, placement: const LayerPlacement.top())],
      );
      await _eventually(
        tester,
        map,
        _all([
          _pixel(300, 50, _isRed, 'the polyline above the water'),
          _pixel(300, 140, _isRed, 'the polyline above the road'),
        ]),
      );
      expect(map.errors, isEmpty);
    });

    testWidgets('Named layer missing', (tester) async {
      final (map, labels) = await _showWithLabels(tester, _lightStyle, [
        _polylines([
          _horizontal(140, width: 12),
        ], placement: const LayerPlacement.belowLayer('road-label')),
      ]);
      await _eventually(
        tester,
        map,
        _all([
          _pixel(
            labels.road.dx,
            labels.road.dy,
            _isRed,
            'the polyline above the road name',
          ),
          _pixel(30, 140, _isRed, 'the polyline above all layers'),
        ]),
      );
      await Future<void>.delayed(const Duration(seconds: 1));
      expect(map.errors, hasLength(1), reason: '${map.errors}');
      expect(map.errors.single, isA<LayerLoadException>());
      expect(map.errors.single.message, contains('road-label'));
    });

    testWidgets('Above everything', (tester) async {
      final (map, labels) = await _showWithLabels(tester, _lightStyle, [
        _polylines([
          _horizontal(140, width: 12),
          _horizontal(215, width: 12),
        ], placement: const LayerPlacement.top()),
      ]);
      await _eventually(
        tester,
        map,
        _all([
          _pixel(
            labels.road.dx,
            labels.road.dy,
            _isRed,
            'the polyline above the road name',
          ),
          _pixel(
            labels.place.dx,
            labels.place.dy,
            _isRed,
            'the polyline above the place name',
          ),
        ]),
      );
    });
  });

  group('Order of several polyline layers', () {
    testWidgets('Two polyline layers', (tester) async {
      final map = await _show(
        tester,
        styleJson: _lightStyle,
        children: [
          _polylines(_crossing(150, 200, _red, _red).take(1).toList()),
          _polylines(_crossing(150, 200, _blue, _blue).skip(1).toList()),
        ],
      );
      await _eventually(
        tester,
        map,
        _all([
          _pixel(150, 200, _isBlue, 'blue at the crossing'),
          _pixel(120, 170, _isRed, 'red away from the crossing'),
        ]),
      );
    });

    testWidgets('Child inserted before an existing polyline layer', (
      tester,
    ) async {
      const blueKey = ValueKey('blue');
      final blue = _crossing(150, 200, _blue, _blue).skip(1).toList();
      final map = await _show(
        tester,
        styleJson: _lightStyle,
        children: [_polylines(blue, key: blueKey)],
      );
      await _eventually(
        tester,
        map,
        _pixel(150, 200, _isBlue, 'blue at the crossing'),
      );
      await _rebuild(
        tester,
        map,
        styleJson: _lightStyle,
        children: [
          _polylines(
            _crossing(150, 200, _red, _red).take(1).toList(),
            key: const ValueKey('red'),
          ),
          _polylines(blue, key: blueKey),
        ],
      );
      await _eventually(
        tester,
        map,
        _all([
          _pixel(120, 170, _isRed, 'the inserted red polyline'),
          _pixel(150, 200, _isBlue, 'blue at the crossing'),
        ]),
      );
    });

    testWidgets('The order follows children when they are reordered', (
      tester,
    ) async {
      const redKey = ValueKey('red');
      const blueKey = ValueKey('blue');
      final red = _crossing(150, 200, _red, _red).take(1).toList();
      final blue = _crossing(150, 200, _blue, _blue).skip(1).toList();
      final map = await _show(
        tester,
        styleJson: _lightStyle,
        children: [
          _polylines(red, key: redKey),
          _polylines(blue, key: blueKey),
        ],
      );
      await _eventually(tester, map, _pixel(150, 200, _isBlue, 'blue'));
      await _rebuild(
        tester,
        map,
        styleJson: _lightStyle,
        children: [
          _polylines(blue, key: blueKey),
          _polylines(red, key: redKey),
        ],
      );
      await _eventually(
        tester,
        map,
        _pixel(150, 200, _isRed, 'red at the crossing after the reorder'),
      );
    });

    testWidgets(
      'Polyline layers below one child are drawn in insertion order',
      (tester) async {
        final red = _crossing(150, 200, _red, _red).take(1).toList();
        final blue = _crossing(150, 200, _blue, _blue).skip(1).toList();
        Widget stack(List<Widget> layers) => Stack(children: layers);
        final map = await _show(
          tester,
          styleJson: _lightStyle,
          children: [
            stack([_polylines(red, key: const ValueKey('red'))]),
          ],
        );
        await _eventually(tester, map, _pixel(120, 170, _isRed, 'red'));
        await _rebuild(
          tester,
          map,
          styleJson: _lightStyle,
          children: [
            stack([
              _polylines(blue, key: const ValueKey('blue')),
              _polylines(red, key: const ValueKey('red')),
            ]),
          ],
        );
        await _eventually(
          tester,
          map,
          _all([
            _pixel(120, 230, _isBlue, 'the inserted blue polyline'),
            _pixel(150, 200, _isBlue, 'blue, inserted later, above red'),
          ]),
        );
      },
    );
  });

  group('Polyline updates', () {
    testWidgets('Polyline points changed', (tester) async {
      final points = [const Offset(40, 190), const Offset(200, 190)];
      final map = await _show(
        tester,
        styleJson: _lightStyle,
        children: [
          _polylines([_route(points)]),
        ],
      );
      await _eventually(
        tester,
        map,
        _all([
          _pixel(100, 190, _isRed, 'the polyline'),
          _pixel(300, 190, (c) => _isWhite(c), 'no polyline yet'),
        ]),
      );
      await _rebuild(
        tester,
        map,
        styleJson: _lightStyle,
        children: [
          _polylines([
            _route([...points, const Offset(320, 190)]),
          ]),
        ],
      );
      await _eventually(
        tester,
        map,
        _pixels([(100, 190), (300, 190)], _isRed, 'the longer polyline'),
      );
    });

    testWidgets('A polyline that is no longer in the list is not drawn', (
      tester,
    ) async {
      final map = await _show(
        tester,
        styleJson: _lightStyle,
        children: [
          _polylines([_horizontal(190), _horizontal(240, color: _blue)]),
        ],
      );
      await _eventually(
        tester,
        map,
        _all([
          _pixel(30, 190, _isRed, 'the first polyline'),
          _pixel(30, 240, _isBlue, 'the second polyline'),
        ]),
      );
      await _rebuild(
        tester,
        map,
        styleJson: _lightStyle,
        children: [
          _polylines([_horizontal(190)]),
        ],
      );
      await _eventually(
        tester,
        map,
        _all([
          _pixel(30, 190, _isRed, 'the first polyline'),
          _pixel(30, 240, _isWhite, 'no second polyline'),
        ]),
      );
    });

    testWidgets('Rebuild with an equal list', (tester) async {
      final map = await _show(
        tester,
        styleJson: _lightStyle,
        children: [
          _polylines([_horizontal(190)]),
        ],
      );
      await _eventually(tester, map, _pixel(30, 190, _isRed, 'the polyline'));
      await _rebuild(
        tester,
        map,
        styleJson: _lightStyle,
        children: [
          _polylines([_horizontal(190)]),
        ],
      );
      await _eventually(tester, map, _pixel(30, 190, _isRed, 'the polyline'));
      expect(map.errors, isEmpty);
      expect(map.renderEvents, isEmpty);
    });

    testWidgets('Polyline layer removed', (tester) async {
      final map = await _show(
        tester,
        styleJson: _lightStyle,
        children: [
          _polylines([_horizontal(190)]),
          _polylines([_horizontal(240, color: _blue)]),
        ],
      );
      await _eventually(
        tester,
        map,
        _all([
          _pixel(30, 190, _isRed, 'the first polyline layer'),
          _pixel(30, 240, _isBlue, 'the second polyline layer'),
        ]),
      );
      await _rebuild(tester, map, styleJson: _lightStyle, children: const []);
      await _eventually(
        tester,
        map,
        _all([
          _pixel(30, 190, _isWhite, 'no polylines'),
          _pixel(30, 240, _isWhite, 'no polylines'),
        ]),
      );
      expect(map.errors, isEmpty);
    });
  });

  group('Map polylines below Flutter children', () {
    testWidgets('a marker is drawn above the polyline', (tester) async {
      const markerColor = Color(0xFF008000);
      final map = await _show(
        tester,
        styleJson: _lightStyle,
        children: [
          fm.MarkerLayer(
            markers: [
              fm.Marker(
                point: _ll(180, 105),
                width: 40,
                height: 40,
                child: const ColoredBox(color: markerColor),
              ),
            ],
          ),
          _polylines([_horizontal(105, width: 12)]),
        ],
      );
      await _eventually(
        tester,
        map,
        _all([
          _pixel(
            180,
            105,
            (c) => c[1] > 100 && c[0] < 40 && c[2] < 40,
            'the marker above the polyline',
          ),
          _pixel(150, 105, _isRed, 'the polyline beside the marker'),
          _pixel(210, 105, _isRed, 'the polyline beside the marker'),
        ]),
      );
    });
  });

  group('Pan with polylines', () {
    testWidgets('the polyline is where the displayed frame draws it', (
      tester,
    ) async {
      final emulator = await _isAndroidEmulator();
      final map = await _show(
        tester,
        styleJson: _lightStyle,
        children: [
          _polylines([
            MapigradePolyline(
              points: const [LatLng(-0.06, 0), LatLng(0.06, 0)],
              color: _red,
              strokeWidth: 8,
              strokeCap: StrokeCap.butt,
            ),
          ]),
        ],
      );
      await _eventually(tester, map, _pixel(180, 175, _isRed, 'the polyline'));
      final samples = await _record<double?>(
        map,
        measure: (shot, camera) async {
          var sum = 0.0, weighted = 0.0;
          for (var y = 160.0; y < 200; y += 1) {
            for (var x = 0.0; x < _size.width; x += 1) {
              final w = _redness(shot.rgb(x + 0.5, y + 0.5));
              sum += w;
              weighted += w * (x + 0.5);
            }
          }
          if (sum < 40 * 4 * 0.5) return null;
          final observed = weighted / sum;
          final expected = camera!.latLngToScreenOffset(const LatLng(0, 0)).dx;
          return observed - expected;
        },
        tick: (elapsed) {
          final east = _panOffset(elapsed.inMicroseconds / 1e6);
          map.mapController.move(LatLng(0, east / _pxPerDegree), _zoom);
        },
        finished: (elapsed, _) => elapsed >= const Duration(seconds: 2),
      );
      double worstOf(Iterable<_Sample<double?>> of) => of
          .map((s) => s.value)
          .whereType<double>()
          .fold<double>(0, (m, e) => math.max(m, e.abs()));
      final paired = [
        for (final s in samples)
          if (s.captureFrameId == s.frameId) s,
      ];
      final unpaired = samples.where((s) => s.captureFrameId != s.frameId);
      final errors = [for (final s in paired) s.value];
      final frames = {for (final s in paired) s.frameId}.length;
      final missing = errors.where((e) => e == null).length;
      final worst = worstOf(paired);
      debugPrint(
        'PAN frames ${paired.length}, map frames $frames, polyline missing '
        'in $missing, largest error ${worst.toStringAsFixed(3)} px; '
        '${unpaired.length} captures straddled a frame change, largest error '
        '${worstOf(unpaired).toStringAsFixed(3)} px',
      );
      expect(
        paired.length,
        greaterThan(emulator ? 3 : 30),
        reason: 'Flutter frames sampled',
      );
      expect(missing, 0, reason: 'frames without the polyline');
      expect(worst, lessThanOrEqualTo(1.0), reason: 'largest error in px');
      expect(map.errors, isEmpty);
    });
  });

  group('Polylines across style loads', () {
    for (final byUrl in [true, false]) {
      testWidgets('Light and dark style${byUrl ? ' by URL' : ' by JSON'}', (
        tester,
      ) async {
        String? json(String style) => byUrl ? null : style;
        String? url(String style) => byUrl
            ? (style == _lightStyle ? _lightStyleUrl : _darkStyleUrl)
            : null;
        final map = await _show(
          tester,
          styleJson: json(_lightStyle),
          styleUrl: url(_lightStyle),
        );
        final baseline = await _eventually(
          tester,
          map,
          (s) => _blockPixel2(s, const Offset(180, 140))
              ? null
              : 'the road name is not drawn',
        );
        final label = _blockPixel(baseline, const Offset(180, 140));
        Future<void> pumpStyle(String style) => _rebuild(
          tester,
          map,
          styleJson: json(style),
          styleUrl: url(style),
          children: [
            _polylines([_horizontal(140, width: 12)]),
          ],
        );
        await pumpStyle(_lightStyle);
        await _eventually(
          tester,
          map,
          _all([
            _pixel(30, 140, _isRed, 'the polyline'),
            _pixel(label.dx, label.dy, _isDark, 'the road name'),
          ]),
        );
        for (var i = 0; i < 4; i++) {
          final toDark = i.isEven;
          final loaded = map.stylesLoaded;
          await pumpStyle(toDark ? _darkStyle : _lightStyle);
          bool newBackground(_Rgb c) =>
              toDark ? c[0] < 60 && c[1] < 60 : _isWhite(c);
          final samples = await _record<({bool newStyle, bool polyline})>(
            map,
            measure: (shot, _) async => (
              newStyle: newBackground(shot.rgb(5, 270)),
              polyline: _isRed(shot.rgb(30, 140)),
            ),
            finished: (elapsed, samples) {
              if (elapsed > const Duration(seconds: 15)) return true;
              if (samples.length < 40) return false;
              final last = samples.sublist(samples.length - 20);
              return last.every((s) => s.value.newStyle && s.value.polyline);
            },
          );
          final newStyle = samples.where((s) => s.value.newStyle).toList();
          final lacking = newStyle.where((s) => !s.value.polyline).toList();
          final lackingAny = samples.where((s) => !s.value.polyline).toList();
          debugPrint(
            'STYLE SWITCH ${byUrl ? 'URL' : 'JSON'} '
            '${toDark ? 'light to dark' : 'dark to light'}: '
            'Flutter frames ${samples.length}, '
            'frames of the new style ${newStyle.length}, '
            'frames of the new style without the polyline '
            '${lacking.length} '
            '(map frames ${{for (final s in lacking) s.frameId}.length}), '
            'frames since the change without the polyline '
            '${lackingAny.length} '
            '(map frames ${{for (final s in lackingAny) s.frameId}.length}), '
            'styles loaded ${map.stylesLoaded - loaded}',
          );
          expect(samples.last.value, (
            newStyle: true,
            polyline: true,
          ), reason: 'the new style with the polyline after the load');
          final shot = await map.capture();
          expect(
            _isRed(shot.rgb(label.dx, label.dy)),
            isFalse,
            reason: 'the road name above the polyline in the new style',
          );
          expect(
            toDark
                ? _isWhite(shot.rgb(label.dx, label.dy))
                : _isDark(shot.rgb(label.dx, label.dy)),
            isTrue,
            reason:
                'the road name has the label color of the new style; the '
                'pixels from 3 left to 3 right of $label are '
                '${[for (var dx = -3; dx <= 3; dx++) shot.rgb(label.dx + dx, label.dy)]}',
          );
        }
        expect(
          map.errors.whereType<LayerRenderException>(),
          isEmpty,
          reason: 'render errors during the style switches: ${map.errors}',
        );
        expect(
          map.renderEvents,
          isEmpty,
          reason:
              'render error events: ${map.renderEvents.map((e) => e.message)}',
        );
        expect(map.errors, isEmpty);
      });
    }
  });
}

MapigradePolyline _vertical(double x, {Color color = _red, double width = 8}) =>
    _route(
      [Offset(x, -20), Offset(x, _size.height + 20)],
      color: color,
      width: width,
    );

/// The number of logical pixels of the column [x] from [y0] to [y1] for which
/// [test] holds.
double _count(_Shot shot, num x, num y0, num y1, bool Function(_Rgb) test) {
  var n = 0;
  for (var py = (y0 * shot.scale).floor(); py < y1 * shot.scale; py++) {
    if (test(shot.rgb(x, py / shot.scale + 0.01))) n++;
  }
  return n / shot.scale;
}
