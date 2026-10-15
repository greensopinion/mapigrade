import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'stages.dart';

/// Magenta with a white border: it contrasts with all four styles.
const _routeColor = Color(0xffd6007e);
const _startColor = Color(0xff1b8a3a);
const _finishColor = Color(0xffd32f2f);

const _pinSize = 40.0;
const _bubbleWidth = 260.0;

/// The room above the start pin; the bubble sizes to its text within it.
const _bubbleHeight = 150.0;

/// The routes, and the start and finish pins with the stage bubbles, of
/// [stages] (design D117).
List<Widget> stageLayers(List<Stage> stages) => [
  PolylineLayer(
    polylines: [
      for (final stage in stages)
        Polyline(
          points: stage.route,
          color: _routeColor,
          strokeWidth: 4,
          borderColor: Colors.white,
          borderStrokeWidth: 2,
        ),
    ],
  ),
  MarkerLayer(
    markers: [
      for (final stage in stages) ...[
        if (!stage.isLoop)
          Marker(
            point: stage.finishPoint,
            width: _pinSize,
            height: _pinSize,
            alignment: Alignment.topCenter,
            rotate: true,
            child: const _Pin(colors: [_finishColor]),
          ),
        // The bubble is part of the start pin's marker, so that the two move
        // together and stay upright.
        Marker(
          point: stage.startPoint,
          width: _bubbleWidth,
          height: _bubbleHeight + _pinSize,
          alignment: Alignment.topCenter,
          rotate: true,
          // The pin at the bottom, so that its tip is on the coordinate.
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _Bubble(stage),
              _Pin(
                colors: stage.isLoop
                    ? const [_startColor, _finishColor]
                    : const [_startColor],
              ),
            ],
          ),
        ),
      ],
    ],
  ),
];

/// A pin whose tip is at the bottom center. With two colors, the left half
/// has the first and the right half the second.
class _Pin extends StatelessWidget {
  const _Pin({required this.colors});

  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    const icon = Icon(Icons.location_on, size: _pinSize, color: Colors.white);
    if (colors.length == 1) {
      return Icon(Icons.location_on, size: _pinSize, color: colors.single);
    }
    return ShaderMask(
      shaderCallback: (bounds) => LinearGradient(
        colors: [colors[0], colors[0], colors[1], colors[1]],
        stops: const [0, 0.5, 0.5, 1],
      ).createShader(bounds),
      child: icon,
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble(this.stage);

  final Stage stage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final route = stage.isLoop
        ? 'Starts and finishes in ${stage.start}'
        : '${stage.start} – ${stage.finish}';
    return Container(
      width: _bubbleWidth,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black26)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // The race, so that "Stage 9" means something on its own.
          Text(
            raceName,
            style: theme.labelSmall,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          Text('Stage ${stage.number}', style: theme.titleSmall),
          Text(route, maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(
            '${_km(stage.distanceKm)} km · ${stage.type}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            'Winner: ${stage.winner}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// 21.0 as "21", 146.8 as "146.8".
String _km(double km) =>
    km == km.roundToDouble() ? km.round().toString() : km.toString();

/// The leader's yellow, with a black border: it stands out on the route's
/// magenta and on all four styles.
const _riderColor = Color(0xffffd400);
const _riderSize = 34.0;

/// The rider on the route while the flyover follows it; nothing otherwise.
/// Only this layer rebuilds when the rider moves.
Widget riderLayer(ValueListenable<LatLng?> rider) => ValueListenableBuilder(
  valueListenable: rider,
  builder: (context, point, _) => point == null
      ? const SizedBox.shrink()
      : MarkerLayer(
          markers: [
            Marker(
              point: point,
              width: _riderSize,
              height: _riderSize,
              // Upright on screen: the flyover turns the map so that the
              // rider's direction points up.
              rotate: true,
              child: Semantics(
                label: 'Rider',
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    color: _riderColor,
                    shape: BoxShape.circle,
                    border: Border.fromBorderSide(
                      BorderSide(color: Colors.black, width: 2),
                    ),
                    boxShadow: [
                      BoxShadow(blurRadius: 4, color: Colors.black38),
                    ],
                  ),
                  child: Icon(
                    Icons.directions_bike,
                    size: 20,
                    color: Colors.black,
                  ),
                ),
              ),
            ),
          ],
        ),
);
