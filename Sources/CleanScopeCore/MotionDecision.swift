/// What motion the app may show right now, derived from system and window state.
public struct MotionDecision: Equatable, Sendable {
  /// Continuous, decorative motion (idle loops, drifting particles). Pauses to save power
  /// and when nobody can see it.
  public var allowsAmbientMotion: Bool
  /// Short, user-triggered transitions. Only Reduce Motion turns these off.
  public var allowsTransitions: Bool

  public init(reduceMotion: Bool, lowPower: Bool, windowVisible: Bool, appActive: Bool) {
    allowsTransitions = !reduceMotion
    allowsAmbientMotion = !reduceMotion && !lowPower && windowVisible && appActive
  }
}
