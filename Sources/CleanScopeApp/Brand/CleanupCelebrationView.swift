import CleanScopeCore
import SwiftUI

struct CleanupCelebrationView: View {
  var recoveredBytes: Int64
  var movedCount: Int
  @EnvironmentObject private var motion: MotionPolicy
  @State private var isVisible = false

  var body: some View {
    HStack(spacing: 18) {
      BrandMarkView(size: 56, field: true, isDecorative: true)
        .scaleEffect(isVisible || !motion.allowsTransitions ? 1 : 0.92)
        .opacity(isVisible ? 1 : 0)

      VStack(alignment: .leading, spacing: 4) {
        Text(movedCount > 0 ? "Moved safely to Trash" : "Nothing was moved")
          .font(.title3.weight(.semibold))
          .foregroundStyle(BrandTheme.textPrimary)
        if movedCount > 0 {
          Text("You found \(ByteCount.string(recoveredBytes)) of breathing room.")
            .font(.system(.title2, design: .rounded).weight(.bold))
            .monospacedDigit()
            .foregroundStyle(BrandTheme.accentText)
        } else {
          Text("Every item stayed in place. The details are below.")
            .foregroundStyle(BrandTheme.textSecondary)
        }
      }
      Spacer()
    }
    .padding(20)
    .background(
      RoundedRectangle(cornerRadius: BrandTheme.radius, style: .continuous)
        .fill(BrandTheme.surfaceRaised)
    )
    .accessibilityElement(children: .combine)
    .onAppear {
      withAnimation(motion.animation()) { isVisible = true }
    }
  }
}
