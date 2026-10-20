#!/usr/bin/env bash
# Clones MapLibre Native FFI at the commit in
# packages/flutter_mapigrade/maplibre_ffi.lock,
# applies the patches in scripts/patches/, builds the presets listed in the
# lock file (or the ones given as arguments), and installs each into
# third_party/maplibre-native-ffi/<preset>/. It combines the
# MaplibreNativeC.framework that the install of every Apple preset creates into
# third_party/maplibre-native-ffi/MaplibreNativeC.xcframework, which
# darwin/flutter_mapigrade/Package.swift uses in place of the remote zip, and
# deletes Swift Package Manager's manifest cache so that the next build does. For
# Android presets, it also builds the FFI's patched rustls-platform-verifier
# Android component and installs it into the Maven repository
# third_party/maplibre-native-ffi/android-maven/. It doesn't copy the
# third-party notices, because the local build may be at a commit without a
# release: scripts/copy_ffi_notices.sh copies them from the pinned release.
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

# Package.swift uses the xcframework only when it exists, but Swift Package
# Manager caches the result of evaluating Package.swift by the manifest's
# contents. Deleting the cache makes the next build evaluate it again and use
# the local build in place of the remote zip.
rm -f "$HOME"/Library/Caches/org.swift.swiftpm/manifests/manifest.db*
echo "Deleted the Swift Package Manager manifest cache"
