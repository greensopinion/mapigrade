## Why

An app built with the package contains MapLibre Native and the libraries it includes (ICU, FastPFOR, nunicode, PMTiles, Boost, HarfBuzz and others), and on Android also 62 Rust crates and the NDK's C++ runtime. Their licenses require the app to reproduce their notices. `showLicensePage` lists only the notices of Dart packages, so none of these appear on any platform. The package's own `LICENSE` contains `TODO: Add your license here.`, and that text appears in the notices of every app that depends on the package. `docs/limitations.md` states that no license review has been done and that the notices must be included before any distribution. We want to fix this before the package is published.

## What Changes

- The package is licensed under BSD-3-Clause, `Copyright (c) 2026 David Green`, in `packages/flutter_mapigrade/LICENSE`. The repository root gets an identical `LICENSE`, which covers the files outside the package.
- The package contains the notice files that the MapLibre Native FFI build installs, unchanged, as assets: six files for every platform (the FFI's `LICENSE`, `maplibre-native.md`, `icu.txt`, `fastpfor.txt`, `nunicode.txt`, `pmtiles.txt`), and two files (`rust.md`, `cxx-runtime.txt`) that only Android builds contain.
- The plugin registers one license entry per notice file with `LicenseRegistry` before `main` runs, through a `dartPluginClass`. An app needs no code for the notices to appear in `showLicensePage`. Android apps list the Rust crate and C++ runtime notices; macOS and iOS apps don't.
- `scripts/build_maplibre_ffi.sh` copies the notice files into the package each time it installs a preset. The copies are committed, so a change to `scripts/maplibre_ffi.lock` shows every change to the notices in the diff. A test checks the committed files against the FFI build when it is present.
- `docs/limitations.md` and the README describe where the notices come from and how they are shown.

Non-goals:

- No legal review of whether each license is acceptable for a given app, for example CDLA-Permissive-2.0 and Unicode-3.0 among the Rust crates. This change makes the notices visible.
- No conversion of the notice files. The Markdown files are shown as they are, including headings, code fences and link syntax.
- No public API for apps that build their own notices page.
- No attribution for map data. That depends on the style and tiles an app uses, and remains the app's responsibility.

## Capabilities

### New Capabilities

- `third-party-notices`: the package's own license, the notices that each platform's apps show in the license registry, and how the committed notice files stay equal to the FFI build.

### Modified Capabilities

None. The `package-api` requirement on exported names doesn't change: the registration classes are in `lib/src/`.

## Impact

- Package: `LICENSE`, `pubspec.yaml` (assets with a `platforms:` filter, and a `dartPluginClass` with `dartFileName` for `android`, `ios` and `macos`), a new `notices/` directory of about 720 KB (97 KB of it shared by all platforms), a new file under `lib/src/`, `CHANGELOG.md`, and tests in `test/`.
- App size: Android apps contain about 720 KB more text before compression, Apple apps about 97 KB.
- Scripts: `scripts/build_maplibre_ffi.sh`.
- Test harness: an integration test of the license entries on macOS, iOS and Android.
- Documentation: `docs/limitations.md`, `README.md`.
