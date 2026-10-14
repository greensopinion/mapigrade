#!/bin/sh
# Builds assets/area.pmtiles for integration_test/resource_test.dart: a vector
# tileset with one layer, `area`, that holds one square around 51.5 N,
# 0.12 W, from about 0.14 W to 0.10 W and 51.487 N to 51.513 N. Needs GDAL's
# ogr2ogr and the pmtiles CLI.
#
#   sh packages/test_harness/tool/make_test_tiles.sh
set -e
cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cat > "$work/area.geojson" <<'EOF'
{"type": "FeatureCollection", "features": [{"type": "Feature",
  "properties": {},
  "geometry": {"type": "Polygon", "coordinates": [[
    [-0.14, 51.487], [-0.10, 51.487], [-0.10, 51.513], [-0.14, 51.513],
    [-0.14, 51.487]]]}}]}
EOF
ogr2ogr -f MBTiles "$work/area.mbtiles" "$work/area.geojson" -nln area \
  -dsco MINZOOM=0 -dsco MAXZOOM=10
pmtiles convert "$work/area.mbtiles" assets/area.pmtiles
