// Integration test for the third-party notices (third-party-notices spec,
// requirement "Native notices in the license registry"; design D96 of the
// third-party-notices change, third item, and D217 of the update-ffi-0-202610-3
// change). It reads the license registry as showLicensePage does, with the
// assets and the plugin registration of a real build, and checks it against
// the notice files that the build contains. Run it on macOS, on the iPhone
// simulator and on the Android emulator:
//
//   cd packages/test_harness && flutter test integration_test/notices_test.dart -d <device>
//
// The test's entrypoint runs the generated plugin registrant, as an app's does,
// so the test doesn't call DartPluginRegistrant.ensureInitialized(): that
// would register the notices a second time. The test binding doesn't add the
// Dart packages' licenses (NOTICES) to the registry, so the package's own
// license is checked on the license page instead (task 4.2 of the
// third-party-notices change).
//
// The test names no notice file, so an FFI update that adds or removes one
// needs no change here.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const noticePrefix = 'packages/flutter_mapigrade/notices/';

/// The text of [entry] as the license page shows it.
String textOf(LicenseEntry entry) =>
    entry.paragraphs.map((paragraph) => paragraph.text).join('\n');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the license registry lists the notice files of this build', (
    tester,
  ) async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final keys = [
      for (final key in manifest.listAssets())
        if (key.startsWith(noticePrefix)) key,
    ];
    final androidKeys = keys.where((key) => key.contains('/notices/android/'));
    expect(keys.where((key) => key.contains('/notices/common/')), isNotEmpty);
    if (Platform.isAndroid) {
      expect(androidKeys, isNotEmpty);
    } else {
      expect(androidKeys, isEmpty);
    }

    final entries = await LicenseRegistry.licenses.toList();
    for (final key in keys) {
      final text = textOf(
        LicenseEntryWithLineBreaks(const [], await rootBundle.loadString(key)),
      );
      expect(
        entries.where((entry) => textOf(entry) == text),
        hasLength(1),
        reason: key,
      );
    }
  });
}
