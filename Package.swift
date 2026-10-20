// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "CleanScope",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "CleanScopeCore", targets: ["CleanScopeCore"]),
    .executable(name: "CleanScopeApp", targets: ["CleanScopeApp"]),
  ],
  targets: [
    .target(name: "CleanScopeCore"),
    .executableTarget(
      name: "CleanScopeApp",
      dependencies: ["CleanScopeCore"],
      resources: [.process("Resources")]
    ),
    .testTarget(
      name: "CleanScopeCoreTests",
      dependencies: ["CleanScopeCore"]
    ),
  ],
  swiftLanguageModes: [.v5]
)
