#!/usr/bin/env bash
# Clones MapLibre Native FFI at the commit in scripts/maplibre_ffi.lock, builds
# the presets listed there (or the ones given as arguments), installs each into
# third_party/maplibre-native-ffi/<preset>/, and combines every installed
# preset into third_party/maplibre-native-ffi/MapLibreNativeC.xcframework.
#
#   scripts/build_maplibre_ffi.sh                     # all presets
#   scripts/build_maplibre_ffi.sh ios-arm64-metal     # one preset; the
#                                                     # xcframework keeps the
#                                                     # other installed slices
#
# Requires: git, Xcode with the macOS and iOS SDKs, and mise
# (https://mise.jdx.dev). The script installs CMake, Ninja, Rust and
# cargo-about through mise, at the versions that the FFI repository's mise.toml
# pins.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=maplibre_ffi.lock
source "$repo_root/scripts/maplibre_ffi.lock"

src_dir="$repo_root/third_party/maplibre-native-ffi-src"
out_dir="$repo_root/third_party/maplibre-native-ffi"
fw_name=MapLibreNativeC

read -r -a all_presets <<< "$MAPLIBRE_FFI_PRESETS"
if [[ $# -gt 0 ]]; then
  presets=("$@")
else
  presets=("${all_presets[@]}")
fi
for preset in "${presets[@]}"; do
  if [[ " ${all_presets[*]} " != *" $preset "* ]]; then
    echo "unknown preset: $preset (expected one of: ${all_presets[*]})" >&2
    exit 1
  fi
done

if [[ ! -d "$src_dir/.git" ]]; then
  git clone "$MAPLIBRE_FFI_REPO" "$src_dir"
fi
git -C "$src_dir" fetch --quiet origin "$MAPLIBRE_FFI_COMMIT" || true
git -C "$src_dir" checkout --quiet --detach "$MAPLIBRE_FFI_COMMIT"

# Reads a version from the [vars] table of the FFI repository's mise.toml.
pinned() {
  sed -n "s/^$1 = \"\(.*\)\"/\1/p" "$src_dir/mise.toml"
}

tools=(
  "aqua:Kitware/CMake@$(pinned cmake_version)"
  "ninja@$(pinned ninja_version)"
  "rust@$(pinned rust_version)"
  "github:EmbarkStudios/cargo-about@$(pinned cargo_about_version)"
)

# Runs a command with the pinned tools on PATH. The command runs from this
# repository's root, which has no mise configuration, so mise doesn't read the
# FFI repository's mise.toml and doesn't run its hooks or dependency tasks.
with_tools() {
  (cd "$repo_root" && mise exec "${tools[@]}" -- "$@")
}

# The FFI repository's own submodule sync: a shallow checkout of MapLibre Native
# plus the vendor submodules the build needs, and the patches the FFI carries.
"$src_dir/.mise/bin/sync-submodules"

# Writes the framework Info.plist for a preset to $1.
write_info_plist() {
  local plist=$1 preset=$2 platform_keys
  case "$preset" in
    macos-*)
      platform_keys="<key>LSMinimumSystemVersion</key><string>14.3</string>" ;;
    ios-simulator-*)
      platform_keys="<key>MinimumOSVersion</key><string>15.5</string>
  <key>CFBundleSupportedPlatforms</key><array><string>iPhoneSimulator</string></array>" ;;
    ios-*)
      platform_keys="<key>MinimumOSVersion</key><string>15.5</string>
  <key>CFBundleSupportedPlatforms</key><array><string>iPhoneOS</string></array>" ;;
  esac
  cat > "$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>$fw_name</string>
  <key>CFBundleIdentifier</key><string>org.maplibre.$fw_name</string>
  <key>CFBundleName</key><string>$fw_name</string>
  <key>CFBundlePackageType</key><string>FMWK</string>
  <key>CFBundleShortVersionString</key><string>0.0.0</string>
  <key>CFBundleVersion</key><string>${MAPLIBRE_FFI_COMMIT:0:12}</string>
  $platform_keys
</dict>
</plist>
PLIST
}

# Wraps the dylib of an installed preset in a framework under $2: the versioned
# layout on macOS, the flat layout on iOS. Swift Package Manager accepts the
# frameworks as a binary target once they are combined into an xcframework, and
# Xcode embeds and signs the framework in the app bundle.
make_framework() {
  local preset=$1 stage=$2 install="$out_dir/$1"
  local fw="$stage/$preset/$fw_name.framework" contents
  if [[ "$preset" == macos-* ]]; then
    contents="$fw/Versions/A"
  else
    contents="$fw"
  fi
  mkdir -p "$contents/Headers" "$contents/Modules"
  cp "$install/lib/libmaplibre-native-c.dylib" "$contents/$fw_name"
  if [[ "$preset" == macos-* ]]; then
    install_name_tool -id "@rpath/$fw_name.framework/Versions/A/$fw_name" "$contents/$fw_name"
  else
    install_name_tool -id "@rpath/$fw_name.framework/$fw_name" "$contents/$fw_name"
  fi
  cp -R "$install/include/maplibre_native_c.h" "$install/include/maplibre_native_c" "$contents/Headers/"
  cat > "$contents/Modules/module.modulemap" <<MODULEMAP
framework module $fw_name {
  umbrella header "maplibre_native_c.h"
  export *
}
MODULEMAP
  if [[ "$preset" == macos-* ]]; then
    mkdir -p "$contents/Resources"
    write_info_plist "$contents/Resources/Info.plist" "$preset"
    ln -s A "$fw/Versions/Current"
    for item in "$fw_name" Headers Modules Resources; do
      ln -s "Versions/Current/$item" "$fw/$item"
    done
  else
    write_info_plist "$contents/Info.plist" "$preset"
  fi
  echo "$fw"
}

for preset in "${presets[@]}"; do
  start=$(date +%s)
  with_tools cmake -S "$src_dir" --preset "$preset"
  with_tools cmake --build "$src_dir/build/$preset" --target install
  end=$(date +%s)

  rm -rf "${out_dir:?}/$preset"
  mkdir -p "$out_dir/$preset"
  cp -R "$src_dir/build/$preset/install/." "$out_dir/$preset/"
  printf '%s %s\n' "$MAPLIBRE_FFI_COMMIT" "$preset" > "$out_dir/$preset/BUILD_INFO"
  echo "Built $preset at $MAPLIBRE_FFI_COMMIT in $((end - start)) s"
  ls -l "$out_dir/$preset/lib/libmaplibre-native-c.dylib"
done

# Combines every installed preset of the pinned commit into the xcframework.
stage="$out_dir/framework-stage"
rm -rf "$stage"
fw_args=()
for preset in "${all_presets[@]}"; do
  if [[ "$(cat "$out_dir/$preset/BUILD_INFO" 2>/dev/null)" == "$MAPLIBRE_FFI_COMMIT $preset" ]]; then
    fw_args+=(-framework "$(make_framework "$preset" "$stage")")
  else
    echo "Not in the xcframework (not built at the pinned commit): $preset" >&2
  fi
done
rm -rf "$out_dir/$fw_name.xcframework"
xcodebuild -create-xcframework "${fw_args[@]}" -output "$out_dir/$fw_name.xcframework" >/dev/null
rm -rf "$stage"
echo "Created $out_dir/$fw_name.xcframework with $(( ${#fw_args[@]} / 2 )) slices"
