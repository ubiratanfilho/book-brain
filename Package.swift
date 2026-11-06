// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "BookBrain",
  platforms: [.macOS(.v14)],
  products: [.executable(name: "BookBrain", targets: ["BookBrain"])],
  targets: [
    .target(name: "BookBrainCore"),
    .executableTarget(name: "BookBrain", dependencies: ["BookBrainCore"]),
    .testTarget(
      name: "BookBrainCoreTests",
      dependencies: ["BookBrainCore"],
      resources: [.copy("Fixtures")]
    ),
  ],
  swiftLanguageModes: [.v5]
)
