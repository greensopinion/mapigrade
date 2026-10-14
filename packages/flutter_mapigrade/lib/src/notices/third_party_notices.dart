// Registers the third-party notices of MapLibre Native FFI with Flutter's
// license registry (design D94 and D95 of the third-party-notices change). The
// generated plugin registrant calls registerWith() before main, through the
// dartPluginClass entries in pubspec.yaml, so applications need no code for the
// notices to appear in showLicensePage.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A notice file in the package's `notices/` directory, and the package name
/// of its license entry.
typedef Notice = ({String packageName, String path});

/// The notices that applications on every platform show.
/// `scripts/copy_ffi_notices.sh` copies the same files.
const commonNotices = <Notice>[
  (
    packageName: 'MapLibre Native FFI',
    path: 'notices/common/maplibre-native-ffi.txt',
  ),
  (packageName: 'MapLibre Native', path: 'notices/common/maplibre-native.md'),
  (packageName: 'ICU', path: 'notices/common/icu.txt'),
  (packageName: 'FastPFOR', path: 'notices/common/fastpfor.txt'),
  (packageName: 'nunicode', path: 'notices/common/nunicode.txt'),
  (packageName: 'PMTiles', path: 'notices/common/pmtiles.txt'),
];

/// The notices that only Android applications show: the FFI's Android build
/// links Rust crates and the NDK's C++ runtime, which the Apple builds don't.
/// `pubspec.yaml` leaves these files out of the other platforms' builds.
const androidNotices = <Notice>[
  (
    packageName: 'MapLibre Native FFI Rust crates',
    path: 'notices/android/rust.md',
  ),
  (
    packageName: 'Android NDK C++ runtime',
    path: 'notices/android/cxx-runtime.txt',
  ),
];

/// Yields one license entry per notice file, with the file's text unchanged.
/// The files are loaded from [bundle] as the registry reads the entries, not
/// before.
Stream<LicenseEntry> thirdPartyNotices(
  AssetBundle bundle, {
  required bool android,
}) async* {
  for (final notice in [...commonNotices, if (android) ...androidNotices]) {
    yield LicenseEntryWithLineBreaks([
      notice.packageName,
    ], await bundle.loadString('packages/flutter_mapigrade/${notice.path}'));
  }
}

/// Registers the notices of Android applications.
abstract final class MapigradeAndroidNotices {
  /// Called by the generated plugin registrant before `main`.
  static void registerWith() {
    LicenseRegistry.addLicense(
      () => thirdPartyNotices(rootBundle, android: true),
    );
  }
}

/// Registers the notices of macOS and iOS applications.
abstract final class MapigradeDarwinNotices {
  /// Called by the generated plugin registrant before `main`.
  static void registerWith() {
    LicenseRegistry.addLicense(
      () => thirdPartyNotices(rootBundle, android: false),
    );
  }
}
