import CleanScopeCore
import SwiftUI

struct CleanupReviewSheet: View {
  var items: [ScanResult]
  var onConfirm: () -> Void
  @EnvironmentObject private var model: AppModel
  @Environment(\.dismiss) private var dismiss
  @State private var confirmsPermanent = false

  private var isPermanent: Bool { model.settings.deleteImmediately }

  private var summary: SelectionSummary {
    SelectionSummary(items: items)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack(spacing: 12) {
        Image(systemName: "trash.circle.fill")
          .font(.system(size: 34))
          .foregroundStyle(BrandTheme.actionCoral)
        VStack(alignment: .leading, spacing: 2) {
          Text("Review cleanup")
            .font(.title2.bold())
          Text(isPermanent ? "Items are deleted immediately." : "Nothing is permanently deleted.")
            .foregroundStyle(.secondary)
        }
      }

      HStack(spacing: 12) {
        StorageMetricView(
          label: "Selected items",
          value: "\(summary.itemCount)",
          symbol: "checkmark.circle",
          tint: BrandTheme.scopeForest
        )
        StorageMetricView(
          label: "Potential space",
          value: ByteCount.string(summary.totalBytes),
          symbol: "internaldrive",
          tint: BrandTheme.finderBlue
        )
      }

      VStack(alignment: .leading, spacing: 8) {
        Text("Selection")
          .font(.headline)
        ForEach(SafetyCategory.allCases, id: \.rawValue) { category in
          let count = summary.categoryCounts[category] ?? 0
          if count > 0 {
            HStack {
              SafetyLabel(category: category)
              Spacer()
              Text("\(count)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
            }
          }
        }
      }
      .padding(14)
      .background(BrandTheme.secondarySurface)
      .clipShape(RoundedRectangle(cornerRadius: BrandTheme.radius))

      Label(
        isPermanent
          ? "CleanScope will delete allowed items permanently. Protected or manual-review items remain in place."
          : "CleanScope will move allowed items to the macOS Trash. Protected or manual-review items remain in place.",
        systemImage: "shield.checkered"
      )
      .font(.subheadline)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)

      HStack {
        Button("Cancel", role: .cancel) {
          dismiss()
        }
        Spacer()
        Button(role: .destructive) {
          if isPermanent {
            confirmsPermanent = true
          } else {
            dismiss()
            onConfirm()
          }
        } label: {
          Label(
            isPermanent ? "Delete Permanently" : "Move Selected Items to Trash",
            systemImage: isPermanent ? "xmark.bin" : "trash")
        }
        .keyboardShortcut(.defaultAction)
      }
    }
    .padding(24)
    .frame(width: 540)
    .alert(
      "Delete \(summary.itemCount) item\(summary.itemCount == 1 ? "" : "s") (\(ByteCount.string(summary.totalBytes))) permanently?",
      isPresented: $confirmsPermanent
    ) {
      Button("Cancel", role: .cancel) {}
      Button("Delete Permanently", role: .destructive) {
        dismiss()
        onConfirm()
      }
    } message: {
      Text("This can't be undone.")
    }
  }
}
