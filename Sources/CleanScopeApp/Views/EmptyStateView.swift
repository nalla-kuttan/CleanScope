import SwiftUI

struct EmptyStateView: View {
  var title: String
  var systemImage: String
  var message: String
  var usesBrandMark = false
  var brandGrowthStage = 3
  var commandLabel: String?
  var action: (() -> Void)?

  var body: some View {
    VStack(spacing: 10) {
      if usesBrandMark {
        BrandMarkView(size: 64, field: true, isDecorative: true, growthStage: brandGrowthStage)
      } else {
        Image(systemName: systemImage)
          .font(.system(size: 30))
          .foregroundStyle(BrandTheme.textSecondary)
          .frame(width: 52, height: 52)
          .accessibilityHidden(true)
      }

      Text(title)
        .font(.title3.weight(.semibold))
        .foregroundStyle(BrandTheme.textPrimary)
      Text(message)
        .foregroundStyle(BrandTheme.textSecondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 420)

      if let commandLabel, let action {
        Button(commandLabel, action: action)
          .buttonStyle(.borderedProminent)
          .tint(BrandTheme.accent)
          .controlSize(.large)
          .padding(.top, 6)
      }
    }
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .accessibilityElement(children: .contain)
  }
}
