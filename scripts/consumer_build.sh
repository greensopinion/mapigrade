#!/usr/bin/env bash
# Builds an application that depends on flutter_mapigrade, with
# flutter_mapigrade and mapigrade as their published archives contain them,
# outside this checkout (design D106 of the publish-readiness change, D233 of
# the split-mapigrade-package change). The workflow consumer-build.yml runs it.
#
#   scripts/consumer_build.sh <work-dir> <platform>...
#
# The platforms are android, ios, macos and web. The script:
#
# 1. Runs `flutter pub publish --dry-run` in packages/mapigrade and
#    packages/flutter_mapigrade, and copies the files that each lists, with
#    symlinks resolved, to <work-dir>/mapigrade and
#    <work-dir>/flutter_mapigrade. Flutter can't write the archive to a file.
# 2. Creates the application <work-dir>/consumer_app with `flutter create`, with
#    a path dependency on the copy of flutter_mapigrade, a dependency override
#    that resolves mapigrade from its copy, and the example's lib/main.dart,
#    and sets the minimum Android SDK and iOS and macOS versions that the package needs.
#    For web it creates a second application, <work-dir>/consumer_web_app,
#    whose lib/main.dart places MapigradeLayer only when
#    MapigradeLayer.isSupported is true, as the package's README shows.
# 3. Builds, per platform: android, a release APK; ios, a simulator build and a
#    device build without code signing; macos, a release build; web, a build
#    compiled to JavaScript and a build compiled to WebAssembly.
# 4. Checks that the APK's lib/ has libmaplibre-native-c.so and
#    libmapigrade.so for arm64-v8a, armeabi-v7a and x86_64, or neither when
#    the lock names no FFI release, and that the iOS and macOS applications
#    contain MaplibreNativeC.framework.
#
# <work-dir> must be outside the checkout, so that a build that reads a file
# through a path outside the package fails. The script deletes and recreates
# <work-dir>/mapigrade, <work-dir>/flutter_mapigrade, <work-dir>/consumer_app
# and <work-dir>/consumer_web_app.
#
# Requires: flutter, python3, unzip; for ios and macos, Xcode.
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "usage: $0 <work-dir> <platform>..." >&2
  exit 2
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
package_dir="$repo_root/packages/flutter_mapigrade"
mkdir -p "$1"
work_dir="$(cd "$1" && pwd -P)"
shift
platforms=("$@")

case "$work_dir/" in
  "$(cd "$repo_root" && pwd -P)/"*)
    echo "The work directory $work_dir is inside the checkout" >&2
    exit 2
    ;;
esac
for platform in "${platforms[@]}"; do
  case $platform in
    android | ios | macos | web) ;;
    *)
      echo "Unknown platform $platform; use android, ios, macos or web" >&2
      exit 2
      ;;
  esac
done

app_dir="$work_dir/consumer_app"
web_app_dir="$work_dir/consumer_web_app"
rm -rf "$work_dir/mapigrade" "$work_dir/flutter_mapigrade" "$app_dir" "$web_app_dir"

# 1. The archives. The dry run prints the file list as a tree: each entry is
# indented by four characters per level and ends with its size, and a
# directory has no size.
copy_archive() {
  local package=$1
  local source_dir="$repo_root/packages/$package"
  local archive_dir="$work_dir/$package"
  local dry_run_output="$work_dir/dry_run_$package.txt"
  local file_list="$work_dir/archive_files_$package.txt"
  echo "== Archive of $package"
  (cd "$source_dir" && flutter pub publish --dry-run) > "$dry_run_output" 2>&1 || {
    cat "$dry_run_output"
    echo "flutter pub publish --dry-run failed in packages/$package" >&2
    exit 1
  }
  python3 - "$dry_run_output" > "$file_list" <<'EOF'
import re
import sys

entry = re.compile(r"^((?:│   |    )*)[├└]── (.+?)(?: \((?:<1|\d+) [KMG]?B\))?$")
sized = re.compile(r" \((?:<1|\d+) [KMG]?B\)$")
path = []
for line in open(sys.argv[1], encoding="utf-8"):
    line = line.rstrip("\n")
    match = entry.match(line)
    if not match:
        continue
    depth = len(match.group(1)) // 4
    name = match.group(2)
    del path[depth:]
    path.append(name)
    if sized.search(line):
        print("/".join(path))
EOF
  if [[ ! -s "$file_list" ]]; then
    cat "$dry_run_output"
    echo "The dry run of $package listed no files" >&2
    exit 1
  fi
  while IFS= read -r file; do
    mkdir -p "$archive_dir/$(dirname "$file")"
    cp -L "$source_dir/$file" "$archive_dir/$file"
  done < "$file_list"
  echo "Copied $(wc -l < "$file_list" | tr -d ' ') files to $archive_dir"
  # The package is a member of this repository's workspace, which the copy is
  # not part of.
  sed -i.bak '/^resolution: workspace$/d' "$archive_dir/pubspec.yaml"
  rm "$archive_dir/pubspec.yaml.bak"
}
copy_archive mapigrade
copy_archive flutter_mapigrade

