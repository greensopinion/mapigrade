#!/usr/bin/env bash
# Copies the third-party notices of MapLibre Native FFI presets, installed by
# scripts/build_maplibre_ffi.sh in
# third_party/maplibre-native-ffi/<preset>/share/maplibre-native-c/, into
# packages/flutter_mapigrade/notices/, unchanged (design D91 and D92 of the
# third-party-notices change). build_maplibre_ffi.sh runs it with the presets
# it built. The copies are committed with a change to maplibre_ffi.lock.
#
#   scripts/copy_ffi_notices.sh macos-arm64-metal android-arm64-egl
#
# The notices are share/maplibre-native-c/LICENSE and the files in
# share/maplibre-native-c/licenses/. The script fails, names the file and
# changes nothing when a preset wasn't built at the pinned commit, when a
# preset installs a notice that the tables below don't list, or when a common
# notice differs between two of the given presets.
#
# The Dart registration (lib/src/notices/third_party_notices.dart) and the
# package's tests (test/notices/) list the same files. A new file goes in all
# three, and in the package's pubspec.yaml if it needs a new directory.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=maplibre_ffi.lock
source "$repo_root/scripts/maplibre_ffi.lock"

ffi_dir="$repo_root/third_party/maplibre-native-ffi"
notices_dir="$repo_root/packages/flutter_mapigrade/notices"

# "<path in share/maplibre-native-c/> <path in notices/>". Every preset
# installs the common notices.
common_notices=(
  "LICENSE common/maplibre-native-ffi.txt"
  "licenses/maplibre-native.md common/maplibre-native.md"
  "licenses/icu.txt common/icu.txt"
  "licenses/fastpfor.txt common/fastpfor.txt"
  "licenses/nunicode.txt common/nunicode.txt"
  "licenses/pmtiles.txt common/pmtiles.txt"
)
# Android presets also install these.
android_notices=(
  "licenses/rust.md android/rust.md"
  "licenses/cxx-runtime.txt android/cxx-runtime.txt"
)

if [[ $# -eq 0 ]]; then
  echo "usage: $0 <preset>..." >&2
  exit 1
fi

# The copies are collected in a staging directory first, so that a failure
# leaves notices/ unchanged.
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

for preset in "$@"; do
  share="$ffi_dir/$preset/share/maplibre-native-c"
  if [[ "$(cat "$ffi_dir/$preset/BUILD_INFO" 2>/dev/null)" != "$MAPLIBRE_FFI_COMMIT $preset" ]]; then
    echo "$preset is not installed at the pinned commit $MAPLIBRE_FFI_COMMIT" >&2
    exit 1
  fi
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
      echo "$preset installs $file, which scripts/copy_ffi_notices.sh doesn't list for $preset; add it to the tables" >&2
      exit 1
    fi
  done

  for entry in "${notices[@]}"; do
    source_file="$share/${entry%% *}"
    target="${entry##* }"
    if [[ ! -f "$source_file" ]]; then
      echo "$preset doesn't install ${entry%% *}" >&2
      exit 1
    fi
    if [[ -e "$stage/$target" ]]; then
      if ! cmp -s "$source_file" "$stage/$target"; then
        echo "$preset's ${entry%% *} differs from the same notice of another given preset" >&2
        exit 1
      fi
    else
      mkdir -p "$stage/$(dirname "$target")"
      cp "$source_file" "$stage/$target"
    fi
  done
done

mkdir -p "$notices_dir"
cp -R "$stage/." "$notices_dir/"
echo "Copied the notices of $* into $notices_dir"
