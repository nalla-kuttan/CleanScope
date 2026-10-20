import CleanScopeCore
import SwiftUI

struct SettingsView: View {
  @EnvironmentObject private var model: AppModel

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

      Section {
        Label("CleanScope only moves items to the Trash. It never deletes them permanently.", systemImage: "trash")
          .foregroundStyle(BrandTheme.textSecondary)
      }
    }
    .formStyle(.grouped)
  }
}
