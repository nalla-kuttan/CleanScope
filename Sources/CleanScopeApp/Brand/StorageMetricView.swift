import SwiftUI

struct StorageMetricView: View {
  var label: String
  var value: String
  var symbol: String
  var tint: Color

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: symbol)
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(tint)
        .frame(width: 32, height: 32)
        .background(tint.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: BrandTheme.smallRadius, style: .continuous))
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 2) {
        Text(label)
          .font(.caption)
          .foregroundStyle(BrandTheme.textSecondary)
        Text(value)
          .font(.system(.title3, design: .rounded, weight: .bold))
          .foregroundStyle(BrandTheme.textPrimary)
          .monospacedDigit()
      }
      Spacer(minLength: 4)
    }
    .padding(12)
    .background(BrandTheme.surfaceRaised)
    .overlay(
      RoundedRectangle(cornerRadius: BrandTheme.radius, style: .continuous)
        .stroke(BrandTheme.hairline)
    )
    .clipShape(RoundedRectangle(cornerRadius: BrandTheme.radius, style: .continuous))
    .accessibilityElement(children: .combine)
  }
}
