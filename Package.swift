// swift-tools-version: 6.0
// Veil8 — the one-way tile encoding behind Veil's Private mode, as an open standard: a picture
// becomes a canonical RGBA image, 32×32 tiles, and one string per tile that cannot be turned back
// into its pixels (rgb-veil8), under a key that never leaves the machine. SPEC.md, the contract,
// will be added later. Veil (github.com/riteshpakala/Veil) embeds the strings and does the matching.
//
// Two libraries. Veil8 is the encoding: it takes a key and never makes one. VeilKey makes and keeps
// the key file an application hands it, the same file Veil keeps.
//
// Nothing beyond the platform: Foundation, CryptoKit (HMAC-SHA256, SHA-256), CoreGraphics / ImageIO
// for loading and resampling pictures, and the POSIX calls a private key file needs.

import PackageDescription

let package = Package(
    name: "Veil8",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "Veil8", targets: ["Veil8"]),
        .library(name: "VeilKey", targets: ["VeilKey"]),
    ],
    targets: [
        .target(name: "Veil8"),
        .target(name: "VeilKey", dependencies: ["Veil8"]),
        .testTarget(
            name: "Veil8Tests",
            dependencies: ["Veil8"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "VeilKeyTests", dependencies: ["VeilKey", "Veil8"]),
    ]
)
