// Integration tests for HTTP header rules and asset:// URLs (map-layer spec
// requirements "HTTP headers" and "Flutter assets", design D84 of the
// http-headers-and-assets change).
//
//   cd packages/test_harness && flutter test integration_test/resource_test.dart -d macos
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_map/flutter_map.dart' hide MapCamera;
import 'package:flutter_mapigrade/flutter_mapigrade.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:latlong2/latlong.dart';

const center = LatLng(51.5, -0.12);

// The colors of assets/style.json: the background, and the square of
// assets/area.pmtiles around [center].
const backgroundColor = [0, 255, 0];
const areaColor = [0, 0, 255];

/// A request that [LoopbackServer] received.
class RecordedRequest {
  RecordedRequest(this.path, this.headers);

  final String path;

  /// The request's headers, with names in lower case.
  final Map<String, List<String>> headers;
}

/// An HTTP server on the loopback address that serves [routes], answers any
/// other path that ends in `.pbf` with an empty tile, and records each
/// request.
class LoopbackServer {
  LoopbackServer._(this._server, this.routes) {
    _server.listen((request) {
      final headers = <String, List<String>>{};
      request.headers.forEach((name, values) => headers[name] = values);
      final path = request.uri.path;
      requests.add(RecordedRequest(path, headers));
      final route = routes[path];
      final response = request.response;
      if (route == null) {
        if (!path.endsWith('.pbf')) response.statusCode = HttpStatus.notFound;
      } else {
        response.headers.contentType = route.$1;
        response.add(route.$2);
      }
      response.close();
    });
  }

  static Future<LoopbackServer> start(
    Map<String, (ContentType, List<int>)> routes,
  ) async => LoopbackServer._(
    await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    routes,
  );

  final HttpServer _server;
  final Map<String, (ContentType, List<int>)> routes;
  final requests = <RecordedRequest>[];

  /// The URL of [path] on this server.
  String url(String path) => 'http://127.0.0.1:${_server.port}$path';

  /// The requests whose path starts with [prefix] and ends in `.pbf`.
  Iterable<RecordedRequest> tileRequests(String prefix) => requests.where(
    (r) => r.path.startsWith(prefix) && r.path.endsWith('.pbf'),
  );

