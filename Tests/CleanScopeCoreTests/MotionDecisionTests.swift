import Testing

@testable import CleanScopeCore

@Suite struct MotionDecisionTests {
  @Test func reduceMotionStopsEverything() {
    let d = MotionDecision(reduceMotion: true, lowPower: false, windowVisible: true, appActive: true)
    #expect(!d.allowsAmbientMotion)
    #expect(!d.allowsTransitions)
  }

  @Test func lowPowerStopsAmbientButKeepsTransitions() {
    let d = MotionDecision(reduceMotion: false, lowPower: true, windowVisible: true, appActive: true)
    #expect(!d.allowsAmbientMotion)
    #expect(d.allowsTransitions)
  }

  @Test func occludedWindowStopsAmbientMotion() {
    let d = MotionDecision(
      reduceMotion: false, lowPower: false, windowVisible: false, appActive: true)
    #expect(!d.allowsAmbientMotion)
    #expect(d.allowsTransitions)
  }

  @Test func inactiveAppStopsAmbientMotion() {
    let d = MotionDecision(
      reduceMotion: false, lowPower: false, windowVisible: true, appActive: false)
    #expect(!d.allowsAmbientMotion)
    #expect(d.allowsTransitions)
  }

  @Test func normalConditionsAllowBoth() {
    let d = MotionDecision(reduceMotion: false, lowPower: false, windowVisible: true, appActive: true)
    #expect(d.allowsAmbientMotion)
    #expect(d.allowsTransitions)
  }
}
