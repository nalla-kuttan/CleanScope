import AppKit
import CleanScopeCore
import SwiftUI

/// Memory pressure, what uses memory, and an honest "free up memory" action.
struct MemoryView: View {
  @State private var snapshot = MemoryService.snapshot()
  @State private var consumers: [ProcessMemory] = []
  @State private var isFreeing = false
  @State private var cancelFlag = CancelFlag()
  @State private var outcome: String?
  @State private var pendingQuit: ProcessMemory?

  private let timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        PageHeader(
          title: "Memory",
          subtitle: "macOS manages memory on its own. This view shows how it's being used.")

        HStack(spacing: 12) {
          StorageMetricView(
            label: "Memory pressure",
            value: MemoryService.pressureTitle(snapshot.pressureLevel),
            symbol: "waveform.path.ecg",
            tint: snapshot.pressureLevel >= 2 ? BrandTheme.review : BrandTheme.safe)
          StorageMetricView(
            label: "Swap used", value: ByteCount.string(snapshot.swapUsedBytes),
            symbol: "arrow.left.arrow.right", tint: BrandTheme.info)
          StorageMetricView(
            label: "Installed", value: ByteCount.string(snapshot.totalBytes),
            symbol: "memorychip", tint: BrandTheme.info)
        }

        breakdown

        freeUpSection

        VStack(alignment: .leading, spacing: 8) {
          Text("Using the most memory")
            .font(.system(.title3, design: .rounded).bold())
            .foregroundStyle(BrandTheme.textPrimary)
          ForEach(consumers) { process in
            HStack {
              Text(process.name).lineLimit(1)
              Spacer()
              Text(ByteCount.string(process.footprintBytes))
                .monospacedDigit()
                .foregroundStyle(.secondary)
              Button("Quit…") { pendingQuit = process }
                .disabled(runningApp(process) == nil)
                .help(runningApp(process) == nil ? "Only apps can be quit here." : "Quit \(process.name)")
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(BrandTheme.surfaceRaised)
            .clipShape(RoundedRectangle(cornerRadius: 8))
          }
        }
      }
      .padding(24)
      .frame(maxWidth: 980, alignment: .leading)
    }
    .background(BrandTheme.surface)
    .task { refresh() }
    .onReceive(timer) { _ in refresh() }
    .alert(
      "Quit \(pendingQuit?.name ?? "")?",
      isPresented: Binding(get: { pendingQuit != nil }, set: { if !$0 { pendingQuit = nil } })
    ) {
      Button("Cancel", role: .cancel) {}
      Button("Quit") {
        if let process = pendingQuit { runningApp(process)?.terminate() }
      }
    } message: {
      Text("The app may ask you to save open documents first.")
    }
  }

  private var breakdown: some View {
    let parts: [(String, Int64, Color)] = [
      ("App memory", snapshot.appBytes, BrandTheme.accent),
      ("Wired", snapshot.wiredBytes, BrandTheme.info),
      ("Compressed", snapshot.compressedBytes, BrandTheme.review),
      ("Cached files", snapshot.cachedBytes, BrandTheme.textSecondary),
    ]
    let total = max(1, snapshot.totalBytes)
    return VStack(alignment: .leading, spacing: 8) {
      GeometryReader { proxy in
        HStack(spacing: 2) {
          ForEach(parts, id: \.0) { part in
            Rectangle()
              .fill(part.2.opacity(0.7))
              .frame(width: max(0, proxy.size.width * CGFloat(part.1) / CGFloat(total)))
          }
          Spacer(minLength: 0)
        }
      }
      .frame(height: 14)
      .clipShape(RoundedRectangle(cornerRadius: 4))
      .background(RoundedRectangle(cornerRadius: 4).fill(BrandTheme.surfaceRaised))
      .accessibilityHidden(true)

      HStack(spacing: 16) {
        ForEach(parts, id: \.0) { part in
          HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(part.2.opacity(0.7)).frame(width: 10, height: 10)
            Text("\(part.0) \(ByteCount.string(part.1))")
          }
          .accessibilityElement(children: .combine)
        }
      }
      .font(.caption)
      .foregroundStyle(.secondary)
    }
  }

  private var freeUpSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 10) {
        Button("Free Up Memory…") { Task { await freeWithPurge() } }
          .disabled(isFreeing)
          .help("Clears the file cache with macOS's purge tool. Asks for your password.")
        Button("Free Up Without Password") { Task { await freeWithAllocation() } }
          .disabled(isFreeing)
          .help("Briefly fills unused memory so macOS clears caches, then releases it.")
        if isFreeing {
          ProgressView().controlSize(.small)
          Button("Stop") { cancelFlag.cancel() }
        }
      }
      Text(
        "Apps may reload data from disk afterward, so they can feel slower for a moment. macOS normally frees memory by itself."
      )
      .font(.caption)
      .foregroundStyle(.secondary)
      if let outcome {
        Label(outcome, systemImage: "info.circle").foregroundStyle(.secondary)
      }
    }
  }

  private func refresh() {
    snapshot = MemoryService.snapshot()
    consumers = MemoryService.topConsumers(limit: 10)
  }

  private func runningApp(_ process: ProcessMemory) -> NSRunningApplication? {
    guard let app = NSRunningApplication(processIdentifier: process.pid),
      app.activationPolicy == .regular
    else { return nil }
    return app
  }

  private func report(before: MemorySnapshot) {
    refresh()
    let change = snapshot.freeBytes + snapshot.inactiveBytes - before.freeBytes - before.inactiveBytes
    outcome =
      "Free memory went from \(ByteCount.string(before.freeBytes)) to \(ByteCount.string(snapshot.freeBytes))"
      + (change > 0 ? "." : ". macOS was already using memory efficiently.")
  }

  private func freeWithPurge() async {
    isFreeing = true
    let before = MemoryService.snapshot()
    do {
      try await MemoryReclaimer.reclaimWithPurge(privileged: AppleScriptPrivilegedRunner())
      report(before: before)
    } catch PrivilegedRunnerError.cancelled {
      outcome = "You didn't authorize this task."
    } catch {
      outcome = "macOS could not clear the file cache."
    }
    isFreeing = false
  }

  private func freeWithAllocation() async {
    isFreeing = true
    cancelFlag = CancelFlag()
    let flag = cancelFlag
    let before = MemoryService.snapshot()
    if before.pressureLevel >= 2 {
      outcome = "Memory pressure is already elevated, so CleanScope won't add to it."
      isFreeing = false
      return
    }
    let limit = MemoryReclaimer.allocationLimit(free: before.freeBytes, inactive: before.inactiveBytes)
    _ = await Task.detached(priority: .utility) {
      await MemoryReclaimer.reclaimWithAllocation(limitBytes: limit, isCancelled: { flag.isCancelled })
    }.value
    report(before: before)
    isFreeing = false
  }
}

final class CancelFlag: @unchecked Sendable {
  private let lock = NSLock()
  private var cancelled = false
  func cancel() { lock.withLock { cancelled = true } }
  var isCancelled: Bool { lock.withLock { cancelled } }
}
