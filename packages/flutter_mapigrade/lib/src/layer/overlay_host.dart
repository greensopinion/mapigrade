import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../texture/map_texture_controller.dart';
import 'layer_exception.dart';
import 'layer_placement.dart';

/// Keeps the overlays of the widgets below a `MapTextureLayer` and sends them
/// to its map: each overlay's latest sources, style layers, placement and
/// order key, from when the map exists. It never throws for a map that
/// doesn't exist or that is disposed; it gives failures of the map to
/// [report].
final class OverlayHost {
  /// A host that reports failures to [report].
  OverlayHost({required this.report});

  /// Called with each failure of an overlay command.
  final void Function(LayerException exception) report;

  MapTextureController? _controller;
  final _registrations = <int, OverlayRegistration>{};
  int _nextId = 1;
  int _nextSeq = 0;

  /// Registers an overlay whose widget is the child [childIndex] of the
  /// `MapTextureLayer`. Nothing is sent until the overlay has sources or
  /// style layers.
  OverlayRegistration register({required int childIndex}) {
    final registration = OverlayRegistration._(
      this,
      OverlayIds(_nextId++),
      _nextSeq++,
      childIndex,
    );
    _registrations[registration.id] = registration;
    return registration;
  }

  /// Sends every overlay to [controller] and sends later changes to it.
  void attach(MapTextureController controller) {
    _controller = controller;
    for (final registration in _registrations.values.toList()) {
      registration._flush();
    }
  }

  /// Stops sending to the map; call before the map is disposed.
  void detach() => _controller = null;
}

/// The IDs of an overlay's sources and layers in the map's style.
@immutable
final class OverlayIds {
  /// The IDs of the overlay [overlayId].
  const OverlayIds(this.overlayId);

  /// The ID of the overlay in the map.
  final int overlayId;

  /// The ID of the overlay's GeoJSON source [index].
  String sourceId(int index) => 'mapigrade-overlay-$overlayId-source-$index';

  /// The ID of the overlay's style layer [index].
  String layerId(int index) => 'mapigrade-overlay-$overlayId-$index';

  @override
  bool operator ==(Object other) =>
      other is OverlayIds && other.overlayId == overlayId;

  @override
  int get hashCode => overlayId.hashCode;
}

/// One overlay of an [OverlayHost]: GeoJSON sources at indexes, and style
/// layers that name them. The map draws the overlay once it has style layers
/// and every source they name, whatever the order of the calls.
final class OverlayRegistration {
  OverlayRegistration._(this._host, this.ids, this._seq, this._childIndex);

  final OverlayHost _host;
  final int _seq;

  /// The IDs of the overlay's sources and layers.
  final OverlayIds ids;

  /// The ID of the overlay in the map.
  int get id => ids.overlayId;

  int _childIndex;
  String? _layersJson;
  LayerPlacement _placement = const LayerPlacement.belowLabels();
  ({String json, LayerPlacement placement, int childIndex})? _sentLayers;

  final _sources = <int, _OverlaySource>{};
  bool _removed = false;

  /// Sets the source [index] to the bytes that [encode] returns, with line
  /// metrics when [lineMetrics]. The newest [encode] replaces an older one
  /// that wasn't called yet, which is the case while the map doesn't exist
  /// or while an earlier call for the source is still running. With
  /// [inBackground], [encode] and the native call run on a background
  /// isolate, so [encode] must be sendable to one.
  void setSource(
    int index,
    Uint8List Function() encode, {
    required bool lineMetrics,
    bool inBackground = false,
  }) {
    if (_removed) return;
    final source = _sources.putIfAbsent(index, () => _OverlaySource(index));
    source.lineMetrics = lineMetrics;
    source.pendingEncode = encode;
    source.pendingInBackground = inBackground;
    _flushSource(source);
  }

  /// Removes the source [index] from the map, after a call for it that is
  /// still running. Nothing happens for an index that was never set.
  void removeSource(int index) {
    final source = _sources.remove(index);
    if (source == null || _removed) return;
    source.pendingEncode = null;
    source.removed = true;
    if (!source.sending) _sendRemoveSource(source);
  }

  /// Sets the overlay's style layers, as a JSON array, and their placement.
  /// Does nothing when the map already has these.
  void setLayers(String layersJson, LayerPlacement placement) {
    if (_removed) return;
    _layersJson = layersJson;
    _placement = placement;
    _flushLayers();
  }

  /// Sets the index of the overlay's widget among the `MapTextureLayer`'s
  /// children, the first part of the overlay's order key.
  set childIndex(int value) {
    if (_removed || value == _childIndex) return;
    _childIndex = value;
    _flushLayers();
  }

  /// Removes the overlay from the map, after the calls for its sources that
  /// are still running.
  void remove() {
    if (_removed) return;
    _removed = true;
    for (final source in _sources.values) {
      source.pendingEncode = null;
    }
    _host._registrations.remove(id);
    if (!_sources.values.any((s) => s.sending)) _sendRemove();
  }

