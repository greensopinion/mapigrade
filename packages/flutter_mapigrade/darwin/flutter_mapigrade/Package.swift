// swift-tools-version: 5.9

import PackageDescription

// Sources/flutter_mapigrade/core is a symlink to the shared C++ core
// in ../../src/core, and Frameworks/MapLibreNativeC.xcframework is a symlink to
// the output of scripts/build_maplibre_ffi.sh at the repository root.
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
        .binaryTarget(
            name: "MapLibreNativeC",
            path: "Frameworks/MapLibreNativeC.xcframework"
        ),
        .target(
            name: "flutter_mapigrade",
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
