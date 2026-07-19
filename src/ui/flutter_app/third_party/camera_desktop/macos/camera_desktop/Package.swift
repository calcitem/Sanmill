// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "camera_desktop",
    platforms: [
        .macOS("10.15")
    ],
    products: [
        .library(name: "camera-desktop", targets: ["camera_desktop"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "camera_desktop",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            resources: [
                .process("PrivacyInfo.xcprivacy"),
            ]
        )
    ]
)
