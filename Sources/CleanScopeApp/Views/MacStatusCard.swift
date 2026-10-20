import CleanScopeCore
import SwiftUI

/// Five named checks with reasons and an optional score. A number and a list, never a dial.
struct MacStatusCard: View {
  @EnvironmentObject private var model: AppModel
  @EnvironmentObject private var status: StatusMonitor
  @State private var showsBreakdown = false

  var body: some View {
    let summary = model.statusSummary
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline) {
        Label("Mac status", systemImage: "stethoscope")
          .font(.headline)
          .foregroundStyle(BrandTheme.textPrimary)
        Spacer()
        Button(showsBreakdown ? "Hide score" : "Score \(summary.score) of 100") {
          showsBreakdown.toggle()
        }
        .buttonStyle(.plain)
        .font(.subheadline.monospacedDigit())
        .foregroundStyle(BrandTheme.textSecondary)
        .help("A weighted sum of the checks below.")
      }

      VStack(spacing: 6) {
        ForEach(summary.checks) { check in
          HStack(spacing: 10) {
            Image(systemName: check.isGood ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
              .foregroundStyle(check.isGood ? BrandTheme.safe : BrandTheme.review)
              .accessibilityHidden(true)
            Text(check.title).fontWeight(.semibold).frame(width: 90, alignment: .leading)
            Text(check.isGood ? "Good" : "Needs attention")
              .foregroundStyle(check.isGood ? BrandTheme.safe : BrandTheme.textPrimary)
              .frame(width: 120, alignment: .leading)
            Text(check.reason).foregroundStyle(.secondary).lineLimit(2)
            Spacer()
            if showsBreakdown {
              Text(check.isGood ? "+\(check.weight)" : "0 of \(check.weight)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
            }
            if let destination = destination(for: check.target) {
              Button("Open") { model.destination = destination }
                .controlSize(.small)
            }
          }
          .font(.subheadline)
          .accessibilityElement(children: .combine)
        }
      }
      .padding(12)
      .background(BrandTheme.surfaceRaised)
      .clipShape(RoundedRectangle(cornerRadius: BrandTheme.radius))
    }
  }

  private func destination(for target: StatusCheck.Target) -> AppModel.Destination? {
    switch target {
    case .storage: return .storageMap
    case .trash: return .trash
    case .protection: return .protection
    case .battery: return nil
    case .memory: return .memory
    }
  }
}
