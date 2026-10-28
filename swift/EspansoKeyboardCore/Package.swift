// swift-tools-version: 6.0
// The Rust core (core/) for Swift: the UniFFI bindings, the XCFramework, and a script
// runner using JavaScriptCore. Run scripts/build-xcframework.sh before building.
import PackageDescription

let package = Package(
    name: "EspansoKeyboardCore",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "EspansoKeyboardCore", targets: ["EspansoKeyboardCore"]),
    ],
    targets: [
        .binaryTarget(
            name: "EspansoKeyboardCoreFFI",
            path: "EspansoKeyboardCoreFFI.xcframework"
        ),
        .target(
            name: "EspansoKeyboardCore",
            dependencies: ["EspansoKeyboardCoreFFI"],
            exclude: ["Generated/README.md"],
            linkerSettings: [.linkedFramework("JavaScriptCore")]
        ),
        .testTarget(
            name: "EspansoKeyboardCoreTests",
            dependencies: ["EspansoKeyboardCore"]
        ),
    ]
)
