import AppKit
import SwiftUI

struct SelectionCheckbox: View {
  enum State {
    case off
    case mixed
    case on
  }

  var state: State
  var isEnabled = true
  var accessibilityLabel: String
  /// Shown as a tooltip and VoiceOver hint when the checkbox is disabled.
  var unavailableReason: String? = nil
  var action: (_ usesRangeSelection: Bool) -> Void

  var body: some View {
    Button {
      action(NSApp.currentEvent?.modifierFlags.contains(.shift) == true)
    } label: {
      Image(systemName: symbol)
        .font(.system(size: 15))
        .foregroundStyle(isEnabled ? tint : BrandTheme.textSecondary.opacity(0.55))
        .frame(width: 22, height: 22)
        .contentShape(Rectangle())
    }
    .buttonStyle(.borderless)
    .disabled(!isEnabled)
    .help(isEnabled ? "" : (unavailableReason ?? ""))
    .accessibilityLabel(accessibilityLabel)
    .accessibilityValue(accessibilityValue)
    .accessibilityHint(isEnabled ? "" : (unavailableReason ?? ""))
    .accessibilityAddTraits(state == .on ? .isSelected : [])
  }

  private var symbol: String {
    switch state {
    case .off: return "square"
    case .mixed: return "minus.square.fill"
    case .on: return "checkmark.square.fill"
    }
  }

  private var tint: Color {
    state == .off ? BrandTheme.textSecondary : BrandTheme.accent
  }

  private var accessibilityValue: String {
    switch state {
    case .off: return "Not selected"
    case .mixed: return "Partially selected"
    case .on: return "Selected"
    }
  }
}
