import Foundation

@testable import CleanScopeCore

/// Records commands and returns canned output.
final class StubProcessRunner: ProcessRunning, @unchecked Sendable {
  private let lock = NSLock()
  private var calls: [(String, [String])] = []
  var output: ProcessOutput

  init(output: ProcessOutput = ProcessOutput(status: 0, stdout: "", stderr: "")) {
    self.output = output
  }

  var recorded: [(String, [String])] { lock.withLock { calls } }

  func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) async throws
    -> ProcessOutput
  {
    lock.withLock { calls.append((executable, arguments)) }
    return output
  }
}

/// Records privileged shell commands.
final class StubPrivilegedRunner: PrivilegedRunning, @unchecked Sendable {
  private let lock = NSLock()
  private var calls: [String] = []
  var output = ProcessOutput(status: 0, stdout: "", stderr: "")

  var recorded: [String] { lock.withLock { calls } }

  func run(command: String) async throws -> ProcessOutput {
    lock.withLock { calls.append(command) }
    return output
  }
}
