import CleanScopeCore
import SwiftUI

extension SafetyCategory {
  var label: String {
    switch self {
    case .safeToDelete: return "Safe to delete"
    case .probablyUnused: return "Review recommended"
    case .deleteIfAppUnused: return "App/tool dependent"
    case .doNotBulkDelete: return "Do not bulk delete"
    }
  }

  var symbolName: String {
    switch self {
    case .safeToDelete: return "checkmark.circle.fill"
    case .probablyUnused: return "questionmark.circle.fill"
    case .deleteIfAppUnused: return "exclamationmark.triangle.fill"
    case .doNotBulkDelete: return "hand.raised.fill"
    }
  }

  var tintColor: Color {
    switch self {
    case .safeToDelete: return BrandTheme.moss
    case .probablyUnused: return BrandTheme.amber
    case .deleteIfAppUnused: return BrandTheme.terracotta
    case .doNotBulkDelete: return BrandTheme.warmGray
    }
  }

  var warningText: String {
    switch self {
    case .safeToDelete:
      return "Temporary or generated data. Safe to remove - apps rebuild it as needed."
    case .probablyUnused:
      return "Appears unused based on location or age. Verify before removing."
    case .deleteIfAppUnused:
      return "Associated with a specific tool. Delete only if the app is no longer needed."
    case .doNotBulkDelete:
      return "Contains personal or system-critical files. Review manually."
    }
  }

  var warningBackground: Color {
    switch self {
    case .safeToDelete: return BrandTheme.moss.opacity(0.10)
    case .probablyUnused: return BrandTheme.amber.opacity(0.10)
    case .deleteIfAppUnused: return BrandTheme.terracotta.opacity(0.08)
    case .doNotBulkDelete: return BrandTheme.warmGray.opacity(0.08)
    }
  }

  var warningTextColor: Color {
    switch self {
    case .safeToDelete: return BrandTheme.moss
    case .probablyUnused: return BrandTheme.bark
    case .deleteIfAppUnused: return BrandTheme.terracotta
    case .doNotBulkDelete: return BrandTheme.warmGray
    }
  }
}
