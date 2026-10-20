import AppKit
import CleanScopeCore
import SwiftUI

/// The menu bar extra: free space, Trash, last scan and quick actions.
struct MenuBarContentView: View {
  @EnvironmentObject private var model: AppModel
  @EnvironmentObject private var status: StatusMonitor
  @Environment(\.openWindow) private var openWindow
  @State private var confirmsEmptyTrash = false

  private var usedFraction: Double {
    guard let disk = status.disk, disk.totalBytes > 0 else { return 0 }
    return Double(disk.usedBytes) / Double(disk.totalBytes)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 8) {
        BrandMarkView(size: 22, isDecorative: true)
        Text("CleanScope").font(.headline)
        Spacer()
      }

      VStack(alignment: .leading, spacing: 4) {
        HStack {
          Text("Startup disk")
          Spacer()
          Text("\(ByteCount.string(status.disk?.availableBytes ?? 0)) free")
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
        ProgressView(value: usedFraction)
          .tint(BrandTheme.sage)
          .accessibilityLabel("Startup disk used")
          .accessibilityValue("\(Int(usedFraction * 100)) percent")
      }

      HStack {
        Text("Trash")
        Spacer()
        if status.trashNeedsFullDiskAccess {
          Text("Needs Full Disk Access").foregroundStyle(.secondary)
        } else {
          Text(ByteCount.string(status.trashBytes ?? 0))
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
      }

      Text(lastScanLine)
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      SystemMonitorSections()

      Divider()

      VStack(alignment: .leading, spacing: 6) {
        Button("Open CleanScope") { openMainWindow() }
        Button("Start Limited Scan") {
          openMainWindow()
          Task { await model.startScan(mode: .limited) }
        }
        .disabled(model.isScanning)
        Button("Empty Trash…") { confirmsEmptyTrash = true }
          .disabled((status.trashBytes ?? 0) == 0)
        Button("Settings…") {
          NSApp.activate(ignoringOtherApps: true)
          NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
        Divider()
        Button("Quit CleanScope") { NSApp.terminate(nil) }
      }
      .buttonStyle(.plain)
      .foregroundStyle(BrandTheme.bark)
    }
    .padding(14)
    .frame(width: 300)
    .onAppear { status.refresh() }
    .alert("Permanently erase \(ByteCount.string(status.trashBytes ?? 0)) in the Trash?",
      isPresented: $confirmsEmptyTrash
    ) {
      Button("Cancel", role: .cancel) {}
      Button("Empty Trash", role: .destructive) { model.emptyTrash() }
    } message: {
      Text("This can't be undone.")
    }
  }

  private var lastScanLine: String {
    guard let session = model.session, let completed = session.completedAt else {
      return "No scan yet."
    }
    return
      "Last scan: \(completed.formatted(date: .abbreviated, time: .shortened)), potential cleanup \(ByteCount.string(session.summary.totalCleanableBytes))"
  }

  private func openMainWindow() {
    NSApp.activate(ignoringOtherApps: true)
    if let window = NSApp.windows.first(where: { $0.canBecomeMain && $0.isVisible }) {
      window.makeKeyAndOrderFront(nil)
    } else {
      openWindow(id: "main")
    }
  }
}

/// Placeholder until the system monitors land; replaced in the monitoring phase.
struct SystemMonitorSections: View {
  var body: some View { EmptyView() }
}
