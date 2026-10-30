// swift-tools-version: 6.0
import PackageDescription

// SkeeCore is the functional core: value types and pure functions only, no
// Foundation-level side effects, no clocks, no global randomness.
// SkeeRender turns game state into pictures: a pure layout/scene layer plus
// a CoreGraphics renderer, shared by the app and the CLI so the PNGs the CLI
// writes are the frames the phone shows.
// SkeeScene is the 3D cabinet: SceneKit, cel-shaded with a port of the toon
// kit from whats_going_through_your_mind. Builds on iOS and macOS so the CLI
// can render the same frames headless.
// `skee` is a macOS command-line shell around it for playing, mapping and
// balancing the game headlessly. The iOS app (App/) is the other shell.
let package = Package(
    name: "SkeeSkeeSkee",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "SkeeCore", targets: ["SkeeCore"]),
        .library(name: "SkeeRender", targets: ["SkeeRender"]),
        .library(name: "SkeeScene", targets: ["SkeeScene"]),
        .executable(name: "skee", targets: ["skee"]),
    ],
    targets: [
        .target(name: "SkeeCore"),
        .target(name: "SkeeRender", dependencies: ["SkeeCore"]),
        .target(name: "SkeeScene", dependencies: ["SkeeCore", "SkeeRender"]),
        .executableTarget(name: "skee", dependencies: ["SkeeCore", "SkeeRender", "SkeeScene"]),
        .testTarget(name: "SkeeCoreTests", dependencies: ["SkeeCore"]),
        .testTarget(name: "SkeeRenderTests", dependencies: ["SkeeRender"]),
    ]
)
