import Foundation

public enum SystemSpaceError: Error, Equatable {
  case commandFailed(String)
}

/// Space macOS manages itself: purgeable space and local Time Machine snapshots.
public struct SystemSpaceService: Sendable {
  private let runner: ProcessRunning

  public init(runner: ProcessRunning = ProcessRunner()) {
    self.runner = runner
  }

  public static func purgeableBytes(important: Int64, available: Int64) -> Int64 {
    max(0, important - available)
  }

  public func purgeableBytes(volume: URL = URL(fileURLWithPath: "/")) -> Int64 {
    let values = try? volume.resourceValues(forKeys: [
      .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey,
    ])
    return Self.purgeableBytes(
      important: values?.volumeAvailableCapacityForImportantUsage ?? 0,
      available: Int64(values?.volumeAvailableCapacity ?? 0))
  }

  public func localSnapshots() async -> [Date] {
    guard
      let output = try? await runner.run(
        "/usr/bin/tmutil", ["listlocalsnapshots", "/"], timeout: 30),
      output.status == 0
    else { return [] }
    return Self.parseSnapshots(output.stdout)
  }

  /// Dates of `com.apple.TimeMachine.YYYY-MM-DD-HHMMSS.local` lines, oldest first.
  public static func parseSnapshots(_ output: String, timeZone: TimeZone = .current) -> [Date] {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = timeZone
    formatter.dateFormat = "yyyy-MM-dd-HHmmss"
    let prefix = "com.apple.TimeMachine."
    let suffix = ".local"
    return output.split(whereSeparator: \.isNewline).compactMap { line -> Date? in
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      guard trimmed.hasPrefix(prefix), trimmed.hasSuffix(suffix) else { return nil }
      let stamp = trimmed.dropFirst(prefix.count).dropLast(suffix.count)
      return formatter.date(from: String(stamp))
    }.sorted()
  }

  /// Asks macOS to remove local snapshots until `requestedBytes` are free. Urgency 1 is the
  /// lowest level; 4 is the highest.
  public func thin(requestedBytes: Int64, urgency: Int = 1) async throws {
    let output = try await runner.run(
      "/usr/bin/tmutil",
      ["thinlocalsnapshots", "/", String(requestedBytes), String(min(max(urgency, 1), 4))],
      timeout: 120)
    guard output.status == 0 else {
      let message = output.stderr.isEmpty ? output.stdout : output.stderr
      throw SystemSpaceError.commandFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
    }
  }
}
