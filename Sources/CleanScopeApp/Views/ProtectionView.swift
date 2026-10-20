import AppKit
import CleanScopeCore
import SwiftUI

/// Rule-based malware scanning. The copy stays factual: detection depends on the rules.
struct ProtectionView: View {
  @EnvironmentObject private var model: AppModel
  @State private var pendingRemoval: Threat?
  @State private var message: String?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        HStack(alignment: .bottom) {
          PageHeader(
            title: "Protection",
            subtitle: "Checks apps, downloads, background items, browser extensions and profiles against known threats.")
          Spacer()
          if model.isProtectionScanning {
            ProgressView().controlSize(.small)
            Button("Stop") { model.cancelProtectionScan() }
          } else {
            Button {
              Task { await model.runProtectionScan() }
            } label: {
              Label("Scan", systemImage: "shield.lefthalf.filled")
            }
            .buttonStyle(.borderedProminent)
            .tint(BrandTheme.accent)
          }
        }

        summary

        if let message {
          Label(message, systemImage: "info.circle").foregroundStyle(.secondary)
        }

        if let report = model.protectionReport, !report.threats.isEmpty {
          ForEach(report.threats) { threat in
            threatRow(threat)
          }
        } else if model.protectionReport != nil {
          EmptyStateView(
            title: "No known threats found", systemImage: "checkmark.shield",
            message: "Nothing matched CleanScope's rules. Keep macOS up to date for Apple's own protection too.")
            .frame(minHeight: 220)
        }

        Text(
          "Detection depends on the rules CleanScope has. No scanner can promise to find everything."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
      .padding(24)
      .frame(maxWidth: 980, alignment: .leading)
    }
    .background(BrandTheme.surface)
    .alert(
      "Remove \(pendingRemoval?.name ?? "")?",
      isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } })
    ) {
      Button("Cancel", role: .cancel) {}
      Button(model.settings.deleteImmediately ? "Delete Permanently" : "Move to Trash", role: .destructive) {
        if let threat = pendingRemoval { Task { await remove(threat) } }
      }
    } message: {
      Text(removalMessage)
    }
  }

  private var removalMessage: String {
    guard let threat = pendingRemoval else { return "" }
    switch threat.kind {
    case .profile: return "CleanScope opens System Settings so you can remove the profile."
    case .browserExtension: return "CleanScope opens the browser's extensions page so you can remove it."
    default:
      let target = threat.containerPath ?? threat.location
      return model.settings.deleteImmediately
        ? "CleanScope stops related processes and deletes \(target). This can't be undone."
        : "CleanScope stops related processes and moves \(target) to the Trash."
    }
  }

  private var summary: some View {
    HStack(spacing: 12) {
      StorageMetricView(
        label: "Last scan",
        value: model.protectionReport.map { $0.date.formatted(date: .abbreviated, time: .shortened) } ?? "Never",
        symbol: "clock", tint: BrandTheme.info)
      StorageMetricView(
        label: "Items to review", value: "\(model.protectionReport?.threats.count ?? 0)",
        symbol: "exclamationmark.shield", tint: BrandTheme.review)
      StorageMetricView(
        label: "Rules", value: model.ruleStatusLine, symbol: "list.bullet.rectangle",
        tint: BrandTheme.accentText)
    }
  }

  private func threatRow(_ threat: Threat) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: "exclamationmark.shield")
        .font(.title2)
        .foregroundStyle(BrandTheme.review)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 3) {
        Text(threat.name).font(.headline).foregroundStyle(BrandTheme.textPrimary)
        Text("\(threat.category.title): \(threat.category.plainDescription)")
          .font(.subheadline)
          .foregroundStyle(.secondary)
        Text(threat.location).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
        Text("Found by: \(threat.detectedBy)").font(.caption).foregroundStyle(.secondary)
      }
      Spacer()
      VStack(alignment: .trailing, spacing: 6) {
        Button("Remove…") { pendingRemoval = threat }
        if threat.kind != .profile {
          Button("Show in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([
              URL(fileURLWithPath: threat.containerPath ?? threat.location)
            ])
          }
          .controlSize(.small)
        }
        Button("Ignore") { model.ignoreThreat(threat) }
          .controlSize(.small)
          .help("Hide this item from future results.")
      }
    }
    .padding(12)
    .background(BrandTheme.surfaceRaised)
    .clipShape(RoundedRectangle(cornerRadius: BrandTheme.radius))
    .accessibilityElement(children: .contain)
  }

  private func remove(_ threat: Threat) async {
    switch await ThreatRemover.remove(threat, deleteImmediately: model.settings.deleteImmediately) {
    case .removed:
      message = "\(threat.name) was removed."
      model.forgetThreat(threat)
    case .openedSettings(let text):
      message = text
    case .failed(let text):
      message = text
    }
  }
}
