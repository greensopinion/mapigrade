#!/usr/bin/env bash
# Clones MapLibre Native FFI at the commit in scripts/maplibre_ffi.lock,
# applies the patches in scripts/patches/, builds the presets listed in the
# lock file (or the ones given as arguments), and installs each into
# third_party/maplibre-native-ffi/<preset>/. It combines every installed Apple
# preset into third_party/maplibre-native-ffi/MapLibreNativeC.xcframework. For
# Android presets, it also builds the FFI's patched rustls-platform-verifier
# Android component and installs it into the Maven repository
# third_party/maplibre-native-ffi/android-maven/. It copies the third-party
# notices of the presets it built into packages/flutter_mapigrade/notices/
# with scripts/copy_ffi_notices.sh.
#
#   scripts/build_maplibre_ffi.sh                     # all presets
#   scripts/build_maplibre_ffi.sh ios-arm64-metal     # one preset; the
#                                                     # xcframework keeps the
#                                                     # other installed slices
#   scripts/build_maplibre_ffi.sh android-arm64-egl   # one Android preset; the
#                                                     # xcframework is unchanged
#
# Requires: git, Xcode with the macOS and iOS SDKs, and mise
# (https://mise.jdx.dev). The script installs CMake, Ninja, Rust and
# cargo-about through mise, at the versions that the FFI repository's mise.toml
# pins. Android presets also require the Android SDK (ANDROID_HOME, or
# ~/Library/Android/sdk) with the NDK version that the FFI's mise.toml pins;
# the script installs the Rust target and the JDK for Gradle through mise.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=maplibre_ffi.lock
source "$repo_root/scripts/maplibre_ffi.lock"

src_dir="$repo_root/third_party/maplibre-native-ffi-src"
out_dir="$repo_root/third_party/maplibre-native-ffi"
fw_name=MapLibreNativeC

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

# Local patches to the FFI, applied on top of the pinned commit. A patch that
# is already applied is skipped, so the script can run again on the same
# checkout.
for patch in "$repo_root"/scripts/patches/maplibre-native-ffi-*.patch; do
  [[ -e "$patch" ]] || continue
  if git -C "$src_dir" apply --reverse --check "$patch" 2>/dev/null; then
    continue
  fi
  git -C "$src_dir" apply "$patch"
  echo "Applied $(basename "$patch")"
done

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

if [[ "$build_android" == true ]]; then
  export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
  # The FFI's CMake presets and Gradle builds read the NDK and CMake versions
  # from these variables, which the FFI's mise.toml sets.
  export MLN_FFI_ANDROID_NDK_VERSION="$(pinned android_ndk_version)"
  export MLN_FFI_ANDROID_CMAKE_VERSION="$(pinned android_cmake_version)"
  if [[ ! -f "$ANDROID_HOME/ndk/$MLN_FFI_ANDROID_NDK_VERSION/build/cmake/android.toolchain.cmake" ]]; then
    echo "Android presets need NDK $MLN_FFI_ANDROID_NDK_VERSION under $ANDROID_HOME" >&2
    exit 1
  fi
  for preset in "${android_presets[@]}"; do
    if [[ " ${presets[*]} " == *" $preset "* ]]; then
      case "$preset" in
        android-arm64-*) with_tools rustup target add aarch64-linux-android ;;
        *) echo "no Rust target known for $preset" >&2; exit 1 ;;
      esac
    fi
  done
  # The FFI's dependency sync for the patched rustls-platform-verifier. The
  # Android presets compile its Rust crate, and the Gradle build below compiles
  # its Kotlin component.
  "$src_dir/.mise/bin/sync-rustls-platform-verifier"
fi

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
  for lib in "$out_dir/$preset"/lib/libmaplibre-native-c.{dylib,so}; do
    if [[ -e "$lib" ]]; then
      ls -l "$lib"
    fi
  done
done

# Copies the presets' third-party notices into the package, which shows them
# in the license registry. The copies are committed with the lock file.
"$repo_root/scripts/copy_ffi_notices.sh" "${presets[@]}"

# Builds the FFI's patched rustls-platform-verifier Android component and
# installs its AAR, with a POM, into a file-based Maven repository. The plugin's
# Gradle build adds the repository and depends on
# org.maplibre.nativeffi:rustls-platform-verifier-android:<version>, where the
# version is the first 12 characters of the FFI commit.
if [[ "$build_android" == true ]]; then
  verifier_version="${MAPLIBRE_FFI_COMMIT:0:12}"
  # Runs from this repository's root for the reason with_tools() states.
  (cd "$repo_root" && mise exec "java@$(pinned java_version)" -- \
    "$src_dir/gradlew" --quiet -p "$src_dir" \
    :bindings:rustls-platform-verifier-android:bundleReleaseAar)
  aar=$(find "$src_dir/bindings/rustls-platform-verifier-android/build/outputs/aar" -name '*-release.aar' | head -n 1)
  maven_dir="$out_dir/android-maven/org/maplibre/nativeffi/rustls-platform-verifier-android"
  rm -rf "$maven_dir"
  mkdir -p "$maven_dir/$verifier_version"
  cp "$aar" "$maven_dir/$verifier_version/rustls-platform-verifier-android-$verifier_version.aar"
  cat > "$maven_dir/$verifier_version/rustls-platform-verifier-android-$verifier_version.pom" <<POM
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>org.maplibre.nativeffi</groupId>
  <artifactId>rustls-platform-verifier-android</artifactId>
  <version>$verifier_version</version>
  <packaging>aar</packaging>
  <description>rustls-platform-verifier Android component as patched by MapLibre Native FFI $MAPLIBRE_FFI_COMMIT</description>
  <licenses>
    <license><name>Apache-2.0</name></license>
    <license><name>MIT</name></license>
  </licenses>
</project>
POM
  echo "Installed rustls-platform-verifier-android $verifier_version into $out_dir/android-maven"
fi

if [[ "$build_apple" != true ]]; then
  exit 0
fi

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
