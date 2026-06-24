import SwiftUI

struct EmptyStateView: View {
  var title: String
  var systemImage: String
  var message: String
  var usesBrandMark = false
  var commandLabel: String?
  var action: (() -> Void)?

  var body: some View {
    VStack(spacing: 10) {
      if usesBrandMark {
        BrandMarkView(size: 66, field: true)
      } else {
        Image(systemName: systemImage)
          .font(.system(size: 34))
          .foregroundStyle(BrandTheme.scopeForest)
          .frame(width: 54, height: 54)
          .background(BrandTheme.openMint)
          .clipShape(RoundedRectangle(cornerRadius: BrandTheme.radius))
          .accessibilityHidden(true)
      }

      Text(title)
        .font(.title3.weight(.semibold))
        .foregroundStyle(BrandTheme.deepInk)
      Text(message)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 440)

      if let commandLabel, let action {
        Button(commandLabel, action: action)
          .buttonStyle(.borderedProminent)
          .tint(BrandTheme.scopeForest)
          .padding(.top, 4)
      }
    }
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
