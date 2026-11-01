#!/usr/bin/env bash
# Copies the third-party notices of the MapLibre Native FFI release in
# packages/flutter_mapigrade/maplibre_ffi.lock into
# packages/flutter_mapigrade/notices/, unchanged (design D91 and D92 of the
# third-party-notices change, D108 of the publish-readiness change, D217 of the
# update-ffi-0-202610-3 change). It reads the release tarballs that
# scripts/fetch_ffi_release.sh downloads into
# third_party/maplibre-native-ffi-release/<version>/. The copies are committed
# with a change to maplibre_ffi.lock.
#
#   scripts/fetch_ffi_release.sh
#   scripts/copy_ffi_notices.sh
#
# The notices are share/maplibre-native-c/LICENSE and the files in
# share/maplibre-native-c/licenses/ of each tarball of the presets in
# MAPLIBRE_FFI_PRESETS and MAPLIBRE_FFI_ANDROID_PRESETS. LICENSE goes to
# common/maplibre-native-ffi.txt. A file in licenses/ goes to android/ when only
# the Android presets' tarballs have it, and otherwise to common/. The script
# replaces notices/ as a whole, so a notice that the release no longer has is
# removed. It fails, names the file and changes nothing when a tarball isn't
# fetched, or when two tarballs have a notice with the same name and different
# content.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../packages/flutter_mapigrade/maplibre_ffi.lock
source "$repo_root/packages/flutter_mapigrade/maplibre_ffi.lock"

release_dir="$repo_root/third_party/maplibre-native-ffi-release/$MAPLIBRE_FFI_VERSION"
notices_dir="$repo_root/packages/flutter_mapigrade/notices"

read -r -a presets <<< "$MAPLIBRE_FFI_PRESETS $MAPLIBRE_FFI_ANDROID_PRESETS"

# The copies are collected in a staging directory first, so that a failure
# leaves notices/ unchanged.
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

# "<file> <preset>" for each notice file of each tarball, where <file> is
# relative to share/maplibre-native-c/.
listing="$stage/listing"
: > "$listing"
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
  (cd "$share" && { echo LICENSE; [[ -d licenses ]] && find licenses -type f; } |
    sed "s|\$| $preset|") >> "$listing"
done

while read -r file preset; do
  if [[ "$file" == LICENSE ]]; then
    target=common/maplibre-native-ffi.txt
  elif ! awk -v file="$file" '$1 == file && $2 !~ /^android-/ { found = 1 } END { exit !found }' "$listing"; then
    target="android/${file#licenses/}"
  else
    target="common/${file#licenses/}"
  fi
  source_file="$stage/tarballs/maplibre-native-c-$preset/share/maplibre-native-c/$file"
  if [[ -e "$stage/notices/$target" ]]; then
    if ! cmp -s "$source_file" "$stage/notices/$target"; then
      echo "$preset's $file differs from the notice of another preset that the script copies to $target" >&2
      exit 1
    fi
  else
    mkdir -p "$stage/notices/$(dirname "$target")"
    cp "$source_file" "$stage/notices/$target"
  fi
done < "$listing"

rm -rf "$notices_dir"
mkdir -p "$notices_dir"
cp -R "$stage/notices/." "$notices_dir/"
echo "Copied the notices of $MAPLIBRE_FFI_VERSION (${presets[*]}) into $notices_dir"
