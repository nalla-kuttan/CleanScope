import CleanScopeCore
import SwiftUI

/// Privacy cleanup. Starts with the download history macOS keeps.
struct PrivacyView: View {
  @State private var count: Int?
  @State private var error: String?
  @State private var confirmsClear = false
  private let history = QuarantineHistory()

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        PageHeader(icon: .privacy, title: "Privacy", subtitle: "Clear records macOS keeps about your activity.")

        VStack(alignment: .leading, spacing: 8) {
          HStack(alignment: .firstTextBaseline) {
            Label("Download history", systemImage: "arrow.down.doc")
              .font(.headline)
              .foregroundStyle(BrandTheme.textPrimary)
            Spacer()
            Text(count.map { "\($0) entr\($0 == 1 ? "y" : "ies")" } ?? "—")
              .monospacedDigit()
              .foregroundStyle(.secondary)
          }
          Text(
            "macOS records every file downloaded by a browser or other app, including where it came from. Clearing the record doesn't delete the files or change how macOS checks them before they open."
          )
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
          if let error {
            Text(error).font(.caption).foregroundStyle(.secondary)
          }
          Button("Clear Download History…") { confirmsClear = true }
            .disabled((count ?? 0) == 0)
        }
        .padding(14)
        .background(BrandTheme.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: BrandTheme.radius))
      }
      .padding(24)
      .frame(maxWidth: 980, alignment: .leading)
    }
    .background(BrandTheme.surface)
    .task { refresh() }
    .alert("Clear \(count ?? 0) download history entries?", isPresented: $confirmsClear) {
      Button("Cancel", role: .cancel) {}
      Button("Clear", role: .destructive) { clear() }
    } message: {
      Text("This can't be undone.")
    }
  }

  private func refresh() {
    do {
      count = try history.count()
      error = nil
    } catch {
      count = nil
      self.error = "CleanScope couldn't read the download history. It may need Full Disk Access."
    }
  }

  private func clear() {
    do {
      try history.clear()
    } catch {
      self.error = "The download history could not be cleared."
    }
    refresh()
  }
}
