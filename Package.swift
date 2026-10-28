// swift-tools-version: 6.2
import PackageDescription

let settings: [SwiftSetting] = [
    .defaultIsolation(MainActor.self),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
]

let package = Package(
    name: "Hex",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "Hex", targets: ["Hex"]),
        .library(name: "Keyboard", targets: ["Keyboard"]),
    ],
    dependencies: [.package(path: "Packages/HexKeyboard")],
    targets: [
        .target(
            name: "Hex",
            dependencies: [.product(name: "KeyboardUI", package: "HexKeyboard")],
            path: "App",
            exclude: ["Assets.xcassets", "Settings.bundle", "Hex.entitlements", "PrivacyInfo.xcprivacy"],
            swiftSettings: settings
        ),
        .target(
            name: "Keyboard",
            dependencies: [.product(name: "KeyboardUI", package: "HexKeyboard")],
            path: "Keyboard",
            exclude: ["Keyboard.entitlements", "PrivacyInfo.xcprivacy"],
            swiftSettings: settings,
            // The principal class is only named in Info.plist, so without -ObjC the linker strips it out of the appex.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-ObjC"])]
        ),
    ]
)
