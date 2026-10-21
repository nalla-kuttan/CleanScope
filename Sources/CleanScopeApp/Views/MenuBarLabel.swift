import AppKit
import CleanScopeCore
import SwiftUI

/// Wakes at each local midnight (and at least hourly, which also covers sleep) so the menu bar
/// label's "days since cleanup" stays current without the app being used. No per-second timers.
@MainActor
final class DayTicker: ObservableObject {
  @Published private(set) var now = Date()
  private var task: Task<Void, Never>?
  private var observer: NSObjectProtocol?

  init() {
    observer = NotificationCenter.default.addObserver(
      forName: .NSCalendarDayChanged, object: nil, queue: .main
    ) { [weak self] _ in
      Task { @MainActor in self?.tick() }
    }
    task = Task { [weak self] in
      while !Task.isCancelled {
        let wait = DayTicker.secondsUntilNextRefresh(from: Date())
        try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
        self?.tick()
      }
    }
  }

  deinit {
    task?.cancel()
    if let observer { NotificationCenter.default.removeObserver(observer) }
  }

  private func tick() {
    now = Date()
  }

  /// Seconds until the next local midnight, capped at an hour (and never under a second).
  nonisolated static func secondsUntilNextRefresh(from date: Date) -> TimeInterval {
    let calendar = Calendar.current
    let midnight = calendar.nextDate(
      after: date, matching: DateComponents(hour: 0, minute: 0, second: 0),
      matchingPolicy: .nextTime)
    let untilMidnight = midnight?.timeIntervalSince(date) ?? 3600
    return min(max(untilMidnight, 1), 3600)
  }
}

/// The menu bar item: the sprout template image, plus a size label after two weeks.
struct MenuBarLabel: View {
  @ObservedObject var model: AppModel
  @ObservedObject var ticker: DayTicker

  var body: some View {
    let days = MenuBarPresentation.daysSinceCleanup(
      log: model.cleanupLog, firstLaunch: model.firstLaunchDate, now: ticker.now)
    let safeBytes = model.session?.summary.safeToDeleteBytes ?? 0
    let stage = MenuBarPresentation.sproutStage(daysSinceCleanup: days, safeBytes: safeBytes)
    let label = MenuBarPresentation.sizeLabel(daysSinceCleanup: days, safeBytes: safeBytes)
    HStack(spacing: 3) {
      Image(nsImage: SproutTemplateImage.image(stage: stage))
      if let label { Text(label) }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(MenuBarPresentation.accessibilityLabel(sizeLabel: label))
  }
}
