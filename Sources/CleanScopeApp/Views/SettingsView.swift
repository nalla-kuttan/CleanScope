import CleanScopeCore
import SwiftUI

struct SettingsView: View {
  @EnvironmentObject private var model: AppModel
  @EnvironmentObject private var status: StatusMonitor
  @State private var snoozesReset = false

  private let gigabyte: Int64 = 1_000_000_000

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 12) {
        BrandMarkView(size: 46, field: true, isDecorative: true)
        VStack(alignment: .leading, spacing: 2) {
          Text("CleanScope")
            .font(.title3.bold())
            .foregroundStyle(BrandTheme.deepInk)
          Text("Make room for what’s next.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        Spacer()
      }
      .padding(.horizontal, 20)
      .padding(.top, 18)
      .padding(.bottom, 10)

      Form {
        Section("Scan Sources") {
          Toggle("Scan hidden folders", isOn: $model.settings.scanHiddenFolders)
          Toggle("Include developer folders", isOn: $model.settings.scanDeveloperFolders)
          Toggle("Include Downloads", isOn: $model.settings.scanDownloads)
          Toggle("Include App Support", isOn: $model.settings.scanAppSupport)
        }

        Section("Results") {
          Toggle("Show advanced categories", isOn: $model.settings.showAdvancedCategories)
          Toggle("Save scan history", isOn: $model.settings.saveScanHistory)
          Stepper(
            "Large file threshold: \(ByteCount.string(model.settings.largeFileThresholdBytes))",
            value: $model.settings.largeFileThresholdBytes,
            in: 100_000_000...5_000_000_000,
            step: 100_000_000
          )
        }

        Section("Menu Bar") {
          Toggle("Show CleanScope in the menu bar", isOn: $model.settings.showMenuBarExtra)
          Toggle("Open at login", isOn: $model.settings.openAtLogin)
          Toggle("Show system monitors in the menu", isOn: $model.settings.showSystemMonitors)
          Toggle("Show CPU temperature (experimental)", isOn: $model.settings.experimentalTemperature)
            .disabled(!model.settings.showSystemMonitors)
          if let error = model.openAtLoginError {
            Text(error).font(.caption).foregroundStyle(.secondary)
          }
        }

        Section("Alerts") {
          if model.notifications.authorization == .denied {
            Text("Notifications are turned off for CleanScope in System Settings › Notifications.")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          Toggle("Low disk space", isOn: $model.settings.lowDiskAlertEnabled)
          Picker("Alert below", selection: $model.settings.lowDiskThresholdBytes) {
            ForEach([5, 10, 20, 50], id: \.self) { Text("\($0) GB").tag(Int64($0) * gigabyte) }
          }
          .disabled(!model.settings.lowDiskAlertEnabled)
          Toggle("Trash size", isOn: $model.settings.trashAlertEnabled)
            .disabled(status.trashNeedsFullDiskAccess)
          if status.trashNeedsFullDiskAccess {
            Text("Needs Full Disk Access").font(.caption).foregroundStyle(.secondary)
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
              .foregroundStyle(.secondary)
          }
          HStack {
            Button("Reset Snoozed Alerts") {
              status.resetSnoozes()
              snoozesReset = true
            }
            if snoozesReset {
              Text("Snoozed alerts can appear again.").font(.caption).foregroundStyle(.secondary)
            }
          }
        }

        Section("Protection") {
          Toggle("Real-time protection while CleanScope is open", isOn: $model.settings.realTimeProtectionEnabled)
          Text("Watches Downloads, background items and browser extensions, and checks apps when they first open.")
            .font(.caption)
            .foregroundStyle(.secondary)
          TrustedTeamsEditor(teamIDs: $model.settings.trustedTeamIDs)
          HStack {
            Text("Rules: \(model.ruleStatusLine)")
            if let updated = model.activeRules.updatedAt {
              Text("· updated \(updated.formatted(date: .abbreviated, time: .omitted))")
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Check for Rule Updates") { Task { await model.checkForRuleUpdates(force: true) } }
          }
          if let message = model.ruleUpdateMessage {
            Text(message).font(.caption).foregroundStyle(.secondary)
          }
        }

        Section("System-managed space") {
          Toggle(
            "Offer to thin local Time Machine snapshots",
            isOn: $model.settings.allowSnapshotThinning)
          Text("Backups on your Time Machine disk are never affected.")
            .font(.caption)
            .foregroundStyle(.secondary)
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
          .foregroundStyle(.secondary)
        }
      }
      .formStyle(.grouped)
    }
    .background(BrandTheme.clearPaper)
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
