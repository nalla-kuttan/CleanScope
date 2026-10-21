import CleanScopeCore
import SwiftUI

/// The scan, made visible: the path being scanned above four jars that fill with the real
/// streamed counts. Each new batch sends a few particles from the path line into their jars
/// (the counts and fills update whether or not anything flies).
struct ScanTheatre: View {
  @EnvironmentObject private var model: AppModel
  @EnvironmentObject private var motion: MotionPolicy

  @State private var theatre = ScanTheatreModel()
  @State private var particles = TheatreParticleStore()
  /// True from a spawn until its last particle has landed; the timeline only runs meanwhile.
  @State private var flying = false
  @State private var settleTask: Task<Void, Never>?

  var body: some View {
    VStack(alignment: .leading, spacing: Layout.gap) {
      Text(pathText)
        .font(.system(size: 12, design: .monospaced))
        .foregroundStyle(BrandTheme.textSecondary)
        .lineLimit(1)
        .truncationMode(.middle)
        .frame(height: Layout.pathHeight, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("Scanning")
        .accessibilityValue(pathText)

      HStack(alignment: .bottom, spacing: Layout.jarGap) {
        ForEach(TheatreJar.allCases, id: \.self) { jar in
          JarView(jar: jar, count: theatre.counts[jar] ?? 0, fill: theatre.fill(jar))
        }
      }
    }
    .overlay { if motion.allowsAmbientMotion { flightLayer } }
    .padding(16)
    .background(
      RoundedRectangle(cornerRadius: BrandTheme.radius, style: .continuous)
        .fill(BrandTheme.surfaceRaised)
    )
    .onAppear(perform: seed)
    .onChange(of: model.lastBatchSequence) { absorbLatest() }
    .onDisappear { settleTask?.cancel() }
  }

  private var pathText: String {
    guard let path = model.currentScanPath else { return "Starting…" }
    return (path as NSString).abbreviatingWithTildeInPath
  }

  // MARK: Counts

  /// Picks up whatever has already streamed in (the view can appear mid-scan), without particles.
  private func seed() {
    _ = theatre.sync(with: model.streamedResults)
  }

  /// Counts everything `streamedResults` gained since the last call, so a flush that lands
  /// between renders is never skipped; the jars always match the hero's count.
  private func absorbLatest() {
    let jars = theatre.sync(with: model.streamedResults)
    guard motion.allowsAmbientMotion, !jars.isEmpty else { return }
    particles.spawn(jars, at: Date.timeIntervalSinceReferenceDate)
    flying = true
    settleTask?.cancel()
    settleTask = Task { @MainActor in
      try? await Task.sleep(nanoseconds: UInt64((TheatreParticleStore.lifetime + 0.25) * 1e9))
      guard !Task.isCancelled else { return }
      flying = false
    }
  }

  // MARK: Particles

  /// One timeline and one canvas for every particle; the store is plain state, not published.
  private var flightLayer: some View {
    TimelineView(.animation(minimumInterval: nil, paused: !flying)) { timeline in
      Canvas { context, size in
        particles.draw(
          in: &context, size: size, now: timeline.date.timeIntervalSinceReferenceDate)
      }
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }

  enum Layout {
    static let gap: CGFloat = 16
    static let pathHeight: CGFloat = 18
    static let jarGap: CGFloat = 10
    static let jarHeight: CGFloat = 96
    static let dot: CGFloat = 7
  }
}

private struct JarView: View {
  let jar: TheatreJar
  let count: Int
  let fill: Double
  @EnvironmentObject private var motion: MotionPolicy

  var body: some View {
    VStack(spacing: 6) {
      GeometryReader { proxy in
        Rectangle()
          .fill(ScanTheatre.color(for: jar))
          .frame(height: proxy.size.height * min(max(fill, 0), 1))
          .frame(maxHeight: .infinity, alignment: .bottom)
          .animation(
            motion.animation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.35)), value: fill)
      }
      .frame(height: ScanTheatre.Layout.jarHeight)
      .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 12, bottomTrailingRadius: 12))
      .overlay {
        JarOutline().stroke(BrandTheme.hairline, lineWidth: 1.5)
      }

