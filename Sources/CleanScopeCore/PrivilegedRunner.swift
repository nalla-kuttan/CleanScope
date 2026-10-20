import Foundation

public enum PrivilegedRunnerError: Error, Equatable {
  case cancelled
  case failed(String)
}

/// Runs one fixed shell command as an administrator. macOS shows its own password prompt each
/// time; nothing stays elevated.
public protocol PrivilegedRunning: Sendable {
  func run(command: String) async throws -> ProcessOutput
}

public enum ShellQuote {
  /// Single-quotes `value` for `/bin/sh`, so it is always one literal argument.
  public static func quote(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
  }

  /// Escapes a shell command for an AppleScript string literal.
  public static func appleScriptLiteral(_ command: String) -> String {
    "\"" + command.replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"") + "\""
  }
}

public struct AppleScriptPrivilegedRunner: PrivilegedRunning {
  public init() {}

  public func run(command: String) async throws -> ProcessOutput {
    let source =
      "do shell script \(ShellQuote.appleScriptLiteral(command)) with administrator privileges"
    return try await MainActor.run {
      var error: NSDictionary?
      guard let script = NSAppleScript(source: source) else {
        throw PrivilegedRunnerError.failed("Could not prepare the command.")
      }
      let result = script.executeAndReturnError(&error)
      if let error {
        if (error[NSAppleScript.errorNumber] as? Int) == -128 {
          throw PrivilegedRunnerError.cancelled
        }
        throw PrivilegedRunnerError.failed(
          error[NSAppleScript.errorMessage] as? String ?? "The command failed.")
      }
      return ProcessOutput(status: 0, stdout: result.stringValue ?? "", stderr: "")
    }
  }
}
