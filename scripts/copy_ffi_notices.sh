#!/usr/bin/env bash
# Copies the third-party notices of the MapLibre Native FFI release in
# packages/mapigrade/maplibre_ffi.lock into
# packages/mapigrade/notices/, unchanged (design D91 and D92 of the
# third-party-notices change, D108 of the publish-readiness change, D217 of the
# update-ffi-0-202610-3 change). It reads the release tarballs that
# scripts/fetch_ffi_release.sh downloads into
# third_party/maplibre-native-ffi-release/<version>/. While the lock names no
# release, it reads the installs that scripts/build_maplibre_ffi.sh made of
# MAPLIBRE_FFI_COMMIT in third_party/maplibre-native-ffi/<preset>/ instead
# (design D219 of the port-ffi-gesture-recognizer change). The copies are
# committed with a change to maplibre_ffi.lock.
#
#   scripts/fetch_ffi_release.sh     # or scripts/build_maplibre_ffi.sh
#   scripts/copy_ffi_notices.sh
#
# The notices are share/maplibre-native-c/LICENSE and the files in
# share/maplibre-native-c/licenses/ of each tarball or install of the presets in
# MAPLIBRE_FFI_PRESETS and MAPLIBRE_FFI_ANDROID_PRESETS. LICENSE is copied as
# maplibre-native-ffi.txt, and a file in licenses/ under its own name. A notice
# that the Apple and the Android presets both have with the same content goes
# to common/; otherwise the Apple presets' copy goes to darwin/ and the Android
# presets' copy to android/ (design D227 of the port-ffi-gesture-recognizer
# change). An HTML notice, such as rust-std.html, is copied as its text in a
# .txt file of the same base name, which scripts/html_notice_to_text.py writes
# (D248), so that the license page shows no markup. The script replaces notices/ as a whole, so a notice that the FFI no
# longer has is removed. It fails, names the file and changes nothing when a
# tarball isn't fetched or a preset isn't installed at the commit, or when two
# Apple presets, or two Android presets, have a notice with the same name and
# different content.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../packages/mapigrade/maplibre_ffi.lock
source "$repo_root/packages/mapigrade/maplibre_ffi.lock"

release_dir="$repo_root/third_party/maplibre-native-ffi-release/$MAPLIBRE_FFI_VERSION"
install_dir="$repo_root/third_party/maplibre-native-ffi"
notices_dir="$repo_root/packages/mapigrade/notices"

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
  share="$stage/tarballs/maplibre-native-c-$preset/share/maplibre-native-c"
  if [[ -z "$MAPLIBRE_FFI_VERSION" ]]; then
    if [[ "$(cat "$install_dir/$preset/BUILD_INFO" 2>/dev/null)" != "$MAPLIBRE_FFI_COMMIT $preset" ]]; then
      echo "$install_dir/$preset isn't a build of $MAPLIBRE_FFI_COMMIT; run scripts/build_maplibre_ffi.sh" >&2
      exit 1
    fi
    mkdir -p "$(dirname "$share")"
    cp -R "$install_dir/$preset/share/maplibre-native-c" "$share"
  else
    tarball="$release_dir/maplibre-native-c-$preset.tar.gz"
    if [[ ! -f "$tarball" ]]; then
      echo "$tarball doesn't exist; run scripts/fetch_ffi_release.sh" >&2
      exit 1
    fi
    mkdir -p "$stage/tarballs"
    tar -xzf "$tarball" -C "$stage/tarballs" \
      "maplibre-native-c-$preset/share/maplibre-native-c"
  fi
  (cd "$share" && { echo LICENSE; [[ -d licenses ]] && find licenses -type f; } |
    sed "s|\$| $preset|") >> "$listing"
done

# Collects each notice per platform family, darwin or android, in
# $stage/family/<family>/.
while read -r file preset; do
  if [[ "$file" == LICENSE ]]; then
    name=maplibre-native-ffi.txt
  else
    name="${file#licenses/}"
  fi
  family=darwin
  [[ "$preset" == android-* ]] && family=android
  source_file="$stage/tarballs/maplibre-native-c-$preset/share/maplibre-native-c/$file"
  target="$stage/family/$family/$name"
  if [[ -e "$target" ]]; then
    if ! cmp -s "$source_file" "$target"; then
      echo "$preset's $file differs from the notice of another $family preset" >&2
      exit 1
    fi
  else
    mkdir -p "$(dirname "$target")"
    cp "$source_file" "$target"
  fi
done < "$listing"

mkdir -p "$stage/notices"
for family in darwin android; do
  [[ -d "$stage/family/$family" ]] || continue
  (cd "$stage/family/$family" && find . -type f | sed 's|^\./||') |
    while read -r name; do
      other=android
      [[ "$family" == android ]] && other=darwin
      if [[ -e "$stage/family/$other/$name" ]] &&
        cmp -s "$stage/family/$family/$name" "$stage/family/$other/$name"; then
        target=common
      else
        target=$family
      fi
      mkdir -p "$stage/notices/$target/$(dirname "$name")"
      if [[ "$name" == *.html ]]; then
        python3 -I "$repo_root/scripts/html_notice_to_text.py" \
          "$stage/family/$family/$name" > "$stage/notices/$target/${name%.html}.txt"
      else
        cp "$stage/family/$family/$name" "$stage/notices/$target/$name"
      fi
    done
done

rm -rf "$notices_dir"
mkdir -p "$notices_dir"
cp -R "$stage/notices/." "$notices_dir/"
echo "Copied the notices of ${MAPLIBRE_FFI_VERSION:-$MAPLIBRE_FFI_COMMIT} (${presets[*]}) into $notices_dir"
