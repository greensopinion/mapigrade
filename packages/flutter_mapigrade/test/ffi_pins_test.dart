// Checks that the URL and checksum of the remote binary target in
// darwin/flutter_mapigrade/Package.swift equal MAPLIBRE_FFI_XCFRAMEWORK_URL and
// MAPLIBRE_FFI_XCFRAMEWORK_CHECKSUM in maplibre_ffi.lock (design D99 of the
// publish-readiness change). scripts/update_ffi_pins.sh writes them from the
// lock file.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

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

void main() {
  test(
    'Package.swift has the xcframework URL and checksum of the lock file',
    () {
      final lock = File('maplibre_ffi.lock').readAsStringSync();
      final package = File('darwin/flutter_mapigrade/Package.swift')
          .readAsStringSync();
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
