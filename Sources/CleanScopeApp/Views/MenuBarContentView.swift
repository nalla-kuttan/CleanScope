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
        ModuleIcon(key: .scan, size: 32)
        Text("CleanScope").font(.headline)
        Spacer()
        if let terrarium = model.terrariumSnapshot {
          Image(nsImage: terrarium)
            .resizable()
            .frame(width: 120, height: 80)
            .accessibilityLabel(TerrariumLayout.accessibilityLabel(for: model.terrariumLayers))
        }
      }

      Button("Review Quick Wins…") {
        model.destination = .dashboard
        openMainWindow()
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.small)

      VStack(alignment: .leading, spacing: 4) {
        HStack {
          Text("Startup disk")
          Spacer()
          Text("\(ByteCount.string(status.disk?.availableBytes ?? 0)) free")
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
        ProgressView(value: usedFraction)
          .tint(BrandTheme.accent)
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

      ForEach(status.externalVolumes, id: \.uuid) { volume in
        HStack {
          Image(systemName: "externaldrive")
          Text(volume.name).lineLimit(1)
          Spacer()
          Text("\(ByteCount.string(volume.availableBytes)) free")
            .monospacedDigit()
            .foregroundStyle(.secondary)
          if let url = volume.url {
            Button("Scan") {
              openMainWindow()
              Task { await model.scanDrive(at: url.path) }
            }
            .controlSize(.small)
            .disabled(model.isScanning)
          }
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
      .foregroundStyle(BrandTheme.textPrimary)
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

/// CPU, memory, battery, network and disk with 60-second sparklines. Rows without data are
/// hidden.
struct SystemMonitorSections: View {
  @EnvironmentObject private var model: AppModel
  @EnvironmentObject private var status: StatusMonitor

  var body: some View {
    let metrics = model.metrics
    VStack(alignment: .leading, spacing: 8) {
      HungAppsSection(monitor: model.hungAppMonitor)
      if model.settings.showSystemMonitors {
        Divider()
        MetricsRows(metrics: metrics, disk: status.disk)
      }
    }
    .onAppear {
      metrics.includesTemperature = model.settings.experimentalTemperature
      if model.settings.showSystemMonitors { metrics.start() }
    }
    .onDisappear { metrics.stop() }
  }
}

private struct HungAppsSection: View {
  @ObservedObject var monitor: HungAppMonitor

  var body: some View {
    if !monitor.hungApps.isEmpty {
      VStack(alignment: .leading, spacing: 4) {
        Text("Not responding").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        ForEach(monitor.hungApps) { app in
          HStack {
            Text(app.name)
            Spacer()
            Button("Force Quit") { monitor.forceQuit(app) }.controlSize(.small)
          }
        }
      }
    }
  }
}

private struct MetricsRows: View {
  @ObservedObject var metrics: MetricsSampler
  var disk: DiskSnapshot?

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if let cpu = metrics.cpuTotal {
        MetricRow(
          title: "CPU", value: "\(Int((cpu * 100).rounded()))%", series: metrics.cpu.values,
          maximum: 1)
      }
      if let memory = metrics.memorySnapshot {
        MetricRow(
          title: "Memory",
          value: "\(ByteCount.string(memory.usedBytes)) · \(MemoryService.pressureTitle(memory.pressureLevel))",
          series: metrics.memory.values, maximum: 1)
      }
      if let battery = metrics.battery {
        MetricRow(
          title: "Battery",
          value: batteryLine(battery),
          series: [], maximum: 1)
      }
      if let health = metrics.batteryHealth, health.isCritical {
        Text("Critical battery health: \(Int((health.healthFraction * 100).rounded()))% of original capacity.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      if let network = metrics.network {
        MetricRow(
          title: "Network",
          value: "↓ \(rate(network.received)) ↑ \(rate(network.sent))",
          series: metrics.networkIn.values,
          maximum: max(metrics.networkIn.values.max() ?? 1, 1))
      }
      if let disk, disk.totalBytes > 0 {
        MetricRow(
          title: "Disk", value: "\(ByteCount.string(disk.availableBytes)) free", series: [],
          maximum: 1)
      }
      if let temperature = metrics.temperature {
        MetricRow(title: "CPU temperature", value: "\(Int(temperature.rounded()))°C", series: [], maximum: 1)
      }
    }
  }

  private func batteryLine(_ battery: BatteryCharge) -> String {
    var text = "\(battery.percent)%"
    if battery.isCharging { text += " · Charging" }
    if let minutes = battery.minutesRemaining {
      text += " · \(minutes / 60)h \(minutes % 60)m"
    }
    return text
  }

  private func rate(_ bytesPerSecond: Double) -> String {
    ByteCount.string(Int64(bytesPerSecond)) + "/s"
  }
}

private struct MetricRow: View {
  var title: String
  var value: String
  var series: [Double]
  var maximum: Double

  var body: some View {
    HStack(spacing: 8) {
      Text(title).frame(width: 64, alignment: .leading)
      Sparkline(values: series, maximum: maximum)
        .frame(height: 16)
        .opacity(series.count > 1 ? 1 : 0)
      Text(value)
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .layoutPriority(1)
    }
    .font(.caption)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(title), \(value)")
  }
}

/// A small line of recent values. Decorative; the number next to it carries the meaning.
struct Sparkline: View {
  var values: [Double]
  var maximum: Double

  var body: some View {
    GeometryReader { proxy in
      Path { path in
        guard values.count > 1, maximum > 0 else { return }
        let step = proxy.size.width / CGFloat(max(values.count - 1, 1))
        for (index, value) in values.enumerated() {
          let point = CGPoint(
            x: CGFloat(index) * step,
            y: proxy.size.height * (1 - CGFloat(min(value / maximum, 1))))
          index == 0 ? path.move(to: point) : path.addLine(to: point)
        }
      }
      .stroke(BrandTheme.accent, lineWidth: 1.5)
    }
    .accessibilityHidden(true)
  }
}