      HStack(spacing: 4) {
        Text(ScanTheatre.title(for: jar))
          .foregroundStyle(BrandTheme.textPrimary)
        Text(count.formatted())
          .foregroundStyle(BrandTheme.textSecondary)
          .monospacedDigit()
      }
      .font(.system(size: 12))
    }
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(ScanTheatre.title(for: jar)), \(CountPhrase.make(count, "item"))")
  }
}

/// A jar's sides and base: no top edge.
private struct JarOutline: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    let radius: CGFloat = 12
    path.move(to: CGPoint(x: rect.minX, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - radius))
    path.addArc(
      center: CGPoint(x: rect.minX + radius, y: rect.maxY - radius), radius: radius,
      startAngle: .degrees(180), endAngle: .degrees(90), clockwise: true)
    path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.maxY))
    path.addArc(
      center: CGPoint(x: rect.maxX - radius, y: rect.maxY - radius), radius: radius,
      startAngle: .degrees(90), endAngle: .degrees(0), clockwise: true)
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
    return path
  }
}

extension ScanTheatre {
  static func title(for jar: TheatreJar) -> String {
    switch jar {
    case .safe: return "Safe"
    case .review: return "Review"
    case .appData: return "App data"
    case .keep: return "Keep"
    }
  }

  static func color(for jar: TheatreJar) -> Color {
    switch jar {
    case .safe: return BrandTheme.color(BrandPalette.safeFill)
    case .review: return BrandTheme.color(BrandPalette.reviewFill)
    case .appData: return BrandTheme.color(BrandPalette.appFill)
    case .keep: return BrandTheme.color(BrandPalette.keepFill)
    }
  }
}

/// The particles in flight. A reference type read by the canvas each frame, so a spawn never
/// invalidates the view; the view starts the timeline when it adds some.
final class TheatreParticleStore {
  /// Seconds a particle takes from the path line to its jar.
  static let lifetime: TimeInterval = 0.62
  /// A batch's particles launch spread over this long rather than all at once.
  private static let spread: TimeInterval = 0.15

  private struct Particle {
    let jar: TheatreJar
    let birth: TimeInterval
    /// Where along the path line it leaves, and how far off the jar's centre it lands (-0.5…0.5).
    let startFraction: Double
    let landingJitter: Double
  }

  private var live: [Particle] = []

  func spawn(_ jars: [TheatreJar], at now: TimeInterval) {
    let count = max(jars.count, 1)
    for (index, jar) in jars.enumerated() {
      live.append(
        Particle(
          jar: jar, birth: now + Self.spread * Double(index) / Double(count),
          startFraction: .random(in: 0...1), landingJitter: .random(in: -0.5...0.5)))
    }
  }

  func draw(in context: inout GraphicsContext, size: CGSize, now: TimeInterval) {
    live.removeAll { now - $0.birth >= Self.lifetime }
    guard size.width > 0 else { return }
    let layout = ScanTheatre.Layout.self
    let jarWidth = (size.width - layout.jarGap * 3) / 4
    let startY = layout.pathHeight
    let endY = layout.pathHeight + layout.gap + 14
    let startSpan = min(260, size.width)

    for particle in live where now >= particle.birth {
      let t = (now - particle.birth) / Self.lifetime
      let index = TheatreJar.allCases.firstIndex(of: particle.jar) ?? 0
      let start = CGPoint(x: particle.startFraction * startSpan, y: startY)
      let end = CGPoint(
        x: (jarWidth + layout.jarGap) * Double(index) + jarWidth / 2 + particle.landingJitter * 20,
        y: endY)
      let control = CGPoint(x: (start.x + end.x) / 2, y: min(start.y, end.y) - 26)

      let eased = 1 - pow(1 - t, 2)
      let u = 1 - eased
      let x = u * u * start.x + 2 * u * eased * control.x + eased * eased * end.x
      let y = u * u * start.y + 2 * u * eased * control.y + eased * eased * end.y
      let scale = t < 0.45 ? 0.6 + 0.4 * (t / 0.45) : 1 - 0.2 * ((t - 0.45) / 0.55)
      let opacity = t < 0.45 ? 1 : 1 - 0.8 * ((t - 0.45) / 0.55)
      let diameter = layout.dot * scale

      context.opacity = opacity
      context.fill(
        Path(
          ellipseIn: CGRect(
            x: x - diameter / 2, y: y - diameter / 2, width: diameter, height: diameter)),
        with: .color(ScanTheatre.color(for: particle.jar)))
    }
  }
}
