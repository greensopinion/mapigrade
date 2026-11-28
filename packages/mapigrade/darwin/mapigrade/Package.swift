// swift-tools-version: 5.9

import Foundation
import PackageDescription

// Sources/mapigrade/core is a symlink to the shared C++ core in
// ../../src/core.
//
// MaplibreNativeC is the xcframework zip that ../../maplibre_ffi.lock names: of
// the MapLibre Native FFI release, or of a build of the pinned commit that we
// host. scripts/update_ffi_pins.sh writes its URL and checksum below from the
// lock file; don't edit them by hand. Both are empty while the lock names
// neither. In this repository,
// Frameworks/MaplibreNativeC.xcframework is a symlink to the output of
// scripts/build_maplibre_ffi.sh, and the package uses that local build when the
// symlink resolves. A published archive has no Frameworks/ directory.
let localFramework = "Frameworks/MaplibreNativeC.xcframework"
let release = (
    url: "https://github.com/greensopinion/mapigrade/releases/download/maplibre-native-ffi-4371ff6/MaplibreNativeC.xcframework.zip",
    checksum: "ef00de824a5b3d162efbe9fd887a55a07172d9d5e1ea23df52cccaa83dedaef4"
)
let hasLocalFramework = FileManager.default.fileExists(
    atPath: Context.packageDirectory + "/" + localFramework)
if !hasLocalFramework && release.url.isEmpty {
    fatalError(
        "maplibre_ffi.lock names no MapLibre Native FFI release; build the FFI with scripts/build_maplibre_ffi.sh")
}
let maplibreNativeC: Target =
    hasLocalFramework
    ? .binaryTarget(name: "MaplibreNativeC", path: localFramework)
    : .binaryTarget(name: "MaplibreNativeC", url: release.url, checksum: release.checksum)

let package = Package(
    name: "mapigrade",
    platforms: [
        .macOS("14.3"),
        .iOS("15.0"),
    ],
    products: [
        .library(name: "mapigrade", targets: ["mapigrade"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        maplibreNativeC,
        .target(
            name: "mapigrade",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                "MaplibreNativeC",
            ],
            cxxSettings: [
                .headerSearchPath("core"),
            ],
            linkerSettings: [
                .linkedFramework("Metal"),
                .linkedFramework("CoreVideo"),
            ]
        ),
    ],
    cxxLanguageStandard: .cxx20
)
