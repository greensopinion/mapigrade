#!/usr/bin/env bash
# Builds MaplibreNativeC.xcframework.zip from the Apple tarballs of the MapLibre
# Native FFI release MAPLIBRE_FFI_VERSION in
# packages/mapigrade/maplibre_ffi.lock (design D102 of the
# publish-readiness change), with the framework steps that
# scripts/build_maplibre_ffi.sh uses for local builds. Run
# scripts/fetch_ffi_release.sh first; it downloads the tarballs and checks
# them against the release's SHA256SUMS.
#
#   scripts/package_xcframework.sh
#   scripts/package_xcframework.sh unstable-native-snapshot
#   scripts/package_xcframework.sh --local
#
# A release tag as argument reads the tarballs that
# `scripts/fetch_ffi_release.sh <tag>` fetched, in place of the pinned
# version's.
#
# --local zips the xcframework of the local build in
# third_party/maplibre-native-ffi/ instead, for a prerelease without an FFI
# release (design D251 of the apple-only-beta-release change). It fails unless
# every Apple preset of the lock was built at MAPLIBRE_FFI_COMMIT, and writes
# third_party/maplibre-native-ffi/MaplibreNativeC.xcframework.zip.
#
# Writes third_party/maplibre-native-ffi-release/<version>/MaplibreNativeC.xcframework.zip,
# with MaplibreNativeC.xcframework/ at its top level, and prints the zip's
# SHA-256, the checksum that `swift package compute-checksum` computes and a
# .binaryTarget(name:url:checksum:) declares. The script doesn't call
# compute-checksum, which creates a .build directory in the working directory.
#
# Requires: Xcode.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../packages/mapigrade/maplibre_ffi.lock
source "$repo_root/packages/mapigrade/maplibre_ffi.lock"
# shellcheck source=ffi_framework.sh
source "$repo_root/scripts/ffi_framework.sh"

read -r -a presets <<< "$MAPLIBRE_FFI_PRESETS"

if [[ ${1:-} == --local ]]; then
  local_dir="$repo_root/third_party/maplibre-native-ffi"
  for preset in "${presets[@]}"; do
    if [[ "$(cat "$local_dir/$preset/BUILD_INFO" 2>/dev/null)" != "$MAPLIBRE_FFI_COMMIT $preset" ]]; then
      echo "$preset isn't built at $MAPLIBRE_FFI_COMMIT; run scripts/build_maplibre_ffi.sh $preset" >&2
      exit 1
    fi
  done
  xcframework="$local_dir/$fw_name.xcframework"
  slices=$(plutil -extract AvailableLibraries raw "$xcframework/Info.plist")
  if [[ "$slices" != "${#presets[@]}" ]]; then
    echo "$xcframework has $slices slices, not ${#presets[@]}; run scripts/build_maplibre_ffi.sh" >&2
    exit 1
  fi
  zip="$local_dir/$fw_name.xcframework.zip"
  rm -f "$zip"
  ditto -c -k --norsrc --noextattr --noacl --keepParent "$xcframework" "$zip"
  echo "Created $zip from the local build at $MAPLIBRE_FFI_COMMIT"
  shasum -a 256 "$zip" | cut -d" " -f1
  exit 0
fi

release_name=${1:-$MAPLIBRE_FFI_VERSION}
release_dir="$repo_root/third_party/maplibre-native-ffi-release/$release_name"
work_dir="$release_dir/xcframework-work"
zip="$release_dir/$fw_name.xcframework.zip"

rm -rf "$work_dir"
mkdir -p "$work_dir/presets" "$work_dir/stage" "$work_dir/out"
fw_args=()
for preset in "${presets[@]}"; do
  tarball="$release_dir/maplibre-native-c-$preset.tar.gz"
  if [[ ! -f "$tarball" ]]; then
    echo "missing $tarball; run scripts/fetch_ffi_release.sh $*" >&2
    exit 1
  fi
  tar -xzf "$tarball" -C "$work_dir/presets"
  install="$work_dir/presets/maplibre-native-c-$preset"
  # The bundle version is the tarball's version without a pre-release suffix,
  # for example 0.202610.0, or 0.0.0 for a snapshot's 0.0.0-dev.202610140641.
  version=$(sed -n 's/.*"version": "\([^"-]*\).*/\1/p' "$install/share/maplibre-native-c/artifact.json")
  fw_args+=(-framework "$(make_framework "$install" "$preset" "$work_dir/stage" "$version")")
done

xcodebuild -create-xcframework "${fw_args[@]}" -output "$work_dir/out/$fw_name.xcframework" >/dev/null
rm -f "$zip"
# --keepParent puts MaplibreNativeC.xcframework/ at the zip's top level, and
# ditto keeps the macOS framework's symlinks. Without --norsrc and --noextattr,
# ditto stores extended attributes, such as com.apple.provenance, as ._ files,
# which Swift Package Manager's unzip extracts into the frameworks.
ditto -c -k --norsrc --noextattr --noacl --keepParent "$work_dir/out/$fw_name.xcframework" "$zip"
rm -rf "$work_dir"

echo "Created $zip with ${#presets[@]} slices"
# The SHA-256 of the zip, as `swift package compute-checksum` prints it,
# without the .build directory that it creates in the working directory.
shasum -a 256 "$zip" | cut -d" " -f1
