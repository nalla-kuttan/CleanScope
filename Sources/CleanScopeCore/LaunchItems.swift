import Foundation

public enum LaunchItemScope: String, Codable, Sendable {
  case userAgent
  case systemAgent
  case systemDaemon

  public var title: String {
    switch self {
    case .userAgent: return "Your account"
    case .systemAgent: return "All users"
    case .systemDaemon: return "System"
    }
  }
}

public enum LaunchItemState: String, Equatable, Sendable {
  case running
  case loaded
  case disabled
  case notLoaded
  /// A system item whose state needs an administrator to read.
  case installed

  public var title: String {
    switch self {
    case .running: return "Running"
    case .loaded: return "Loaded"
    case .disabled: return "Disabled"
    case .notLoaded: return "Not loaded"
    case .installed: return "Installed"
    }
  }
}

public struct LaunchItem: Identifiable, Equatable, Sendable {
  public var id: String { plistPath }
  public var label: String
  public var program: String?
  public var plistPath: String
  public var scope: LaunchItemScope
  public var runAtLoad: Bool
  public var keepAlive: Bool
  public var disabled: Bool
  public var isBroken: Bool
  public var owningAppPath: String?
  public var teamID: String?
  public var state: LaunchItemState

  public var requiresAdmin: Bool { scope != .userAgent }

  public var displayName: String {
    if let app = owningAppPath {
      return URL(fileURLWithPath: app).deletingPathExtension().lastPathComponent
    }
    if let program { return URL(fileURLWithPath: program).lastPathComponent }
    return label
  }

  public init(
    label: String, program: String?, plistPath: String, scope: LaunchItemScope,
    runAtLoad: Bool = false, keepAlive: Bool = false, disabled: Bool = false,
    isBroken: Bool = false, owningAppPath: String? = nil, teamID: String? = nil,
    state: LaunchItemState = .notLoaded
  ) {
    self.label = label
    self.program = program
    self.plistPath = plistPath
    self.scope = scope
    self.runAtLoad = runAtLoad
    self.keepAlive = keepAlive
    self.disabled = disabled
    self.isBroken = isBroken
    self.owningAppPath = owningAppPath
    self.teamID = teamID
    self.state = state
  }
}

public enum LaunchItemParser {
  public static func parse(
    plistURL: URL, scope: LaunchItemScope, fileExists: (String) -> Bool
  ) -> LaunchItem? {
    guard let data = try? Data(contentsOf: plistURL),
      let plist = try? PropertyListSerialization.propertyList(from: data, format: nil)
        as? [String: Any],
      let label = plist["Label"] as? String, !label.isEmpty
    else { return nil }

    let program =
      (plist["Program"] as? String) ?? (plist["ProgramArguments"] as? [String])?.first
    let keepAlive: Bool
    if let flag = plist["KeepAlive"] as? Bool {
      keepAlive = flag
    } else {
      keepAlive = plist["KeepAlive"] is [String: Any]
    }
    return LaunchItem(
      label: label,
      program: program,
      plistPath: plistURL.path,
      scope: scope,
      runAtLoad: plist["RunAtLoad"] as? Bool ?? false,
      keepAlive: keepAlive,
      disabled: plist["Disabled"] as? Bool ?? false,
      isBroken: program.map { !fileExists($0) } ?? true,
      owningAppPath: program.flatMap(enclosingApp)
    )
  }

  /// The `.app` bundle that contains `path`, if any.
  public static func enclosingApp(_ path: String) -> String? {
    guard let range = path.range(of: ".app/", options: .backwards) else {
      return path.hasSuffix(".app") ? path : nil
    }
    return String(path[..<range.lowerBound]) + ".app"
  }
}

/// What `launchctl list` and `launchctl print-disabled` report for the user's domain.
public struct LaunchctlStatus: Sendable {
  private var pids: [String: Bool] = [:]
  private var overrides: [String: Bool] = [:]

  public init() {}

  public init(listOutput: String, disabledOutput: String) {
    for line in listOutput.split(whereSeparator: \.isNewline).dropFirst() {
      let columns = line.split(separator: "\t")
      guard columns.count >= 3 else { continue }
      pids[String(columns[2])] = columns[0] != "-"
    }
    for line in disabledOutput.split(whereSeparator: \.isNewline) {
      let parts = line.components(separatedBy: "=>")
      guard parts.count == 2 else { continue }
      let label = parts[0].trimmingCharacters(in: .whitespaces).trimmingCharacters(
        in: CharacterSet(charactersIn: "\""))
      let value = parts[1].trimmingCharacters(in: .whitespaces)
      overrides[label] = value == "disabled" || value == "true"
    }
  }

