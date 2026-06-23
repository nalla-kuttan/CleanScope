import AppKit
import CleanScopeCore
import SwiftUI

struct ItemDetailView: View {
  var result: ScanResult
  @EnvironmentObject private var model: AppModel
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: result.itemType == .folder ? "folder.fill" : "doc.fill")
          .font(.system(size: 30))
          .foregroundStyle(BrandTheme.finderBlue)
        VStack(alignment: .leading, spacing: 4) {
          Text(result.name)
            .font(.title2.bold())
            .lineLimit(2)
          Text(ByteCount.string(result.sizeBytes))
            .font(.system(.headline, design: .rounded))
            .foregroundStyle(.secondary)
        }
        Spacer()
        SafetyLabel(category: result.category)
      }

      inspectorSection("Safety") {
        detail("Confidence", result.confidence.rawValue.capitalized)
        detail("What happens if removed", result.riskNote)
      }

      inspectorSection("Why CleanScope found it") {
        Text(result.reason)
        Text(result.recommendedAction)
          .foregroundStyle(BrandTheme.scopeForest)
      }

      inspectorSection("Location") {
        detail("Path", result.path)
        if let modified = result.lastModified {
          detail("Last modified", modified.formatted(date: .long, time: .shortened))
        }
        if let owner = result.ownerTool ?? result.ownerApp {
          detail("Associated with", owner)
        }
      }

      Spacer()

      HStack {
        Button {
          NSWorkspace.shared.activateFileViewerSelecting([
            URL(fileURLWithPath: result.normalizedPath)
          ])
        } label: {
          Label("Open in Finder", systemImage: "folder")
        }

        Button {
          model.exclude(result)
          dismiss()
        } label: {
          Label(result.isExcluded ? "Excluded" : "Exclude", systemImage: "eye.slash")
        }
        .disabled(result.isExcluded)

        Spacer()

        if result.canDelete {
          Button(role: .destructive) {
            dismiss()
            Task { await model.cleanup(result) }
          } label: {
            Label("Move to Trash", systemImage: "trash")
          }
        }

        Button("Close") {
          dismiss()
        }
        .keyboardShortcut(.cancelAction)
      }
    }
    .padding(24)
    .frame(width: 620, height: 570)
  }

  private func inspectorSection<Content: View>(
    _ title: String, @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.headline)
      VStack(alignment: .leading, spacing: 8) {
        content()
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(12)
      .background(BrandTheme.secondarySurface)
      .clipShape(RoundedRectangle(cornerRadius: BrandTheme.radius))
    }
  }

  private func detail(_ title: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)
      Text(value)
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}
