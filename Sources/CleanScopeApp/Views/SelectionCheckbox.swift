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
  var action: (_ usesRangeSelection: Bool) -> Void

  var body: some View {
    Button {
      action(NSApp.currentEvent?.modifierFlags.contains(.shift) == true)
    } label: {
      Image(systemName: symbol)
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(isEnabled ? tint : Color.secondary)
        .frame(width: 20, height: 20)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(!isEnabled)
    .accessibilityLabel(accessibilityLabel)
    .accessibilityValue(accessibilityValue)
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
    state == .off ? .secondary : BrandTheme.scopeForest
  }

  private var accessibilityValue: String {
    switch state {
    case .off: return "Not selected"
    case .mixed: return "Partially selected"
    case .on: return "Selected"
    }
  }
}