  public func state(for label: String, plistDisabled: Bool, scope: LaunchItemScope = .userAgent)
    -> LaunchItemState
  {
    if let disabled = overrides[label] {
      if disabled { return .disabled }
    } else if plistDisabled {
      return .disabled
    }
    if let running = pids[label] { return running ? .running : .loaded }
    return scope == .userAgent ? .notLoaded : .installed
  }
}

public struct LaunchItemService: Sendable {
  private let fileExists: @Sendable (String) -> Bool
  private let signer: @Sendable (String) -> SignerInfo?

  public init(
    fileExists: @escaping @Sendable (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
    signer: @escaping @Sendable (String) -> SignerInfo? = { CodeSigning.signer(path: $0) }
  ) {
    self.fileExists = fileExists
    self.signer = signer
  }

  public static func standardDirectories(homeDirectory: String = NSHomeDirectory())
    -> [(URL, LaunchItemScope)]
  {
    [
      (URL(fileURLWithPath: homeDirectory).appendingPathComponent("Library/LaunchAgents"), .userAgent),
      (URL(fileURLWithPath: "/Library/LaunchAgents"), .systemAgent),
      (URL(fileURLWithPath: "/Library/LaunchDaemons"), .systemDaemon),
    ]
  }

  /// Third-party launch items. Items labeled `com.apple.` or signed by Apple are left out.
  public func items(in directories: [(URL, LaunchItemScope)], status: LaunchctlStatus)
    -> [LaunchItem]
  {
    directories.flatMap { directory, scope -> [LaunchItem] in
      let files =
        (try? FileManager.default.contentsOfDirectory(
          at: directory, includingPropertiesForKeys: nil)) ?? []
      return files.filter { $0.pathExtension == "plist" }.compactMap { url in
        guard var item = LaunchItemParser.parse(plistURL: url, scope: scope, fileExists: fileExists),
          !item.label.hasPrefix("com.apple.")
        else { return nil }
        if let program = item.program, !item.isBroken {
          let info = signer(item.owningAppPath ?? program)
          if info?.isApple == true { return nil }
          item.teamID = info?.teamID
        }
        item.state = status.state(for: item.label, plistDisabled: item.disabled, scope: scope)
        return item
      }
    }
    .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
  }

  public static func currentStatus(runner: ProcessRunning = ProcessRunner()) async
    -> LaunchctlStatus
  {
    let uid = getuid()
    let list = try? await runner.run("/bin/launchctl", ["list"], timeout: 10)
    let disabled = try? await runner.run(
      "/bin/launchctl", ["print-disabled", "gui/\(uid)"], timeout: 10)
    return LaunchctlStatus(
      listOutput: list?.stdout ?? "", disabledOutput: disabled?.stdout ?? "")
  }
}

public enum LaunchItemCommands {
  public static func bootout(_ item: LaunchItem, uid: uid_t) -> [String] {
    ["/bin/launchctl", "bootout", "gui/\(uid)", item.plistPath]
  }

  public static func disable(_ item: LaunchItem, uid: uid_t) -> [String] {
    ["/bin/launchctl", "disable", "gui/\(uid)/\(item.label)"]
  }

  public static func adminDisable(_ item: LaunchItem) -> String {
    "/bin/launchctl bootout system \(ShellQuote.quote(item.plistPath)); /bin/launchctl disable \(ShellQuote.quote("system/" + item.label))"
  }

  public static func adminRemove(_ item: LaunchItem) -> String {
    "/bin/launchctl bootout system \(ShellQuote.quote(item.plistPath)); /usr/bin/trash \(ShellQuote.quote(item.plistPath))"
  }
}

/// Login items added the older way, read and removed through System Events.
public enum LegacyLoginItems {
  public static let listScript =
    #"tell application "System Events" to get the name of every login item"#

  public static func deleteScript(name: String) -> String {
    #"tell application "System Events" to delete login item "#
      + ShellQuote.appleScriptLiteral(name)
  }

  public static func parseNames(_ output: String) -> [String] {
    output.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }
  }

  public static let settingsURL = URL(
    string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!
}
