## Why

`MapigradeMap` needs the mln-rs-based MapLibre Native FFI, which no FFI release contains yet: `maplibre_ffi.lock` pins FFI commit `4371ff6`, and the newest release, v0.202611.0, is older. A build of the packages from pub.dev therefore fails on every platform, so we can't publish them, not even as a beta. On iOS and macOS the package downloads the FFI as one xcframework archive from a URL and checksum that the lock states, and any HTTPS URL works there. On Android the FFI comes from Maven Central under MapLibre's namespace, where we can't publish. A beta for iOS and macOS only, with an xcframework that we build from the pinned commit and host ourselves, lets developers try `MapigradeMap` before the FFI release.

## What Changes

- A prerelease of both packages, `0.2.0-beta.1`, may pin an FFI commit that has no release. Its iOS and macOS builds download an xcframework that we build from that commit with `scripts/build_maplibre_ffi.sh` and attach to a GitHub release of this repository, checked against the checksum in the lock.
- **BREAKING** for Android, in the prerelease only: `mapigrade`'s prerelease declares only iOS and macOS as plugin platforms. An Android application that depends on the prerelease builds and runs, `Mapigrade.isSupported` and `MapigradeLayer.isSupported` are false, and a map widget reports a `MapigradeCreateException`. Stable releases still require an FFI release and support Android.
- The prerelease is made from a release branch, not from `main`, so that the repository's Android builds (test harness, demo, examples) keep working with the local FFI build.
- A script packages the local xcframework as a zip and prints its checksum; the lock and `Package.swift` take the URL and checksum.
- The pin test and the release runbook accept a self-hosted xcframework for a prerelease, and still require an FFI release for a stable release.
- The READMEs and CHANGELOGs of the prerelease state that it supports iOS and macOS only, and why.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `package-distribution`: "Native libraries from the pinned release" allows a prerelease to take the iOS and macOS framework from an xcframework that we build from a pinned FFI commit and host, and to declare no Android support; "Application build from the published archive" covers an Android build of such a prerelease.
- `map-texture`: "Supported platforms" states that a prerelease without an FFI release supports only macOS and iOS.

## Impact

- `packages/mapigrade/maplibre_ffi.lock`, `darwin/mapigrade/Package.swift` (through `scripts/update_ffi_pins.sh`), `pubspec.yaml` of both packages on the release branch.
- `packages/mapigrade/test/ffi_pins_test.dart`; `scripts/consumer_build.sh` and `.github/workflows/consumer-build.yml` for a prerelease without Android.
- A new script, or a mode of `scripts/package_xcframework.sh`, that zips the local xcframework.
- `docs/releasing.md`, `docs/packaging.md`, both package READMEs and CHANGELOGs.
- A GitHub release of `greensopinion/mapigrade` that holds the xcframework zip, and the publication of both packages on pub.dev; both are public actions that the user approves and performs.
