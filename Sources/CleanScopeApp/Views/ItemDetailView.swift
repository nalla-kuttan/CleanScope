import AppKit
import CleanScopeCore
import SwiftUI

struct ItemDetailView: View {
  var result: ScanResult
  @EnvironmentObject private var model: AppModel
  @Environment(\.dismiss) private var dismiss
  @State private var review: ReviewRequest?

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
        .padding(20)

      Form {
        Section {
          Label(result.category.warningText, systemImage: result.category.symbolName)
            .foregroundStyle(result.category.tintColor)
            .fixedSize(horizontal: false, vertical: true)
        }

        Section("Why it’s here") {
          Text(result.reason)
            .foregroundStyle(BrandTheme.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
          LabeledContent("Recommended") {
            Text(result.recommendedAction).multilineTextAlignment(.trailing)
          }
          LabeledContent("Confidence", value: "\(result.confidence.rawValue.capitalized) confidence")
          LabeledContent("If removed") {
            Text(result.riskNote).multilineTextAlignment(.trailing)
          }
        }

        Section("Location") {
          LabeledContent("Path") {
            Text(result.path)
              .textSelection(.enabled)
              .multilineTextAlignment(.trailing)
          }
          if let modified = result.lastModified {
            LabeledContent("Modified", value: modified.formatted(date: .long, time: .shortened))
          }
          if let owner = result.ownerTool ?? result.ownerApp {
            LabeledContent("Associated app", value: owner)
          }
          if let reason = result.unavailableReason {
            Text(reason)
              .font(.callout)
              .foregroundStyle(BrandTheme.textSecondary)
          }
        }
      }
      .formStyle(.grouped)

      Divider()
      actions
        .padding(16)
    }
    .frame(width: 560, height: 560)
    .sheet(item: $review) { request in
      CleanupReviewSheet(items: request.items) { reviewed in
        dismiss()
        Task { await model.cleanup(reviewed) }
      }
    }
  }

  private var header: some View {
    HStack(alignment: .center, spacing: 14) {
      Image(nsImage: FileIcon.image(for: result))
        .resizable()
        .frame(width: 44, height: 44)
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 3) {
        Text(result.name)
          .font(.title3.weight(.semibold))
          .foregroundStyle(BrandTheme.textPrimary)
          .lineLimit(2)
          .help(result.name)
        HStack(spacing: 6) {
          Text(ByteCount.string(result.sizeBytes))
            .font(.system(.body, design: .rounded).weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(BrandTheme.textPrimary)
          Text("·").foregroundStyle(BrandTheme.textSecondary).accessibilityHidden(true)
          Text(result.itemType.rawValue.capitalized)
            .foregroundStyle(BrandTheme.textSecondary)
        }
      }
      Spacer()
      SafetyLabel(category: result.category)
    }
  }

  private var actions: some View {
    HStack(spacing: 10) {
      Button("Show in Finder") {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: result.normalizedPath)])
      }

      Button(result.isExcluded ? "Excluded" : "Exclude from Results") {
        model.exclude(result)
        dismiss()
      }
      .disabled(result.isExcluded)

      Spacer()

      if result.canDelete && !result.isExcluded {
        Button("Move to Trash…", role: .destructive) {
          review = ReviewRequest(items: [result])
        }
      }

      Button("Done") { dismiss() }
        .keyboardShortcut(.defaultAction)
    }
  }
}
