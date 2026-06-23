import AppKit
import CleanScopeCore
import SwiftUI

struct ItemDetailView: View {
  var result: ScanResult
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Text(result.name)
          .font(.title2.bold())
        Spacer()
        SafetyLabel(category: result.category)
      }
      detail("Full path", result.path)
      detail("Size", ByteCount.string(result.sizeBytes))
      detail("Why it was flagged", result.reason)
      detail("What happens if deleted", result.riskNote)
      detail("Recommended action", result.recommendedAction)
      if let ownerTool = result.ownerTool {
        detail("Owner tool", ownerTool)
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
        Spacer()
        Button("Close") {
          dismiss()
        }
        .keyboardShortcut(.defaultAction)
      }
    }
    .padding(24)
    .frame(width: 560, height: 440)
  }

  private func detail(_ title: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)
      Text(value)
        .textSelection(.enabled)
    }
  }
}
