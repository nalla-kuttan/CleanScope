import Foundation
import Testing

@testable import CleanScopeCore

@Suite struct ScanBenchmarkTests {
  /// Runs only with CLEANSCOPE_BENCHMARK=1; prints serial and parallel Developer scan timings.
  @Test(.enabled(if: ProcessInfo.processInfo.environment["CLEANSCOPE_BENCHMARK"] == "1"))
  func developerScanTimings() async {
    let paths = ScanLocations.recommended(mode: .developer)
    for concurrency in [1, 6] {
      let start = Date()
      let session = await ScannerService(
        classifier: ClassificationService(), maxConcurrency: concurrency
      ).scan(paths: paths, mode: .developer, settings: .default) { _ in }
      print(
        "BENCH concurrency=\(concurrency) seconds=\(Date().timeIntervalSince(start)) results=\(session.results.count)"
      )
    }
  }
}
