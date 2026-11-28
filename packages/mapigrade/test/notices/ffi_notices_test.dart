// Checks that the notice files in notices/ equal the notices of the MapLibre
// Native FFI release in maplibre_ffi.lock, and that every notice file has a
// source in the release (design D96 of the third-party-notices change, second
// item, D108 of the publish-readiness change, D217 of the update-ffi-0-202610-3
// change, and D219, D227 and D248 of the port-ffi-gesture-recognizer change).
// An HTML notice's copy is compared with the text that
// scripts/html_notice_to_text.py writes of it. The test reads the tarballs of
// the presets in the lock file that scripts/fetch_ffi_release.sh downloads into
// third_party/maplibre-native-ffi-release/<version>/, or while the lock names
// no release, the installs of MAPLIBRE_FFI_COMMIT that
// scripts/build_maplibre_ffi.sh makes in third_party/maplibre-native-ffi/. It
// is skipped when none of them is there.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const repositoryRoot = '../..';

/// The value of [key] in `maplibre_ffi.lock`, without quotes.
String lockValue(String lock, String key) =>
    RegExp('^$key="?([^"\\n]*)"?\$', multiLine: true).firstMatch(lock)![1]!;

/// The presets in the lock file.
List<String> presets() {
  final lock = File('maplibre_ffi.lock').readAsStringSync();
  return [
    ...lockValue(lock, 'MAPLIBRE_FFI_PRESETS').split(' '),
    ...lockValue(lock, 'MAPLIBRE_FFI_ANDROID_PRESETS').split(' '),
  ].where((preset) => preset.isNotEmpty).toList();
}

/// The installs of the lock file's commit, by preset, while the lock names no
/// release.
Map<String, Directory> installedShares() {
  final lock = File('maplibre_ffi.lock').readAsStringSync();
  if (lockValue(lock, 'MAPLIBRE_FFI_VERSION').isNotEmpty) return {};
  final commit = lockValue(lock, 'MAPLIBRE_FFI_COMMIT');
  final installs = p.join(repositoryRoot, 'third_party', 'maplibre-native-ffi');
  return {
    for (final preset in presets())
      if (File(p.join(installs, preset, 'BUILD_INFO')).existsSync() &&
          File(p.join(installs, preset, 'BUILD_INFO'))
                  .readAsStringSync()
                  .trim() ==
              '$commit $preset')
        preset: Directory(
          p.join(installs, preset, 'share', 'maplibre-native-c'),
        ),
  };
}

/// The fetched tarballs of the presets in the lock file, by preset.
Map<String, File> fetchedTarballs() {
  final lock = File('maplibre_ffi.lock').readAsStringSync();
  final version = lockValue(lock, 'MAPLIBRE_FFI_VERSION');
  if (version.isEmpty) return {};
  return {
    for (final preset in presets())
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
  final name = p.extension(file) == '.html'
      ? '${p.basenameWithoutExtension(file)}.txt'
      : p.basename(file);
  final candidates = [
    'notices/common/$name',
    preset.startsWith('android-')
        ? 'notices/android/$name'
        : 'notices/darwin/$name',
  ];
  return candidates.where((path) => File(path).existsSync()).firstOrNull;
}

void main() {
  final tarballs = fetchedTarballs();
  final installs = installedShares();
  final sources = {...tarballs.keys, ...installs.keys};

  test(
    'the notice files equal the notices of the FFI',
    () {
      final extracted = Directory.systemTemp.createTempSync('ffi-notices');
      addTearDown(() => extracted.deleteSync(recursive: true));
      final problems = <String>[];
      final copies = <String>{};
      for (final preset in sources) {
        final String shareDirectory;
        final String origin;
        if (tarballs[preset] case final tarball?) {
          final share = 'maplibre-native-c-$preset/share/maplibre-native-c';
          final result = Process.runSync('tar', [
            '-xzf',
            tarball.path,
            '-C',
            extracted.path,
            share,
          ]);
          expect(result.exitCode, 0, reason: '${result.stderr}');
          shareDirectory = p.join(extracted.path, share);
          origin = '${p.basename(tarball.path)}: $share';
        } else {
          shareDirectory = installs[preset]!.path;
          origin = shareDirectory;
        }
        final licenses = Directory(p.join(shareDirectory, 'licenses'));
        final files = [
          'LICENSE',
          if (licenses.existsSync())
            for (final file in licenses.listSync().whereType<File>())
              p.posix.join('licenses', p.basename(file.path)),
        ]..sort();
        for (final file in files) {
          final source = '$origin/$file';
          final copy = packageCopy(preset, file);
          if (copy == null) {
            problems.add('$source has no copy in notices/');
            continue;
          }
          copies.add(copy);
          if (!_equalBytes(
            _expectedCopy(p.join(shareDirectory, file)),
            File(copy).readAsBytesSync(),
          )) {
            problems.add('$copy differs from $source');
          }
        }
      }
      // Only when every preset's notices are there does a file without a
      // source mean that the FFI no longer has it.
      if (sources.length == presets().length) {
        for (final file in Directory('notices').listSync(recursive: true)) {
          final path = p.posix.joinAll(p.split(file.path));
          if (file is File && !copies.contains(path)) {
            problems.add('$path is in no preset of the FFI');
          }
        }
      }
      expect(problems, isEmpty, reason: 'Run scripts/copy_ffi_notices.sh');
    },
    skip: sources.isEmpty
        ? 'neither a tarball of the MapLibre Native FFI release nor a local '
              'build of its commit is there; run scripts/fetch_ffi_release.sh '
              'or scripts/build_maplibre_ffi.sh'
        : null,
  );
}

/// The bytes that the package's copy of the notice file at [path] has: the
/// file's, or for an HTML notice, those of its text.
List<int> _expectedCopy(String path) {
  if (p.extension(path) != '.html') return File(path).readAsBytesSync();
  final result = Process.runSync('python3', [
    '-I',
    p.join(repositoryRoot, 'scripts', 'html_notice_to_text.py'),
    path,
  ], stdoutEncoding: null);
  expect(result.exitCode, 0, reason: '${result.stderr}');
  return result.stdout as List<int>;
}

bool _equalBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
