// swift-tools-version:6.0
// DryRunVault: encrypted on-device household vault + known-good public pack cache.
// Uses CryptoKit on Apple platforms. swift-crypto (Apple's API-compatible implementation) is linked
// ONLY on Linux so the vault can be tested on the Linux CI host. Version pinned exactly.
import PackageDescription

let package = Package(
    name: "DryRunVault",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "DryRunVault", targets: ["DryRunVault"]),
    ],
    dependencies: [
        .package(path: "../DryRunCore"),
        .package(url: "https://github.com/apple/swift-crypto.git", exact: "4.5.2"),
    ],
    targets: [
        .target(
            name: "DryRunVault",
            dependencies: [
                .product(name: "DryRunCore", package: "DryRunCore"),
                .product(name: "Crypto", package: "swift-crypto", condition: .when(platforms: [.linux])),
            ],
            path: "Sources/DryRunVault"
        ),
        .testTarget(name: "DryRunVaultTests", dependencies: ["DryRunVault"], path: "Tests/DryRunVaultTests"),
    ]
)
