import CleanScopeCore
import SwiftUI

struct CleanupCelebrationView: View {
  var recoveredBytes: Int64
  var reduceMotion: Bool
  @State private var isVisible = false

  var body: some View {
    HStack(spacing: 20) {
      BrandMarkView(size: 64, field: true, isDecorative: true)
        .scaleEffect(isVisible || reduceMotion ? 1 : 0.9)
        .opacity(isVisible ? 1 : 0)

      VStack(alignment: .leading, spacing: 5) {
        Text("Moved safely to Trash")
          .font(.system(.title2, design: .rounded).bold())
          .foregroundStyle(BrandTheme.bark)
        Text(ByteCount.string(recoveredBytes))
          .font(.system(size: 34, weight: .bold, design: .rounded))
          .foregroundStyle(BrandTheme.sage)
          .monospacedDigit()
        Text("of breathing room recovered")
          .font(.system(.subheadline, design: .rounded))
          .foregroundStyle(BrandTheme.warmGray)
      }
      Spacer()
    }
    .padding(20)
    .background(
      RoundedRectangle(cornerRadius: BrandTheme.radius, style: .continuous)
        .fill(BrandTheme.clay)
    )
    .overlay(
      RoundedRectangle(cornerRadius: BrandTheme.radius, style: .continuous)
        .stroke(BrandTheme.sage.opacity(0.2))
    )
    .onAppear {
      BrandTheme.triggerHaptic()
      if reduceMotion { isVisible = true }
      else {
        withAnimation(.easeOut(duration: BrandTheme.motionDuration)) { isVisible = true }
      }
    }
  }
}
