// swift-tools-version: 5.9

import Foundation
import PackageDescription

// Sources/flutter_mapigrade/core is a symlink to the shared C++ core in
// ../../src/core.
//
// MaplibreNativeC is the xcframework zip of the MapLibre Native FFI release in
// ../../maplibre_ffi.lock. scripts/update_ffi_pins.sh writes its URL and
// checksum below from the lock file; don't edit them by hand. In this
// repository, Frameworks/MaplibreNativeC.xcframework is a symlink to the output
// of scripts/build_maplibre_ffi.sh, and the package uses that local build when
// the symlink resolves. A published archive has no Frameworks/ directory.
let localFramework = "Frameworks/MaplibreNativeC.xcframework"
let maplibreNativeC: Target =
    FileManager.default.fileExists(
        atPath: Context.packageDirectory + "/" + localFramework)
    ? .binaryTarget(name: "MaplibreNativeC", path: localFramework)
    : .binaryTarget(
        name: "MaplibreNativeC",
        url: "https://github.com/maplibre/maplibre-native-ffi/releases/download/core/v0.202610.1/MaplibreNativeC.xcframework.zip",
        checksum: "76c36bc70e83a78ee77f6d92970283714bcf860f8845c1de42fc8d59a9eb7ae6"
    )

let package = Package(
    name: "flutter_mapigrade",
    platforms: [
        .macOS("14.3"),
        .iOS("15.5"),
    ],
    products: [
        .library(name: "flutter-mapigrade", targets: ["flutter_mapigrade"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        maplibreNativeC,
        .target(
            name: "flutter_mapigrade",
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
