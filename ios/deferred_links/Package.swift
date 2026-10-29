// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "deferred_links",
    platforms: [
        .iOS("13.0")
    ],
    products: [
        .library(name: "deferred-links", targets: ["deferred_links"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "deferred_links",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            resources: [
                .process("PrivacyInfo.xcprivacy")
            ]
        )
    ]
)
