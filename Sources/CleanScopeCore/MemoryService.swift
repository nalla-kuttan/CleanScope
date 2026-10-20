import Darwin
import Foundation

public struct MemorySnapshot: Equatable, Sendable {
  public var totalBytes: Int64
  public var appBytes: Int64
  public var wiredBytes: Int64
  public var compressedBytes: Int64
  public var cachedBytes: Int64
  public var freeBytes: Int64
  public var inactiveBytes: Int64
  public var swapUsedBytes: Int64
  /// `kern.memorystatus_vm_pressure_level`: 1 normal, 2 warning, 4 critical.
  public var pressureLevel: Int

  public var usedBytes: Int64 { appBytes + wiredBytes + compressedBytes }
}

public struct ProcessMemory: Identifiable, Equatable, Sendable {
  public var id: Int32 { pid }
  public var pid: Int32
  public var name: String
  public var footprintBytes: Int64
}

public enum MemoryService {
  public static func snapshot() -> MemorySnapshot {
    var stats = vm_statistics64()
    var count = mach_msg_type_number_t(
      MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
    let result = withUnsafeMutablePointer(to: &stats) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
      }
    }
    let page = Int64(vm_kernel_page_size)
    func bytes(_ pages: UInt32) -> Int64 { Int64(pages) * page }
    func bytes(_ pages: UInt64) -> Int64 { Int64(pages) * page }

    var snapshot = MemorySnapshot(
      totalBytes: Int64(ProcessInfo.processInfo.physicalMemory), appBytes: 0, wiredBytes: 0,
      compressedBytes: 0, cachedBytes: 0, freeBytes: 0, inactiveBytes: 0,
      swapUsedBytes: swapUsedBytes(), pressureLevel: pressureLevel())
    guard result == KERN_SUCCESS else { return snapshot }
    snapshot.appBytes = max(0, bytes(stats.internal_page_count) - bytes(stats.purgeable_count))
    snapshot.wiredBytes = bytes(stats.wire_count)
    snapshot.compressedBytes = bytes(stats.compressor_page_count)
    snapshot.cachedBytes = bytes(stats.external_page_count) + bytes(stats.purgeable_count)
    snapshot.freeBytes = bytes(stats.free_count)
    snapshot.inactiveBytes = bytes(stats.inactive_count)
    return snapshot
  }

  public static func pressureLevel() -> Int {
    var level: Int32 = 1
    var size = MemoryLayout<Int32>.size
    guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else {
      return 1
    }
    return Int(level)
  }

  public static func pressureTitle(_ level: Int) -> String {
    switch level {
    case 4...: return "Critical"
    case 2...: return "Elevated"
    default: return "Normal"
    }
  }

  public static func swapUsedBytes() -> Int64 {
    var usage = xsw_usage()
    var size = MemoryLayout<xsw_usage>.size
    guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return 0 }
    return Int64(usage.xsu_used)
  }

  /// The largest processes by physical footprint, the figure Activity Monitor shows as Memory.
  /// Processes owned by other users can't be read and are skipped.
  public static func topConsumers(limit: Int = 10) -> [ProcessMemory] {
    let capacity = Int(proc_listallpids(nil, 0)) + 32
    guard capacity > 32 else { return [] }
    var pids = [pid_t](repeating: 0, count: capacity)
    let count = pids.withUnsafeMutableBytes {
      Int(proc_listallpids($0.baseAddress, Int32($0.count)))
    }
    guard count > 0 else { return [] }

    var processes: [ProcessMemory] = []
    for pid in pids.prefix(count) where pid > 0 {
      var info = rusage_info_v4()
      let status = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
          proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
        }
      }
      guard status == 0, info.ri_phys_footprint > 0 else { continue }
      processes.append(
        ProcessMemory(pid: pid, name: processName(pid), footprintBytes: Int64(info.ri_phys_footprint)))
    }
    return Array(processes.sorted { $0.footprintBytes > $1.footprintBytes }.prefix(limit))
  }

  private static func processName(_ pid: pid_t) -> String {
    var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
    if proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 {
      let path = String(cString: buffer)
      if let app = LaunchItemParser.enclosingApp(path) {
        return URL(fileURLWithPath: app).deletingPathExtension().lastPathComponent
      }
      return URL(fileURLWithPath: path).lastPathComponent
    }
    return "Process \(pid)"
  }
}

public enum MemoryReclaimer {
  private static let gibibyte: Int64 = 1_073_741_824

  /// Never allocate more than free plus inactive memory, minus 1 GB.
  public static func allocationLimit(free: Int64, inactive: Int64) -> Int64 {
    max(0, free + inactive - gibibyte)
  }

  /// Flushes the file cache with `purge`, which asks for an administrator password.
  public static func reclaimWithPurge(privileged: PrivilegedRunning) async throws {
    _ = try await privileged.run(command: "/usr/sbin/purge")
  }

  /// Fills memory with incompressible blocks so macOS evicts caches, then frees it all.
  /// Stops at the limit, when pressure reaches 2, or when cancelled. Returns the bytes held at
  /// the peak.
  public static func reclaimWithAllocation(
    limitBytes: Int64,
    blockBytes: Int = 256 * 1_048_576,
    pressure: @Sendable () -> Int = { MemoryService.pressureLevel() },
    isCancelled: @Sendable () -> Bool
  ) async -> Int64 {
    var blocks: [UnsafeMutableRawPointer] = []
    defer { blocks.forEach { $0.deallocate() } }
    var allocated: Int64 = 0
    while allocated + Int64(blockBytes) <= limitBytes, !isCancelled(), pressure() < 2 {
      let block = UnsafeMutableRawPointer.allocate(byteCount: blockBytes, alignment: 16)
      arc4random_buf(block, blockBytes)
      blocks.append(block)
      allocated += Int64(blockBytes)
      await Task.yield()
    }
    return allocated
  }
}
