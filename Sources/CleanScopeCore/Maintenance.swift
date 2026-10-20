import Foundation

public enum MaintenanceOutcome: Codable, Equatable, Sendable {
  case completed(String)
  case failed(String)
  case skipped(String)

  public var message: String {
    switch self {
    case .completed(let text), .failed(let text), .skipped(let text): return text
    }
  }

  public var isSuccess: Bool {
    if case .completed = self { return true }
    return false
  }
}

public struct MaintenanceContext: Sendable {
  public var runner: ProcessRunning
  public var privileged: PrivilegedRunning
  public var homeDirectory: String
  public var uid: uid_t
  /// Quits Mail and returns once it has quit or 10 seconds pass.
  public var quitMail: @Sendable () async -> Void
  public var isMailRunning: @Sendable () -> Bool

  public init(
    runner: ProcessRunning,
    privileged: PrivilegedRunning,
    homeDirectory: String = NSHomeDirectory(),
    uid: uid_t = getuid(),
    quitMail: @escaping @Sendable () async -> Void = {},
    isMailRunning: @escaping @Sendable () -> Bool = { false }
  ) {
    self.runner = runner
    self.privileged = privileged
    self.homeDirectory = homeDirectory
    self.uid = uid
    self.quitMail = quitMail
    self.isMailRunning = isMailRunning
  }
}

public protocol MaintenanceTask: Sendable {
  var id: String { get }
  var title: String { get }
  var summary: String { get }
  var requiresAdmin: Bool { get }
  var isRecommended: Bool { get }
  var isAvailable: Bool { get }
  func run(context: MaintenanceContext) async -> MaintenanceOutcome
}

/// A task that runs one fixed administrator command.
struct AdminCommandTask: MaintenanceTask {
  let id: String
  let title: String
  let summary: String
  let isRecommended: Bool
  let isAvailable: Bool
  let successMessage: String
  var requiresAdmin: Bool { true }

  func run(context: MaintenanceContext) async -> MaintenanceOutcome {
    guard let command = MaintenanceCatalog.adminCommand(for: id, uid: context.uid) else {
      return .failed("This task has no command.")
    }
    do {
      _ = try await context.privileged.run(command: command)
      return .completed(successMessage)
    } catch PrivilegedRunnerError.cancelled {
      return .skipped("You didn't authorize this task.")
    } catch PrivilegedRunnerError.failed(let message) {
      return .failed(message)
    } catch {
      return .failed(error.localizedDescription)
    }
  }
}

/// Asks macOS to thin local Time Machine snapshots.
struct ThinSnapshotsTask: MaintenanceTask {
  let id: String
  let title: String
  let summary: String
  let isRecommended: Bool
  let requestedBytes: Int64
  let urgency: Int
  var requiresAdmin: Bool { false }
  var isAvailable: Bool { true }

  func run(context: MaintenanceContext) async -> MaintenanceOutcome {
    do {
      try await SystemSpaceService(runner: context.runner).thin(
        requestedBytes: requestedBytes, urgency: urgency)
      return .completed("macOS finished thinning local snapshots.")
    } catch SystemSpaceError.commandFailed(let message) {
      return .failed(message.isEmpty ? "macOS could not thin local snapshots." : message)
    } catch {
      return .failed(error.localizedDescription)
    }
  }
}

struct SpeedUpMailTask: MaintenanceTask {
  var id: String { "speed-up-mail" }
  var title: String { "Speed up Mail" }
  var summary: String {
    "Quits Mail, compacts its message index and asks Spotlight to index your mail again. Needs Full Disk Access."
  }
  var requiresAdmin: Bool { false }
  var isRecommended: Bool { true }
  var isAvailable: Bool { true }

