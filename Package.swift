// swift-tools-version:4.2
import PackageDescription

let package = Package(
    name: "Backtrace",
    platforms: [
      .macOS(.v10_10), .iOS(.v10), .tvOS(.v12_1)
    ],
    products: [
        .library(name: "Backtrace", targets: ["Backtrace"]),
    ],
    dependencies: [
        .package(url: "https://github.com/microsoft/plcrashreporter.git", from: "1.11.0"),
        	.package(url: "https://github.com/Quick/Nimble.git", from: "10.0.0"),
        	.package(url: "https://github.com/Quick/Quick.git", from: "5.0.1")
    ],
    targets: [
        .target(
            name: "Nimble",
            dependencies: [
                .package(url: "https://github.com/microsoft/plcrashreporter.git", from: "1.11.0"),
        	.package(url: "https://github.com/Quick/Nimble.git", from: "10.0.0"),
        	.package(url: "https://github.com/Quick/Quick.git", from: "5.0.1")
            ],
            exclude: ["Info.plist"]
        ),
        .testTarget(
            name: "NimbleTests",
            dependencies: ["Nimble"],
            exclude: ["objc", "Info.plist"]
        ),
    ],
    swiftLanguageVersions: [.v4_2]
)
