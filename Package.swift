// swift-tools-version: 5.4
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Backtrace",
    platforms: [
        .iOS(.v10),
        .macOS(.v10_10),
        .tvOS(.v12)
    ],
    products: [
        .library(
            name: "Backtrace",
            targets: ["Backtrace"]),
    ],
    dependencies: [
        .package(url: "https://github.com/microsoft/plcrashreporter.git", from: "1.10.0"),
        .package(url: "https://github.com/Quick/Nimble.git", from: "9.1.1"),
        .package(url: "https://github.com/Quick/Quick.git", from: "4.0.0")
    ],
    targets: [
        .target(
            name: "Backtrace",
            dependencies: [
                .product(name: "CrashReporter", package: "plcrashreporter")
            ],
            path: "Sources"
        ),
        .testTarget(
            name: "BacktraceTests",
            dependencies: [
                "Backtrace",
                .product(name: "CrashReporter", package: "plcrashreporter"),
                .product(name: "Nimble", package: "Nimble"),
                .product(name: "Quick", package: "Quick")
            ],
            path: "Tests",
            resources: [.process("Resources/test.txt")]
        )
    ]
)

