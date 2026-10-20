import Testing

@testable import CleanScopeCore

@Suite struct BrandPaletteTests {
  private let fills: [(String, PaletteColor)] = [
    ("safeFill", BrandPalette.safeFill),
    ("reviewFill", BrandPalette.reviewFill),
    ("appFill", BrandPalette.appFill),
    ("keepFill", BrandPalette.keepFill),
    ("systemFill", BrandPalette.systemFill),
    ("freeFill", BrandPalette.freeFill),
    ("unclassifiedFill", BrandPalette.unclassifiedFill),
  ]

  @Test func tileLabelsMeetContrastOnEveryFill() {
    for (name, fill) in fills {
      let label = BrandPalette.labelColor(onFill: fill)
      let light = BrandPalette.contrast(label.light, fill.light)
      let dark = BrandPalette.contrast(label.dark, fill.dark)
      #expect(light >= 4.5, "\(name) light: \(light)")
      #expect(dark >= 4.5, "\(name) dark: \(dark)")
    }
  }

  @Test func roleTextTokensMeetContrastOnSurfaces() {
    let textTokens: [(String, PaletteColor)] = [
      ("textPrimary", BrandPalette.textPrimary),
      ("textSecondary", BrandPalette.textSecondary),
      ("accentText", BrandPalette.accentText),
      ("safe", BrandPalette.safe),
      ("review", BrandPalette.review),
      ("destructive", BrandPalette.destructive),
      ("info", BrandPalette.info),
    ]
    let surfaces = [
      ("surface", BrandPalette.surface), ("surfaceRaised", BrandPalette.surfaceRaised),
    ]
    for (name, token) in textTokens {
      for (surfaceName, surface) in surfaces {
        let pairs: [(String, UInt32, UInt32)] = [
          ("light", token.light, surface.light),
          ("dark", token.dark, surface.dark),
          ("increasedLight", token.increasedLight, surface.increasedLight),
          ("increasedDark", token.increasedDark, surface.increasedDark),
        ]
        for (appearance, text, background) in pairs {
          let ratio = BrandPalette.contrast(text, background)
          #expect(ratio >= 4.5, "\(name) on \(surfaceName) \(appearance): \(ratio)")
        }
      }
    }
  }

  @Test func contrastMatchesKnownExtremes() {
    #expect(abs(BrandPalette.contrast(0x000000, 0xFFFFFF) - 21) < 0.001)
    #expect(BrandPalette.contrast(0x777777, 0x777777) == 1)
  }
}
