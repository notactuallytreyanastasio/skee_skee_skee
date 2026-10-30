// swift-tools-version: 6.0
import PackageDescription

// SkeeCore is the functional core: value types and pure functions only, no
// Foundation-level side effects, no clocks, no global randomness.
// `skee` is a macOS command-line shell around it for playing, mapping and
// balancing the game headlessly. The iOS app (App/) is the other shell.
let package = Package(
    name: "SkeeSkeeSkee",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "SkeeCore", targets: ["SkeeCore"]),
        .executable(name: "skee", targets: ["skee"]),
    ],
    targets: [
        .target(name: "SkeeCore"),
        .executableTarget(name: "skee", dependencies: ["SkeeCore"]),
        .testTarget(name: "SkeeCoreTests", dependencies: ["SkeeCore"]),
    ]
)
