import CleanScopeCore
import SwiftUI

struct PermissionBannerView: View {
  var summary: PermissionSummary
  @State private var isExpanded = false

  var body: some View {
    DisclosureGroup(isExpanded: $isExpanded) {
      if !summary.setupSteps.isEmpty {
        VStack(alignment: .leading, spacing: 5) {
          ForEach(Array(summary.setupSteps.enumerated()), id: \.offset) { index, step in
            Text("\(index + 1). \(step)")
          }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.top, 8)
      }
    } label: {
      Label(
        summary.message,
        systemImage: summary.isLikelyComplete ? "checkmark.shield.fill" : "lock.shield.fill"
      )
      .font(.subheadline.weight(.medium))
      .foregroundStyle(summary.isLikelyComplete ? BrandTheme.scopeForest : BrandTheme.finderBlue)
    }
    .disabled(summary.setupSteps.isEmpty)
    .padding(12)
    .background(
      (summary.isLikelyComplete ? BrandTheme.openMint : BrandTheme.finderBlue.opacity(0.1))
    )
    .clipShape(RoundedRectangle(cornerRadius: BrandTheme.radius))
  }
}
