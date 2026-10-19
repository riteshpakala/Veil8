// swift-tools-version: 6.0
// Veil8 — the one-way tile encoding behind Veil's Private mode, as an open standard: a picture
// becomes a canonical RGBA image, 32×32 tiles, and one string per tile that cannot be turned back
// into its pixels (rgb-veil8), under a key that never leaves the machine. SPEC.md is the contract;
// Veil (github.com/riteshpakala/Veil) embeds the strings and does the matching.
//
// Nothing beyond the platform: Foundation, CryptoKit (HMAC-SHA256, SHA-256) and CoreGraphics /
// ImageIO for loading and resampling pictures.

import PackageDescription

let package = Package(
    name: "Veil8",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "Veil8", targets: ["Veil8"]),
    ],
    targets: [
        .target(name: "Veil8"),
        .testTarget(
            name: "Veil8Tests",
            dependencies: ["Veil8"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
