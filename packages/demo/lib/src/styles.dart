import 'package:flutter_map/flutter_map.dart';
import 'package:url_launcher/url_launcher.dart';

/// A style that needs no API key, with the attribution it requires.
class DemoStyle {
  const DemoStyle(this.name, this.url, this.attributions);

  final String name;
  final String url;

  /// The style's own entries, as text and link. The OpenStreetMap entry,
  /// which the routes also need, follows them for every style.
  final List<(String, String)> attributions;
}

const _openFreeMap = [
  ('OpenFreeMap', 'https://openfreemap.org'),
  ('© OpenMapTiles', 'https://www.openmaptiles.org'),
];

const demoStyles = [
  DemoStyle(
    'Liberty',
    'https://tiles.openfreemap.org/styles/liberty',
    _openFreeMap,
  ),
  DemoStyle(
    'Bright',
    'https://tiles.openfreemap.org/styles/bright',
    _openFreeMap,
  ),
  DemoStyle(
    'Positron',
    'https://tiles.openfreemap.org/styles/positron',
    _openFreeMap,
  ),
  DemoStyle(
    'MapLibre demo tiles',
    'https://demotiles.maplibre.org/style.json',
    [('MapLibre', 'https://maplibre.org')],
  ),
];

/// The attribution of [style] and of the routes (design D120).
RichAttributionWidget attributionOf(DemoStyle style) => RichAttributionWidget(
  popupInitialDisplayDuration: const Duration(seconds: 5),
  attributions: [
    for (final (text, url) in [
      ...style.attributions,
      (
        '© OpenStreetMap contributors',
        'https://www.openstreetmap.org/copyright',
      ),
    ])
      TextSourceAttribution(text, onTap: () => launchUrl(Uri.parse(url))),
  ],
);
