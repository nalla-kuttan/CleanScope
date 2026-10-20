import Foundation

public struct ProcessOutput: Equatable, Sendable {
  public var status: Int32
  public var stdout: String
  public var stderr: String

  public init(status: Int32, stdout: String, stderr: String) {
    self.status = status
    self.stdout = stdout
    self.stderr = stderr
  }
}

public enum ProcessRunnerError: Error, Equatable {
  case timedOut
  case launchFailed(String)
}

/// Runs a system tool. Injected everywhere so tests can feed canned output.
public protocol ProcessRunning: Sendable {
  func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) async throws
    -> ProcessOutput
}

public struct ProcessRunner: ProcessRunning {
  public init() {}

  public func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) async throws
    -> ProcessOutput
  {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr
    process.standardInput = FileHandle.nullDevice

    return try await withCheckedThrowingContinuation { continuation in
      let state = RunState()
      let group = DispatchGroup()
      let outData = DataBox()
      let errData = DataBox()
      group.enter()
      DispatchQueue.global().async {
        outData.set(stdout.fileHandleForReading.readDataToEndOfFile())
        group.leave()
      }
      group.enter()
      DispatchQueue.global().async {
        errData.set(stderr.fileHandleForReading.readDataToEndOfFile())
        group.leave()
      }

      process.terminationHandler = { finished in
        group.notify(queue: .global()) {
          guard state.finish() else { return }
          continuation.resume(
            returning: ProcessOutput(
              status: finished.terminationStatus,
              stdout: String(decoding: outData.value, as: UTF8.self),
              stderr: String(decoding: errData.value, as: UTF8.self)))
        }
      }

      do {
        try process.run()
      } catch {
        if state.finish() {
          continuation.resume(throwing: ProcessRunnerError.launchFailed(error.localizedDescription))
        }
        return
      }

      DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
        guard state.finish() else { return }
        process.terminate()
        continuation.resume(throwing: ProcessRunnerError.timedOut)
      }
    }
  }
}

/// Makes sure a continuation resumes exactly once.
private final class RunState: @unchecked Sendable {
  private let lock = NSLock()
  private var done = false

  func finish() -> Bool {
    lock.withLock {
      if done { return false }
      done = true
      return true
    }
  }
}

private final class DataBox: @unchecked Sendable {
  private let lock = NSLock()
  private var data = Data()

  func set(_ newValue: Data) { lock.withLock { data = newValue } }
  var value: Data { lock.withLock { data } }
}
