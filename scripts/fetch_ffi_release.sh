#!/usr/bin/env bash
# Downloads the MapLibre Native FFI release tarballs that the package uses, and
# the release's SHA256SUMS, for MAPLIBRE_FFI_VERSION in
# packages/flutter_mapigrade/maplibre_ffi.lock, into
# third_party/maplibre-native-ffi-release/<version>/ (design D106 of the
# publish-readiness change). It checks every tarball against SHA256SUMS, and
# skips a file that is already present and, for a tarball, matches SHA256SUMS.
#
#   scripts/fetch_ffi_release.sh
#   scripts/fetch_ffi_release.sh unstable-native-snapshot
#
# A release tag as argument fetches that release into
# third_party/maplibre-native-ffi-release/<tag>/ in place of the pinned
# version. Stage 0 of the change uses it for unstable-native-snapshot, whose
# assets upstream replaces: delete the directory to fetch a newer snapshot.
#
# The tarballs are maplibre-native-c-<preset>.tar.gz for the presets in
# MAPLIBRE_FFI_PRESETS and MAPLIBRE_FFI_ANDROID_PRESETS. The script fails and
# names the tarball when one doesn't match SHA256SUMS; delete the file and run
# the script again to download it again.
#
# Requires: curl and shasum.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../packages/flutter_mapigrade/maplibre_ffi.lock
source "$repo_root/packages/flutter_mapigrade/maplibre_ffi.lock"

if [[ $# -gt 0 ]]; then
  release_tag=$1
  release_name=$1
else
  release_tag="core/v$MAPLIBRE_FFI_VERSION"
  release_name=$MAPLIBRE_FFI_VERSION
fi
release_url="https://github.com/maplibre/maplibre-native-ffi/releases/download/$release_tag"
release_dir="$repo_root/third_party/maplibre-native-ffi-release/$release_name"

read -r -a presets <<< "$MAPLIBRE_FFI_PRESETS $MAPLIBRE_FFI_ANDROID_PRESETS"

# Downloads a release asset to $release_dir/$1, through a temporary file, so
# that an interrupted download leaves no file behind.
download() {
  local name=$1
  echo "Downloading $name"
  curl --fail --silent --show-error --location --retry 3 \
    --output "$release_dir/$name.part" "$release_url/$name"
  mv "$release_dir/$name.part" "$release_dir/$name"
}

# Prints the SHA256SUMS entry for a file, or fails if there is none.
expected_sum() {
  local name=$1 sum
  sum=$(awk -v name="$name" '$2 == name || $2 == "*" name { print $1 }' "$release_dir/SHA256SUMS")
  if [[ -z "$sum" ]]; then
    echo "SHA256SUMS of $release_name has no entry for $name" >&2
    exit 1
  fi
  echo "$sum"
}

actual_sum() {
  shasum -a 256 "$release_dir/$1" | awk '{ print $1 }'
}

mkdir -p "$release_dir"
if [[ ! -f "$release_dir/SHA256SUMS" ]]; then
  download SHA256SUMS
fi

for preset in "${presets[@]}"; do
  name="maplibre-native-c-$preset.tar.gz"
  expected=$(expected_sum "$name")
  if [[ ! -f "$release_dir/$name" ]]; then
    download "$name"
  fi
  if [[ "$(actual_sum "$name")" != "$expected" ]]; then
    echo "$release_dir/$name doesn't match SHA256SUMS of $release_name" >&2
    exit 1
  fi
  echo "Checked $name"
done