# 2. The application.
echo "== Application"
(cd "$work_dir" && flutter create --org com.example --platforms android,ios,macos consumer_app)
cp "$package_dir/example/lib/main.dart" "$app_dir/lib/main.dart"
rm -f "$app_dir/test/widget_test.dart"
(
  cd "$app_dir"
  flutter pub add 'flutter_mapigrade:{"path":"../flutter_mapigrade"}' \
    'override:mapigrade:{"path":"../mapigrade"}'
  flutter pub add flutter_map:8.3.2 latlong2:^0.10.1
)
# The minimum versions of the package: iOS 15.0 and macOS 14.3. On Android the
# app keeps Flutter's default minSdk.
sed -i.bak 's/IPHONEOS_DEPLOYMENT_TARGET = [0-9.]*;/IPHONEOS_DEPLOYMENT_TARGET = 15.0;/' \
  "$app_dir/ios/Runner.xcodeproj/project.pbxproj"
sed -i.bak 's/MACOSX_DEPLOYMENT_TARGET = [0-9.]*;/MACOSX_DEPLOYMENT_TARGET = 14.3;/' \
  "$app_dir/macos/Runner.xcodeproj/project.pbxproj"
# The FFI's xcframework has arm64 slices only. As in the example, iOS simulator
# builds exclude x86_64, and macOS builds are arm64 only.
for config in Debug Release; do
  echo 'EXCLUDED_ARCHS[sdk=iphonesimulator*] = x86_64' >> "$app_dir/ios/Flutter/$config.xcconfig"
done
echo 'ARCHS = arm64' >> "$app_dir/macos/Runner/Configs/AppInfo.xcconfig"
# The macOS application loads the style and tiles over the network.
for entitlements in DebugProfile Release; do
  /usr/libexec/PlistBuddy -c "Add :com.apple.security.network.client bool true" \
    "$app_dir/macos/Runner/$entitlements.entitlements" 2>/dev/null || true
done
find "$app_dir" -name '*.bak' -delete

if [[ " ${platforms[*]} " == *" web "* ]]; then
  echo "== Web application"
  (cd "$work_dir" && flutter create --org com.example --platforms web consumer_web_app)
  rm -f "$web_app_dir/test/widget_test.dart"
  (
    cd "$web_app_dir"
    flutter pub add 'flutter_mapigrade:{"path":"../flutter_mapigrade"}' \
      'override:mapigrade:{"path":"../mapigrade"}'
    flutter pub add flutter_map:8.3.2 latlong2:^0.10.1
  )
  cat > "$web_app_dir/lib/main.dart" <<'EOF'
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_mapigrade/flutter_mapigrade.dart';
import 'package:latlong2/latlong.dart';

void main() => runApp(
  MaterialApp(
    home: Scaffold(
      body: FlutterMap(
        options: const MapOptions(initialCenter: LatLng(49.25, -123.1)),
        children: [
          if (MapigradeLayer.isSupported)
            MapigradeLayer(styleUrl: 'https://tiles.openfreemap.org/styles/liberty')
          else
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.consumer_web_app',
            ),
        ],
      ),
    ),
  ),
);
EOF
fi

# 3 and 4. The builds and their checks.
failures=()
fail() {
  echo "FAIL: $1" >&2
  failures+=("$1")
}

for platform in "${platforms[@]}"; do
  case $platform in
    android)
      echo "== Android"
      (cd "$app_dir" && flutter build apk --release)
      apk="$app_dir/build/app/outputs/flutter-apk/app-release.apk"
      apk_files=$(unzip -Z1 "$apk")
      # A prerelease without an FFI release declares no Android plugin, so
      # the APK has neither library (design D253 of the apple-only-beta-release
      # change).
      if grep -qx 'MAPLIBRE_FFI_VERSION=' "$work_dir/mapigrade/maplibre_ffi.lock"; then
        for library in libmaplibre-native-c.so libmapigrade.so; do
          ! grep -q "/$library\$" <<< "$apk_files" \
            || fail "the APK of a prerelease without an FFI release has $library"
        done
      else
        for abi in arm64-v8a armeabi-v7a x86_64; do
          for library in libmaplibre-native-c.so libmapigrade.so; do
            grep -qx "lib/$abi/$library" <<< "$apk_files" \
              || fail "the APK has no lib/$abi/$library"
          done
        done
      fi
      ;;
    ios)
      echo "== iOS"
      (cd "$app_dir" && flutter build ios --simulator --debug)
      [[ -d "$app_dir/build/ios/iphonesimulator/Runner.app/Frameworks/MaplibreNativeC.framework" ]] \
        || fail "the iOS simulator app has no MaplibreNativeC.framework"
      (cd "$app_dir" && flutter build ios --release --no-codesign)
      [[ -d "$app_dir/build/ios/iphoneos/Runner.app/Frameworks/MaplibreNativeC.framework" ]] \
        || fail "the iOS device app has no MaplibreNativeC.framework"
      ;;
    macos)
      echo "== macOS"
      (cd "$app_dir" && flutter build macos --release)
      [[ -d "$app_dir/build/macos/Build/Products/Release/consumer_app.app/Contents/Frameworks/MaplibreNativeC.framework" ]] \
        || fail "the macOS app has no MaplibreNativeC.framework"
      ;;
    web)
      echo "== Web"
      (cd "$web_app_dir" && flutter build web)
      (cd "$web_app_dir" && flutter build web --wasm)
      ;;
  esac
done

if [[ ${#failures[@]} -gt 0 ]]; then
  echo "The consumer build failed ${#failures[@]} check(s)" >&2
  exit 1
fi
echo "The consumer build passed for ${platforms[*]}"
