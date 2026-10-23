# Releasing flutter_mapigrade

This runbook publishes a new version of `flutter_mapigrade` to pub.dev. We publish by hand, not from CI. The package belongs to the verified publisher [greensopinion.com](https://pub.dev/publishers/greensopinion.com/packages), so the account that publishes must be a member of that publisher.

## Before the release

Check that `main` can be released:

- `packages/flutter_mapigrade/maplibre_ffi.lock` pins a MapLibre Native FFI release, not `unstable-native-snapshot`. To update the pin, follow "Update the FFI" in [CONTRIBUTING.md](../CONTRIBUTING.md).
- `packages/flutter_mapigrade/pubspec.yaml` has no `publish_to: none`.
- The last pull request that changed the plugin's native code passed the `consumer-build` workflow. That workflow builds an application from the published archive of the package.

## Prepare the release

On `main`:

1. Choose the version. While the version is below 1.0.0, increase the minor version for a change that breaks the API and the patch version for everything else.
2. Set `version` in `packages/flutter_mapigrade/pubspec.yaml`.
3. In `packages/flutter_mapigrade/CHANGELOG.md`, rename `## Unreleased` to the version. Keep only what a user of the package needs to know: changes to the API, to its behavior, to supported platforms and versions, and to the FFI version. Leave out internal changes.
4. Commit and push.

## Check the package

Run pana on a clean clone of `main`, so that it checks only committed files:

```sh
git clone https://github.com/greensopinion/mapigrade.git /tmp/mapigrade-release
cd /tmp/mapigrade-release
flutter pub get
dart pub global activate pana
dart pub global run pana packages/flutter_mapigrade
```

Fix what pana reports before publishing.

## Publish

From the clean clone:

```sh
cd packages/flutter_mapigrade
flutter pub publish --dry-run
flutter pub publish
```

The dry run must report no warnings. After publishing, check the package page on pub.dev: the version, the changelog and, after pub.dev finishes its analysis, the score.

Add a `## Unreleased` section at the top of `CHANGELOG.md` with the first change after the release.