  /// Waits until each of [prefixes] has received a tile request.
  Future<void> waitForTiles(List<String> prefixes) async {
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (prefixes.any((p) => tileRequests(p).isEmpty)) {
      if (DateTime.now().isAfter(deadline)) {
        fail(
          'no tile requests for '
          '${prefixes.where((p) => tileRequests(p).isEmpty)}; '
          'requests ${requests.map((r) => r.path)}',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  Future<void> close() => _server.close(force: true);
}

(ContentType, List<int>) json(Object value) =>
    (ContentType.json, utf8.encode(jsonEncode(value)));

/// A style with one vector source and one fill layer for each of [prefixes],
/// whose tiles are at `<prefix>{z}/{x}/{y}.pbf` on [server].
Object tileStyle(LoopbackServer server, List<String> prefixes) => {
  'version': 8,
  'sources': {
    for (final (i, prefix) in prefixes.indexed)
      's$i': {
        'type': 'vector',
        'tiles': [server.url('$prefix{z}/{x}/{y}.pbf')],
        'maxzoom': 14,
      },
  },
  'layers': [
    for (final i in prefixes.indexed.map((e) => e.$1))
      {'id': 'l$i', 'type': 'fill', 'source': 's$i', 'source-layer': 'x'},
  ],
};

/// The values of the header `X-Access-Key` in [request].
List<String>? accessKeys(RecordedRequest request) =>
    request.headers['x-access-key'];

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  /// A 400x300 FlutterMap at [center] with [layer] as its only child.
  Widget appWith(Widget layer, {GlobalKey? boundaryKey}) => MaterialApp(
    home: Center(
      child: RepaintBoundary(
        key: boundaryKey,
        child: SizedBox(
          width: 400,
          height: 300,
          child: FlutterMap(
            options: const MapOptions(initialCenter: center, initialZoom: 12),
            children: [layer],
          ),
        ),
      ),
    ),
  );

  testWidgets('a style from a loopback HTTP server loads', (tester) async {
    final server = await LoopbackServer.start({
      '/style.json': json({'version': 8, 'sources': {}, 'layers': []}),
    });
    addTearDown(server.close);
    final loaded = Completer<void>();
    await tester.pumpWidget(
      appWith(
        MapigradeLayer(
          styleUrl: server.url('/style.json'),
          onStyleLoaded: loaded.complete,
          onError: (e) => fail('unexpected failure $e'),
        ),
      ),
    );
    await loaded.future.timeout(const Duration(seconds: 20));
    expect(server.requests.map((r) => r.path), contains('/style.json'));
  });

  group('HTTP headers', () {
    late LoopbackServer server;

    /// Starts [server] with a style whose tiles are under [prefixes], and
    /// places the layer with [rules] and that style.
    Future<void> placeLayer(
      WidgetTester tester,
      List<String> prefixes,
      List<HttpHeaderRule> Function(LoopbackServer) rules,
    ) async {
      final routes = <String, (ContentType, List<int>)>{};
      server = await LoopbackServer.start(routes);
      addTearDown(server.close);
      routes['/style.json'] = json(tileStyle(server, prefixes));
      await tester.pumpWidget(
        appWith(
          MapigradeLayer(
            styleUrl: server.url('/style.json'),
            httpHeaders: rules(server),
            onError: (e) => fail('unexpected failure $e'),
          ),
        ),
      );
      await server.waitForTiles(prefixes);
    }

    testWidgets('are sent to a matching prefix and not to another prefix', (
      tester,
    ) async {
      await placeLayer(
        tester,
        ['/a/', '/b/'],
        (server) => [
          HttpHeaderRule(
            url: server.url('/a/**'),
            headers: {'X-Access-Key': 'k1'},
          ),
        ],
      );
      for (final request in server.tileRequests('/a/')) {
        expect(accessKeys(request), ['k1'], reason: request.path);
      }
      for (final request in [
        ...server.tileRequests('/b/'),
        ...server.requests.where((r) => r.path == '/style.json'),
      ]) {
        expect(accessKeys(request), isNull, reason: request.path);
      }
    });

    testWidgets('come from the first matching rule', (tester) async {
      await placeLayer(
        tester,
        ['/a/v2/', '/a/v1/'],
        (server) => [
          HttpHeaderRule(
            url: server.url('/a/v2/**'),
            headers: {'X-Access-Key': 'k2'},
          ),
          HttpHeaderRule(
            url: server.url('/a/**'),
            headers: {'X-Access-Key': 'k1'},
          ),
        ],
      );
      for (final request in server.tileRequests('/a/v2/')) {
        expect(accessKeys(request), ['k2'], reason: request.path);
      }
      for (final request in server.tileRequests('/a/v1/')) {
        expect(accessKeys(request), ['k1'], reason: request.path);
      }
    });

    testWidgets('a header that MapLibre manages reports a creation failure '
        'that names it and doesn\'t contain its value', (tester) async {
      const secret = 'secret-host-value';
      final failed = Completer<LayerException>();
      await tester.pumpWidget(
        appWith(
          MapigradeLayer(
            styleUrl: 'http://127.0.0.1:1/style.json',
            httpHeaders: [
              HttpHeaderRule(url: '**', headers: {'Host': secret}),
            ],
            onError: (e) {
              if (!failed.isCompleted) failed.complete(e);
            },
          ),
        ),
      );
      final exception = await failed.future.timeout(
        const Duration(seconds: 20),
      );
      expect(exception, isA<LayerCreateException>());
      expect(exception.message, contains('Host'));
      expect(exception.message, isNot(contains(secret)));
      expect(exception.toString(), isNot(contains(secret)));
    });
  });

  group('Flutter assets', () {
    /// The RGB color at ([x], [y]) of the image of [boundaryKey].
    Future<List<int>> pixelAt(GlobalKey boundaryKey, double x, double y) async {
      final boundary =
          boundaryKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      final offset = (y.round() * image.width + x.round()) * 4;
      return [for (var c = 0; c < 3; c++) bytes.getUint8(offset + c)];
    }

    /// Places the layer with [styleUrl], and waits until the pixel at
    /// ([x], [y]) has [color].
    Future<void> expectColor(
      WidgetTester tester,
      String styleUrl,
      double x,
      double y,
      List<int> color,
    ) async {
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        appWith(
          MapigradeLayer(
            styleUrl: styleUrl,
            onError: (e) => fail('unexpected failure $e'),
          ),
          boundaryKey: boundaryKey,
        ),
      );
      final deadline = DateTime.now().add(const Duration(seconds: 20));
      var pixel = await pixelAt(boundaryKey, x, y);
      while (!listEquals(pixel, color)) {
        if (DateTime.now().isAfter(deadline)) {
          fail('the pixel at ($x, $y) is $pixel, not $color');
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
        pixel = await pixelAt(boundaryKey, x, y);
      }
    }

    testWidgets('a style from an asset renders', (tester) async {
      // A corner of the 400x300 map, outside the square of area.pmtiles.
      await expectColor(
        tester,
        'asset://assets/style.json',
        2,
        2,
        backgroundColor,
      );
    });

    testWidgets('PMTiles from an asset render', (tester) async {
      // The center of the map is the center of the square.
      await expectColor(
        tester,
        'asset://assets/style.json',
        200,
        150,
        areaColor,
      );
    });

    testWidgets('glyphs that fail to load report a load failure', (
      tester,
    ) async {
      // Answers every glyph request with 404.
      final server = await LoopbackServer.start({});
      addTearDown(server.close);
      final failed = Completer<LayerException>();
      await tester.pumpWidget(
        appWith(
          MapigradeLayer(
            styleJson: jsonEncode({
              'version': 8,
              'glyphs': server.url('/fonts/{fontstack}/{range}.glyphs'),
              'sources': {
                'area': {
                  'type': 'vector',
                  'url': 'pmtiles://asset://assets/area.pmtiles',
                },
              },
              'layers': [
                {
                  'id': 'label',
                  'type': 'symbol',
                  'source': 'area',
                  'source-layer': 'area',
                  'layout': {
                    'text-field': 'A',
                    'text-font': ['Missing Font'],
                  },
                },
              ],
            }),
            onError: (e) {
              if (!failed.isCompleted) failed.complete(e);
            },
          ),
        ),
      );
      final exception = await failed.future.timeout(
        const Duration(seconds: 20),
      );
      expect(exception, isA<LayerLoadException>());
      expect(exception.message, contains('glyph'));
      expect(exception.message, contains('Missing Font'));
      expect(
        server.requests.map((r) => r.path),
        contains(startsWith('/fonts/')),
      );
    });

    testWidgets('a missing asset reports a load failure', (tester) async {
      final failed = Completer<LayerException>();
      await tester.pumpWidget(
        appWith(
          MapigradeLayer(
            styleUrl: 'asset://assets/missing.json',
            onError: (e) {
              if (!failed.isCompleted) failed.complete(e);
            },
          ),
        ),
      );
      final exception = await failed.future.timeout(
        const Duration(seconds: 20),
      );
      expect(exception, isA<LayerLoadException>());
    });
  });
}
