// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ITDOApp",
    defaultLocalization: "ru",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ITDOApp", type: .dynamic, targets: ["ITDOApp"])
    ],
    dependencies: [
        .package(url: "https://source.skip.dev/skip.git", from: "1.0.0"),
        .package(url: "https://source.skip.dev/skip-fuse.git", from: "1.0.0"),
        .package(url: "https://source.skip.dev/skip-fuse-ui.git", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "ITDOApp",
            dependencies: [
                .product(name: "SkipFuse", package: "skip-fuse"),
                .product(name: "SkipFuseUI", package: "skip-fuse-ui")
            ],
            path: "ITDOApp",
            exclude: ["Info.plist", "ITDOApp.entitlements"],
            resources: [.process("Assets.xcassets")],
            plugins: [.plugin(name: "skipstone", package: "skip")]
        )
    ]
)
