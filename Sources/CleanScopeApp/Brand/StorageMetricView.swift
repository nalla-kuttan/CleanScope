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
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

      VStack(alignment: .leading, spacing: 2) {
        Text(label)
          .font(.caption)
          .foregroundStyle(.secondary)
        Text(value)
          .font(.system(.title3, design: .rounded, weight: .bold))
          .foregroundStyle(BrandTheme.deepInk)
          .monospacedDigit()
      }
      Spacer(minLength: 4)
    }
    .padding(12)
    .background(BrandTheme.secondarySurface)
    .overlay(
      RoundedRectangle(cornerRadius: BrandTheme.radius)
        .stroke(BrandTheme.hairline)
    )
    .clipShape(RoundedRectangle(cornerRadius: BrandTheme.radius))
  }
}
