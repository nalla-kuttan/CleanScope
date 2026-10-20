import Foundation

/// One colour token as sRGB hex values for each appearance. Increased-contrast values default
/// to the standard ones.
public struct PaletteColor: Equatable, Sendable {
  public let light: UInt32
  public let dark: UInt32
  public let increasedLight: UInt32
  public let increasedDark: UInt32

  public init(
    light: UInt32, dark: UInt32, increasedLight: UInt32? = nil, increasedDark: UInt32? = nil
  ) {
    self.light = light
    self.dark = dark
    self.increasedLight = increasedLight ?? light
    self.increasedDark = increasedDark ?? dark
  }
}

/// Greenhouse palette values. `BrandTheme` builds its colours from these; tests check contrast.
public enum BrandPalette {
  // Surfaces
  public static let surface = PaletteColor(light: 0xFAF7F2, dark: 0x1A1816)
  public static let surfaceRaised = PaletteColor(light: 0xF0EAE2, dark: 0x252220)

  // Text
  public static let textPrimary = PaletteColor(light: 0x2C2420, dark: 0xF2EDE8)
  public static let textSecondary = PaletteColor(
    light: 0x6B6561, dark: 0x918C87, increasedLight: 0x4A4440, increasedDark: 0xBDB7B1)

  // Accent: `accent` fills controls that carry white labels; `accentText` is for text and icons.
  public static let accent = PaletteColor(
    light: 0x526D56, dark: 0x4D814D, increasedLight: 0x3E5642, increasedDark: 0x3F6E3F)
  public static let accentText = PaletteColor(
    light: 0x526D56, dark: 0x8FBC8F, increasedLight: 0x3E5642, increasedDark: 0xA9D1A9)

  // Semantic state colours, all usable as text.
  public static let safe = PaletteColor(
    light: 0x3D6B4A, dark: 0x5DA96A, increasedLight: 0x2C5237, increasedDark: 0x7CC488)
  public static let review = PaletteColor(
    light: 0x816025, dark: 0xE0B05A, increasedLight: 0x634917, increasedDark: 0xF0C878)
  public static let destructive = PaletteColor(
    light: 0xA54C3F, dark: 0xE8836F, increasedLight: 0x863A2F, increasedDark: 0xF5A291)
  public static let info = PaletteColor(
    light: 0x4B698A, dark: 0x7DA4CC, increasedLight: 0x37526F, increasedDark: 0x9DBEE0)

  /// The Sprout Lens mark keeps its original colours so the in-app mark matches the app icon.
  public static let markLens = PaletteColor(light: 0x176F5D, dark: 0x63C6A7)
  public static let markLeaf = PaletteColor(light: 0x50B77A, dark: 0x71D198)
  public static let markField = PaletteColor(light: 0xDFF2E8, dark: 0x173C33)

  // Storage map tile fills. Labels on them use `labelColor(onFill:)`. The dark safe and app
  // fills are lifted slightly from the plan (0x4F8A5D, 0xB8644F) so their labels reach 4.5:1.
  public static let safeFill = PaletteColor(light: 0x86B892, dark: 0x528F60)
  public static let reviewFill = PaletteColor(light: 0xE4BC6A, dark: 0xB98A35)
  public static let appFill = PaletteColor(light: 0xDE9682, dark: 0xBC6C58)
  public static let keepFill = PaletteColor(light: 0xC3B8AC, dark: 0x625A53)
  public static let systemFill = PaletteColor(light: 0x9C9085, dark: 0x4A423C)
  public static let freeFill = PaletteColor(light: 0xD4ECDD, dark: 0x27443A)
  public static let unclassifiedFill = PaletteColor(light: 0xD9D2C9, dark: 0x3A3531)

  /// WCAG 2.x contrast ratio between two sRGB colours (1…21).
  public static func contrast(_ a: UInt32, _ b: UInt32) -> Double {
    let la = relativeLuminance(a)
    let lb = relativeLuminance(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
  }

  /// Label colour for text on `fill`: `textPrimary` or `surface`, chosen per appearance as the
  /// one that passes 4.5:1 (the higher-contrast one when both or neither do).
  public static func labelColor(onFill fill: PaletteColor) -> PaletteColor {
    func pick(_ primary: UInt32, _ inverse: UInt32, on background: UInt32) -> UInt32 {
      contrast(primary, background) >= contrast(inverse, background) ? primary : inverse
    }
    return PaletteColor(
      light: pick(textPrimary.light, surface.light, on: fill.light),
      dark: pick(textPrimary.dark, surface.dark, on: fill.dark),
      increasedLight: pick(
        textPrimary.increasedLight, surface.increasedLight, on: fill.increasedLight),
      increasedDark: pick(
        textPrimary.increasedDark, surface.increasedDark, on: fill.increasedDark))
  }

  /// Channels of `hex` (0xRRGGBB) as 0…1 values.
  public static func components(_ hex: UInt32) -> (red: Double, green: Double, blue: Double) {
    (
      Double((hex >> 16) & 0xFF) / 255,
      Double((hex >> 8) & 0xFF) / 255,
      Double(hex & 0xFF) / 255
    )
  }

  private static func relativeLuminance(_ hex: UInt32) -> Double {
    func linear(_ channel: Double) -> Double {
      channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
    }
    let c = components(hex)
    return 0.2126 * linear(c.red) + 0.7152 * linear(c.green) + 0.0722 * linear(c.blue)
  }
}
