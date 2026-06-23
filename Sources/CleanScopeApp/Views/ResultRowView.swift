import CleanScopeCore
import SwiftUI

struct ResultRowView: View {
  var result: ScanResult

  var body: some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading) {
        Text(result.name)
          .font(.headline)
        Text(result.path)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      Spacer()
      Text(ByteCount.string(result.sizeBytes))
      SafetyLabel(category: result.category)
    }
    .padding(.vertical, 6)
  }
}
