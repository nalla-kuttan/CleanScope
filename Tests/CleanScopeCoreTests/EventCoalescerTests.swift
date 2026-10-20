import Foundation
import Testing

@testable import CleanScopeCore

@Suite struct EventCoalescerTests {
  @Test func mergesEventsForSamePathWithinWindow() {
    var coalescer = EventCoalescer(window: 10)
    let start = Date(timeIntervalSince1970: 100)
    var results: [Bool] = []
    results.append(coalescer.shouldProcess(path: "/a", at: start))
    results.append(coalescer.shouldProcess(path: "/a", at: start.addingTimeInterval(5)))
    results.append(coalescer.shouldProcess(path: "/b", at: start.addingTimeInterval(5)))
    results.append(coalescer.shouldProcess(path: "/a", at: start.addingTimeInterval(10.5)))
    #expect(results == [true, false, true, true])
  }

  @Test func coalescerForgetsOldEntries() {
    var coalescer = EventCoalescer(window: 10)
    for index in 0..<1_000 {
      _ = coalescer.shouldProcess(path: "/f\(index)", at: Date(timeIntervalSince1970: Double(index)))
    }
    #expect(coalescer.trackedCount <= 11)
  }

  @Test func launchCacheScansEachVersionOnce() {
    var cache = LaunchScanCache()
    let date = Date(timeIntervalSince1970: 1)
    var results: [Bool] = []
    results.append(cache.shouldScan(path: "/Applications/A.app", modified: date))
    results.append(cache.shouldScan(path: "/Applications/A.app", modified: date))
    results.append(cache.shouldScan(path: "/Applications/A.app", modified: date.addingTimeInterval(60)))
    results.append(cache.shouldScan(path: "/Applications/A.app", modified: nil))
    #expect(results == [true, false, true, true])
  }

  @Test func watchedPathsCoverSpec() {
    let paths = RealTimeWatchList.paths(homeDirectory: "/Users/me")
    #expect(paths.contains("/Users/me/Downloads"))
    #expect(paths.contains("/Users/me/Library/LaunchAgents"))
    #expect(paths.contains("/Library/LaunchAgents"))
    #expect(paths.contains("/Library/LaunchDaemons"))
    #expect(paths.contains("/Users/me/Library/Application Support/Google/Chrome"))
  }
}
