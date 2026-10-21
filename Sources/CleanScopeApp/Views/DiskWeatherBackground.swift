import CleanScopeCore
import SwiftUI

/// The Dashboard's sky: a soft gradient with a low sun that warms from a fresh morning to a
/// warm afternoon as the disk fills. It sits behind the top of the page and fades into the
/// plain surface, so only the hero reads over it; everything below keeps the normal surface.
/// On macOS 15 the gradient is a mesh whose inner points drift a little while ambient motion
/// is allowed; otherwise (and on macOS 14) it is still. Decorative, hidden from VoiceOver.
struct DiskWeatherBackground: View {
  var usedFraction: Double
  @Environment(\.colorScheme) private var colorScheme
  @EnvironmentObject private var motion: MotionPolicy

  /// How far down the page the sky reaches before it has faded into the surface.
  static let height: CGFloat = 440

  private var stops: (top: Color, bottom: Color, sun: Color) {
    let hex = DiskWeather.stops(usedFraction: usedFraction, dark: colorScheme == .dark)
    return (Self.color(hex.top), Self.color(hex.bottom), Self.color(hex.sun))
  }

  var body: some View {
    let stops = stops
    ZStack(alignment: .topTrailing) {
      sky(top: stops.top, bottom: stops.bottom)
      sun(stops.sun)
    }
    .frame(height: Self.height)
    .mask(
      LinearGradient(
        stops: [
          .init(color: .black, location: 0),
          .init(color: .black, location: 0.55),
          .init(color: .clear, location: 1),
        ], startPoint: .top, endPoint: .bottom)
    )
    .animation(motion.animation(.easeInOut(duration: 0.4)), value: usedFraction)
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }

  @ViewBuilder
  private func sky(top: Color, bottom: Color) -> some View {
    if #available(macOS 15, *) {
      WeatherMesh(top: top, bottom: bottom, drifts: motion.allowsAmbientMotion)
    } else {
      LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
    }
  }

  /// A soft glow in the top-right corner of the hero area.
  private func sun(_ color: Color) -> some View {
    Circle()
      .fill(
        RadialGradient(
          colors: [color.opacity(colorScheme == .dark ? 0.55 : 0.85), color.opacity(0)],
          center: .center, startRadius: 0, endRadius: 130)
      )
      .frame(width: 260, height: 260)
      .padding(.top, -50)
      .padding(.trailing, 20)
  }

  private static func color(_ hex: UInt32) -> Color {
    Color(nsColor: BrandTheme.srgb(hex))
  }
}

/// The 3 × 3 mesh. Its inner points (the centre, and each edge's midpoint sliding along its
/// edge) move ±0.03 over a 20 s cycle while `drifts`; when it is false no timeline exists.
@available(macOS 15, *)
private struct WeatherMesh: View {
  var top: Color
  var bottom: Color
  var drifts: Bool

  private static let amplitude: Float = 0.03
  private static let period: Double = 20

  var body: some View {
    if drifts {
      // 20 fps is plenty for a 20 s drift, and keeps the gradient cheap.
      TimelineView(.animation(minimumInterval: 1.0 / 20)) { context in
        mesh(phase: context.date.timeIntervalSinceReferenceDate / Self.period)
      }
    } else {
      mesh(phase: 0)
    }
  }

  private func mesh(phase: Double) -> some View {
    func wave(_ offset: Double) -> Float {
      Self.amplitude * Float(sin((phase + offset) * 2 * .pi))
    }
    let middle = top.mix(with: bottom, by: 0.5)
    return MeshGradient(
      width: 3, height: 3,
      points: [
        [0, 0], [0.5 + wave(0), 0], [1, 0],
        [0, 0.5 + wave(0.25)], [0.5 + wave(0.5), 0.5 + wave(0.75)], [1, 0.5 + wave(0.6)],
        [0, 1], [0.5 + wave(0.1), 1], [1, 1],
      ],
      colors: [
        top, top, top,
        middle, middle, middle,
        bottom, bottom, bottom,
      ])
  }
}
