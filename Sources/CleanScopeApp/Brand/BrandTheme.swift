import AppKit
import SwiftUI

/// Greenhouse palette. Every text-role token meets WCAG AA (4.5:1) on both `surface` and
/// `surfaceRaised` in light and dark appearances; see DESIGN.md for the measured ratios.
enum BrandTheme {
  static let radius: CGFloat = 10
  static let smallRadius: CGFloat = 7
  static let motionDuration = 0.2

  // Surfaces
  static let surface = adaptive(light: 0xFAF7F2, dark: 0x1A1816)
  static let surfaceRaised = adaptive(light: 0xF0EAE2, dark: 0x252220)
  static let hairline = Color(nsColor: .separatorColor)

  // Text
  static let textPrimary = adaptive(light: 0x2C2420, dark: 0xF2EDE8)
  static let textSecondary = adaptive(
    light: 0x6B6561, dark: 0x918C87, increasedLight: 0x4A4440, increasedDark: 0xBDB7B1)

  // Accent: `accent` fills controls that carry white labels; `accentText` is for text and icons.
  static let accent = adaptive(
    light: 0x526D56, dark: 0x4D814D, increasedLight: 0x3E5642, increasedDark: 0x3F6E3F)
  static let accentText = adaptive(
    light: 0x526D56, dark: 0x8FBC8F, increasedLight: 0x3E5642, increasedDark: 0xA9D1A9)

  // Semantic state colors, all usable as text.
  static let safe = adaptive(
    light: 0x3D6B4A, dark: 0x5DA96A, increasedLight: 0x2C5237, increasedDark: 0x7CC488)
  static let review = adaptive(
    light: 0x816025, dark: 0xE0B05A, increasedLight: 0x634917, increasedDark: 0xF0C878)
  static let destructive = adaptive(
    light: 0xA54C3F, dark: 0xE8836F, increasedLight: 0x863A2F, increasedDark: 0xF5A291)
  static let info = adaptive(
    light: 0x4B698A, dark: 0x7DA4CC, increasedLight: 0x37526F, increasedDark: 0x9DBEE0)

  /// The Sprout Lens keeps its original colors so the in-app mark matches the app icon.
  enum Mark {
    static let lens = adaptive(light: 0x176F5D, dark: 0x63C6A7)
    static let leaf = adaptive(light: 0x50B77A, dark: 0x71D198)
    static let field = adaptive(light: 0xDFF2E8, dark: 0x173C33)
  }

  static func animation(_ reduceMotion: Bool) -> Animation? {
    reduceMotion ? nil : .easeOut(duration: motionDuration)
  }

  private static func adaptive(
    light: UInt32, dark: UInt32, increasedLight: UInt32? = nil, increasedDark: UInt32? = nil
  ) -> Color {
    Color(
      nsColor: NSColor(name: nil) { appearance in
        switch appearance.bestMatch(from: [
          .aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua,
        ]) {
        case .darkAqua?: return srgb(dark)
        case .accessibilityHighContrastAqua?: return srgb(increasedLight ?? light)
        case .accessibilityHighContrastDarkAqua?: return srgb(increasedDark ?? dark)
        default: return srgb(light)
        }
      })
  }

  private static func srgb(_ hex: UInt32) -> NSColor {
    NSColor(
      srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
      green: CGFloat((hex >> 8) & 0xFF) / 255,
      blue: CGFloat(hex & 0xFF) / 255,
      alpha: 1
    )
  }
}
