import AppKit
import CleanScopeCore
import SwiftUI

// MARK: - Toolbar basket

/// The toolbar's one primary action on result destinations and the Storage Map. It shows how
/// many items are selected and their deduplicated total, and opens the cleanup review for
/// exactly those items. A chip flies into it when items are selected.
struct HarvestBasket: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.flightCenter) private var center
  /// How many selected items are not listed in the current view; they are still in the basket.
  var otherSections = 0
  /// Receives the items to review: `model.selectedResults()` at the moment of the click.
  var onReview: ([ScanResult]) -> Void

  var body: some View {
    let selected = model.selectedResults()
    let bytes = ByteCount.string(ResultPresentation.totalBytes(selected))
    let reason = unavailableReason(selected)
    Button {
      onReview(selected)
    } label: {
      HStack(spacing: 6) {
        Image(systemName: "basket")
          .accessibilityHidden(true)
        Text(
          selected.isEmpty
            ? "Nothing selected" : "\(CountPhrase.make(selected.count, "item")) · \(bytes)"
        )
        .monospacedDigit()
      }
      .background { if let center { BasketAnchor(center: center) } }
      .modifier(BasketPulse(stage: center?.stage))
    }
    .disabled(reason != nil)
    .help(help(selected, reason: reason))
    .accessibilityLabel(
      selected.isEmpty
        ? "Review selected items"
        : "Review \(CountPhrase.make(selected.count, "selected item")), \(bytes)"
    )
    .accessibilityValue(BasketPresentation.otherSectionsPhrase(otherSections) ?? "")
    .accessibilityHint(reason ?? "Opens the cleanup review")
  }

  /// Why the basket can't be opened right now, if it can't.
  private func unavailableReason(_ selected: [ScanResult]) -> String? {
    if model.isScanning { return "Available once the scan finishes" }
    if model.isCleaningUp { return AppModel.cleanupRunningNote }
    if selected.isEmpty { return "Select items to review them for cleanup" }
    return nil
  }

  private func help(_ selected: [ScanResult], reason: String?) -> String {
    if let reason { return reason }
    let count = CountPhrase.make(selected.count, "selected item")
    let base =
      model.settings.deleteImmediately
      ? "Review \(count) before deleting them permanently"
      : "Review \(count) before moving them to Trash"
    guard let others = BasketPresentation.otherSectionsPhrase(otherSections) else { return base }
    return "\(base) (\(others))"
  }
}

extension View {
  /// Puts the harvest basket in the toolbar as the primary action. `otherSections` is how many
  /// selected items this view doesn't list.
  func harvestBasketToolbar(
    otherSections: Int = 0, onReview: @escaping ([ScanResult]) -> Void
  ) -> some View {
    toolbar {
      ToolbarItem(placement: .primaryAction) {
        HarvestBasket(otherSections: otherSections, onReview: onReview)
      }
    }
  }
}

/// Scales the basket 1 → 1.04 → 1 once for each arriving chip.
private struct BasketPulse: ViewModifier {
  var stage: FlightStage?
  @State private var scale = 1.0

  func body(content: Content) -> some View {
    content
      .scaleEffect(scale)
      .background { if let stage { PulseListener(stage: stage) { pulse() } } }
  }

  private func pulse() {
    withAnimation(.easeOut(duration: 0.14)) { scale = 1.04 }
    Task {
      try? await Task.sleep(nanoseconds: 140_000_000)
      withAnimation(.easeInOut(duration: 0.2)) { scale = 1 }
    }
  }
}

/// Observes the stage so only this invisible view, not the basket, re-renders on a pulse.
private struct PulseListener: View {
  @ObservedObject var stage: FlightStage
  var onPulse: () -> Void

  var body: some View {
    Color.clear
      .onChange(of: stage.pulse) { onPulse() }
  }
}

/// Lets the flight find the basket's on-screen frame when it starts.
private struct BasketAnchor: NSViewRepresentable {
  var center: FlightCenter

  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    center.basketView = view
    return view
  }

  func updateNSView(_ view: NSView, context: Context) {
    center.basketView = view
  }
}

// MARK: - Flight

/// What the window-level overlay draws: the chip in flight and a counter the basket pulses on.
@MainActor
final class FlightStage: ObservableObject {
  struct Flight: Identifiable {
    let id = UUID()
    var label: String
    /// Start and end frames in the overlay's coordinate space (top-left origin).
    var from: CGRect
    var to: CGRect
  }

  @Published fileprivate(set) var flight: Flight?
  @Published fileprivate(set) var pulse = 0
}

/// Flies a chip from the item just selected to the toolbar basket. Rows, tiles and the header
/// checkbox register their frames (in the window's SwiftUI "global" space) here; the basket
/// reports its view; the chip is drawn by a click-through hosting view above everything in the
/// window, the toolbar included.
@MainActor
final class FlightCenter {
  static let duration = 0.55
  /// The header's select-all checkbox, the source of a bulk select.
  static let headerKey = "header"

  let stage = FlightStage()
  weak var basketView: NSView?
  private var sources: [String: CGRect] = [:]
  private var overlay: NSView?

  func register(_ id: String, frame: CGRect) { sources[id] = frame }

  func unregister(_ id: String) { sources[id] = nil }

  /// Whether a basket is on screen to fly into.
  var hasBasket: Bool {
    guard let view = basketView else { return false }
    return view.window != nil && !view.isHiddenOrHasHiddenAncestor
  }

