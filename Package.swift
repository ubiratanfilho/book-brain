// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "BookBrain",
  platforms: [.macOS(.v14)],
  products: [.executable(name: "BookBrain", targets: ["BookBrain"])],
  dependencies: [
    .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.4.1")
  ],
  targets: [
    .target(name: "BookBrainCore"),
    .executableTarget(
      name: "BookBrain",
      dependencies: ["BookBrainCore", .product(name: "MarkdownUI", package: "swift-markdown-ui")]
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
