// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "HexWeb",
    dependencies: [
        .package(path: "../Packages/HexKeyboard"),
        .package(url: "https://github.com/swiftwasm/JavaScriptKit.git", exact: "0.59.0"),
    ],
    targets: [
        .executableTarget(
            name: "HexWeb",
            dependencies: [
                .product(name: "KeyboardCore", package: "HexKeyboard"),
                .product(name: "JavaScriptKit", package: "JavaScriptKit"),
            ],
            swiftSettings: [.enableExperimentalFeature("Extern")],
            plugins: [.plugin(name: "BridgeJS", package: "JavaScriptKit")]
        ),
    ]
)
