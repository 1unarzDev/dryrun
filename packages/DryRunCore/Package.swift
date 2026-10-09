// swift-tools-version:6.0
// DryRunCore is Foundation-only: no SwiftUI, RoomPlan, RealityKit, MapKit, CryptoKit, or simd.
import PackageDescription

let package = Package(
    name: "DryRunCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "DryRunCore", targets: ["DryRunCore"]),
    ],
    targets: [
        .target(name: "DryRunCore", path: "Sources/DryRunCore"),
        .testTarget(name: "DryRunCoreTests", dependencies: ["DryRunCore"], path: "Tests/DryRunCoreTests"),
    ]
)
