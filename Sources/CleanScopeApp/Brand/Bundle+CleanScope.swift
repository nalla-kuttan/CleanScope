import Foundation

extension Bundle {
  /// The app's SwiftPM resource bundle. In the staged .app it sits in
  /// Contents/Resources; under `swift run` and tests it is next to the binary,
  /// which `Bundle.module` finds. The staged lookup runs first so the
  /// generated accessor (which traps when nothing is found) is never reached
  /// from the packaged app.
  static let cleanScope: Bundle = {
    if let url = Bundle.main.resourceURL?.appendingPathComponent("CleanScope_CleanScopeApp.bundle"),
      let bundle = Bundle(url: url)
    {
      return bundle
    }
    return Bundle.module
  }()
}
