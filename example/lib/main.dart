import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_mapigrade/flutter_mapigrade.dart';

import 'alignment_benchmark.dart';
import 'benchmark.dart';
import 'flutter_map_page.dart';
import 'timing_probe.dart';

/// Prints every displayed frame with its camera:
/// `--dart-define=LOG_FRAMES=true`.
const logFrames = bool.fromEnvironment('LOG_FRAMES');

/// Starts continuous pan at launch, for scripted device tests:
/// `--dart-define=CONTINUOUS_PAN=true`.
const continuousPanAtLaunch = bool.fromEnvironment('CONTINUOUS_PAN');

class MapStyle {
  const MapStyle(this.name, this.url);
  final String name;
  final String url;
}

const styles = [
  MapStyle('OpenFreeMap Liberty', 'https://tiles.openfreemap.org/styles/liberty'),
  MapStyle('MapLibre demo tiles', 'https://demotiles.maplibre.org/style.json'),
  MapStyle('Invalid URL', 'https://invalid.example.invalid/style.json'),
];

void main() => runApp(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: alignmentBenchmarkEnabled
          ? const AlignmentBenchmarkPage()
          : flutterMapPageAtLaunch
              ? FlutterMapPage(styleUrl: styles.first.url)
              : const MapScreen(),
    ));

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  MapTextureController? _controller;
  final _subscriptions = <StreamSubscription<Object>>[];
  late final Ticker _panTicker = createTicker(_onPanTick);

  MapCamera _camera =
      const MapCamera(latitude: 37.7749, longitude: -122.4194, zoom: 12);
  int _styleIndex = 0;
  String _status = 'loading style';
  String? _error;
  FrameCamera? _frame;
  int _framesInLastSecond = 0;
  int _mapFps = 0;
  Timer? _fpsTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  // The plugin handles memory warnings natively; this prints the map's stats
  // afterwards, so the reduction shows in the log.
  @override
  void didHaveMemoryPressure() {
    Timer(const Duration(milliseconds: 500), () {
      final controller = _controller;
      if (controller == null || controller.isDisposed) return;
      debugPrint('memory pressure: ${controller.stats()}');
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    // Before the window's metrics arrive (on Android), the size is empty and
    // the device pixel ratio is 1; the map's ratio is fixed at creation.
    if (MediaQuery.sizeOf(context).isEmpty) return;
    final controller = MapTextureController.create(
        pixelRatio: MediaQuery.devicePixelRatioOf(context),
        copyFree: copyFree);
    _subscriptions.add(controller.events.listen(_onEvent));
    _subscriptions.add(controller.frames.listen(_onFrame));
    if (benchmarkEnabled || timingProbeEnabled) _camera = start;
    controller.loadStyleUrl(styles[_styleIndex].url);
    controller.setCamera(_camera);
    _controller = controller;
    if (continuousPanAtLaunch && !benchmarkEnabled) _panTicker.start();
    if (benchmarkEnabled) {
      Benchmark(controller, onCamera: (camera) {
        _camera = camera;
        controller.setCamera(camera);
      }).run();
    }
    if (timingProbeEnabled) {
      TimingProbe(controller, onCamera: (camera) {
        _camera = camera;
        controller.setCamera(camera);
      }).run();
    }
    _fpsTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {
        _mapFps = _framesInLastSecond;
        _framesInLastSecond = 0;
      });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _panTicker.dispose();
    _fpsTimer?.cancel();
    for (final s in _subscriptions) {
      s.cancel();
    }
    _controller?.dispose();
    super.dispose();
  }

  void _onEvent(MapEvent event) {
    debugPrint('map event: $event');
    setState(() {
      switch (event) {
        case StyleLoaded():
          _status = 'style loaded';
          _error = null;
        case LoadingFailed(:final message):
          _status = 'loading failed';
          _error = message;
        case RenderError(:final message):
          _error = message;
        case MapIdle():
          _status = 'idle';
      }
    });
  }

  void _onFrame(FrameCamera frame) {
    if (logFrames) debugPrint('frame displayed: $frame');
    // On standard output, which reaches the console in release builds too
    // (for example through devicectl --console), unlike debugPrint on iOS.
    if (frame.physicalSize != _frame?.physicalSize) {
      stdout.writeln('frame size: ${frame.physicalSize.width.toInt()}x'
          '${frame.physicalSize.height.toInt()} @${frame.scaleFactor}');
    }
    _framesInLastSecond++;
    _frame = frame;
  }

  void _setCamera(MapCamera camera) {
    _camera = camera;
    _controller?.setCamera(camera);
    setState(() {});
  }

  void _zoom(double delta) => _setCamera(MapCamera(
      latitude: _camera.latitude,
      longitude: _camera.longitude,
      zoom: (_camera.zoom + delta).clamp(0, 22),
      bearing: _camera.bearing));

  void _rotate(double delta) => _setCamera(MapCamera(
      latitude: _camera.latitude,
      longitude: _camera.longitude,
      zoom: _camera.zoom,
      bearing: (_camera.bearing + delta) % 360));

  /// Pans by a fraction of the viewport in screen directions.
  void _pan(double dx, double dy) {
    final degreesPerViewport = 360 / math.pow(2, _camera.zoom);
    final b = _camera.bearing * math.pi / 180;
    final east = dx * math.cos(b) + dy * math.sin(b);
    final north = -(-dx * math.sin(b) + dy * math.cos(b));
    _setCamera(MapCamera(
        latitude: (_camera.latitude + north * degreesPerViewport * 0.5)
            .clamp(-85, 85),
        longitude: _camera.longitude + east * degreesPerViewport,
        zoom: _camera.zoom,
        bearing: _camera.bearing));
  }

  Duration? _lastTick;

  /// Changes the camera on every Flutter frame.
  void _onPanTick(Duration elapsed) {
    final dt = _lastTick == null ? 0.0 : (elapsed - _lastTick!).inMicroseconds / 1e6;
    _lastTick = elapsed;
    final degreesPerSecond = 0.2 * 360 / math.pow(2, _camera.zoom);
    _camera = MapCamera(
        latitude: _camera.latitude,
        longitude: _camera.longitude + degreesPerSecond * dt,
        zoom: _camera.zoom,
        bearing: _camera.bearing);
    _controller?.setCamera(_camera);
  }

  void _toggleContinuousPan(bool on) {
    setState(() {
      if (on) {
        _lastTick = null;
        _panTicker.start();
      } else {
        _panTicker.stop();
      }
    });
  }

  void _selectStyle(int index) {
    setState(() {
      _styleIndex = index;
      _status = 'loading style';
      _error = null;
    });
    _controller?.loadStyleUrl(styles[index].url);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(children: [
        if (_controller case final controller?)
          Positioned.fill(child: MapTextureView(controller: controller)),
        // SafeArea keeps the panel clear of the iPhone status bar and
        // Dynamic Island; on macOS the insets are zero.
        Positioned(
          top: 12,
          left: 12,
          child: SafeArea(child: _buildPanel(context)),
        ),
      ]),
    );
  }

  Widget _buildPanel(BuildContext context) {
    final frame = _frame;
    return Card(
      key: const Key('control-panel'),
      color: Colors.white.withValues(alpha: 0.9),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          width: 280,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButton<int>(
                key: const Key('style-select'),
                value: _styleIndex,
                isExpanded: true,
                items: [
                  for (var i = 0; i < styles.length; i++)
                    DropdownMenuItem(value: i, child: Text(styles[i].name)),
                ],
                onChanged: (i) => _selectStyle(i!),
              ),
              Wrap(spacing: 4, children: [
                _button('zoom-in', Icons.add, () => _zoom(1)),
                _button('zoom-out', Icons.remove, () => _zoom(-1)),
                _button('rotate-left', Icons.rotate_left, () => _rotate(-15)),
                _button('rotate-right', Icons.rotate_right, () => _rotate(15)),
                _button('open-flutter-map', Icons.layers, _openFlutterMapPage),
              ]),
              Wrap(spacing: 4, children: [
                _button('pan-west', Icons.arrow_back, () => _pan(-0.25, 0)),
                _button('pan-north', Icons.arrow_upward, () => _pan(0, -0.25)),
                _button('pan-south', Icons.arrow_downward, () => _pan(0, 0.25)),
                _button('pan-east', Icons.arrow_forward, () => _pan(0.25, 0)),
              ]),
              SwitchListTile(
                key: const Key('continuous-pan'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Continuous pan'),
                value: _panTicker.isActive,
                onChanged: _toggleContinuousPan,
              ),
              Text('Status: $_status', key: const Key('status')),
              if (_error != null)
                Text('Error: $_error',
                    key: const Key('error'),
                    style: const TextStyle(color: Colors.red)),
              Text('Requested: ${_fmt(_camera)}'),
              Text(frame == null
                  ? 'Displayed: -'
                  : 'Displayed #${frame.frameId}: ${_fmt(frame.camera)}'),
              Text('Map frames/s: $_mapFps'),
            ],
          ),
        ),
      ),
    );
  }

  void _openFlutterMapPage() => Navigator.push(
      context,
      MaterialPageRoute<void>(
          builder: (_) => FlutterMapPage(styleUrl: styles[_styleIndex].url)));

  Widget _button(String key, IconData icon, VoidCallback onPressed) =>
      IconButton.filledTonal(
          key: Key(key), icon: Icon(icon), onPressed: onPressed);

  static String _fmt(MapCamera c) =>
      '${c.latitude.toStringAsFixed(4)}, ${c.longitude.toStringAsFixed(4)} '
      'z${c.zoom.toStringAsFixed(2)} b${c.bearing.toStringAsFixed(0)}';
}
