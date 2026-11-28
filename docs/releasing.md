# Releasing mapigrade and flutter_mapigrade

This runbook publishes a new version of `mapigrade` and `flutter_mapigrade` to pub.dev. We publish by hand, not from CI. The packages belong to the verified publisher [greensopinion.com](https://pub.dev/publishers/greensopinion.com/packages), so the account that publishes must be a member of that publisher.

Both packages always have the same version, and `flutter_mapigrade` depends on `mapigrade` with the range from that version to the next patch version, such as `>=0.2.0 <0.2.1`, which allows no other release of `mapigrade` (design D231 of the split-mapigrade-package change). A release of one package is unusable without a release of the other, so every release publishes both. `packages/flutter_mapigrade/test/version_test.dart` fails while the versions and the constraint differ.

## Before the release

Check that `main` can be released:

- `packages/mapigrade/maplibre_ffi.lock` pins a MapLibre Native FFI release, not `unstable-native-snapshot` or a commit without a release; `packages/mapigrade/test/ffi_pins_test.dart` fails while it names no release. Without an FFI release, only a prerelease can be published; see "Prerelease without an FFI release". To update the pin, follow "Update the FFI" in [CONTRIBUTING.md](../CONTRIBUTING.md).
- Neither `packages/mapigrade/pubspec.yaml` nor `packages/flutter_mapigrade/pubspec.yaml` has `publish_to: none`.
- The last pull request that changed `mapigrade`'s native code passed the `consumer-build` workflow. That workflow builds an application from the published archives of both packages.

## Prepare the release

On `main`:

1. Choose the version. While the version is below 1.0.0, increase the minor version for a change that breaks the API of either package and the patch version for everything else.
2. Run `scripts/set_version.sh <version>` at the repository root. It sets the `version` in both `pubspec.yaml` files and `flutter_mapigrade`'s constraint on `mapigrade` to the range from that version.
3. In `packages/mapigrade/CHANGELOG.md` and `packages/flutter_mapigrade/CHANGELOG.md`, rename `## Unreleased` to the version, and replace `<release>` with the FFI release that the lock pins. Keep only what a user of the package needs to know: changes to the API, to its behavior, to supported platforms and versions, and to the FFI version. Leave out internal changes. When a package has no such change, give it the entry "No changes; released with `<other package>` <version>."
4. Commit and push.

## Check the packages

Run pana on both packages in a clean clone of `main`, so that it checks only committed files:

```sh
git clone https://github.com/greensopinion/mapigrade.git /tmp/mapigrade-release
cd /tmp/mapigrade-release
flutter pub get
dart pub global activate pana
dart pub global run pana packages/mapigrade
dart pub global run pana packages/flutter_mapigrade
```

Fix what pana reports before publishing.

## Publish

`flutter pub publish` resolves `mapigrade` from pub.dev, so publish `mapigrade` first. From the clean clone:

```sh
cd packages/mapigrade
flutter pub publish --dry-run
flutter pub publish
```

When the new version of `mapigrade` is listed on pub.dev:

```sh
cd ../flutter_mapigrade
flutter pub publish --dry-run
flutter pub publish
```

Each dry run must report no warnings. After publishing, check each package's page on pub.dev: the version, the changelog and, after pub.dev finishes its analysis, the score and the platforms. Both packages must list Android, iOS and macOS.

Add a `## Unreleased` section at the top of each `CHANGELOG.md` with the first change after the release.

## Prerelease without an FFI release

While the lock pins an FFI commit that no FFI release contains, we can publish a prerelease, such as `0.2.0-beta.1`, for iOS and macOS only (designs D250 to D255 of the apple-only-beta-release change). Its iOS and macOS builds download an xcframework that we build from the pinned commit and host. Android needs the FFI's runtime from Maven Central, which only an FFI release provides, so the prerelease doesn't declare Android: an Android app that depends on it builds, and `Mapigrade.isSupported` is false.

On `main`:

1. Build the Apple presets at the pinned commit, and zip the xcframework:

   ```sh
   scripts/build_maplibre_ffi.sh macos-arm64 ios-arm64 ios-simulator-arm64
   scripts/package_xcframework.sh --local
   ```

   The second script checks that each preset was built at `MAPLIBRE_FFI_COMMIT`, writes `third_party/maplibre-native-ffi/MaplibreNativeC.xcframework.zip` and prints its checksum.
2. Create a GitHub prerelease of `greensopinion/mapigrade` with the tag `maplibre-native-ffi-<first 7 characters of the commit>`, and attach the zip as `MaplibreNativeC.xcframework.zip`. In its notes, name the FFI commit and repository, and state that it isn't an official MapLibre release. Never replace the asset: Swift Package Manager rejects a zip whose checksum changed, so a new build gets a new tag.
3. Set `MAPLIBRE_FFI_XCFRAMEWORK_URL` to the asset's download URL and `MAPLIBRE_FFI_XCFRAMEWORK_CHECKSUM` to the checksum in the lock, run `scripts/update_ffi_pins.sh`, and commit.

Then, on a branch `release/<version>` from `main`:

1. Run `scripts/set_version.sh <version>`. For a prerelease it sets `flutter_mapigrade`'s constraint on `mapigrade` to the exact version.
2. Remove the `android` entry under `flutter.plugin.platforms` in `packages/mapigrade/pubspec.yaml`. `main` keeps it, so that the repository's Android builds keep working with a local FFI build.
3. Under "Supported platforms" in both READMEs, and at the top of both CHANGELOG entries, state that the prerelease supports iOS and macOS only because its FFI has no release yet, and which release supports Android.
4. Check that `ffi_pins_test.dart` and `version_test.dart` pass, commit, and push the branch.

Check and publish the packages as above, from a clean clone of the branch (`git clone --branch release/<version> …`), and tag the published commit `v<version>`. `scripts/consumer_build.sh` expects an APK without the FFI and plugin libraries when the lock names no FFI release. On pub.dev, `mapigrade` lists iOS and macOS, not Android. Don't merge the branch into `main`: when an FFI release contains the pinned commit, pin it on `main` and release from `main` as above.
