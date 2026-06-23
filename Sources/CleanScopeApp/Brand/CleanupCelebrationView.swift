import CleanScopeCore
import SwiftUI

struct CleanupCelebrationView: View {
  var recoveredBytes: Int64
  var reduceMotion: Bool
  @State private var isVisible = false

  var body: some View {
    HStack(spacing: 20) {
      BrandMarkView(size: 72, field: true)
        .scaleEffect(isVisible || reduceMotion ? 1 : 0.92)
        .opacity(isVisible ? 1 : 0)

      VStack(alignment: .leading, spacing: 5) {
        Text("Moved safely to Trash")
          .font(.title2.bold())
          .foregroundStyle(BrandTheme.deepInk)
        Text(ByteCount.string(recoveredBytes))
          .font(.system(size: 34, weight: .bold, design: .rounded))
          .foregroundStyle(BrandTheme.scopeForest)
          .monospacedDigit()
        Text("of breathing room recovered")
          .foregroundStyle(.secondary)
      }
      Spacer()
    }
    .padding(20)
    .background(BrandTheme.openMint)
    .clipShape(RoundedRectangle(cornerRadius: BrandTheme.radius))
    .onAppear {
      if reduceMotion {
        isVisible = true
      } else {
        withAnimation(.easeOut(duration: BrandTheme.motionDuration)) {
          isVisible = true
        }
      }
    }
  }
}
