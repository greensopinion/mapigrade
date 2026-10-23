#!/usr/bin/env bash
# Copies the third-party notices of the MapLibre Native FFI release in
# packages/flutter_mapigrade/maplibre_ffi.lock into
# packages/flutter_mapigrade/notices/, unchanged (design D91 and D92 of the
# third-party-notices change, D108 of the publish-readiness change). It reads
# the release tarballs that scripts/fetch_ffi_release.sh downloads into
# third_party/maplibre-native-ffi-release/<version>/. The copies are committed
# with a change to maplibre_ffi.lock.
#
#   scripts/fetch_ffi_release.sh
#   scripts/copy_ffi_notices.sh
#
# The notices are share/maplibre-native-c/LICENSE and the files in
# share/maplibre-native-c/licenses/ of each tarball of the presets in
# MAPLIBRE_FFI_PRESETS and MAPLIBRE_FFI_ANDROID_PRESETS. The script fails,
# names the file and changes nothing when a tarball isn't fetched, when a
# preset's tarball has a notice that the tables below don't list, or when a
# common notice differs between two presets.
#
# The Dart registration (lib/src/notices/third_party_notices.dart) and the
# package's tests (test/notices/) list the same files. A new file goes in all
# three, and in the package's pubspec.yaml if it needs a new directory.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../packages/flutter_mapigrade/maplibre_ffi.lock
source "$repo_root/packages/flutter_mapigrade/maplibre_ffi.lock"

release_dir="$repo_root/third_party/maplibre-native-ffi-release/$MAPLIBRE_FFI_VERSION"
notices_dir="$repo_root/packages/flutter_mapigrade/notices"

# "<path in share/maplibre-native-c/> <path in notices/>". The tarball of every
# preset has the common notices.
common_notices=(
  "LICENSE common/maplibre-native-ffi.txt"
  "licenses/maplibre-native.md common/maplibre-native.md"
  "licenses/icu.txt common/icu.txt"
  "licenses/fastpfor.txt common/fastpfor.txt"
  "licenses/nunicode.txt common/nunicode.txt"
  "licenses/pmtiles.txt common/pmtiles.txt"
)
# The tarballs of Android presets also have these.
android_notices=(
  "licenses/rust.md android/rust.md"
  "licenses/cxx-runtime.txt android/cxx-runtime.txt"
  "licenses/kotlin.txt android/kotlin.txt"
  "licenses/kotlin-notice.txt android/kotlin-notice.txt"
  "licenses/rustls-platform-verifier-notice.txt android/rustls-platform-verifier-notice.txt"
)

read -r -a presets <<< "$MAPLIBRE_FFI_PRESETS $MAPLIBRE_FFI_ANDROID_PRESETS"

# The copies are collected in a staging directory first, so that a failure
# leaves notices/ unchanged.
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

for preset in "${presets[@]}"; do
  tarball="$release_dir/maplibre-native-c-$preset.tar.gz"
  if [[ ! -f "$tarball" ]]; then
    echo "$tarball doesn't exist; run scripts/fetch_ffi_release.sh" >&2
    exit 1
  fi
  mkdir -p "$stage/tarballs"
  tar -xzf "$tarball" -C "$stage/tarballs" \
    "maplibre-native-c-$preset/share/maplibre-native-c"
  share="$stage/tarballs/maplibre-native-c-$preset/share/maplibre-native-c"
  notices=("${common_notices[@]}")
  if [[ "$preset" == android-* ]]; then
    notices+=("${android_notices[@]}")
  fi

  installed="LICENSE"
  if [[ -d "$share/licenses" ]]; then
    installed="$installed $(cd "$share" && find licenses -type f | sort | tr '\n' ' ')"
  fi
  for file in $installed; do
    listed=false
    for entry in "${notices[@]}"; do
      if [[ "${entry%% *}" == "$file" ]]; then
        listed=true
      fi
    done
    if [[ "$listed" != true ]]; then
      echo "$preset's tarball has $file, which scripts/copy_ffi_notices.sh doesn't list for $preset; add it to the tables" >&2
      exit 1
    fi
  done

  for entry in "${notices[@]}"; do
    source_file="$share/${entry%% *}"
    target="${entry##* }"
    if [[ ! -f "$source_file" ]]; then
      echo "$preset's tarball has no ${entry%% *}" >&2
      exit 1
    fi
    if [[ -e "$stage/notices/$target" ]]; then
      if ! cmp -s "$source_file" "$stage/notices/$target"; then
        echo "$preset's ${entry%% *} differs from the same notice of another preset" >&2
        exit 1
      fi
    else
      mkdir -p "$stage/notices/$(dirname "$target")"
      cp "$source_file" "$stage/notices/$target"
    fi
  done
done

mkdir -p "$notices_dir"
cp -R "$stage/notices/." "$notices_dir/"
echo "Copied the notices of $MAPLIBRE_FFI_VERSION (${presets[*]}) into $notices_dir"
