import SwiftUI

struct BrandMarkView: View {
  var size: CGFloat = 40
  var field: Bool = false
  var isDecorative = false
  /// 0 shows the lens alone; stages 1–3 add the stem, then each leaf.
  var growthStage = 3
  /// How stages grow in; the dashboard hero passes a spring.
  var growthAnimation: Animation = .easeOut(duration: BrandTheme.motionDuration)
  @EnvironmentObject private var motion: MotionPolicy

  var body: some View {
    ZStack {
      if field {
        RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
          .fill(BrandTheme.Mark.field)
      }

      ZStack {
        Circle()
          .stroke(BrandTheme.Mark.lens, lineWidth: size * 0.075)
          .frame(width: size * 0.52, height: size * 0.52)
          .offset(x: -size * 0.06, y: -size * 0.04)

        Capsule()
          .fill(BrandTheme.Mark.lens)
          .frame(width: size * 0.09, height: size * 0.34)
          .rotationEffect(.degrees(-45))
          .offset(x: size * 0.24, y: size * 0.23)

        Capsule()
          .fill(BrandTheme.Mark.lens)
          .frame(width: size * 0.045, height: size * 0.24)
          .scaleEffect(y: growthStage >= 1 ? 1 : 0.2, anchor: .bottom)
          .offset(x: -size * 0.06, y: size * 0.01)
          .opacity(growthStage >= 1 ? 1 : 0)

        LeafShape()
          .fill(BrandTheme.Mark.leaf)
          .frame(width: size * 0.2, height: size * 0.13)
          .scaleEffect(growthStage >= 2 ? 1 : 0.3, anchor: .bottomLeading)
          .rotationEffect(.degrees(22))
          .offset(x: -size * 0.15, y: -size * 0.13)
          .opacity(growthStage >= 2 ? 1 : 0)

        LeafShape()
          .fill(BrandTheme.Mark.leaf)
          .frame(width: size * 0.21, height: size * 0.14)
          .scaleEffect(growthStage >= 3 ? 1 : 0.3, anchor: .bottomLeading)
          .scaleEffect(x: -1)
          .rotationEffect(.degrees(-20))
          .offset(x: size * 0.04, y: -size * 0.17)
          .opacity(growthStage >= 3 ? 1 : 0)
      }
      .padding(field ? size * 0.1 : 0)
      .animation(motion.animation(growthAnimation), value: growthStage)
    }
    .frame(width: size, height: size)
    .accessibilityElement(children: .ignore)
    .accessibilityHidden(isDecorative)
    .accessibilityLabel("CleanScope")
  }
}

private struct LeafShape: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
    path.addCurve(
      to: CGPoint(x: rect.maxX, y: rect.minY),
      control1: CGPoint(x: rect.minX + rect.width * 0.18, y: rect.minY),
      control2: CGPoint(x: rect.maxX * 0.78, y: rect.minY)
    )
    path.addCurve(
      to: CGPoint(x: rect.minX, y: rect.maxY),
      control1: CGPoint(x: rect.maxX, y: rect.maxY * 0.72),
      control2: CGPoint(x: rect.minX + rect.width * 0.34, y: rect.maxY)
    )
    return path
  }
}
