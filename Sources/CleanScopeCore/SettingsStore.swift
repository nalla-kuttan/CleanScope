import Foundation

public struct SettingsStore: @unchecked Sendable {
  private let defaults: UserDefaults
  private let key = "CleanScope.settings"

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  public func load() throws -> Settings {
    guard let data = defaults.data(forKey: key) else {
      return .default
    }
    return try JSONDecoder().decode(Settings.self, from: data)
  }

  public func save(_ settings: Settings) throws {
    let data = try JSONEncoder().encode(settings)
    defaults.set(data, forKey: key)
  }
}
