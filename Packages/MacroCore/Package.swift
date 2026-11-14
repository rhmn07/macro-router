// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MacroCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "MacroCore", targets: ["MacroCore"]),
    ],
    targets: [
        .target(name: "MacroCore"),
        .testTarget(name: "MacroCoreTests", dependencies: ["MacroCore"]),
    ]
)
