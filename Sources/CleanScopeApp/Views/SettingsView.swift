import CleanScopeCore
import SwiftUI

struct SettingsView: View {
  @EnvironmentObject private var model: AppModel
  @EnvironmentObject private var status: StatusMonitor
  @State private var snoozesReset = false

  private let gigabyte: Int64 = 1_000_000_000

  private static let thresholds: [Int64] = [
    100_000_000, 250_000_000, 500_000_000, 1_000_000_000, 2_000_000_000, 5_000_000_000,
  ]

  private var thresholdOptions: [Int64] {
    let current = model.settings.largeFileThresholdBytes
    return Self.thresholds.contains(current) ? Self.thresholds : (Self.thresholds + [current]).sorted()
  }

  var body: some View {
    Form {
      Section {
        HStack(spacing: 12) {
          BrandMarkView(size: 40, field: true, isDecorative: true)
          VStack(alignment: .leading, spacing: 2) {
            Text("CleanScope")
              .font(.headline)
              .foregroundStyle(BrandTheme.textPrimary)
            Text("Make room for what’s next.")
              .foregroundStyle(BrandTheme.textSecondary)
          }
        }
        .accessibilityElement(children: .combine)
      }

      Section {
        Toggle("Hidden folders", isOn: $model.settings.scanHiddenFolders)
        Toggle("Developer folders", isOn: $model.settings.scanDeveloperFolders)
        Toggle("Downloads", isOn: $model.settings.scanDownloads)
        Toggle("Application Support", isOn: $model.settings.scanAppSupport)
      } header: {
        Text("Scan sources")
      } footer: {
        Text("Changes apply to the next scan.")
          .foregroundStyle(BrandTheme.textSecondary)
      }

      Section("Results") {
        Picker("Large file threshold", selection: $model.settings.largeFileThresholdBytes) {
          ForEach(thresholdOptions, id: \.self) { bytes in
            Text(ByteCount.string(bytes)).tag(bytes)
          }
        }
        Toggle("Keep the latest scan between launches", isOn: $model.settings.saveScanHistory)
      }

      Section {
        if model.exclusions.isEmpty {
          Text("Nothing is excluded. Use Exclude from Results on any item to keep it out of cleanup.")
            .foregroundStyle(BrandTheme.textSecondary)
        } else {
          ForEach(model.exclusions) { rule in
            HStack {
              VStack(alignment: .leading, spacing: 2) {
                Text(URL(fileURLWithPath: rule.path).lastPathComponent)
                  .foregroundStyle(BrandTheme.textPrimary)
                Text(rule.path)
                  .font(.caption)
                  .foregroundStyle(BrandTheme.textSecondary)
                  .lineLimit(1)
                  .truncationMode(.middle)
                  .help(rule.path)
              }
              Spacer()
              Button("Remove") { model.removeExclusion(rule) }
                .accessibilityLabel("Remove exclusion for \(rule.path)")
            }
          }
        }
      } header: {
        Text("Exclusions")
      } footer: {
        if !model.exclusions.isEmpty {
          Text("Removed exclusions return to results on the next scan.")
            .foregroundStyle(BrandTheme.textSecondary)
        }
      }

      Section("Menu Bar") {
        Toggle("Show CleanScope in the menu bar", isOn: $model.settings.showMenuBarExtra)
        Toggle("Open at login", isOn: $model.settings.openAtLogin)
        Toggle("Show system monitors in the menu", isOn: $model.settings.showSystemMonitors)
        Toggle("Show CPU temperature (experimental)", isOn: $model.settings.experimentalTemperature)
          .disabled(!model.settings.showSystemMonitors)
        if let error = model.openAtLoginError {
          Text(error).font(.caption).foregroundStyle(BrandTheme.textSecondary)
        }
      }

      Section("Alerts") {
        if model.notifications.authorization == .denied {
          Text("Notifications are turned off for CleanScope in System Settings › Notifications.")
            .font(.caption)
            .foregroundStyle(BrandTheme.textSecondary)
        }
        Toggle("Low disk space", isOn: $model.settings.lowDiskAlertEnabled)
        Picker("Alert below", selection: $model.settings.lowDiskThresholdBytes) {
          ForEach([5, 10, 20, 50], id: \.self) { Text("\($0) GB").tag(Int64($0) * gigabyte) }
        }
        .disabled(!model.settings.lowDiskAlertEnabled)
        Toggle("Trash size", isOn: $model.settings.trashAlertEnabled)
          .disabled(status.trashNeedsFullDiskAccess)
        if status.trashNeedsFullDiskAccess {
          Text("Needs Full Disk Access").font(.caption).foregroundStyle(BrandTheme.textSecondary)
        }
        Picker("Alert above", selection: $model.settings.trashThresholdBytes) {
          ForEach([1, 5, 10, 20], id: \.self) { Text("\($0) GB").tag(Int64($0) * gigabyte) }
        }
        .disabled(!model.settings.trashAlertEnabled || status.trashNeedsFullDiskAccess)
        Toggle("External drive almost full", isOn: $model.settings.externalDriveAlertEnabled)
        Toggle("Notify when a drive connects", isOn: $model.settings.externalDriveMountedNotice)
        Toggle("Restart reminder after 14 days", isOn: $model.settings.restartReminderEnabled)
        Toggle("Low Bluetooth device battery", isOn: $model.settings.bluetoothBatteryAlertEnabled)
        Toggle("Heavy memory use", isOn: $model.settings.memoryAlertEnabled)
        Toggle("Apps that stop responding", isOn: $model.settings.hungAppMonitoringEnabled)
        if model.settings.hungAppMonitoringEnabled && !model.hungAppMonitor.isTrusted {
          Text("Needs Accessibility access: System Settings › Privacy & Security › Accessibility.")
            .font(.caption)
            .foregroundStyle(BrandTheme.textSecondary)
        }
        HStack {
          Button("Reset Snoozed Alerts") {
            status.resetSnoozes()
            snoozesReset = true
          }
          if snoozesReset {
            Text("Snoozed alerts can appear again.").font(.caption).foregroundStyle(BrandTheme.textSecondary)
          }
        }
      }

      Section("Protection") {
        Toggle("Real-time protection while CleanScope is open", isOn: $model.settings.realTimeProtectionEnabled)
        Text("Watches Downloads, background items and browser extensions, and checks apps when they first open.")
          .font(.caption)
          .foregroundStyle(BrandTheme.textSecondary)
        TrustedTeamsEditor(teamIDs: $model.settings.trustedTeamIDs)
        HStack {
          Text("Rules: \(model.ruleStatusLine)")
          if let updated = model.activeRules.updatedAt {
            Text("· updated \(updated.formatted(date: .abbreviated, time: .omitted))")
              .foregroundStyle(BrandTheme.textSecondary)
          }
          Spacer()
          Button("Check for Rule Updates") { Task { await model.checkForRuleUpdates(force: true) } }
        }
        if let message = model.ruleUpdateMessage {
          Text(message).font(.caption).foregroundStyle(BrandTheme.textSecondary)
        }
      }

      Section("System-managed space") {
        Toggle(
          "Offer to thin local Time Machine snapshots",
          isOn: $model.settings.allowSnapshotThinning)
        Text("Backups on your Time Machine disk are never affected.")
          .font(.caption)
          .foregroundStyle(BrandTheme.textSecondary)
      }

      Section("Cleanup") {
        Picker("When cleaning up", selection: $model.settings.deleteImmediately) {
          Text("Move to Trash").tag(false)
          Text("Delete immediately").tag(true)
        }
        Toggle(
          "Preselect Ready to Delete caches after a scan",
          isOn: $model.settings.preselectSafeCaches)
        Label(
          model.settings.deleteImmediately
            ? "Cleanup deletes items permanently after a second confirmation."
            : "CleanScope moves allowed files to Trash by default.",
          systemImage: model.settings.deleteImmediately ? "xmark.bin" : "trash"
        )
        .foregroundStyle(BrandTheme.textSecondary)
      }
    }
    .formStyle(.grouped)
  }
}

/// Developers whose signed apps are never reported.
private struct TrustedTeamsEditor: View {
  @Binding var teamIDs: [String]
  @State private var draft = ""

  private var normalizedDraft: String {
    draft.trimmingCharacters(in: .whitespaces).uppercased()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Trusted developer Team IDs")
      ForEach(teamIDs, id: \.self) { id in
        HStack {
          Text(id).monospaced()
          Spacer()
          Button("Remove") { teamIDs.removeAll { $0 == id } }
            .controlSize(.small)
        }
      }
      HStack {
        TextField("Team ID, for example ABCDE12345", text: $draft)
          .onSubmit(add)
        Button("Add", action: add)
          .disabled(normalizedDraft.count != 10 || teamIDs.contains(normalizedDraft))
      }
    }
  }

  private func add() {
    let id = normalizedDraft
    guard id.count == 10, !teamIDs.contains(id) else { return }
    teamIDs.append(id)
    draft = ""
  }
}
