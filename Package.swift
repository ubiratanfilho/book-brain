// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "BookBrain",
  platforms: [.macOS(.v14)],
  products: [.executable(name: "BookBrain", targets: ["BookBrain"])],
  dependencies: [
    .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.4.1"),
    .package(url: "https://github.com/gonzalezreal/swiftui-math", from: "0.1.0"),
  ],
  targets: [
    .target(name: "BookBrainCore"),
    .executableTarget(
      name: "BookBrain",
      dependencies: [
        "BookBrainCore", .product(name: "MarkdownUI", package: "swift-markdown-ui"),
        .product(name: "SwiftUIMath", package: "swiftui-math"),
      ],
      resources: [.process("Resources")]
    ),
    .testTarget(name: "BookBrainTests", dependencies: ["BookBrain"]),
    .testTarget(
      name: "BookBrainCoreTests",
      dependencies: ["BookBrainCore"],
      resources: [.copy("Fixtures")]
    ),
  ],
  swiftLanguageModes: [.v5]
)
