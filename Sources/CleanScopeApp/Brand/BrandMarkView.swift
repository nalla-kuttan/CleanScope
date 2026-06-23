import SwiftUI

struct BrandMarkView: View {
  var size: CGFloat = 40
  var field: Bool = false

  var body: some View {
    ZStack {
      if field {
        RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
          .fill(BrandTheme.openMint)
      }

      ZStack {
        Circle()
          .stroke(BrandTheme.scopeForest, lineWidth: size * 0.075)
          .frame(width: size * 0.52, height: size * 0.52)
          .offset(x: -size * 0.06, y: -size * 0.04)

        Capsule()
          .fill(BrandTheme.scopeForest)
          .frame(width: size * 0.09, height: size * 0.34)
          .rotationEffect(.degrees(-45))
          .offset(x: size * 0.24, y: size * 0.23)

        Capsule()
          .fill(BrandTheme.scopeForest)
          .frame(width: size * 0.045, height: size * 0.24)
          .offset(x: -size * 0.06, y: size * 0.01)

        LeafShape()
          .fill(BrandTheme.freshLeaf)
          .frame(width: size * 0.2, height: size * 0.13)
          .rotationEffect(.degrees(22))
          .offset(x: -size * 0.15, y: -size * 0.13)

        LeafShape()
          .fill(BrandTheme.freshLeaf)
          .frame(width: size * 0.21, height: size * 0.14)
          .scaleEffect(x: -1)
          .rotationEffect(.degrees(-20))
          .offset(x: size * 0.04, y: -size * 0.17)
      }
      .padding(field ? size * 0.1 : 0)
    }
    .frame(width: size, height: size)
    .accessibilityElement(children: .ignore)
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
