import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_mapigrade/flutter_mapigrade.dart';
import 'package:latlong2/latlong.dart';

import '../common/panel.dart';
import '../common/style_picker.dart';
import '../common/styles.dart';
import 'flyover.dart';
import 'flyover_player.dart';
import 'metrics_panel.dart';
import 'recording.dart';
import 'stage_layers.dart';
import 'stages.dart';

/// The start of stage 9 in Nice.
const _initialCenter = LatLng(43.6975, 7.2700);
const _initialZoom = 12.0;

/// The center and zoom of the map's camera.
typedef _Position = ({LatLng center, double zoom});

/// The flyover showcase: `MapigradeLayer` as the base layer of a `FlutterMap`,
/// with the stage overlays, the attribution and the controls above it.
class FlyoverScreen extends StatefulWidget {
  const FlyoverScreen({super.key, this.recording});

  /// The recording mode, or null (design D144 of readme-demo-recording).
  final Recording? recording;

  @override
  State<FlyoverScreen> createState() => _FlyoverScreenState();
}

class _FlyoverScreenState extends State<FlyoverScreen>
    with SingleTickerProviderStateMixin {
  final _mapController = MapController();

  /// One metrics object for the life of the screen: the layer keeps its key,
  /// so a style change keeps its map (design D115).
  final _metrics = LayerMetrics();
  late final FlyoverPlayer _player;

  /// Updated on every camera change; only the readout listens, so a camera
  /// change doesn't rebuild the panel.
  final _position = ValueNotifier<_Position>((
    center: _initialCenter,
    zoom: _initialZoom,
  ));

  List<Stage>? _stages;
  DemoStyle _style = demoStyles.first;
  bool _showStages = true;
  bool _warmUp = false;

  late final _recording = widget.recording;
  late bool _settingsOpen = _recording == null;
  bool _styleLoaded = false;
  bool _recordingStarted = false;
  bool _readyWritten = false;

  @override
  void initState() {
    super.initState();
    _player = FlyoverPlayer(vsync: this, controller: _mapController)
      ..addListener(_onPlayerChanged);
    loadStages(rootBundle).then((stages) {
      if (!mounted) return;
      setState(() => _stages = stages);
      _startRecording();
    });
  }

  void _onPlayerChanged() {
    setState(() {});
    final recording = _recording;
    if (recording != null &&
        _player.phase == FlyoverPhase.waiting &&
        !_readyWritten) {
      _readyWritten = true;
      recording.ready(_metrics).then((_) {
        if (mounted) _player.start();
      });
    }
  }

  void _onStyleLoaded() {
    _styleLoaded = true;
    _startRecording();
  }

  /// In the recording mode, plays the warm-up pass and waits at the start
  /// once the style and the stages have loaded (design D145).
  void _startRecording() {
    final recording = _recording;
    final stages = _stages;
    if (recording == null || _recordingStarted) return;
    if (!_styleLoaded || stages == null) return;
    _recordingStarted = true;
    final camera = _mapController.camera;
    recording.log(
      'warm-up ${recording.warmUp.inSeconds} s, viewport '
      '${camera.nonRotatedSize.width.round()} x '
      '${camera.nonRotatedSize.height.round()}',
    );
    _player.play(
      Flyover.build(stages, camera),
      warmUp: recording.warmUp,
      waitAfterWarmUp: true,
    );
  }

  @override
  void dispose() {
    _player.dispose();
    _position.dispose();
    _mapController.dispose();
    super.dispose();
  }

  /// A touch or click on the map stops the flyover (design D119).
  void _onPointerDown(PointerDownEvent event, LatLng point) => _player.stop();

  /// Called on every camera change, by gestures and by the flyover.
  void _onPositionChanged(MapCamera camera, bool hasGesture) =>
      _position.value = (center: camera.center, zoom: camera.zoom);

  /// Any camera change that isn't the flyover's own stops it: scroll-wheel
  /// and trackpad zoom, keyboard input, and gestures without a pointer down.
  /// A resize doesn't: the flyover keeps the sequence it started with.
  void _onMapEvent(MapEvent event) {
    if (event.source != MapEventSource.mapController &&
        event.source != MapEventSource.nonRotatedSizeChange) {
      _player.stop();
    }
  }

  /// Shows a failure of the map. The layer can report one while it builds,
  /// so the snack bar is shown after the frame.
  void _showError(LayerException exception) {
    if (_recording != null) Recording.fail(exception.message);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(exception.message)));
    });
  }

  void _playOrStop() {
    final stages = _stages;
    if (_player.isActive || stages == null) {
      _player.stop();
    } else {
      final flyover = Flyover.build(stages, _mapController.camera);
      _player.play(flyover, warmUp: _warmUp ? flyover.duration : null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stages = _stages;
    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            // Method tear-offs compare equal, so these options are equal
            // from one build to the next and FlutterMap keeps them.
            options: MapOptions(
              initialCenter: _initialCenter,
              initialZoom: _initialZoom,
              maxPitch: MapOptions.pitchLimit,
              onPointerDown: _onPointerDown,
              onMapEvent: _onMapEvent,
              onPositionChanged: _onPositionChanged,
            ),
            children: [
              // The base layer: first among the children, so that the layers
              // after it are drawn above it. The route, the pins and the rider
              // are its children, so that they stay on the map while the
              // camera moves; the attribution is screen UI and follows it.
              MapigradeLayer(
                styleUrl: _style.url,
                onStyleLoaded: _onStyleLoaded,
                onError: _showError,
                metrics: _metrics,
                children: [
                  if (_showStages && stages != null) ...stageLayers(stages),
                  riderLayer(_player.rider),
                ],
              ),
              attributionOf(_style),
            ],
          ),
          _panel(context),
        ],
      ),
    );
  }

  Widget _panel(BuildContext context) {
    final theme = Theme.of(context);
    final player = _player;
    return DemoPanel(
      title: 'Mapigrade demo',
      actions: [
        IconButton(
          tooltip: player.isActive ? 'Stop flyover' : 'Play flyover',
          icon: Icon(player.isActive ? Icons.stop : Icons.play_arrow),
          onPressed: _stages == null ? null : _playOrStop,
        ),
        IconButton(
          tooltip: _settingsOpen ? 'Hide settings' : 'Show settings',
          icon: Icon(_settingsOpen ? Icons.expand_less : Icons.tune),
          onPressed: () => setState(() => _settingsOpen = !_settingsOpen),
        ),
      ],
      children: [
        if (player.isActive)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              switch (player.phase) {
                FlyoverPhase.warmingUp =>
                  'Warming up: loading tiles'
                      '${player.stage == null ? '' : ' (stage ${player.stage})'}',
                FlyoverPhase.waiting => 'Waiting to start',
                _ => 'Flyover: stage ${player.stage ?? ''}',
              },
              style: theme.textTheme.bodySmall!.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        _PositionReadout(_position),
        const SizedBox(height: 4),
        MetricsPanel(metrics: _metrics),
        if (_showStages)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Tour de France Femmes 2026 routes are approximate.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        if (_settingsOpen) ..._settings(theme),
      ],
    );
  }

  List<Widget> _settings(ThemeData theme) => [
    const Divider(),
    StylePicker(
      value: _style,
      onChanged: (style) => setState(() => _style = style),
    ),
    SwitchListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: const Text('Stage overlays'),
      value: _showStages,
      onChanged: (value) => setState(() => _showStages = value),
    ),
    CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: const Text('Warm-up pass before the flyover'),
      value: _warmUp,
      onChanged: _player.isActive
          ? null
          : (value) => setState(() => _warmUp = value!),
    ),
  ];
}

/// The map's center, in degrees to 5 decimals (about 1 m), and its zoom.
class _PositionReadout extends StatelessWidget {
  const _PositionReadout(this.position);

  final ValueListenable<_Position> position;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall!
        .copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    return ValueListenableBuilder(
      valueListenable: position,
      builder: (context, p, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Center: ${p.center.latitude.toStringAsFixed(5)}, '
            '${p.center.longitude.toStringAsFixed(5)}',
            style: style,
          ),
          Text('Zoom: ${p.zoom.toStringAsFixed(2)}', style: style),
        ],
      ),
    );
  }
}
