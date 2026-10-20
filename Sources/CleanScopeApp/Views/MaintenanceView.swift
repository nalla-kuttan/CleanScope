import AppKit
import CleanScopeCore
import SwiftUI

/// Maintenance tasks. Nothing runs on its own; each task explains what it does first.
struct MaintenanceView: View {
  @State private var runs: [String: MaintenanceRun] = [:]
  @State private var running: Set<String> = []

  private let tasks = MaintenanceCatalog.all().filter(\.isAvailable)
  private let store = MaintenanceRunStore()

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        HStack(alignment: .bottom) {
          VStack(alignment: .leading, spacing: 3) {
            Text("Maintenance")
              .font(.system(size: 26, weight: .bold, design: .rounded))
              .foregroundStyle(BrandTheme.bark)
            Text("Routine tasks you can run when you need them. Tasks marked Administrator ask for your password each time.")
              .font(.system(.subheadline, design: .rounded))
              .foregroundStyle(BrandTheme.warmGray)
              .fixedSize(horizontal: false, vertical: true)
          }
          Spacer()
          Button {
            Task { await runRecommended() }
          } label: {
            Label("Run Recommended", systemImage: "checklist")
          }
          .buttonStyle(.borderedProminent)
          .tint(BrandTheme.sage)
          .disabled(!running.isEmpty)
        }

        ForEach(tasks, id: \.id) { task in
          row(task)
        }
      }
      .padding(24)
      .frame(maxWidth: 980, alignment: .leading)
    }
    .background(BrandTheme.cream)
    .onAppear { runs = (try? store.load()) ?? [:] }
  }

  private func row(_ task: any MaintenanceTask) -> some View {
    HStack(alignment: .top, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 6) {
          Text(task.title).font(.headline).foregroundStyle(BrandTheme.bark)
          if task.isRecommended {
            Text("Recommended")
              .font(.caption2.weight(.semibold))
              .padding(.horizontal, 6)
              .padding(.vertical, 2)
              .background(Capsule().fill(BrandTheme.sage.opacity(0.15)))
              .foregroundStyle(BrandTheme.moss)
          }
          if task.requiresAdmin {
            Label("Administrator", systemImage: "lock")
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
        }
        Text(task.summary)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        Text(lastRunLine(task.id))
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
      if running.contains(task.id) {
        ProgressView().controlSize(.small)
      } else {
        Button("Run") { Task { await run(task) } }
          .disabled(!running.isEmpty)
      }
    }
    .padding(14)
    .background(BrandTheme.clay)
    .clipShape(RoundedRectangle(cornerRadius: BrandTheme.radius))
  }

  private func lastRunLine(_ id: String) -> String {
    guard let run = runs[id] else { return "Not run yet" }
    return
      "Last run \(run.date.formatted(date: .abbreviated, time: .shortened)): \(run.outcome.message)"
  }

  private func runRecommended() async {
    for task in tasks where task.isRecommended {
      await run(task)
    }
  }

  private func run(_ task: any MaintenanceTask) async {
    running.insert(task.id)
    let context = MaintenanceContext(
      runner: ProcessRunner(),
      privileged: AppleScriptPrivilegedRunner(),
      quitMail: { await Self.quitMail() },
      isMailRunning: { Self.isMailRunning() })
    let outcome = await task.run(context: context)
    let record = MaintenanceRun(taskID: task.id, date: Date(), outcome: outcome)
    try? store.record(record)
    runs[task.id] = record
    running.remove(task.id)
  }

  nonisolated private static let mailBundleID = "com.apple.mail"

  nonisolated private static func isMailRunning() -> Bool {
    !NSRunningApplication.runningApplications(withBundleIdentifier: mailBundleID).isEmpty
  }

  /// Asks Mail to quit and waits up to 10 seconds.
  private static func quitMail() async {
    let apps = await MainActor.run {
      NSRunningApplication.runningApplications(withBundleIdentifier: mailBundleID)
    }
    guard !apps.isEmpty else { return }
    await MainActor.run { apps.forEach { $0.terminate() } }
    for _ in 0..<20 where isMailRunning() {
      try? await Task.sleep(nanoseconds: 500_000_000)
    }
  }
}
