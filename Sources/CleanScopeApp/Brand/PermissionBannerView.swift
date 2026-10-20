import AppKit
import CleanScopeCore
import SwiftUI

struct PermissionBannerView: View {
  var summary: PermissionSummary
  @State private var isExpanded = false

  private static let fullDiskAccessURL = URL(
    string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!

  var body: some View {
    if summary.isLikelyComplete {
      Label(summary.message, systemImage: "checkmark.shield.fill")
        .font(.callout)
        .foregroundStyle(BrandTheme.safe)
    } else {
      VStack(alignment: .leading, spacing: 10) {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
          Image(systemName: "lock.shield.fill")
            .foregroundStyle(BrandTheme.info)
            .accessibilityHidden(true)
          VStack(alignment: .leading, spacing: 6) {
            Text(summary.message)
              .foregroundStyle(BrandTheme.textPrimary)
              .fixedSize(horizontal: false, vertical: true)
            DisclosureGroup("How to allow access", isExpanded: $isExpanded) {
              VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(summary.setupSteps.enumerated()), id: \.offset) { index, step in
                  Text("\(index + 1). \(step)")
                }
              }
              .font(.callout)
              .foregroundStyle(BrandTheme.textSecondary)
              .padding(.top, 4)
            }
            .font(.callout)
          }
          Spacer(minLength: 8)
          Button("Open Full Disk Access") {
            NSWorkspace.shared.open(Self.fullDiskAccessURL)
          }
        }
      }
      .padding(12)
      .background(
        RoundedRectangle(cornerRadius: BrandTheme.radius, style: .continuous)
          .fill(BrandTheme.info.opacity(0.08))
      )
      .overlay(
        RoundedRectangle(cornerRadius: BrandTheme.radius, style: .continuous)
          .stroke(BrandTheme.info.opacity(0.25))
      )
    }
  }
}
