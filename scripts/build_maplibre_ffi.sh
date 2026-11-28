#!/usr/bin/env bash
# Clones MapLibre Native FFI at the commit in
# packages/flutter_mapigrade/maplibre_ffi.lock, builds the presets listed in the
# lock file (or the ones given as arguments) with the FFI's own mise tasks, and
# installs each into third_party/maplibre-native-ffi/<preset>/. It combines the
# MaplibreNativeC.framework that the install of every Apple preset creates into
# third_party/maplibre-native-ffi/MaplibreNativeC.xcframework, which
# darwin/flutter_mapigrade/Package.swift uses, and deletes Swift Package
# Manager's manifest cache so that the next build does. Android builds use the
# install of each Android preset through the Gradle property mapigrade.ffiDir.
#
#   scripts/build_maplibre_ffi.sh                  # all presets
#   scripts/build_maplibre_ffi.sh ios-arm64        # one preset; the xcframework
#                                                  # keeps the other installed
#                                                  # slices
#   scripts/build_maplibre_ffi.sh android-arm64    # one Android preset; the
#                                                  # xcframework is unchanged
#
# Requires: git, Xcode with the macOS and iOS SDKs, and mise
# (https://mise.jdx.dev). The script trusts the FFI checkout's mise
# configuration and installs the tools it pins, including Rust, CMake and Ninja.
# Android presets also require the Android SDK (ANDROID_HOME, or
# ~/Library/Android/sdk); the FFI's build installs the NDK and CMake versions it
# pins into that SDK.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../packages/flutter_mapigrade/maplibre_ffi.lock
source "$repo_root/packages/flutter_mapigrade/maplibre_ffi.lock"

src_dir="$repo_root/third_party/maplibre-native-ffi-src"
out_dir="$repo_root/third_party/maplibre-native-ffi"
fw_name=MaplibreNativeC

read -r -a all_presets <<< "$MAPLIBRE_FFI_PRESETS"
read -r -a android_presets <<< "$MAPLIBRE_FFI_ANDROID_PRESETS"
if [[ $# -gt 0 ]]; then
  presets=("$@")
else
  presets=("${all_presets[@]}" "${android_presets[@]}")
fi
build_apple=false
build_android=false
for preset in "${presets[@]}"; do
  if [[ " ${all_presets[*]} " == *" $preset "* ]]; then
    build_apple=true
  elif [[ " ${android_presets[*]} " == *" $preset "* ]]; then
    build_android=true
  else
    echo "unknown preset: $preset (expected one of: ${all_presets[*]} ${android_presets[*]})" >&2
    exit 1
  fi
done

if [[ ! -d "$src_dir/.git" ]]; then
  git clone "$MAPLIBRE_FFI_REPO" "$src_dir"
fi
git -C "$src_dir" fetch --quiet origin "$MAPLIBRE_FFI_COMMIT" || true
git -C "$src_dir" checkout --quiet --detach "$MAPLIBRE_FFI_COMMIT"

# The FFI's tasks sync its submodules (mln-rs and the headers it needs) and
# apply its patches to them before each build. Its bootstrap also installs
# Homebrew packages for bindings that this build doesn't use, so only the tools
# are installed.
cd "$src_dir"
mise trust --quiet "$src_dir/.config/mise.toml"
mise bootstrap --yes --only tools
if [[ "$build_android" == true ]]; then
  export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
fi

for preset in "${presets[@]}"; do
  start=$(date +%s)
  if [[ "$preset" == android-* ]]; then
    mise -E android run build "$preset"
  else
    mise run build "$preset"
  fi
  end=$(date +%s)

  rm -rf "${out_dir:?}/$preset"
  mkdir -p "$out_dir/$preset"
  cp -R "$src_dir/build/$preset/install/." "$out_dir/$preset/"
  # The FFI's build signs only the framework's binary, so the signature's
  # identifier isn't the bundle identifier, and an iPhone refuses to install
  # an app that embeds it. Signing the bundle gives it the bundle identifier.
  if [[ -d "$out_dir/$preset/Frameworks/$fw_name.framework" ]]; then
    codesign --force --sign - "$out_dir/$preset/Frameworks/$fw_name.framework"
  fi
  printf '%s %s\n' "$MAPLIBRE_FFI_COMMIT" "$preset" > "$out_dir/$preset/BUILD_INFO"
  echo "Built $preset at $MAPLIBRE_FFI_COMMIT in $((end - start)) s"
  for lib in "$out_dir/$preset"/lib/libmaplibre-native-c.{dylib,so}; do
    if [[ -e "$lib" ]]; then
      ls -l "$lib"
    fi
  done
done

if [[ "$build_apple" != true ]]; then
  exit 0
fi

# Combines the framework of every installed preset of the pinned commit into
# the xcframework.
fw_args=()
for preset in "${all_presets[@]}"; do
  if [[ "$(cat "$out_dir/$preset/BUILD_INFO" 2>/dev/null)" == "$MAPLIBRE_FFI_COMMIT $preset" ]]; then
    fw_args+=(-framework "$out_dir/$preset/Frameworks/$fw_name.framework")
  else
    echo "Not in the xcframework (not built at the pinned commit): $preset" >&2
  fi
done
rm -rf "$out_dir/$fw_name.xcframework"
xcodebuild -create-xcframework "${fw_args[@]}" -output "$out_dir/$fw_name.xcframework" >/dev/null
echo "Created $out_dir/$fw_name.xcframework with $(( ${#fw_args[@]} / 2 )) slices"

# Swift Package Manager caches the result of evaluating Package.swift by the
# manifest's contents. Deleting the cache makes the next build evaluate it again
# and find the local build.
rm -f "$HOME"/Library/Caches/org.swift.swiftpm/manifests/manifest.db*
echo "Deleted the Swift Package Manager manifest cache"
