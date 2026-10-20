#!/usr/bin/env bash
# Builds an application that depends on flutter_mapigrade as the published
# archive contains it, outside this checkout (design D106 of the
# publish-readiness change). The workflow consumer-build.yml runs it.
#
#   scripts/consumer_build.sh <work-dir> <platform>...
#
# The platforms are android, ios and macos. The script:
#
# 1. Runs `flutter pub publish --dry-run` in packages/flutter_mapigrade and
#    copies the files it lists, with symlinks resolved, to
#    <work-dir>/flutter_mapigrade. Flutter can't write the archive to a file.
# 2. Creates the application <work-dir>/consumer_app with `flutter create`, with
#    a path dependency on that copy and the example's lib/main.dart, and sets
#    the minimum Android SDK and iOS and macOS versions that the package needs.
# 3. Builds, per platform: android, a release APK; ios, a simulator build and a
#    device build without code signing; macos, a release build.
# 4. Checks that the APK's lib/ has libmaplibre-native-c.so and
#    libflutter_mapigrade.so for arm64-v8a, armeabi-v7a and x86_64, and that
#    the iOS and macOS applications contain MaplibreNativeC.framework.
#
# <work-dir> must be outside the checkout, so that a build that reads a file
# through a path outside the package fails. The script deletes and recreates
# <work-dir>/flutter_mapigrade and <work-dir>/consumer_app.
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
    android | ios | macos) ;;
    *)
      echo "Unknown platform $platform; use android, ios or macos" >&2
      exit 2
      ;;
  esac
done

archive_dir="$work_dir/flutter_mapigrade"
app_dir="$work_dir/consumer_app"
rm -rf "$archive_dir" "$app_dir"

# 1. The archive. The dry run prints the file list as a tree: each entry is
# indented by four characters per level and ends with its size, and a
# directory has no size.
echo "== Archive"
dry_run_output="$work_dir/dry_run.txt"
(cd "$package_dir" && flutter pub publish --dry-run) > "$dry_run_output" 2>&1 || {
  cat "$dry_run_output"
  echo "flutter pub publish --dry-run failed" >&2
  exit 1
}
file_list="$work_dir/archive_files.txt"
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
  echo "The dry run listed no files" >&2
  exit 1
fi
while IFS= read -r file; do
  mkdir -p "$archive_dir/$(dirname "$file")"
  cp -L "$package_dir/$file" "$archive_dir/$file"
done < "$file_list"
echo "Copied $(wc -l < "$file_list" | tr -d ' ') files to $archive_dir"
# The package is a member of this repository's workspace, which the copy is
# not part of.
sed -i.bak '/^resolution: workspace$/d' "$archive_dir/pubspec.yaml"
rm "$archive_dir/pubspec.yaml.bak"

# 2. The application.
echo "== Application"
(cd "$work_dir" && flutter create --org com.example --platforms android,ios,macos consumer_app)
cp "$package_dir/example/lib/main.dart" "$app_dir/lib/main.dart"
rm -f "$app_dir/test/widget_test.dart"
(
  cd "$app_dir"
  flutter pub add flutter_mapigrade --path ../flutter_mapigrade
  flutter pub add flutter_map:8.3.2 latlong2:^0.10.1
)
# The minimum versions of the package: Android API level 29, iOS 15.5 and
# macOS 14.3.
sed -i.bak 's/minSdk = flutter.minSdkVersion/minSdk = 29/' \
  "$app_dir/android/app/build.gradle.kts"
sed -i.bak 's/IPHONEOS_DEPLOYMENT_TARGET = [0-9.]*;/IPHONEOS_DEPLOYMENT_TARGET = 15.5;/' \
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
      for abi in arm64-v8a armeabi-v7a x86_64; do
        for library in libmaplibre-native-c.so libflutter_mapigrade.so; do
          grep -qx "lib/$abi/$library" <<< "$apk_files" \
            || fail "the APK has no lib/$abi/$library"
        done
      done
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
  esac
done

if [[ ${#failures[@]} -gt 0 ]]; then
  echo "The consumer build failed ${#failures[@]} check(s)" >&2
  exit 1
fi
echo "The consumer build passed for ${platforms[*]}"
