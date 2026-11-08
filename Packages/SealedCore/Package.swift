// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SealedCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "SealedCore", targets: ["SealedCore"])
    ],
    dependencies: [
        // On Apple platforms `Crypto` re-exports CryptoKit; elsewhere it's BoringSSL-backed,
        // so the core can be unit-tested on Linux CI too.
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0")
    ],
    targets: [
        .target(
            name: "SealedCore",
            dependencies: [.product(name: "Crypto", package: "swift-crypto")]
        ),
        .testTarget(
            name: "SealedCoreTests",
            dependencies: ["SealedCore"]
        )
    ]
)
