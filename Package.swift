// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.
import PackageDescription

let package = Package(
    name: "Backtrace",
    platforms: [
        .iOS(.v12),
        .macOS(.v10_13),
        .tvOS(.v12)
    ],
    products: [
        .library(name: "Backtrace", targets: ["Backtrace"])
    ],
    dependencies: [
        .package(url: "https://github.com/Quick/Nimble.git", from: "10.0.0"),
        .package(url: "https://github.com/Quick/Quick.git", from: "5.0.1")
    ],
    targets: [
        .binaryTarget(
            name: "CrashReporter",
            url: "https://github.com/backtrace-labs/plcrashreporter/releases/download/1.11.2-rc1/CrashReporter.xcframework.zip",
            checksum: "5f429bb012b928291607030dfd69ac4c215e038f718a2d3aaf1458360c31baa1"
        ),
        .target(
            name: "Backtrace",
            dependencies: ["CrashReporter"],
            path: "Sources",
            resources: [.process("Features/Resources/Model.xcdatamodeld"),
                        .process("Resources/PrivacyInfo.xcprivacy")
            ]
        ),
        .testTarget(
            name: "Backtrace-Tests",
            dependencies: ["Backtrace", "Quick", "Nimble"],
            path: "Tests",
            resources: [.process("Resources")]
        ),
    ],
    swiftLanguageVersions: [.v5]
)
