// Checks that the notice files in notices/ equal the notices of the MapLibre
// Native FFI release in maplibre_ffi.lock (design D96 of the
// third-party-notices change, second item, and D108 of the publish-readiness
// change). The test reads the tarballs of the presets in the lock file that
// scripts/fetch_ffi_release.sh downloads into
// third_party/maplibre-native-ffi-release/<version>/, and is skipped when none
// of them is there, for example in a checkout without the fetched release.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const repositoryRoot = '../..';

/// The value of [key] in `maplibre_ffi.lock`, without quotes.
String lockValue(String lock, String key) =>
    RegExp('^$key="?([^"\\n]*)"?\$', multiLine: true).firstMatch(lock)![1]!;

/// The fetched tarballs of the presets in the lock file, by preset.
Map<String, File> fetchedTarballs() {
  final lock = File('maplibre_ffi.lock').readAsStringSync();
  final version = lockValue(lock, 'MAPLIBRE_FFI_VERSION');
  final presets = [
    ...lockValue(lock, 'MAPLIBRE_FFI_PRESETS').split(' '),
    ...lockValue(lock, 'MAPLIBRE_FFI_ANDROID_PRESETS').split(' '),
  ].where((preset) => preset.isNotEmpty);
  return {
    for (final preset in presets)
      preset: File(
        p.join(
          repositoryRoot,
          'third_party',
          'maplibre-native-ffi-release',
          version,
          'maplibre-native-c-$preset.tar.gz',
        ),
      ),
  }..removeWhere((_, tarball) => !tarball.existsSync());
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
  final tarballs = fetchedTarballs();

  test(
    'the notice files equal the notices of the fetched FFI release',
    () {
      final extracted = Directory.systemTemp.createTempSync('ffi-notices');
      addTearDown(() => extracted.deleteSync(recursive: true));
      final problems = <String>[];
      for (final MapEntry(key: preset, value: tarball) in tarballs.entries) {
        final share = 'maplibre-native-c-$preset/share/maplibre-native-c';
        final result = Process.runSync('tar', [
          '-xzf',
          tarball.path,
          '-C',
          extracted.path,
          share,
        ]);
        expect(result.exitCode, 0, reason: '${result.stderr}');
        final shareDirectory = p.join(extracted.path, share);
        final licenses = Directory(p.join(shareDirectory, 'licenses'));
        final files = [
          'LICENSE',
          if (licenses.existsSync())
            for (final file in licenses.listSync().whereType<File>())
              p.posix.join('licenses', p.basename(file.path)),
        ]..sort();
        for (final file in files) {
          final source = '${p.basename(tarball.path)}: $share/$file';
          final copy = packageCopy(preset, file);
          if (copy == null) {
            problems.add('$source has no copy in notices/');
          } else if (!_equalBytes(
            File(p.join(shareDirectory, file)).readAsBytesSync(),
            File(copy).readAsBytesSync(),
          )) {
            problems.add('$copy differs from $source');
          }
        }
      }
      expect(problems, isEmpty, reason: 'Run scripts/copy_ffi_notices.sh');
    },
    skip: tarballs.isEmpty
        ? 'no tarball of the MapLibre Native FFI release is fetched; '
              'run scripts/fetch_ffi_release.sh'
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
