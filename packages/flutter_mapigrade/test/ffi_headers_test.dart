// Checks that android/src/main/cpp/ffi-include/ equals include/ of the
// android-arm64-egl tarball of the MapLibre Native FFI release in
// maplibre_ffi.lock (design D101 of the publish-readiness change). The test
// reads the tarball that scripts/fetch_ffi_release.sh downloads into
// third_party/maplibre-native-ffi-release/<version>/, and is skipped when it
// isn't there.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const repositoryRoot = '../..';
const committedHeaders = 'android/src/main/cpp/ffi-include';
const preset = 'android-arm64-egl';

/// The fetched tarball of [preset] for the version in the lock file.
File releaseTarball() {
  final lock = File('maplibre_ffi.lock').readAsStringSync();
  final version = RegExp(
    r'^MAPLIBRE_FFI_VERSION=(\S+)$',
    multiLine: true,
  ).firstMatch(lock)![1]!;
  return File(
    p.join(
      repositoryRoot,
      'third_party',
      'maplibre-native-ffi-release',
      version,
      'maplibre-native-c-$preset.tar.gz',
    ),
  );
}

/// The files under [directory], as paths relative to it.
Map<String, File> filesUnder(String directory) => {
  for (final file in Directory(
    directory,
  ).listSync(recursive: true).whereType<File>())
    p.relative(file.path, from: directory): file,
};

void main() {
  final tarball = releaseTarball();

  test(
    'ffi-include equals include/ of the release tarball',
    () {
      final extracted = Directory.systemTemp.createTempSync('ffi-headers');
      addTearDown(() => extracted.deleteSync(recursive: true));
      final result = Process.runSync('tar', [
        '-xzf',
        tarball.path,
        '-C',
        extracted.path,
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}');

      final release = filesUnder(
        p.join(extracted.path, 'maplibre-native-c-$preset', 'include'),
      );
      final committed = filesUnder(committedHeaders);
      final problems = <String>[
        for (final path in release.keys)
          if (!committed.containsKey(path))
            '$committedHeaders/$path is missing'
          else if (committed[path]!.readAsStringSync() !=
              release[path]!.readAsStringSync())
            '$committedHeaders/$path differs from the release',
        for (final path in committed.keys)
          if (!release.containsKey(path))
            '$committedHeaders/$path is not in the release',
      ]..sort();
      expect(
        problems,
        isEmpty,
        reason:
            'copy include/ of ${tarball.path} to $committedHeaders:\n'
            '${problems.join('\n')}',
      );
    },
    skip: tarball.existsSync()
        ? false
        : '${tarball.path} is not fetched; run scripts/fetch_ffi_release.sh',
  );
}
