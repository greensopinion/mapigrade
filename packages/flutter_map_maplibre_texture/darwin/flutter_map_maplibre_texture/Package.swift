// swift-tools-version: 5.9

import PackageDescription

// Sources/flutter_map_maplibre_texture/core is a symlink to the shared C++ core
// in ../../src/core, and Frameworks/MapLibreNativeC.xcframework is a symlink to
// the output of scripts/build_maplibre_ffi.sh at the repository root.
let package = Package(
    name: "flutter_map_maplibre_texture",
    platforms: [
        .macOS("14.3"),
        .iOS("15.5"),
    ],
    products: [
        .library(name: "flutter-map-maplibre-texture", targets: ["flutter_map_maplibre_texture"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .binaryTarget(
            name: "MapLibreNativeC",
            path: "Frameworks/MapLibreNativeC.xcframework"
        ),
        .target(
            name: "flutter_map_maplibre_texture",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                "MapLibreNativeC",
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
