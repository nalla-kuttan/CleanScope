import CleanScopeCore
import SwiftUI

/// The Dashboard's opening line. One view that morphs through idle, scanning, results and
/// cleaned: the headline settles in with a short blur, the sprout grows to the state's stage,
/// and a scan shows its real progress. Under Reduce Motion the text only crossfades.
struct DashboardHero: View {
  @EnvironmentObject private var model: AppModel
  @EnvironmentObject private var motion: MotionPolicy

  private var state: HeroState {
    StoragePresentation.heroState(
      hasScanned: model.hasScanned, isScanning: model.isScanning,
      cleanedThisSession: model.cleanedThisSession)
  }

  var body: some View {
    let state = state
    HStack(alignment: .top, spacing: 14) {
      BrandMarkView(
        size: 44, field: true, isDecorative: true, growthStage: state.sproutStage,
        growthAnimation: .spring(response: 0.4, dampingFraction: 0.7)
      )

      VStack(alignment: .leading, spacing: 6) {
        headlineBlock(state)

        if state == .scanning {
          ProgressView(value: min(max(model.scanProgress, 0), 1))
            .progressViewStyle(.linear)
            .tint(BrandTheme.accent)
            .frame(maxWidth: 320)
            .padding(.top, 4)
            .accessibilityLabel("Scan progress")
            .accessibilityValue(
              Text(min(max(model.scanProgress, 0), 1), format: .percent.precision(.fractionLength(0))))
        }
      }
    }
    // Under Reduce Motion the state change is a plain crossfade of the text.
    .animation(motion.allowsTransitions ? nil : .easeInOut(duration: 0.2), value: state)
  }

  @ViewBuilder
  private func headlineBlock(_ state: HeroState) -> some View {
    let content = VStack(alignment: .leading, spacing: 4) {
      Text(headline(for: state))
        .font(.system(size: 26, weight: .bold))
        .foregroundStyle(BrandTheme.textPrimary)
        .accessibilityAddTraits(.isHeader)

      if state == .cleaned, let session = model.cleanupSession {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          RollingBytesText(
            bytes: session.recoveredBytes, sessionID: session.id,
            rolls: model.pendingRollSessionID == session.id
          )
          .font(.system(size: 30, weight: .bold, design: .rounded))
          .foregroundStyle(BrandTheme.accentText)
          Text("recovered")
            .font(.callout)
            .foregroundStyle(BrandTheme.textPrimary)
        }
        .accessibilityElement(children: .combine)
      }

      // Primary text: it sits on the weather gradient, whose ends are checked against it.
      Text(subheadline(for: state))
        .foregroundStyle(BrandTheme.textPrimary)
        .fixedSize(horizontal: false, vertical: true)
    }

    if motion.allowsTransitions {
      content.phaseAnimator(Self.settlePhases, trigger: state) { view, phase in
        view
          .blur(radius: phase == .settled ? 0 : 4)
          .opacity(phase == .settled ? 1 : 0)
      } animation: { phase in
        // Called with the phase being left: the jump from rest into `.entering` is instant, the
        // way back to `.settled` takes 0.25 s.
        phase == .settled ? nil : .easeOut(duration: 0.25)
      }
    } else {
      content
    }
  }

  enum SettlePhase { case settled, entering }
  /// A phase animator rests on its first phase. Each state change jumps to `.entering` (blurred,
  /// transparent) and eases back to `.settled`.
  private static let settlePhases: [SettlePhase] = [.settled, .entering]

  private func headline(for state: HeroState) -> String {
    if state == .cleaned { return "Moved safely to Trash." }
    return StoragePresentation.headline(
      hasScanned: model.hasScanned, isScanning: model.isScanning,
      safeBytes: model.summary.safeToDeleteBytes)
  }

  /// Idle keeps the first-run reassurance, scanning the live count, everything after the
  /// disk weather. The review-count line lives in the summary card.
  private func subheadline(for state: HeroState) -> String {
    StoragePresentation.heroSubline(
      state: state, itemsFound: model.summary.totalResults,
      usedFraction: model.weatherUsedFraction,
      availableBytes: model.weatherDisk?.availableBytes ?? 0,
      safeBytes: model.summary.safeToDeleteBytes)
  }
}

/// A byte figure that rolls up from zero once per cleanup session, then stays still. `rolls`
/// is read once, when the view appears; the figure it rolls to is always the real recovered
/// total. With transitions off it simply shows the total.
struct RollingBytesText: View {
  var bytes: Int64
  var sessionID: String
  var rolls: Bool
  var format: (Int64) -> String = { ByteCount.string($0) }
  @EnvironmentObject private var model: AppModel
  @EnvironmentObject private var motion: MotionPolicy
  @State private var shown: Int64

  init(
    bytes: Int64, sessionID: String, rolls: Bool,
    format: @escaping (Int64) -> String = { ByteCount.string($0) }
  ) {
    self.bytes = bytes
    self.sessionID = sessionID
    self.rolls = rolls
    self.format = format
    _shown = State(initialValue: rolls ? 0 : bytes)
  }

  var body: some View {
    Text(format(shown))
      .monospacedDigit()
      .contentTransition(motion.allowsTransitions ? .numericText(value: Double(shown)) : .identity)
      .accessibilityLabel(format(bytes))
      .task(id: sessionID) {
        guard shown != bytes else {
          model.finishRoll(sessionID)
          return
        }
        withAnimation(motion.animation(.easeOut(duration: 0.9))) { shown = bytes }
        model.finishRoll(sessionID)
      }
  }
}
