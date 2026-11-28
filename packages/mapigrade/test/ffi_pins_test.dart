// Checks that the URL and checksum of the remote binary target in
// darwin/mapigrade/Package.swift equal MAPLIBRE_FFI_XCFRAMEWORK_URL and
// MAPLIBRE_FFI_XCFRAMEWORK_CHECKSUM in maplibre_ffi.lock (design D99 of the
// publish-readiness change). scripts/update_ffi_pins.sh writes them from the
// lock file. Also checks that the lock names an FFI release, or that the
// package is a prerelease that may do without one (design D252 of the
// apple-only-beta-release change).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

/// The value of [key] in the lock file.
String lockValue(String lock, String key) =>
    RegExp('^$key=(.*)\$', multiLine: true).firstMatch(lock)![1]!.trim();

/// The string arguments named [label] in Package.swift.
List<String> packageValues(String package, String label) => [
  for (final match in RegExp(
    '^ *$label: "([^"]*)"',
    multiLine: true,
  ).allMatches(package))
    match[1]!,
];

const _hostedPrefix =
    'https://github.com/greensopinion/mapigrade/releases/download/';

/// Why [lock] and [pubspec] can't be published: a stable version needs an FFI
/// release, and a prerelease without one must not declare Android and must
/// take the xcframework from a release asset of this repository.
List<String> releaseProblems(String lock, String pubspec) {
  if (lockValue(lock, 'MAPLIBRE_FFI_VERSION').isNotEmpty) return [];
  final yaml = loadYaml(pubspec) as YamlMap;
  final version = '${yaml['version']}';
  final platforms =
      ((yaml['flutter'] as YamlMap)['plugin'] as YamlMap)['platforms']
          as YamlMap;
  final url = lockValue(lock, 'MAPLIBRE_FFI_XCFRAMEWORK_URL');
  if (!RegExp(r'^\d+\.\d+\.\d+-').hasMatch(version)) {
    return [
      'maplibre_ffi.lock names no MapLibre Native FFI release, which the '
          'stable version $version needs',
    ];
  }
  return [
    if (platforms.containsKey('android'))
      'the prerelease $version without an FFI release declares the android '
          'plugin platform',
    if (!url.startsWith(_hostedPrefix))
      'the prerelease $version without an FFI release takes the xcframework '
          'from "$url", not from a release asset of greensopinion/mapigrade',
  ];
}

void main() {
  test('the package can be released with its FFI pin', () {
    final problems = releaseProblems(
      File('maplibre_ffi.lock').readAsStringSync(),
      File('pubspec.yaml').readAsStringSync(),
    );
    expect(problems, isEmpty, reason: problems.join('\n'));
  });

  group('releaseProblems', () {
    String lock({String version = '', String url = ''}) =>
        'MAPLIBRE_FFI_VERSION=$version\n'
        'MAPLIBRE_FFI_XCFRAMEWORK_URL=$url\n';
    String pubspec(String version, {bool android = true}) =>
        'version: $version\n'
        'flutter:\n'
        '  plugin:\n'
        '    platforms:\n'
        '${android ? '      android:\n        pluginClass: P\n' : ''}'
        '      ios:\n'
        '        pluginClass: P\n';
    const hosted = '${_hostedPrefix}maplibre-native-ffi-4371ff6/z.zip';

    test('a release version passes', () {
      expect(
        releaseProblems(lock(version: '0.202611.0'), pubspec('0.2.0')),
        isEmpty,
      );
    });

    test('a stable version without a release fails', () {
      expect(
        releaseProblems(lock(url: hosted), pubspec('0.2.0', android: false)),
        [contains('stable version 0.2.0')],
      );
    });

    test('a prerelease that declares android fails', () {
      expect(releaseProblems(lock(url: hosted), pubspec('0.2.0-beta.1')), [
        contains('android'),
      ]);
    });

    test('a prerelease with an archive elsewhere fails', () {
      expect(
        releaseProblems(
          lock(url: 'https://example.com/z.zip'),
          pubspec('0.2.0-beta.1', android: false),
        ),
        [contains('https://example.com/z.zip')],
      );
    });

    test('a prerelease without android and with a hosted archive passes', () {
      expect(
        releaseProblems(
          lock(url: hosted),
          pubspec('0.2.0-beta.1', android: false),
        ),
        isEmpty,
      );
    });
  });

  test(
    'Package.swift has the xcframework URL and checksum of the lock file',
    () {
      final lock = File('maplibre_ffi.lock').readAsStringSync();
      final package = File('darwin/mapigrade/Package.swift').readAsStringSync();
      final problems = <String>[];
      for (final (label, key) in [
        ('url', 'MAPLIBRE_FFI_XCFRAMEWORK_URL'),
        ('checksum', 'MAPLIBRE_FFI_XCFRAMEWORK_CHECKSUM'),
      ]) {
        final expected = lockValue(lock, key);
        final actual = packageValues(package, label);
        if (actual.length != 1 || actual.single != expected) {
          problems.add(
            'Package.swift $label is $actual, '
            'but $key in maplibre_ffi.lock is "$expected"',
          );
        }
      }
      expect(
        problems,
        isEmpty,
        reason: 'run scripts/update_ffi_pins.sh:\n${problems.join('\n')}',
      );
    },
  );
}
