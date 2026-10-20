import AppKit
import CleanScopeCore
import SwiftUI

/// Greenhouse palette. Every text-role token meets WCAG AA (4.5:1) on both `surface` and
/// `surfaceRaised` in light and dark appearances; see DESIGN.md for the measured ratios.
/// Values live in `BrandPalette` (CleanScopeCore) so tests can check them.
enum BrandTheme {
  static let radius: CGFloat = 10
  static let smallRadius: CGFloat = 7
  static let motionDuration = 0.2

  // Surfaces
  static let surface = color(BrandPalette.surface)
  static let surfaceRaised = color(BrandPalette.surfaceRaised)
  static let hairline = Color(nsColor: .separatorColor)

  // Text
  static let textPrimary = color(BrandPalette.textPrimary)
  static let textSecondary = color(BrandPalette.textSecondary)

  // Accent: `accent` fills controls that carry white labels; `accentText` is for text and icons.
  static let accent = color(BrandPalette.accent)
  static let accentText = color(BrandPalette.accentText)

  // Semantic state colors, all usable as text.
  static let safe = color(BrandPalette.safe)
  static let review = color(BrandPalette.review)
  static let destructive = color(BrandPalette.destructive)
  static let info = color(BrandPalette.info)

  /// The Sprout Lens keeps its original colors so the in-app mark matches the app icon.
  enum Mark {
    static let lens = color(BrandPalette.markLens)
    static let leaf = color(BrandPalette.markLeaf)
    static let field = color(BrandPalette.markField)
  }

  /// An appearance-adaptive colour for a palette token.
  static func color(_ token: PaletteColor) -> Color {
    Color(nsColor: nsColor(token))
  }

  static func nsColor(_ token: PaletteColor) -> NSColor {
    NSColor(name: nil) { appearance in
      switch appearance.bestMatch(from: [
        .aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua,
      ]) {
      case .darkAqua?: return srgb(token.dark)
      case .accessibilityHighContrastAqua?: return srgb(token.increasedLight)
      case .accessibilityHighContrastDarkAqua?: return srgb(token.increasedDark)
      default: return srgb(token.light)
      }
    }
  }

  static func srgb(_ hex: UInt32) -> NSColor {
    let c = BrandPalette.components(hex)
    return NSColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: 1)
  }
}
