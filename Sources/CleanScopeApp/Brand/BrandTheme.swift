import AppKit
import SwiftUI

enum BrandTheme {
  static let radius: CGFloat = 14
  static let motionDuration = 0.22

  // — Greenhouse Palette (adaptive light / dark) —
  static let sage = adaptive(light: 0x6B8F71, dark: 0x8FBC8F)          // Primary accent — muted botanical green
  static let terracotta = adaptive(light: 0xC0675A, dark: 0xE8836F)    // Destructive / warning — warm red-orange
  static let amber = adaptive(light: 0xC7963E, dark: 0xE0B05A)         // Attention — rich gold
  static let cream = adaptive(light: 0xFAF7F2, dark: 0x1A1816)         // Window surface — warm off-white / warm dark
  static let bark = adaptive(light: 0x2C2420, dark: 0xF2EDE8)          // Primary text — deep warm brown
  static let clay = adaptive(light: 0xF0EAE2, dark: 0x252220)          // Card / secondary surface
  static let moss = adaptive(light: 0x3D6B4A, dark: 0x5DA96A)          // Success — deep botanical green
  static let warmGray = adaptive(light: 0x8C8580, dark: 0x7A7570)      // Secondary text

  // Legacy aliases (keeps existing code compiling without mass renames)
  static let scopeForest = sage
  static let freshLeaf = moss
  static let openMint = clay
  static let sunToken = amber
  static let actionCoral = terracotta
  static let finderBlue = adaptive(light: 0x5A7FA6, dark: 0x7DA4CC)    // Muted steel-blue
  static let deepInk = bark
  static let clearPaper = cream

  static let hairline = Color(nsColor: .separatorColor).opacity(0.45)
  static let secondarySurface = clay

  // Gradients
  static let sageGradient = LinearGradient(
    colors: [sage, moss],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
  )

  static let warmGradient = LinearGradient(
    colors: [terracotta, amber],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
  )

  static let softGradient = LinearGradient(
    colors: [clay, cream],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
  )

  // Legacy gradient aliases
  static let sproutGradient = sageGradient
  static let coralGradient = warmGradient
  static let mintGradient = softGradient

  static func triggerHaptic() {
    #if os(macOS)
    NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
    #endif
  }

  private static func adaptive(light: UInt32, dark: UInt32) -> Color {
    Color(
      nsColor: NSColor(name: nil) { appearance in
        let match = appearance.bestMatch(from: [
          .darkAqua, .aqua, .accessibilityHighContrastDarkAqua,
        ])
        let isDark = match == .darkAqua || match == .accessibilityHighContrastDarkAqua
        return nsColor(hex: isDark ? dark : light)
      })
  }

  private static func nsColor(hex: UInt32) -> NSColor {
    NSColor(
      calibratedRed: CGFloat((hex >> 16) & 0xFF) / 255,
      green: CGFloat((hex >> 8) & 0xFF) / 255,
      blue: CGFloat(hex & 0xFF) / 255,
      alpha: 1
    )
  }
}
