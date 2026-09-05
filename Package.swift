// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.
//
//  YYModel — High performance JSON model framework for iOS/macOS.
//  GitHub: https://github.com/leeeeeeeefulong/YYModel
//
//  SPM support added 2026.09.
//  CocoaPods: pod 'YYModel2' (trunk closes 2026-12-02)

import PackageDescription

let package = Package(
    name: "YYModel",
    platforms: [
        .iOS(.v11),
        .macOS(.v10_13),
        .tvOS(.v11),
        .watchOS(.v4)
    ],
    products: [
        .library(
            name: "YYModel",
            targets: ["YYModel"]
        )
    ],
    targets: [
        .target(
            name: "YYModel",
            path: "YYModel",
            publicHeadersPath: ".",
            cSettings: [
                .headerSearchPath(".")
            ],
            linkerSettings: [
                .linkedFramework("Foundation"),
                .linkedFramework("CoreFoundation")
            ]
        )
    ]
)
