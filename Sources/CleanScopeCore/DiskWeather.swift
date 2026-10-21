import Foundation

/// The Dashboard's sky: it drifts from a fresh morning to a warm afternoon as the disk fills.
/// Colours are plain sRGB hex values so tests can check them; no stop is ever the destructive
/// colour, and the primary text colour reads on every stop (see `DiskWeatherTests`).
public enum DiskWeather {
  /// Used fraction at which the sky is at its freshest, and where it is at its warmest.
  public static let freshFraction = 0.40
  public static let warmFraction = 0.98

  /// Fresh → warm endpoints per appearance: top, bottom and sun colours.
  private struct Palette {
    var top: (UInt32, UInt32)
    var bottom: (UInt32, UInt32)
    var sun: (UInt32, UInt32)
  }

  private static let light = Palette(
    top: (0xE3F1E8, 0xF8DDB2), bottom: (0xF7F3EA, 0xF4CB93), sun: (0xF3D98A, 0xF0A95A))
  private static let dark = Palette(
    top: (0x1F2E27, 0x3A2C18), bottom: (0x1A1816, 0x2A2014), sun: (0x5C8A6C, 0xC08A3A))

  /// The sky colours for `usedFraction`, clamped to 0.40…0.98 and interpolated per channel.
  public static func stops(usedFraction: Double, dark isDark: Bool) -> (
    top: UInt32, bottom: UInt32, sun: UInt32
  ) {
    let palette = isDark ? dark : light
    let raw = (usedFraction - freshFraction) / (warmFraction - freshFraction)
    let t = raw.isNaN ? 0 : min(max(raw, 0), 1)
    return (
      top: mix(palette.top.0, palette.top.1, t),
      bottom: mix(palette.bottom.0, palette.bottom.1, t),
      sun: mix(palette.sun.0, palette.sun.1, t)
    )
  }

  /// Share of the disk in use, 0…1. An unknown disk (no total) counts as empty.
  public static func usedFraction(totalBytes: Int64, availableBytes: Int64) -> Double {
    guard totalBytes > 0 else { return 0 }
    let used = Double(totalBytes - availableBytes) / Double(totalBytes)
    return min(max(used, 0), 1)
  }

  private static func mix(_ a: UInt32, _ b: UInt32, _ t: Double) -> UInt32 {
    func channel(_ shift: UInt32) -> UInt32 {
      let from = Double((a >> shift) & 0xFF)
      let to = Double((b >> shift) & 0xFF)
      return UInt32((from + (to - from) * t).rounded())
    }
    return channel(16) << 16 | channel(8) << 8 | channel(0)
  }
}
