# Framework steps for MaplibreNativeC.xcframework, which
# scripts/build_maplibre_ffi.sh (from local builds) and
# scripts/package_xcframework.sh (from release tarballs) source. Both give the
# frameworks the same layout and install names.

fw_name=MaplibreNativeC

# Writes the framework Info.plist for a preset to $1, with the bundle version
# $3.
write_info_plist() {
  local plist=$1 preset=$2 bundle_version=$3 platform_keys
  case "$preset" in
    macos-*)
      platform_keys="<key>LSMinimumSystemVersion</key><string>14.3</string>" ;;
    ios-simulator-*)
      platform_keys="<key>MinimumOSVersion</key><string>15.0</string>
  <key>CFBundleSupportedPlatforms</key><array><string>iPhoneSimulator</string></array>" ;;
    ios-*)
      platform_keys="<key>MinimumOSVersion</key><string>15.0</string>
  <key>CFBundleSupportedPlatforms</key><array><string>iPhoneOS</string></array>" ;;
  esac
  cat > "$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>$fw_name</string>
  <key>CFBundleIdentifier</key><string>org.maplibre.$fw_name</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>$fw_name</string>
  <key>CFBundlePackageType</key><string>FMWK</string>
  <key>CFBundleShortVersionString</key><string>0.0.0</string>
  <key>CFBundleVersion</key><string>$bundle_version</string>
  $platform_keys
</dict>
</plist>
PLIST
}

# Wraps the dylib of an installed preset in $1 (a directory with include/ and
# lib/) in a framework under $3: the versioned layout on macOS, the flat layout
# on iOS. Prints the framework's path. Swift Package Manager accepts the
# frameworks as a binary target once they are combined into an xcframework, and
# Xcode embeds and signs the framework in the app bundle.
make_framework() {
  local install=$1 preset=$2 stage=$3 bundle_version=$4
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
    write_info_plist "$contents/Resources/Info.plist" "$preset" "$bundle_version"
    ln -s A "$fw/Versions/Current"
    for item in "$fw_name" Headers Modules Resources; do
      ln -s "Versions/Current/$item" "$fw/$item"
    done
  else
    write_info_plist "$contents/Info.plist" "$preset" "$bundle_version"
  fi
  echo "$fw"
}
