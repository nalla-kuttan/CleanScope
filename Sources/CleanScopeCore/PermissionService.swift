import Foundation

public struct PermissionSummary: Equatable, Sendable {
  public var isLikelyComplete: Bool
  public var message: String
  public var setupSteps: [String]

  public init(isLikelyComplete: Bool, message: String, setupSteps: [String]) {
    self.isLikelyComplete = isLikelyComplete
    self.message = message
    self.setupSteps = setupSteps
  }
}

public struct PermissionService: Sendable {
  public init() {}

  public func summary(skippedPaths: [SkippedPath]) -> PermissionSummary {
    let permissionSkips = skippedPaths.filter {
      $0.reason == .permissionDenied || $0.reason == .protectedByMacOS
    }
    guard !permissionSkips.isEmpty else {
      return PermissionSummary(
        isLikelyComplete: true,
        message: "Scan completed for available folders.",
        setupSteps: []
      )
    }

    return PermissionSummary(
      isLikelyComplete: false,
      message:
        "Some folders could not be scanned without Full Disk Access or macOS permission approval.",
      setupSteps: [
        "Open System Settings.",
        "Choose Privacy & Security.",
        "Open Full Disk Access.",
        "Enable CleanScope, then run the scan again.",
      ]
    )
  }
}
