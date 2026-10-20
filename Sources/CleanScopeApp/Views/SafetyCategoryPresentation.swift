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

  /// Every tint is a text-grade token, so labels drawn in it meet AA contrast.
  var tintColor: Color {
    switch self {
    case .safeToDelete: return BrandTheme.safe
    case .probablyUnused: return BrandTheme.review
    case .deleteIfAppUnused: return BrandTheme.destructive
    case .doNotBulkDelete: return BrandTheme.textSecondary
    }
  }

  /// Orders the Safety column from least to most caution.
  var sortRank: Int {
    switch self {
    case .safeToDelete: return 0
    case .probablyUnused: return 1
    case .deleteIfAppUnused: return 2
    case .doNotBulkDelete: return 3
    }
  }

  var warningText: String {
    switch self {
    case .safeToDelete:
      return "Temporary or generated data. Apps rebuild it as needed."
    case .probablyUnused:
      return "Looks unused based on its location or age. Check it before you remove it."
    case .deleteIfAppUnused:
      return "Belongs to a specific app or tool. Remove it only if you no longer use that app."
    case .doNotBulkDelete:
      return "May contain personal, synced, or system-critical files. Review it in Finder instead."
    }
  }

  /// Why the cleanup checkbox is unavailable, shown as a tooltip and VoiceOver hint.
  var unavailableReason: String {
    switch self {
    case .doNotBulkDelete:
      return "CleanScope won’t bulk delete personal, synced, or protected data. Review it in Finder."
    default:
      return "This item can’t be moved to Trash from CleanScope."
    }
  }
}

extension ScanResult {
  var unavailableReason: String? {
    if isExcluded { return "Excluded from cleanup. Remove the exclusion in Settings to change this." }
    guard !canDelete else { return nil }
    return category.unavailableReason
  }
}

struct SafetyLabel: View {
  var category: SafetyCategory

  var body: some View {
    Label(category.label, systemImage: category.symbolName)
      .font(.callout.weight(.medium))
      .foregroundStyle(category.tintColor)
      .lineLimit(1)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(category.label)
  }
}
