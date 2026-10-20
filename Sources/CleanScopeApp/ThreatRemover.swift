import AppKit
import CleanScopeCore
import Darwin

/// Carries out `MalwareRemoval` steps. Files go to the Trash unless Delete immediately is on.
enum ThreatRemover {
  enum Outcome {
    case removed
    case openedSettings(String)
    case failed(String)
  }

  @MainActor
  static func remove(_ threat: Threat, deleteImmediately: Bool) async -> Outcome {
    var openedSettings: String?
    for step in MalwareRemoval.steps(for: threat, deleteImmediately: deleteImmediately) {
      switch step {
      case .terminateProcesses(let inside):
        terminateProcesses(inside: inside)
      case .bootout(let plist):
        await bootout(plist: plist)
      case .detach(let mountPoint):
        _ = try? await ProcessRunner().run(
          "/usr/bin/hdiutil", ["detach", mountPoint, "-force"], timeout: 60)
      case .moveToTrash(let path):
        if let failure = await removeFile(path, permanently: false) { return .failed(failure) }
      case .deletePermanently(let path):
        if let failure = await removeFile(path, permanently: true) { return .failed(failure) }
      case .openProfilesSettings:
        NSWorkspace.shared.open(ConfigurationProfiles.settingsURL)
        openedSettings = "Remove the profile in System Settings › Device Management."
      case .openBrowserExtensions(let browser):
        openExtensions(browser: browser)
        openedSettings = "Remove the extension from \(browser)'s extensions page."
      }
    }
    return openedSettings.map(Outcome.openedSettings) ?? .removed
  }

  private static func terminateProcesses(inside path: String) {
    let capacity = Int(proc_listallpids(nil, 0)) + 32
    var pids = [pid_t](repeating: 0, count: max(capacity, 32))
    let count = pids.withUnsafeMutableBytes { Int(proc_listallpids($0.baseAddress, Int32($0.count))) }
    for pid in pids.prefix(max(count, 0)) where pid > 0 && pid != getpid() {
      var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
      guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { continue }
      let executable = String(cString: buffer)
      if executable == path || executable.hasPrefix(path + "/") {
        if let app = NSRunningApplication(processIdentifier: pid) {
          app.forceTerminate()
        } else {
          kill(pid, SIGTERM)
        }
      }
    }
  }

  private static func bootout(plist: String) async {
    if plist.hasPrefix(NSHomeDirectory()) {
      _ = try? await ProcessRunner().run(
        "/bin/launchctl", ["bootout", "gui/\(getuid())", plist], timeout: 10)
    } else {
      _ = try? await AppleScriptPrivilegedRunner().run(
        command: "/bin/launchctl bootout system \(ShellQuote.quote(plist))")
    }
  }

  /// Returns a failure message, or nil on success.
  private static func removeFile(_ path: String, permanently: Bool) async -> String? {
    let url = URL(fileURLWithPath: path)
    guard FileManager.default.fileExists(atPath: path) else { return nil }
    do {
      if permanently {
        try FileManager.default.removeItem(at: url)
      } else {
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
      }
      return nil
    } catch {
      let command =
        permanently ? "/bin/rm -rf \(ShellQuote.quote(path))" : "/usr/bin/trash \(ShellQuote.quote(path))"
      do {
        _ = try await AppleScriptPrivilegedRunner().run(command: command)
        return FileManager.default.fileExists(atPath: path) ? "The item is still in place." : nil
      } catch PrivilegedRunnerError.cancelled {
        return "You didn't authorize removing this item."
      } catch {
        return "The item could not be removed."
      }
    }
  }

  private static func openExtensions(browser: String) {
    switch browser {
    case "Safari":
      NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Safari.app"))
    default:
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
      process.arguments = ["-a", browser, BrowserExtensions.chromeExtensionsPage.absoluteString]
      try? process.run()
    }
  }
}
