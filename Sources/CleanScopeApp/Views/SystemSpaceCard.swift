import CleanScopeCore
import SwiftUI

/// Read-only summary of space macOS manages itself, with an opt-in snapshot thinning action.
struct SystemSpaceCard: View {
  @EnvironmentObject private var model: AppModel
  @State private var showsThinSheet = false

  private var snapshotSummary: String {
    let snapshots = model.localSnapshots
    guard let first = snapshots.first, let last = snapshots.last else {
      return "No local snapshots"
    }
    let range =
      snapshots.count == 1
      ? first.formatted(date: .abbreviated, time: .omitted)
      : "\(first.formatted(date: .abbreviated, time: .omitted)) – \(last.formatted(date: .abbreviated, time: .omitted))"
    return "\(snapshots.count) local snapshot\(snapshots.count == 1 ? "" : "s") · \(range)"
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline) {
        Label("System-managed space", systemImage: "gearshape.2")
          .font(.headline)
          .foregroundStyle(BrandTheme.textPrimary)
        Spacer()
        if model.settings.allowSnapshotThinning && !model.localSnapshots.isEmpty {
          Button("Ask macOS to thin local snapshots…") { showsThinSheet = true }
            .controlSize(.small)
        }
      }

      HStack(spacing: 12) {
        StorageMetricView(
          label: "Purgeable",
          value: ByteCount.string(model.purgeableBytes),
          symbol: "arrow.3.trianglepath",
          tint: BrandTheme.info
        )
        StorageMetricView(
          label: "Time Machine",
          value: snapshotSummary,
          symbol: "clock.arrow.circlepath",
          tint: BrandTheme.info
        )
      }

      Text(
        "macOS can reclaim purgeable space automatically when space runs low. Available space includes \(ByteCount.string(model.purgeableBytes)) that macOS can reclaim."
      )
      .font(.caption)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
    }
    .sheet(isPresented: $showsThinSheet) {
      ThinSnapshotsSheet()
    }
  }
}

private struct ThinSnapshotsSheet: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.dismiss) private var dismiss
  @State private var requestedGB = 10
  @State private var isRunning = false
  @State private var outcome: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Thin local snapshots")
        .font(.title2.bold())
      Text(
        "macOS removes local Time Machine snapshots until the requested space is free. Backups on your Time Machine disk are not affected."
      )
      .fixedSize(horizontal: false, vertical: true)

      Picker("Space to request", selection: $requestedGB) {
        ForEach([5, 10, 20, 50], id: \.self) { Text("\($0) GB").tag($0) }
      }
      .pickerStyle(.segmented)

      if let outcome {
        Label(outcome, systemImage: "info.circle")
          .foregroundStyle(.secondary)
      }

      HStack {
        Button(outcome == nil ? "Cancel" : "Done") { dismiss() }
          .keyboardShortcut(.cancelAction)
        Spacer()
        if isRunning { ProgressView().controlSize(.small) }
        Button("Thin Snapshots") {
          isRunning = true
          Task {
            outcome = await model.thinLocalSnapshots(
              requestedBytes: Int64(requestedGB) * 1_000_000_000)
            isRunning = false
          }
        }
        .disabled(isRunning || outcome != nil)
        .keyboardShortcut(.defaultAction)
      }
    }
    .padding(24)
    .frame(width: 460)
  }
}
