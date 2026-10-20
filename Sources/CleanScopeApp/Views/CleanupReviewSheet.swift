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
    "Move \(CountPhrase.make(summary.itemCount, "Item")) to Trash"
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: "trash")
          .font(.system(size: 26))
          .foregroundStyle(BrandTheme.destructive)
          .frame(width: 36)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 4) {
          Text(
            "Move \(CountPhrase.make(summary.itemCount, "item")) (\(ByteCount.string(summary.totalBytes))) to Trash?"
          )
          .font(.title3.weight(.semibold))
          .foregroundStyle(BrandTheme.textPrimary)
          .fixedSize(horizontal: false, vertical: true)
          Text("Nothing is permanently deleted. You can put items back from the Trash until you empty it.")
            .foregroundStyle(BrandTheme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }

      VStack(alignment: .leading, spacing: 6) {
        ForEach(SafetyCategory.allCases, id: \.rawValue) { category in
          let count = summary.categoryCounts[category] ?? 0
          if count > 0 {
            HStack {
              SafetyLabel(category: category)
              Spacer()
              Text(count.formatted())
                .monospacedDigit()
                .foregroundStyle(BrandTheme.textSecondary)
            }
          }
        }
      }

      List(items) { item in
        HStack {
          Text(item.name)
            .foregroundStyle(BrandTheme.textPrimary)
            .lineLimit(1)
            .help(item.path)
          Spacer()
          Text(ByteCount.string(item.sizeBytes))
            .monospacedDigit()
            .foregroundStyle(BrandTheme.textSecondary)
        }
      }
      .listStyle(.bordered(alternatesRowBackgrounds: true))
      .frame(height: min(CGFloat(items.count) * 24 + 8, 200))
      .accessibilityLabel("Items to move to Trash")

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
          Text(trashButtonTitle)
        }
        .disabled(items.isEmpty)
      }
    }
    .padding(20)
    .frame(width: 500)
  }
}
