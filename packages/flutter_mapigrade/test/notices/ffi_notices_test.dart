// Checks that the notice files in notices/ equal the notices of the MapLibre
// Native FFI presets installed in third_party/ (design D96 of the
// third-party-notices change, second item). Only presets built at the commit in
// scripts/maplibre_ffi.lock are compared. The test is skipped when no such
// preset is installed, for example in a checkout without the FFI build.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const repositoryRoot = '../..';
final ffiDirectory = p.join(
  repositoryRoot,
  'third_party',
  'maplibre-native-ffi',
);

/// The presets installed at the commit in `scripts/maplibre_ffi.lock`.
List<String> pinnedPresets() {
  final lock = File(p.join(repositoryRoot, 'scripts', 'maplibre_ffi.lock'))
      .readAsStringSync();
  final commit = RegExp(
    r'^MAPLIBRE_FFI_COMMIT=(\S+)$',
    multiLine: true,
  ).firstMatch(lock)![1];
  final directory = Directory(ffiDirectory);
  if (!directory.existsSync()) return [];
  return [
    for (final entry in directory.listSync().whereType<Directory>())
      if (File(p.join(entry.path, 'BUILD_INFO')).existsSync() &&
          File(p.join(entry.path, 'BUILD_INFO')).readAsStringSync().trim() ==
              '$commit ${p.basename(entry.path)}')
        p.basename(entry.path),
  ]..sort();
}

/// The package's copy of a preset's notice file, or null if the package has
/// none. [file] is relative to `share/maplibre-native-c/`.
String? packageCopy(String preset, String file) {
  if (file == 'LICENSE') return 'notices/common/maplibre-native-ffi.txt';
  final name = p.basename(file);
  final candidates = [
    'notices/common/$name',
    if (preset.startsWith('android-')) 'notices/android/$name',
  ];
  return candidates.where((path) => File(path).existsSync()).firstOrNull;
}

void main() {
  final presets = pinnedPresets();

  test(
    'the notice files equal the notices of the installed FFI presets',
    () {
      final problems = <String>[];
      for (final preset in presets) {
        final share = p.join(
          ffiDirectory,
          preset,
          'share',
          'maplibre-native-c',
        );
        final licenses = Directory(p.join(share, 'licenses'));
        final files = [
          'LICENSE',
          if (licenses.existsSync())
            for (final file in licenses.listSync().whereType<File>())
              p.posix.join('licenses', p.basename(file.path)),
        ]..sort();
        for (final file in files) {
          final source = '$preset/share/maplibre-native-c/$file';
          final copy = packageCopy(preset, file);
          if (copy == null) {
            problems.add('$source has no copy in notices/');
          } else if (!_equalBytes(
            File(p.join(share, file)).readAsBytesSync(),
            File(copy).readAsBytesSync(),
          )) {
            problems.add('$copy differs from $source');
          }
        }
      }
      expect(
        problems,
        isEmpty,
        reason: 'Run scripts/copy_ffi_notices.sh ${presets.join(' ')}',
      );
    },
    skip: presets.isEmpty
        ? 'no MapLibre Native FFI preset is installed at the pinned commit'
        : null,
  );
}

bool _equalBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
