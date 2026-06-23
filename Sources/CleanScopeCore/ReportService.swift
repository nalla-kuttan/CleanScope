import Foundation

public struct ReportService: Sendable {
  public init() {}

  public func report(from session: CleanupSession) -> String {
    var lines: [String] = [
      "Cleanup Report",
      "Recovered: \(session.recoveredBytes) bytes (\(ByteCount.string(session.recoveredBytes)))",
      "Deleted: \(session.deletedItems.count)",
      "Skipped: \(session.skippedItems.count)",
      "Permission-blocked: \(session.blockedItems.count)",
      "Failed: \(session.failedItems.count)",
    ]
    for item in session.blockedItems + session.failedItems + session.skippedItems {
      lines.append("\(item.path): \(item.message)")
    }
    return lines.joined(separator: "\n")
  }
}