  func run(context: MaintenanceContext) async -> MaintenanceOutcome {
    let databases = MailVacuum.envelopeIndexURLs(homeDirectory: context.homeDirectory)
    guard !databases.isEmpty else {
      return .skipped("No Mail data was found, or CleanScope needs Full Disk Access to read it.")
    }
    await context.quitMail()
    do {
      for database in databases {
        try MailVacuum.vacuum(databaseURL: database, isMailRunning: context.isMailRunning)
      }
    } catch MailVacuumError.mailStillRunning {
      return .skipped("Mail is still open. Quit Mail and try again.")
    } catch {
      return .failed("Mail's index could not be compacted. It was restored from a backup.")
    }
    let mail = URL(fileURLWithPath: context.homeDirectory).appendingPathComponent("Library/Mail")
    _ = try? await context.runner.run("/usr/bin/mdimport", [mail.path], timeout: 120)
    return .completed("Mail's index was compacted.")
  }
}

public enum MaintenanceCatalog {
  public static func all(
    fileExists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
  ) -> [any MaintenanceTask] {
    [
      ThinSnapshotsTask(
        id: "free-purgeable",
        title: "Free up purgeable space",
        summary: "Asks macOS to release up to 1 GB of purgeable space now instead of waiting until space runs low.",
        isRecommended: true,
        requestedBytes: 1_073_741_824,
        urgency: 3),
      ThinSnapshotsTask(
        id: "thin-snapshots",
        title: "Thin Time Machine snapshots",
        summary: "Asks macOS to remove local snapshots to free up to 20 GB. Backups on your Time Machine disk are not affected.",
        isRecommended: false,
        requestedBytes: 20_000_000_000,
        urgency: 1),
      AdminCommandTask(
        id: "flush-dns",
        title: "Flush DNS cache",
        summary: "Clears saved network addresses. Helps when websites fail to load after a network change.",
        isRecommended: true,
        isAvailable: true,
        successMessage: "The DNS cache was cleared."),
      AdminCommandTask(
        id: "reindex-spotlight",
        title: "Reindex Spotlight",
        summary: "Rebuilds the search index for your startup disk. Search is slow until it finishes, which can take a while.",
        isRecommended: false,
        isAvailable: true,
        successMessage: "Spotlight is rebuilding its index. Search may be slow for a while."),
      AdminCommandTask(
        id: "periodic",
        title: "Run maintenance scripts",
        summary: "Runs the daily, weekly and monthly system maintenance scripts.",
        isRecommended: false,
        isAvailable: fileExists("/usr/sbin/periodic"),
        successMessage: "Maintenance scripts finished."),
      AdminCommandTask(
        id: "repair-home-permissions",
        title: "Repair home folder permissions",
        summary: "Resets permissions in your home folder to macOS defaults. Custom sharing permissions you set are reset too.",
        isRecommended: false,
        isAvailable: true,
        successMessage: "Home folder permissions were reset."),
      SpeedUpMailTask(),
    ]
  }

  /// Fixed administrator commands. The only argument is the numeric user id.
  public static func adminCommand(for id: String, uid: uid_t) -> String? {
    switch id {
    case "flush-dns": return "/usr/bin/dscacheutil -flushcache; /usr/bin/killall -HUP mDNSResponder"
    case "reindex-spotlight": return "/usr/bin/mdutil -E /"
    case "periodic": return "/usr/sbin/periodic daily weekly monthly"
    case "repair-home-permissions": return "/usr/sbin/diskutil resetUserPermissions / \(uid)"
    default: return nil
    }
  }
}

public struct MaintenanceRun: Codable, Equatable, Sendable {
  public var taskID: String
  public var date: Date
  public var outcome: MaintenanceOutcome

  public init(taskID: String, date: Date, outcome: MaintenanceOutcome) {
    self.taskID = taskID
    self.date = date
    self.outcome = outcome
  }
}

public struct MaintenanceRunStore: @unchecked Sendable {
  private let defaults: UserDefaults
  private let key = "CleanScope.maintenanceRuns"

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  public func load() throws -> [String: MaintenanceRun] {
    guard let data = defaults.data(forKey: key) else { return [:] }
    return try JSONDecoder().decode([String: MaintenanceRun].self, from: data)
  }

  public func record(_ run: MaintenanceRun) throws {
    var runs = try load()
    runs[run.taskID] = run
    defaults.set(try JSONEncoder().encode(runs), forKey: key)
  }
}
