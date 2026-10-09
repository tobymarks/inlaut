// swift-tools-version: 6.2
import PackageDescription

// Wraps FluidAudio so the app can switch off its default NemoTextProcessing
// trait: a prebuilt text-normalisation binary inlaut does not use.
let package = Package(
    name: "InlautSpeech",
    platforms: [.macOS(.v26)],
    products: [.library(name: "InlautSpeech", targets: ["InlautSpeech"])],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.7", traits: []),
    ],
    targets: [
        .target(name: "InlautSpeech", dependencies: [.product(name: "FluidAudio", package: "FluidAudio")]),
    ]
)
