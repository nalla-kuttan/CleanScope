import CleanScopeCore
import SwiftUI

struct SettingsView: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 12) {
        BrandMarkView(size: 46, field: true)
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

        Section {
          Label("CleanScope moves allowed files to Trash by default.", systemImage: "trash")
            .foregroundStyle(.secondary)
        }
      }
      .formStyle(.grouped)
    }
    .background(BrandTheme.clearPaper)
  }
}
