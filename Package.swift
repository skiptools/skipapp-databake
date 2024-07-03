// swift-tools-version: 5.9
// This is free software: you can redistribute and/or modify it
// under the terms of the GNU Lesser General Public License 3.0
// as published by the Free Software Foundation https://fsf.org

import PackageDescription

let package = Package(
    name: "skipapp-databake",
    defaultLocalization: "en",
    platforms: [.iOS(.v16), .macOS(.v13), .tvOS(.v16), .watchOS(.v9), .macCatalyst(.v16)],
    products: [
        .library(name: "DataBakeApp", type: .dynamic, targets: ["DataBake"]),
        .library(name: "DataBakeModel", type: .dynamic, targets: ["DataBakeModel"]),
    ],
    dependencies: [
        .package(url: "https://source.skip.tools/skip.git", from: "0.9.2"),
        .package(url: "https://source.skip.tools/skip-ui.git", from: "0.10.0"),
        .package(url: "https://source.skip.tools/skip-foundation.git", from: "0.7.0"),
        .package(url: "https://source.skip.tools/skip-model.git", from: "0.8.0"),
        .package(url: "https://source.skip.tools/skip-sql.git", from: "0.6.2")
    ],
    targets: [
        .target(name: "DataBake", dependencies: ["DataBakeModel", .product(name: "SkipUI", package: "skip-ui")], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
        .testTarget(name: "DataBakeTests", dependencies: ["DataBake", .product(name: "SkipTest", package: "skip")], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
        .target(name: "DataBakeModel", dependencies: [.product(name: "SkipFoundation", package: "skip-foundation"), .product(name: "SkipModel", package: "skip-model"), .product(name: "SkipSQL", package: "skip-sql")], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
        .testTarget(name: "DataBakeModelTests", dependencies: ["DataBakeModel", .product(name: "SkipTest", package: "skip")], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
    ]
)
