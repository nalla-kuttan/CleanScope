import CleanScopeCore
import SwiftUI

struct CleanupReviewSheet: View {
  var items: [ScanResult]
  /// Receives exactly the items this sheet displayed.
  var onConfirm: ([ScanResult]) -> Void
  @EnvironmentObject private var model: AppModel
  @Environment(\.dismiss) private var dismiss
  @State private var confirmsPermanent = false

  private var isPermanent: Bool { model.settings.deleteImmediately }

  private var summary: SelectionSummary {
    SelectionSummary(items: items)
  }

  private var itemPhrase: String {
    "\(CountPhrase.make(summary.itemCount, "item")) (\(ByteCount.string(summary.totalBytes)))"
  }

  private var confirmButtonTitle: String {
    isPermanent
      ? "Delete \(CountPhrase.make(summary.itemCount, "Item")) Permanently"
      : "Move \(CountPhrase.make(summary.itemCount, "Item")) to Trash"
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: isPermanent ? "xmark.bin" : "trash")
          .font(.system(size: 26))
          .foregroundStyle(BrandTheme.destructive)
          .frame(width: 36)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 4) {
          Text(isPermanent ? "Delete \(itemPhrase) permanently?" : "Move \(itemPhrase) to Trash?")
            .font(.title3.weight(.semibold))
            .foregroundStyle(BrandTheme.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
          Text(
            isPermanent
              ? "These items are deleted immediately and can't be put back. Turn off permanent deletion in Settings to use the Trash."
              : "Nothing is permanently deleted. You can put items back from the Trash until you empty it."
          )
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
      .accessibilityLabel(isPermanent ? "Items to delete permanently" : "Items to move to Trash")

      HStack {
        Button("Cancel", role: .cancel) {
          dismiss()
        }
        .keyboardShortcut(.cancelAction)
        Spacer()
        Button(role: .destructive) {
          if isPermanent {
            confirmsPermanent = true
          } else {
            let reviewed = items
            dismiss()
            onConfirm(reviewed)
          }
        } label: {
          Text(confirmButtonTitle)
        }
        .disabled(items.isEmpty)
      }
    }
    .padding(20)
    .frame(width: 500)
    .alert("Delete \(itemPhrase) permanently?", isPresented: $confirmsPermanent) {
      Button("Cancel", role: .cancel) {}
        .keyboardShortcut(.defaultAction)
      Button("Delete Permanently", role: .destructive) {
        let reviewed = items
        dismiss()
        onConfirm(reviewed)
      }
    } message: {
      Text("This can't be undone.")
    }
  }
}
