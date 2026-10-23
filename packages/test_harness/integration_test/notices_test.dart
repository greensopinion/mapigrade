// Integration test for the third-party notices (third-party-notices spec,
// requirement "Native notices in the license registry"; design D96 of the
// third-party-notices change, third item). It reads the
// license registry as showLicensePage does, with the assets and the plugin
// registration of a real build. Run it on macOS, on the iPhone simulator and on
// the Android emulator:
//
//   cd packages/test_harness && flutter test integration_test/notices_test.dart -d <device>
//
// The test's entrypoint runs the generated plugin registrant, as an app's does,
// so the test doesn't call DartPluginRegistrant.ensureInitialized(): that
// would register the notices a second time. The test binding doesn't add the
// Dart packages' licenses (NOTICES) to the registry, so the package's own
// license is checked on the license page instead (task 4.2).
//
// The unit test test/notices/third_party_notices_test.dart of the package
// checks the full texts. This test checks the first line of each text, so it
// needs updating when an FFI update changes a notice's first line.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// The package name of each entry, and the first non-empty line of its text.
const commonNotices = {
  'MapLibre Native FFI': 'BSD 2-Clause License',
  'MapLibre Native':
      '### [Maplibre Native](https://github.com/maplibre/maplibre-native/)',
  'ICU': 'COPYRIGHT AND PERMISSION NOTICE (ICU 58 and later)',
  'FastPFOR': 'Apache License',
  'nunicode': 'Copyright (c) 2013 Aleksey Tulinov <aleksey.tulinov@gmail.com>',
  'PMTiles':
      'The below license (BSD-3) applies to the reference implementations in '
      'this repository.',
};

const androidNotices = {
  'MapLibre Native FFI Rust crates': '# Rust dependency notices',
  'Android NDK C++ runtime':
      'Copyright (c) 2015, The Android Open Source Project',
  'Kotlin': 'Apache License',
  'Kotlin NOTICE':
      '=========================================================================',
  'rustls-platform-verifier':
      'This product includes software from the rustls-platform-verifier project',
};

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the license registry lists the notices of this platform', (
    tester,
  ) async {
    final entries = await LicenseRegistry.licenses.toList();
    String textOf(LicenseEntry entry) =>
        entry.paragraphs.map((paragraph) => paragraph.text).join('\n');

    final expected = {
      ...commonNotices,
      if (Platform.isAndroid) ...androidNotices,
    };
    for (final MapEntry(key: name, value: firstLine) in expected.entries) {
      final matching = entries.where((e) => e.packages.contains(name));
      expect(matching, hasLength(1), reason: name);
      expect(
        textOf(matching.single).trimLeft(),
        startsWith(firstLine),
        reason: name,
      );
    }
    if (!Platform.isAndroid) {
      for (final name in androidNotices.keys) {
        expect(
          entries.where((e) => e.packages.contains(name)),
          isEmpty,
          reason: name,
        );
      }
    }
  });
}
