// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Floresta",
    platforms: [
        .iOS(.v17),
    ],
    products: [
        .library(name: "Floresta", targets: ["Floresta"]),
    ],
    targets: [
        .binaryTarget(
            name: "FlorestaFFI",
            path: "FlorestaFFI.xcframework"
        ),
        .target(
            name: "Floresta",
            dependencies: ["FlorestaFFI"],
            path: "Sources/Floresta"
        ),
    ]
)
