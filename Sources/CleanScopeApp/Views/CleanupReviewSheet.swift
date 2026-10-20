import CleanScopeCore
import SwiftUI

struct CleanupReviewSheet: View {
  var items: [ScanResult]
  /// Receives exactly the items this sheet displayed.
  var onConfirm: ([ScanResult]) -> Void
  @Environment(\.dismiss) private var dismiss

  private var summary: SelectionSummary {
    SelectionSummary(items: items)
  }

  private var trashButtonTitle: String {
    let count = summary.itemCount
    return "Move \(count) \(count == 1 ? "Item" : "Items") to Trash"
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
          Text("Nothing is permanently deleted.")
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
        "CleanScope will move allowed items to the macOS Trash. Protected or manual-review items remain in place.",
        systemImage: "shield.checkered"
      )
      .font(.subheadline)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)

      HStack {
        Button("Cancel", role: .cancel) {
          dismiss()
        }
        .keyboardShortcut(.cancelAction)
        Spacer()
        Button(role: .destructive) {
          let reviewed = items
          dismiss()
          onConfirm(reviewed)
        } label: {
          Label(trashButtonTitle, systemImage: "trash")
        }
        .disabled(items.isEmpty)
      }
    }
    .padding(24)
    .frame(width: 540)
  }
}
