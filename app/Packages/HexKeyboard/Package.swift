// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "HexKeyboard",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "KeyboardCore", targets: ["KeyboardCore"]),
        .library(name: "KeyboardUI", targets: ["KeyboardUI"]),
    ],
    targets: [
        .target(name: "KeyboardCore"),
        .target(name: "KeyboardArbiter"),
        .target(name: "KeyboardUI", dependencies: ["KeyboardCore", "KeyboardArbiter"], exclude: ["Resources/LEXICON-LICENSE"], resources: [.copy("Resources/en.lexicon"), .copy("Resources/en.phrases"), .copy("Resources/nl.lexicon"), .copy("Resources/nl.phrases"), .copy("Resources/emoji.txt")], swiftSettings: [.defaultIsolation(MainActor.self)]),
        .executableTarget(name: "LexiconBuilder", dependencies: ["KeyboardCore"], path: "Tools/LexiconBuilder"),
        .executableTarget(name: "PhrasesBuilder", dependencies: ["KeyboardCore"], path: "Tools/PhrasesBuilder"),
        .testTarget(name: "KeyboardCoreTests", dependencies: ["KeyboardCore"]),
        .testTarget(name: "KeyboardUITests", dependencies: ["KeyboardUI"], resources: [.copy("phrases.txt"), .copy("chat.txt"), .copy("phrases-nl.txt"), .copy("chat-nl.txt")]),
    ]
)
