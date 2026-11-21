// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "Jaude",
    // Liquid Glass (glassEffect) has no pre-26 equivalent.
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(name: "Jaude"),
    ],
    swiftLanguageModes: [.v5]
)
