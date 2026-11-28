import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:latlong2/latlong.dart';

import 'mapigrade_frame.dart';

/// How a marker aligns with the map, as MapLibre's `icon-pitch-alignment` and
/// `icon-rotation-alignment` define it.
enum MarkerAlignment {
  /// With the screen: upright, facing the screen, or with its top to the top
  /// of the screen.
  viewport,

  /// With the map: on the ground plane, or with its top to the map's north.
  map,
}

/// A widget that [MapigradeMarkers] places at a coordinate.
@immutable
final class MapigradeMarker {
  /// A marker that places the point [alignment] of [child] at [coordinate].
  const MapigradeMarker({
    this.key,
    required this.coordinate,
    required this.child,
    this.alignment = Alignment.center,
    this.pitchAlignment = MarkerAlignment.viewport,
    this.rotationAlignment = MarkerAlignment.viewport,
    this.scaleWithPerspective = false,
  });

  /// Identifies the marker's child among the markers, as a widget key does,
  /// so that its `State` follows it when the list changes.
  final Key? key;

  /// The coordinate the marker marks.
  final LatLng coordinate;

  /// The marker's widget, laid out at the size it chooses.
  final Widget child;

  /// The point of [child] that is placed at [coordinate].
  final Alignment alignment;

  /// [MarkerAlignment.viewport] draws [child] upright, and
  /// [MarkerAlignment.map] on the ground plane, where the frame's perspective
  /// shortens and shrinks it as it does the map.
  final MarkerAlignment pitchAlignment;

  /// [MarkerAlignment.viewport] points [child]'s top to the top of the
  /// screen, and [MarkerAlignment.map] to the map's north.
  final MarkerAlignment rotationAlignment;

  /// Whether an upright marker is scaled by the frame's perspective at its
  /// coordinate, by 1 at the camera's center. A marker on the ground plane is
  /// scaled by the perspective whatever this is.
  final bool scaleWithPerspective;
}

/// Places [markers] at their coordinates in every frame that the
/// `MapigradeMap` above it displays (design D242), without rebuilding their
/// children. Place it among the map's `children`.
///
/// Markers farther from the camera are drawn behind nearer ones, and markers
/// at the same distance in list order, later above. Each marker is drawn
/// once, in the copy of the world nearest the camera's center. A marker
/// behind the camera, beyond the ground that the frame draws, or outside the
/// map isn't drawn and receives no hit tests, and its child stays mounted.
/// Terrain doesn't hide markers.
final class MapigradeMarkers extends MultiChildRenderObjectWidget {
  /// Markers drawn above the map.
  MapigradeMarkers({super.key, required this.markers})
    : super(
        children: [
          for (final marker in markers)
            _MarkerData(key: marker.key, marker: marker, child: marker.child),
        ],
      );

  /// The markers, in list order.
  final List<MapigradeMarker> markers;

  @override
  RenderMapigradeMarkers createRenderObject(BuildContext context) {
    final listenable = MapigradeFrameScope.listenableOf(context);
    assert(listenable != null, 'MapigradeMarkers must be below a MapigradeMap');
    return RenderMapigradeMarkers(listenable);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderMapigradeMarkers renderObject,
  ) {
    renderObject.frames = MapigradeFrameScope.listenableOf(context);
  }
}

class _MarkerData extends ParentDataWidget<MarkerParentData> {
  const _MarkerData({super.key, required this.marker, required super.child});

  final MapigradeMarker marker;

  @override
  void applyParentData(RenderObject renderObject) {
    final data = renderObject.parentData! as MarkerParentData;
    if (identical(data.marker, marker)) return;
    data.marker = marker;
    renderObject.parent?.markNeedsPaint();
  }

  @override
  Type get debugTypicalAncestorWidgetClass => MapigradeMarkers;
}

/// The marker of a child of [RenderMapigradeMarkers].
class MarkerParentData extends ContainerBoxParentData<RenderBox> {
  /// The marker whose child this is.
  MapigradeMarker? marker;
}

/// Where a marker's child is drawn in a frame.
class _Placement {
  _Placement(this.child, this.transform, this.distance, this.index);

  final RenderBox child;
  final Matrix4 transform;
  // The clip w of the coordinate: larger is farther.
  final double distance;
  final int index;
}

/// The render object of [MapigradeMarkers].
class RenderMapigradeMarkers extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, MarkerParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, MarkerParentData> {
  /// Markers that follow the frames of [frames].
  RenderMapigradeMarkers(this._frames);

  ValueListenable<MapigradeFrame?>? _frames;
  MapigradeFrame? _placedFrame;
  List<_Placement>? _placements;

  /// The displayed frames that the markers follow.
  set frames(ValueListenable<MapigradeFrame?>? value) {
    if (identical(value, _frames)) return;
    if (attached) _frames?.removeListener(_onFrame);
    _frames = value;
    if (attached) _frames?.addListener(_onFrame);
    _onFrame();
  }

  void _onFrame() {
    _placements = null;
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _frames?.addListener(_onFrame);
  }

