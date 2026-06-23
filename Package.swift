// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "CleanScope",
  platforms: [.macOS(.v13)],
  products: [
    .library(name: "CleanScopeCore", targets: ["CleanScopeCore"]),
    .executable(name: "CleanScopeApp", targets: ["CleanScopeApp"]),
  ],
  targets: [
    .target(name: "CleanScopeCore"),
    .executableTarget(
      name: "CleanScopeApp",
      dependencies: ["CleanScopeCore"]
    ),
    .testTarget(
      name: "CleanScopeCoreTests",
      dependencies: ["CleanScopeCore"]
    ),
  ],
  swiftLanguageModes: [.v5]
)
