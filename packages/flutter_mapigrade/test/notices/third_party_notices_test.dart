// Tests the license entries of the third-party notices (design D96 of the
// third-party-notices change, first item): their names and texts, that the
// files in notices/, the Dart lists and the table of
// scripts/copy_ffi_notices.sh agree, and the plugin and asset entries in
// pubspec.yaml. The entries are read through a test AssetBundle, because
// `flutter test` bundles every asset and doesn't apply the platform filter.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mapigrade/src/notices/third_party_notices.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

const keyPrefix = 'packages/flutter_mapigrade/';

/// Serves the files of the package directory under the keys that an
/// application's asset bundle uses for the package's assets, and records the
/// keys it was asked for.
class PackageFilesBundle extends AssetBundle {
  final requestedKeys = <String>[];

  @override
  Future<ByteData> load(String key) async {
    requestedKeys.add(key);
    if (!key.startsWith(keyPrefix)) {
      throw FlutterError('not a key of the package: $key');
    }
    final bytes = await File(key.substring(keyPrefix.length)).readAsBytes();
    return ByteData.sublistView(bytes);
  }

  @override
  Future<T> loadStructuredData<T>(
    String key,
    Future<T> Function(String value) parser,
  ) async => parser(await loadString(key));
}

/// The files in `notices/`, as paths relative to the package directory.
Set<String> noticeFiles() =>
    Directory('notices')
        .listSync(recursive: true)
        .whereType<File>()
        .map((file) => p.posix.joinAll(p.split(file.path)))
        .toSet();

void main() {
  test('the repository root has the same LICENSE as the package', () {
    expect(
      File('../../LICENSE').readAsStringSync(),
      File('LICENSE').readAsStringSync(),
    );
  });

  test('applications on macOS and iOS list the six common notices', () async {
    final bundle = PackageFilesBundle();
    final entries = await thirdPartyNotices(bundle, android: false).toList();

    expect(entries.map((entry) => entry.packages.single), [
      'MapLibre Native FFI',
      'MapLibre Native',
      'ICU',
      'FastPFOR',
      'nunicode',
      'PMTiles',
    ]);
    for (final (index, notice) in commonNotices.indexed) {
      expect(
        (entries[index] as LicenseEntryWithLineBreaks).text,
        File(notice.path).readAsStringSync(),
        reason: notice.path,
      );
    }
    expect(bundle.requestedKeys, everyElement(contains('/notices/common/')));
  });

  test('applications on Android also list the Android notices', () async {
    final entries = await thirdPartyNotices(
      PackageFilesBundle(),
      android: true,
    ).toList();

    expect(entries.map((entry) => entry.packages.single), [
      for (final notice in commonNotices) notice.packageName,
      'MapLibre Native FFI Rust crates',
      'Android NDK C++ runtime',
      'Kotlin',
      'Kotlin NOTICE',
      'rustls-platform-verifier',
    ]);
    for (final (index, notice) in androidNotices.indexed) {
      expect(
        (entries[commonNotices.length + index] as LicenseEntryWithLineBreaks)
            .text,
        File(notice.path).readAsStringSync(),
        reason: notice.path,
      );
    }
  });

  test('no notice file is loaded before the entries are read', () async {
    final bundle = PackageFilesBundle();
    final notices = thirdPartyNotices(bundle, android: true);
    await pumpEventQueue();
    expect(bundle.requestedKeys, isEmpty);

    await notices.first;
    expect(bundle.requestedKeys, hasLength(1));
  });

  test('the files in notices/ are exactly the files of the Dart lists', () {
    expect(noticeFiles(), {
      for (final notice in [...commonNotices, ...androidNotices]) notice.path,
    });
    expect(
      commonNotices.map((notice) => notice.path),
      everyElement(startsWith('notices/common/')),
    );
    expect(
      androidNotices.map((notice) => notice.path),
      everyElement(startsWith('notices/android/')),
    );
  });

  test('scripts/copy_ffi_notices.sh copies the files of the Dart lists', () {
    final script = File('../../scripts/copy_ffi_notices.sh').readAsStringSync();
    final scriptTargets = RegExp(
      r'^  "\S+ ((?:common|android)/\S+)"$',
      multiLine: true,
    ).allMatches(script).map((match) => 'notices/${match[1]}').toSet();

    expect(scriptTargets, noticeFiles());
  });

  test('pubspec.yaml registers the notices on each platform', () {
    final pubspec =
        loadYaml(File('pubspec.yaml').readAsStringSync()) as YamlMap;
    final flutter = pubspec['flutter'] as YamlMap;
    final platforms = (flutter['plugin'] as YamlMap)['platforms'] as YamlMap;
    const dartFileName = 'src/notices/third_party_notices.dart';

    expect(File(p.join('lib', dartFileName)).existsSync(), isTrue);
    for (final (platform, dartPluginClass) in [
      ('android', 'MapigradeAndroidNotices'),
      ('ios', 'MapigradeDarwinNotices'),
      ('macos', 'MapigradeDarwinNotices'),
    ]) {
      final entry = platforms[platform] as YamlMap;
      expect(entry['dartPluginClass'], dartPluginClass, reason: platform);
      expect(entry['dartFileName'], dartFileName, reason: platform);
      expect(entry['pluginClass'], 'MapigradePlugin', reason: platform);
    }

    final assets = [
      for (final asset in flutter['assets'] as YamlList)
        '${(asset as YamlMap)['path']} ${asset['platforms'] ?? 'all'}',
    ];
    expect(assets, ['notices/common/ all', 'notices/android/ [android]']);
  });
}
