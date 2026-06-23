import Testing

@testable import CleanScopeCore

@Suite struct PermissionServiceTests {
  @Test func permissionSummaryMarksSkippedPermissionPathsIncomplete() {
    let service = PermissionService()
    let skipped = [
      SkippedPath(
        path: "/Users/me/Documents", reason: .permissionDenied, message: "Permission required")
    ]

    let summary = service.summary(skippedPaths: skipped)

    #expect(!summary.isLikelyComplete)
    #expect(summary.message.contains("Full Disk Access"))
  }

  @Test func permissionSummaryIsCompleteWhenNoPermissionSkipsExist() {
    let service = PermissionService()

    let summary = service.summary(skippedPaths: [])

    #expect(summary.isLikelyComplete)
  }
}
