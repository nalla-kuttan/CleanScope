import Foundation
import Testing

@testable import CleanScopeCore

@Suite("Menu bar presentation")
struct MenuBarPresentationTests {
  @Test func stageZeroWhenRecentOrSmall() {
    #expect(MenuBarPresentation.sproutStage(daysSinceCleanup: 4, safeBytes: 5_000_000_000) == 0)
    #expect(MenuBarPresentation.sproutStage(daysSinceCleanup: 20, safeBytes: 249_999_999) == 0)
  }

  @Test func stageTwoNeedsTimeAndSize() {
    #expect(MenuBarPresentation.sproutStage(daysSinceCleanup: 12, safeBytes: 1_000_000_000) == 2)
    #expect(MenuBarPresentation.sproutStage(daysSinceCleanup: 11, safeBytes: 5_000_000_000) == 1)
    #expect(MenuBarPresentation.sproutStage(daysSinceCleanup: 30, safeBytes: 999_999_999) == 1)
  }

  @Test func sizeLabelThresholds() {
    #expect(MenuBarPresentation.sizeLabel(daysSinceCleanup: 14, safeBytes: 500_000_000) == "500 MB")
    #expect(MenuBarPresentation.sizeLabel(daysSinceCleanup: 13, safeBytes: 5_000_000_000) == nil)
    #expect(MenuBarPresentation.sizeLabel(daysSinceCleanup: 20, safeBytes: 499_999_999) == nil)
  }

  @Test func noCleanupLogFallsBackToFirstLaunch() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let firstLaunch = Calendar.current.date(byAdding: .day, value: -9, to: now)!
    #expect(MenuBarPresentation.daysSinceCleanup(log: [], firstLaunch: firstLaunch, now: now) == 9)
  }

  @Test func newestLogEntryWinsAndNeverNegative() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let calendar = Calendar.current
    let log = [
      CleanupLogEntry(
        completedAt: calendar.date(byAdding: .day, value: -3, to: now)!, recoveredBytes: 1),
      CleanupLogEntry(
        completedAt: calendar.date(byAdding: .day, value: -40, to: now)!, recoveredBytes: 1),
    ]
    #expect(MenuBarPresentation.daysSinceCleanup(log: log, firstLaunch: now, now: now) == 3)
    let future = calendar.date(byAdding: .day, value: 2, to: now)!
    #expect(MenuBarPresentation.daysSinceCleanup(log: [], firstLaunch: future, now: now) == 0)
  }
}
