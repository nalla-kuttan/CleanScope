import AppKit
import SwiftUI

enum BrandTheme {
  static let radius: CGFloat = 8
  static let motionDuration = 0.18

  static let scopeForest = adaptive(light: 0x176F5D, dark: 0x63C6A7)
  static let freshLeaf = adaptive(light: 0x50B77A, dark: 0x71D198)
  static let openMint = adaptive(light: 0xDFF2E8, dark: 0x173C33)
  static let sunToken = adaptive(light: 0xFFCF4A, dark: 0xE7BC43)
  static let actionCoral = adaptive(light: 0xE9573F, dark: 0xFF7865)
  static let finderBlue = adaptive(light: 0x426BD2, dark: 0x7395F2)
  static let deepInk = adaptive(light: 0x17231F, dark: 0xF1F6F3)
  static let clearPaper = adaptive(light: 0xFBFDFC, dark: 0x121816)

  static let hairline = Color(nsColor: .separatorColor).opacity(0.55)
  static let secondarySurface = Color(nsColor: .controlBackgroundColor)

  private static func adaptive(light: UInt32, dark: UInt32) -> Color {
    Color(
      nsColor: NSColor(name: nil) { appearance in
        let isDark =
          appearance.bestMatch(from: [.darkAqua, .aqua, .accessibilityHighContrastDarkAqua])
          == .darkAqua
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
