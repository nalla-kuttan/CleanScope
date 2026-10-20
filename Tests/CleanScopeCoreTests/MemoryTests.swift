import Foundation
import Testing

@testable import CleanScopeCore

@Suite struct MemoryTests {
  let gib: Int64 = 1_073_741_824

  @Test func allocationLimitLeavesOneGibibyte() {
    #expect(MemoryReclaimer.allocationLimit(free: 2 * gib, inactive: 3 * gib) == 4 * gib)
    #expect(MemoryReclaimer.allocationLimit(free: gib / 2, inactive: gib / 4) == 0)
  }

  @Test func cancelStopsWithinOneBlock() async {
    let calls = Counter()
    let allocated = await MemoryReclaimer.reclaimWithAllocation(
      limitBytes: 64 * 1_048_576, blockBytes: 1_048_576, pressure: { 1 },
      isCancelled: { calls.increment() > 1 })
    #expect(allocated == 1_048_576)
  }

  @Test func pressureStopsAllocation() async {
    let allocated = await MemoryReclaimer.reclaimWithAllocation(
      limitBytes: 64 * 1_048_576, blockBytes: 1_048_576, pressure: { 2 }, isCancelled: { false })
    #expect(allocated == 0)
  }

  @Test func allocationRespectsLimit() async {
    let allocated = await MemoryReclaimer.reclaimWithAllocation(
      limitBytes: 3 * 1_048_576 + 10, blockBytes: 1_048_576, pressure: { 1 }, isCancelled: { false })
    #expect(allocated == 3 * 1_048_576)
  }

  @Test func purgeRunsThroughPrivilegedRunner() async throws {
    let privileged = StubPrivilegedRunner()
    try await MemoryReclaimer.reclaimWithPurge(privileged: privileged)
    #expect(privileged.recorded == ["/usr/sbin/purge"])
  }

  @Test func liveSnapshotIsPlausible() {
    let snapshot = MemoryService.snapshot()
    #expect(snapshot.totalBytes > 0)
    #expect(snapshot.wiredBytes > 0)
    #expect([1, 2, 4].contains(snapshot.pressureLevel))
    #expect(MemoryService.pressureTitle(snapshot.pressureLevel) != "")
    let top = MemoryService.topConsumers(limit: 5)
    #expect(top.count <= 5)
    #expect(top == top.sorted { $0.footprintBytes > $1.footprintBytes })
  }
}

final class Counter: @unchecked Sendable {
  private let lock = NSLock()
  private var value = 0
  func increment() -> Int { lock.withLock { value += 1; return value } }
}
