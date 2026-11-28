// Tests the license entries of the third-party notices (design D96 of the
// third-party-notices change, first item, D217 of the update-ffi-0-202610-3
// change, and D227 of the port-ffi-gesture-recognizer change): one entry with the file's text for each file in notices/, and the
// plugin and asset entries in pubspec.yaml. The entries are read through a test
// AssetBundle, because `flutter test` bundles every asset and doesn't apply the
// platform filter. The tests name no notice file, so an FFI update that adds or
// removes one needs no change here.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:mapigrade/src/notices/third_party_notices.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

const keyPrefix = 'packages/mapigrade/';

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

/// The files in `notices/<directory>/`, as paths relative to the package
/// directory; none when the directory doesn't exist.
List<String> noticeFiles(String directory) =>
    !Directory(p.join('notices', directory)).existsSync()
          ? []
          : Directory(p.join('notices', directory))
                .listSync()
                .whereType<File>()
                .map((file) => p.posix.joinAll(p.split(file.path)))
                .toList()
      ..sort();

/// The notice files of an Android build ([android]) or a macOS or iOS build:
/// `pubspec.yaml` puts the files in `notices/android/` only in the former, and
/// those in `notices/darwin/` only in the latter.
List<String> buildFiles({required bool android}) => [
  ...noticeFiles('common'),
  ...noticeFiles(android ? 'android' : 'darwin'),
];

/// The asset keys of an Android build ([android]) or a macOS or iOS build.
Future<List<String>> Function(AssetBundle) buildKeys({required bool android}) =>
    (_) async => [
      for (final file in buildFiles(android: android)) '$keyPrefix$file',
    ];

Future<Map<String, String>> entryTexts({required bool android}) async {
  final entries = await thirdPartyNotices(
    PackageFilesBundle(),
    keys: buildKeys(android: android),
  ).toList();
  return {
    for (final entry in entries)
      entry.packages.single: (entry as LicenseEntryWithLineBreaks).text,
  };
}

void main() {
  test('the repository root has the same LICENSE as the package', () {
    expect(
      File('../../LICENSE').readAsStringSync(),
      File('LICENSE').readAsStringSync(),
    );
  });

  test('notices/ has common notice files, and only per-platform directories '
      'beside them', () {
    expect(noticeFiles('common'), isNotEmpty);
    expect(
      Directory('notices').listSync().map((entry) => p.basename(entry.path)),
      everyElement(isIn(['common', 'darwin', 'android'])),
    );
  });

  for (final android in [false, true]) {
    final platform = android ? 'Android' : 'macOS and iOS';
    test('applications on $platform list each notice file of their build '
        'once, with its text', () async {
      final files = buildFiles(android: android);
      final texts = await entryTexts(android: android);

      expect(texts, hasLength(files.length));
      for (final file in files) {
        expect(
          texts[noticeName(file)],
          File(file).readAsStringSync(),
          reason: file,
        );
      }
    });
  }

  test('a notice file has its known name, or its file name', () {
    for (final MapEntry(key: fileName, value: name) in noticeNames.entries) {
      expect(noticeName('${keyPrefix}notices/common/$fileName'), name);
    }
    expect(
      noticeName('${keyPrefix}notices/common/new-component.txt'),
      'new-component',
    );
  });

  test('known notices come first, in the order of the names table', () async {
    final names = (await entryTexts(android: true)).keys.toList();
    final known = names.where(noticeNames.containsValue).toList();

    expect(names.take(known.length), known);
    expect(known, [
      for (final name in noticeNames.values)
        if (known.contains(name)) name,
    ]);
  });

  test('no notice file is loaded before the entries are read', () async {
    final bundle = PackageFilesBundle();
    final notices = thirdPartyNotices(bundle, keys: buildKeys(android: true));
    await pumpEventQueue();
    expect(bundle.requestedKeys, isEmpty);

    await notices.first;
    expect(bundle.requestedKeys, hasLength(1));
  });

  test('pubspec.yaml registers the notices on each platform', () {
    final pubspec =
        loadYaml(File('pubspec.yaml').readAsStringSync()) as YamlMap;
    final flutter = pubspec['flutter'] as YamlMap;
    final platforms = (flutter['plugin'] as YamlMap)['platforms'] as YamlMap;
    const dartFileName = 'src/notices/third_party_notices.dart';

    expect(File(p.join('lib', dartFileName)).existsSync(), isTrue);
    for (final platform in ['android', 'ios', 'macos']) {
      final entry = platforms[platform] as YamlMap;
      expect(entry['dartPluginClass'], 'MapigradeNotices', reason: platform);
      expect(entry['dartFileName'], dartFileName, reason: platform);
      expect(entry['pluginClass'], 'MapigradePlugin', reason: platform);
    }

    final assets = [
      for (final asset in flutter['assets'] as YamlList)
        '${(asset as YamlMap)['path']} ${asset['platforms'] ?? 'all'}',
    ];
    expect(assets, [
      'notices/common/ all',
      'notices/darwin/ [ios, macos]',
      'notices/android/ [android]',
    ]);
  });
}