  void _flush() {
    for (final source in _sources.values) {
      _flushSource(source);
    }
    _flushLayers();
  }

  void _flushLayers() {
    final controller = _host._controller;
    final json = _layersJson;
    if (controller == null || json == null) return;
    final wanted = (json: json, placement: _placement, childIndex: _childIndex);
    if (wanted == _sentLayers) return;
    _sentLayers = wanted;
    _call('map_texture_overlay_set_layers', () {
      controller.setOverlayLayers(
        id,
        layersJson: json,
        placementKind: _placement.kind,
        belowLayerId: _placement.belowLayerId,
        orderChild: _childIndex,
        orderSeq: _seq,
      );
    });
  }

  void _flushSource(_OverlaySource source) {
    final controller = _host._controller;
    final encode = source.pendingEncode;
    if (controller == null || encode == null || source.sending) return;
    source.pendingEncode = null;
    source.sent = true;
    if (!source.pendingInBackground) {
      _call(
        'map_texture_overlay_set_source',
        () => controller.setOverlaySource(
          id,
          source.index,
          encode(),
          lineMetrics: source.lineMetrics,
        ),
      );
      return;
    }
    source.sending = true;
    _sendInBackground(controller, source, encode);
  }

  Future<void> _sendInBackground(
    MapTextureController controller,
    _OverlaySource source,
    Uint8List Function() encode,
  ) async {
    try {
      await controller.setOverlaySourceInBackground(
        id,
        source.index,
        encode,
        lineMetrics: source.lineMetrics,
      );
    } on MapTextureDisposedException {
      // The map is disposed, and the overlay with it.
    } on MapTextureException catch (e) {
      _reportFailure('map_texture_overlay_set_source', e);
    } finally {
      source.sending = false;
    }
    if (_removed) {
      if (!_sources.values.any((s) => s.sending)) _sendRemove();
    } else if (source.removed) {
      _sendRemoveSource(source);
    } else {
      _flushSource(source);
    }
  }

  void _sendRemoveSource(_OverlaySource source) {
    final controller = _host._controller;
    if (controller == null || !source.sent) return;
    _call(
      'map_texture_overlay_remove_source',
      () => controller.removeOverlaySource(id, source.index),
    );
  }

  void _sendRemove() {
    final controller = _host._controller;
    if (controller == null) return;
    _call('map_texture_overlay_remove', () => controller.removeOverlay(id));
  }

  void _call(String operation, void Function() call) {
    try {
      call();
    } on MapTextureDisposedException {
      // The map is disposed, and the overlay with it.
    } on MapTextureException catch (e) {
      _reportFailure(operation, e);
    }
  }

  void _reportFailure(String operation, MapTextureException e) => _host.report(
    LayerRenderException(
      '$operation (mapigrade-overlay-$id) failed: ${e.message}',
    ),
  );
}

/// One source of an [OverlayRegistration]: what to send next, and whether a
/// background call for it is running.
final class _OverlaySource {
  _OverlaySource(this.index);

  final int index;
  bool lineMetrics = false;
  Uint8List Function()? pendingEncode;
  bool pendingInBackground = false;
  bool sending = false;
  // Whether a call for the source was sent to the map, so that removing the
  // source has something to remove.
  bool sent = false;
  bool removed = false;
}

/// Provides the [OverlayHost] of the nearest `MapTextureLayer` to the widgets
/// below its children.
class OverlayHostScope extends InheritedWidget {
  /// Provides [host] to [child].
  const OverlayHostScope({super.key, required this.host, required super.child});

  /// The host.
  final OverlayHost host;

  /// The host of the nearest scope above [context], or null without one.
  static OverlayHost? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<OverlayHostScope>()?.host;

  @override
  bool updateShouldNotify(OverlayHostScope oldWidget) => host != oldWidget.host;
}

/// Gives the widgets below a child of a `MapTextureLayer` the child's index.
class OverlayChildIndex extends InheritedWidget {
  /// Wraps [child], which is the child [index] of the `MapTextureLayer`.
  const OverlayChildIndex({
    super.key,
    required this.index,
    required super.child,
  });

  /// The index of the child in `MapTextureLayer.children`.
  final int index;

  /// The index of the nearest child above [context], or 0 without one. With
  /// [listen], the element rebuilds when the index changes.
  static int of(BuildContext context, {bool listen = true}) {
    final widget = listen
        ? context.dependOnInheritedWidgetOfExactType<OverlayChildIndex>()
        : context.getInheritedWidgetOfExactType<OverlayChildIndex>();
    return widget?.index ?? 0;
  }

  @override
  bool updateShouldNotify(OverlayChildIndex oldWidget) =>
      index != oldWidget.index;
}
