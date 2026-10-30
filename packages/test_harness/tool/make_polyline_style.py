#!/usr/bin/env python3
"""Builds the style assets of integration_test/polyline_layer_test.dart:
assets/polyline_style.json and assets/polyline_style_dark.json, and the glyph
file assets/fonts/Test/0-255.pbf, in which every printable ASCII character is
a solid block, so that the tests need no network access or font.

The features are placed by screen position for a 360x280 map centered on
latitude 0, longitude 0 at flutter_map zoom 12: the road is a west-east line
through the center, the bridge crosses it north to south at x = 100, a 3D
building is beside the road at the right edge, and a boundary line, the last
layer that isn't a symbol layer, is along the bottom right.

    python3 packages/test_harness/tool/make_polyline_style.py
"""
import json
import math
import os
import struct

root = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'assets')

WIDTH, HEIGHT, ZOOM = 360, 280, 12
WORLD = 256 * 2**ZOOM


def lonlat(x, y):
    lon = (x - WIDTH / 2) / WORLD * 360
    lat = math.degrees(math.atan(math.sinh(-2 * math.pi * (y - HEIGHT / 2) / WORLD)))
    return [lon, lat]


def feature(geometry_type, coordinates):
    return {'type': 'Feature', 'properties': {},
            'geometry': {'type': geometry_type, 'coordinates': coordinates}}


def source(*features):
    return {'type': 'geojson',
            'data': {'type': 'FeatureCollection', 'features': list(features)}}


def label(layer_id, source_id, text, size, color):
    return {
        'id': layer_id, 'type': 'symbol', 'source': source_id,
        'layout': {'text-field': text, 'text-font': ['Test'],
                   'text-size': size, 'text-offset': [0, size * 1.1 / 16],
                   'text-allow-overlap': True,
                   'text-ignore-placement': True},
        'paint': {'text-color': color},
    }


def style(dark):
    c = (lambda light, dark_: dark_ if dark else light)
    return {
        'version': 8,
        'glyphs': 'asset://assets/fonts/{fontstack}/{range}.pbf',
        'sources': {
            'water': source(feature('Polygon', [[
                lonlat(270, 10), lonlat(350, 10), lonlat(350, 100),
                lonlat(270, 100), lonlat(270, 10)]])),
            'road': source(feature('LineString', [[-1, 0], [1, 0]])),
            'arrow': source(feature('Point', lonlat(250, 140))),
            'bridge': source(feature('LineString', [
                [lonlat(100, 0)[0], -1], [lonlat(100, 0)[0], 1]])),
            'building': source(feature('Polygon', [[
                lonlat(336, 112), lonlat(358, 112), lonlat(358, 126),
                lonlat(336, 126), lonlat(336, 112)]])),
            'boundary': source(feature('LineString', [
                lonlat(300, 275), lonlat(380, 275)])),
            'road_name': source(feature('Point', lonlat(180, 140))),
            'place': source(feature('Point', lonlat(240, 215))),
        },
        'layers': [
            {'id': 'background', 'type': 'background',
             'paint': {'background-color': c('#ffffff', '#14181c')}},
            {'id': 'water', 'type': 'fill', 'source': 'water',
             'paint': {'fill-color': c('#0000ff', '#1a237e'),
                       'fill-antialias': False}},
            {'id': 'road', 'type': 'line', 'source': 'road',
             'layout': {'line-cap': 'butt'},
             'paint': {'line-width': 24, 'line-color': c('#808080', '#505050')}},
            label('road_one_way_arrow', 'arrow', '>', 14, '#ffffff'),
            {'id': 'bridge', 'type': 'line', 'source': 'bridge',
             'layout': {'line-cap': 'butt'},
             'paint': {'line-width': 16, 'line-color': c('#00a0a0', '#006464')}},
            {'id': 'building_3d', 'type': 'fill-extrusion', 'source': 'building',
             'paint': {'fill-extrusion-color': c('#ff8000', '#a05000'),
                       'fill-extrusion-height': 20}},
            {'id': 'boundary', 'type': 'line', 'source': 'boundary',
             'layout': {'line-cap': 'butt'},
             'paint': {'line-width': 2, 'line-color': c('#a000a0', '#780078')}},
            label('road_label', 'road_name', 'ROAD', 16,
                  c('#000000', '#ffffff')),
            label('place_label', 'place', 'CITY', 16, c('#000000', '#ffffff')),
        ],
    }


def varint(n):
    out = bytearray()
    while True:
        b = n & 0x7F
        n >>= 7
        if n:
            out.append(b | 0x80)
        else:
            out.append(b)
            return bytes(out)


def field(number, wire, payload):
    tag = varint(number << 3 | wire)
    return tag + (varint(len(payload)) + payload if wire == 2 else payload)


def zigzag(n):
    return varint((n << 1) ^ (n >> 63))


def glyph(code):
    ink, buffer = 20, 3
    if code == 32:
        return field(1, 0, varint(code)) + field(3, 0, varint(0)) + \
            field(4, 0, varint(0)) + field(5, 0, zigzag(0)) + \
            field(6, 0, zigzag(0)) + field(7, 0, varint(12))
    size = ink + 2 * buffer
    bitmap = bytearray()
    for y in range(size):
        for x in range(size):
            dx = max(buffer - (x + 0.5), 0, (x + 0.5) - (buffer + ink))
            dy = max(buffer - (y + 0.5), 0, (y + 0.5) - (buffer + ink))
            outside = math.hypot(dx, dy)
            depth = min(x + 0.5 - buffer, buffer + ink - (x + 0.5),
                        y + 0.5 - buffer, buffer + ink - (y + 0.5))
            signed = outside if outside > 0 else -depth
            bitmap.append(max(0, min(255, round(255 * (0.75 - signed / 8)))))
    return (field(1, 0, varint(code)) + field(2, 2, bytes(bitmap)) +
            field(3, 0, varint(ink)) + field(4, 0, varint(ink)) +
            field(5, 0, zigzag(2)) + field(6, 0, zigzag(ink)) +
            field(7, 0, varint(24)))


def glyphs():
    stack = field(1, 2, b'Test') + field(2, 2, b'0-255')
    for code in range(32, 127):
        stack += field(3, 2, glyph(code))
    return field(1, 2, stack)


for name, dark in [('polyline_style.json', False),
                   ('polyline_style_dark.json', True)]:
    with open(os.path.join(root, name), 'w') as f:
        json.dump(style(dark), f, indent=2)
        f.write('\n')
os.makedirs(os.path.join(root, 'fonts', 'Test'), exist_ok=True)
with open(os.path.join(root, 'fonts', 'Test', '0-255.pbf'), 'wb') as f:
    f.write(glyphs())
