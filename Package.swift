// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Pruva",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "RaceCore", targets: ["RaceCore"])],
    targets: [
        .target(name: "RaceCore"),
        .testTarget(name: "RaceCoreTests", dependencies: ["RaceCore"])
    ]
)
