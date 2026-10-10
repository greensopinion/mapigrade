#!/usr/bin/env bash
# Clones MapLibre Native FFI at the commit in scripts/maplibre_ffi.lock, builds
# the macos-arm64-metal preset, and installs the library and headers into
# third_party/maplibre-native-ffi/.
#
# Requires: git, Xcode with the macOS SDK, and mise (https://mise.jdx.dev).
# The script installs CMake, Ninja, Rust and cargo-about through mise, at the
# versions that the FFI repository's mise.toml pins.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=maplibre_ffi.lock
source "$repo_root/scripts/maplibre_ffi.lock"

src_dir="$repo_root/third_party/maplibre-native-ffi-src"
out_dir="$repo_root/third_party/maplibre-native-ffi"

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

start=$(date +%s)
with_tools cmake -S "$src_dir" --preset "$MAPLIBRE_FFI_PRESET"
with_tools cmake --build "$src_dir/build/$MAPLIBRE_FFI_PRESET" --target install
end=$(date +%s)

rm -rf "$out_dir"
mkdir -p "$out_dir"
cp -R "$src_dir/build/$MAPLIBRE_FFI_PRESET/install/." "$out_dir/"
printf '%s %s\n' "$MAPLIBRE_FFI_COMMIT" "$MAPLIBRE_FFI_PRESET" > "$out_dir/BUILD_INFO"

# Wraps the dylib in a versioned macOS framework inside an xcframework, which
# is the form Swift Package Manager accepts as a binary target. The Flutter
# plugin links it and Xcode embeds and signs it in the app bundle.
fw_name=MapLibreNativeC
fw_stage="$out_dir/framework"
fw="$fw_stage/$fw_name.framework"
mkdir -p "$fw/Versions/A/Headers" "$fw/Versions/A/Modules" "$fw/Versions/A/Resources"
cp "$out_dir/lib/libmaplibre-native-c.dylib" "$fw/Versions/A/$fw_name"
install_name_tool -id "@rpath/$fw_name.framework/Versions/A/$fw_name" "$fw/Versions/A/$fw_name"
cp -R "$out_dir/include/maplibre_native_c.h" "$out_dir/include/maplibre_native_c" "$fw/Versions/A/Headers/"
cat > "$fw/Versions/A/Modules/module.modulemap" <<EOF
framework module $fw_name {
  umbrella header "maplibre_native_c.h"
  export *
}
EOF
cat > "$fw/Versions/A/Resources/Info.plist" <<EOF
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
  <key>LSMinimumSystemVersion</key><string>14.3</string>
</dict>
</plist>
EOF
ln -s A "$fw/Versions/Current"
for item in "$fw_name" Headers Modules Resources; do
  ln -s "Versions/Current/$item" "$fw/$item"
done
xcodebuild -create-xcframework -framework "$fw" -output "$out_dir/$fw_name.xcframework" >/dev/null
rm -rf "$fw_stage"

echo "Built $MAPLIBRE_FFI_PRESET at $MAPLIBRE_FFI_COMMIT in $((end - start)) s"
find "$out_dir/lib" -name 'libmaplibre-native-c*.dylib' -type f -exec ls -l {} \;
