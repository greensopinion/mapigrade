// The dartPluginClass entries in pubspec.yaml make the generated plugin
// registrant call registerWith(), so applications need no code for the
// notices to appear in showLicensePage.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The asset key prefix of the package's notice files, which
/// `scripts/copy_ffi_notices.sh` copies from the FFI. `pubspec.yaml` puts the
/// files in `notices/darwin/` only in the macOS and iOS builds, and the files in
/// `notices/android/` only in the Android build.
const noticeKeyPrefix = 'packages/flutter_mapigrade/notices/';

/// The package names of the license entries of known notice files, by file
/// name, in the order the entries are listed. A notice file that isn't here
/// gets its file name without the extension, after the known ones.
const noticeNames = {
  'maplibre-native-ffi.txt': 'MapLibre Native FFI',
  'mln-rs.md': 'mln-rs',
  'rust.md': 'MapLibre Native FFI Rust crates',
  'rust-std.txt': 'Rust standard library',
};

/// The package name of the license entry of the notice file at [key].
String noticeName(String key) {
  final fileName = key.substring(key.lastIndexOf('/') + 1);
  final extension = fileName.lastIndexOf('.');
  return noticeNames[fileName] ??
      (extension > 0 ? fileName.substring(0, extension) : fileName);
}

/// The keys of the notice files in [bundle]'s asset manifest.
Future<List<String>> noticeKeys(AssetBundle bundle) async {
  final manifest = await AssetManifest.loadFromAssetBundle(bundle);
  return [
    for (final key in manifest.listAssets())
      if (key.startsWith(noticeKeyPrefix)) key,
  ];
}

/// Yields one license entry per notice file, with the file's text unchanged.
/// [keys] lists the notice files; the files are loaded from [bundle] as the
/// registry reads the entries, not before.
Stream<LicenseEntry> thirdPartyNotices(
  AssetBundle bundle, {
  Future<List<String>> Function(AssetBundle bundle) keys = noticeKeys,
}) async* {
  final names = noticeNames.keys.toList();
  int rank(String key) {
    final index = names.indexOf(key.substring(key.lastIndexOf('/') + 1));
    return index < 0 ? names.length : index;
  }

  final ordered = (await keys(bundle)).toList()
    ..sort((a, b) {
      final byRank = rank(a).compareTo(rank(b));
      return byRank != 0 ? byRank : a.compareTo(b);
    });
  for (final key in ordered) {
    yield LicenseEntryWithLineBreaks([
      noticeName(key),
    ], await bundle.loadString(key));
  }
}

/// Registers the notices of the files that the application's build contains.
abstract final class MapigradeNotices {
  /// Called by the generated plugin registrant before `main`.
  static void registerWith() {
    LicenseRegistry.addLicense(() => thirdPartyNotices(rootBundle));
  }
}
