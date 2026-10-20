import Foundation

public struct AlertIgnoreRecord: Codable, Equatable, Sendable {
  public var kind: AlertKind
  /// A volume UUID, device name or `"home"`.
  public var discriminator: String
  public var ignoredAt: Date
  /// Nil means the alert is snoozed forever.
  public var interval: TimeInterval?

  public init(kind: AlertKind, discriminator: String, ignoredAt: Date, interval: TimeInterval?) {
    self.kind = kind
    self.discriminator = discriminator
    self.ignoredAt = ignoredAt
    self.interval = interval
  }

  public func isActive(at date: Date) -> Bool {
    guard let interval else { return true }
    return date < ignoredAt.addingTimeInterval(interval)
  }
}

public enum SnoozeOption: String, CaseIterable, Identifiable, Sendable {
  case untilTomorrow
  case day
  case threeDays
  case week
  case forever

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .untilTomorrow: return "Until tomorrow"
    case .day: return "For a day"
    case .threeDays: return "For 3 days"
    case .week: return "For a week"
    case .forever: return "Forever"
    }
  }

  public func record(
    kind: AlertKind, discriminator: String, now: Date = Date(), calendar: Calendar = .current
  ) -> AlertIgnoreRecord {
    let interval: TimeInterval?
    switch self {
    case .untilTomorrow:
      let startOfToday = calendar.startOfDay(for: now)
      let midnight =
        calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? now.addingTimeInterval(86_400)
      interval = midnight.timeIntervalSince(now)
    case .day: interval = 86_400
    case .threeDays: interval = 3 * 86_400
    case .week: interval = 7 * 86_400
    case .forever: interval = nil
    }
    return AlertIgnoreRecord(
      kind: kind, discriminator: discriminator, ignoredAt: now, interval: interval)
  }
}

public struct AlertIgnoreStore: @unchecked Sendable {
  private let defaults: UserDefaults
  private let key = "CleanScope.alertIgnores"

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  public func load() throws -> [AlertIgnoreRecord] {
    guard let data = defaults.data(forKey: key) else { return [] }
    return try JSONDecoder().decode([AlertIgnoreRecord].self, from: data)
  }

  public func save(_ records: [AlertIgnoreRecord]) throws {
    defaults.set(try JSONEncoder().encode(records), forKey: key)
  }

  /// Adds a snooze, replacing any earlier one for the same alert.
  public func add(_ record: AlertIgnoreRecord) throws {
    var records = try load().filter {
      !($0.kind == record.kind && $0.discriminator == record.discriminator)
    }
    records.append(record)
    try save(records)
  }

  public func reset() throws {
    defaults.removeObject(forKey: key)
  }
}