  @override
  void detach() {
    _frames?.removeListener(_onFrame);
    super.detach();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! MarkerParentData) {
      child.parentData = MarkerParentData();
    }
  }

  @override
  void markNeedsPaint() {
    _placements = null;
    super.markNeedsPaint();
  }

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  void performLayout() {
    final loose = BoxConstraints.loose(size);
    var child = firstChild;
    while (child != null) {
      child.layout(loose, parentUsesSize: true);
      child = childAfter(child);
    }
    _placements = null;
  }

  /// The children drawn in the current frame with their transforms, in paint
  /// order.
  List<_Placement> _place() {
    final frame = _frames?.value;
    if (_placements != null && identical(frame, _placedFrame)) {
      return _placements!;
    }
    _placedFrame = frame;
    final placements = <_Placement>[];
    if (frame != null) {
      final centerWorld = frame.centerWorld;
      final centerW = frame.clipOfWorld(centerWorld.dx, centerWorld.dy, 0).w;
      var index = 0;
      var child = firstChild;
      while (child != null) {
        final data = child.parentData! as MarkerParentData;
        final marker = data.marker;
        if (marker != null) {
          final placement = _placeMarker(frame, marker, child, centerW, index);
          if (placement != null) placements.add(placement);
        }
        index++;
        child = data.nextSibling;
      }
      placements.sort((a, b) {
        final byDistance = b.distance.compareTo(a.distance);
        return byDistance != 0 ? byDistance : a.index.compareTo(b.index);
      });
    }
    return _placements = placements;
  }

  _Placement? _placeMarker(
    MapigradeFrame frame,
    MapigradeMarker marker,
    RenderBox child,
    double centerW,
    int index,
  ) {
    final clip = frame.clipOf(marker.coordinate);
    if (!frame.withinDepth(clip)) return null;
    final anchor = marker.alignment.alongSize(child.size);
    final bearing = frame.camera.bearing! * math.pi / 180;
    final Matrix4 transform;
    if (marker.pitchAlignment == MarkerAlignment.map) {
      transform = _groundTransform(frame, marker, anchor, bearing);
    } else {
      final position = frame.positionOfClip(clip);
      final scale = marker.scaleWithPerspective ? centerW / clip.w : 1.0;
      transform = Matrix4.translationValues(position.dx, position.dy, 0);
      if (marker.rotationAlignment == MarkerAlignment.map) {
        transform.rotateZ(-bearing);
      }
      transform
        ..scaleByDouble(scale, scale, 1, 1)
        ..translateByDouble(-anchor.dx, -anchor.dy, 0, 1);
    }
    if (!_overlaps(transform, child.size)) return null;
    return _Placement(child, transform, clip.w, index);
  }

  // Maps the child's logical pixels to the ground at the marker's
  // coordinate: one pixel to the ground length of one logical pixel at the
  // camera's center, then the frame's matrix, then the viewport.
  Matrix4 _groundTransform(
    MapigradeFrame frame,
    MapigradeMarker marker,
    Offset anchor,
    double bearing,
  ) {
    final world = frame.clipOfWorldPoint(marker.coordinate);
    final unit = 1 / frame.worldSizeInPixels;
    // The world directions of the child's right and down: east and south, or
    // turned by the bearing to the screen's right and down.
    final turn = marker.rotationAlignment == MarkerAlignment.map
        ? 0.0
        : bearing;
    final rightX = math.cos(turn) * unit, rightY = math.sin(turn) * unit;
    final downX = -math.sin(turn) * unit, downY = math.cos(turn) * unit;
    // Matrix4's constructor takes the 16 values column by column.
    final basis = Matrix4(
      rightX,
      rightY,
      0,
      0, //
      downX,
      downY,
      0,
      0, //
      0,
      0,
      1,
      0, //
      world.dx - anchor.dx * rightX - anchor.dy * downX,
      world.dy - anchor.dx * rightY - anchor.dy * downY,
      0,
      1,
    );
    final w = frame.size.width, h = frame.size.height;
    final viewport = Matrix4(
      w / 2,
      0,
      0,
      0, //
      0,
      -h / 2,
      0,
      0, //
      0,
      0,
      1,
      0, //
      w / 2,
      h / 2,
      0,
      1,
    );
    return viewport
      ..multiply(Matrix4.fromFloat64List(frame.matrix))
      ..multiply(basis);
  }

  bool _overlaps(Matrix4 transform, Size childSize) {
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (final corner in [
      Offset.zero,
      Offset(childSize.width, 0),
      Offset(childSize.width, childSize.height),
      Offset(0, childSize.height),
    ]) {
      final m = transform.storage;
      final px = m[0] * corner.dx + m[4] * corner.dy + m[12];
      final py = m[1] * corner.dx + m[5] * corner.dy + m[13];
      final pw = m[3] * corner.dx + m[7] * corner.dy + m[15];
      // A corner behind the camera of a marker on the ground near the camera.
      if (!(pw > 0)) return true;
      final x = px / pw, y = py / pw;
      minX = math.min(minX, x);
      minY = math.min(minY, y);
      maxX = math.max(maxX, x);
      maxY = math.max(maxY, y);
    }
    return maxX > 0 && maxY > 0 && minX < size.width && minY < size.height;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    for (final placement in _place()) {
      context.pushTransform(
        needsCompositing,
        offset,
        placement.transform,
        placement.child.paint,
      );
    }
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    for (final placement in _place()) {
      if (identical(placement.child, child)) {
        transform.multiply(placement.transform);
        return;
      }
    }
    // A hidden child: nowhere on screen.
    transform.setZero();
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final placements = _place();
    for (var i = placements.length - 1; i >= 0; --i) {
      final placement = placements[i];
      final hit = result.addWithPaintTransform(
        transform: placement.transform,
        position: position,
        hitTest: (result, local) {
          if (!(Offset.zero & placement.child.size).contains(local)) {
            return false;
          }
          return placement.child.hitTest(result, position: local);
        },
      );
      if (hit) return true;
    }
    return false;
  }

  /// The children in paint order, for tests.
  @visibleForTesting
  List<RenderBox> get paintedChildren => [
    for (final placement in _place()) placement.child,
  ];
}
