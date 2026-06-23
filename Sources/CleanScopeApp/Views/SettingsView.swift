import SwiftUI

struct SettingsView: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
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
          "Large file threshold: \(model.settings.largeFileThresholdBytes / 1_000_000) MB",
          value: $model.settings.largeFileThresholdBytes,
          in: 100_000_000...5_000_000_000,
          step: 100_000_000
        )
      }
      Section {
        Label("CleanScope moves files to Trash by default.", systemImage: "trash")
          .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .padding(16)
  }
}