  /// Plays one flight for `newlySelected` (see `BasketPresentation.flights`). Nothing flies for a
  /// deselection, without a basket, without a known origin, or when motion is reduced.
  func fly(newlySelected: [ScanResult], allowsMotion: Bool) {
    guard allowsMotion, hasBasket, let basket = basketView, let window = basket.window,
      let content = window.contentView, let frameView = content.superview,
      let item = BasketPresentation.flights(newlySelected: newlySelected).first
    else { return }

    let visible = CGRect(origin: .zero, size: content.bounds.size)
    let header = sources[Self.headerKey]
    let own = sources[item.id]
    let candidates = newlySelected.count > 1 ? [header, own] : [own, header]
    guard let source = candidates.compactMap({ $0 }).first(where: { $0.intersects(visible) })
    else { return }

    let from = overlayRect(fromContent: source, content: content, frameView: frameView)
    let to = overlayRect(of: basket, frameView: frameView)
    ensureOverlay(in: frameView)

    let flight = FlightStage.Flight(
      label: BasketPresentation.chipLabel(for: item, totalNewlySelected: newlySelected.count),
      from: from, to: to)
    stage.flight = flight
    // The chip normally reports its own arrival; this covers a window that stops animating.
    Task {
      try? await Task.sleep(nanoseconds: UInt64((Self.duration + 0.3) * 1_000_000_000))
      arrive(flight.id)
    }
  }

  fileprivate func arrive(_ id: UUID) {
    guard stage.flight?.id == id else { return }
    stage.flight = nil
    stage.pulse += 1
  }

  // MARK: Geometry

  /// A rect in `view`'s AppKit coordinates as a top-left-origin rect, or back (it is its own inverse).
  private func flip(_ rect: CGRect, in view: NSView) -> CGRect {
    view.isFlipped
      ? rect
      : CGRect(x: rect.minX, y: view.bounds.height - rect.maxY, width: rect.width, height: rect.height)
  }

  private func overlayRect(fromContent rect: CGRect, content: NSView, frameView: NSView) -> CGRect {
    let inFrame = frameView.convert(flip(rect, in: content), from: content)
    return flip(inFrame, in: frameView)
  }

  private func overlayRect(of view: NSView, frameView: NSView) -> CGRect {
    flip(frameView.convert(view.bounds, from: view), in: frameView)
  }

  private func ensureOverlay(in frameView: NSView) {
    if let overlay, overlay.superview === frameView { return }
    overlay?.removeFromSuperview()
    let host = ClickThroughHostingView(rootView: FlightLayer(center: self))
    host.frame = frameView.bounds
    host.autoresizingMask = [.width, .height]
    host.setAccessibilityElement(false)
    frameView.addSubview(host, positioned: .above, relativeTo: nil)
    overlay = host
  }
}

private final class ClickThroughHostingView: NSHostingView<FlightLayer> {
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private struct FlightLayer: View {
  var center: FlightCenter
  @ObservedObject private var stage: FlightStage

  init(center: FlightCenter) {
    self.center = center
    stage = center.stage
  }

  var body: some View {
    ZStack {
      if let flight = stage.flight {
        FlightChip(flight: flight) { center.arrive(flight.id) }
          .id(flight.id)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .ignoresSafeArea()
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}

private struct FlightChip: View {
  var flight: FlightStage.Flight
  var onArrive: () -> Void
  @State private var progress = 0.0

  var body: some View {
    Text(flight.label)
      .font(.caption.weight(.semibold))
      .foregroundStyle(.white)
      .lineLimit(1)
      .truncationMode(.middle)
      .padding(.horizontal, 10)
      .padding(.vertical, 4)
      .frame(maxWidth: 200)
      .background(Capsule().fill(BrandTheme.accent))
      .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
      .fixedSize()
      .modifier(FlightPath(from: flight.from, to: flight.to, progress: progress))
      .onAppear {
        withAnimation(.timingCurve(0.35, 0, 0.2, 1, duration: FlightCenter.duration)) {
          progress = 1
        } completion: {
          onArrive()
        }
      }
  }
}

/// Positions the chip along an arc from the start frame's centre to the end frame's, shrinking
/// it and fading it out over the last stretch so it seems to drop in.
private struct FlightPath: ViewModifier, Animatable {
  var from: CGRect
  var to: CGRect
  var progress: Double

  var animatableData: Double {
    get { progress }
    set { progress = newValue }
  }

  func body(content: Content) -> some View {
    let start = CGPoint(x: from.midX, y: from.midY)
    let end = CGPoint(x: to.midX, y: to.midY)
    let distance = hypot(end.x - start.x, end.y - start.y)
    let lift = min(70, distance * 0.18) * sin(progress * .pi)
    let fade = max(0, (progress - 0.8) / 0.2)
    content
      .scaleEffect(1 - 0.45 * progress)
      .opacity(1 - fade)
      .position(
        x: start.x + (end.x - start.x) * progress,
        y: start.y + (end.y - start.y) * progress - lift)
  }
}

// MARK: - Registering sources

private struct FlightCenterKey: EnvironmentKey {
  static let defaultValue: FlightCenter? = nil
}

extension EnvironmentValues {
  /// The window's flight center. Reading it doesn't observe anything, so views that only
  /// register their frames never re-render for a flight.
  var flightCenter: FlightCenter? {
    get { self[FlightCenterKey.self] }
    set { self[FlightCenterKey.self] = newValue }
  }
}

private struct FlightSource: ViewModifier {
  var id: String
  @Environment(\.flightCenter) private var center

  func body(content: Content) -> some View {
    content
      .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
        center?.register(id, frame: frame)
      }
      .onDisappear { center?.unregister(id) }
  }
}

extension View {
  /// Reports this view's frame as where `id`'s flight into the basket starts.
  func flightSource(_ id: String) -> some View { modifier(FlightSource(id: id)) }
}
