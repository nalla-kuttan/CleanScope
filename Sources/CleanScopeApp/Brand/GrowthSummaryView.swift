import CleanScopeCore
import SwiftUI

/// The dashboard's detail surface under the hero: what the safe space is made of, the review
/// space beside it, and the real disk it belongs to. The hero owns the headline figure.
struct GrowthSummaryView: View {
  var summary: ScanSummary
  var safeCount: Int
  var reviewCount: Int
  var disk: AppModel.Disk?
  var isScanning: Bool
  var hasScanned: Bool

  private var reviewBytes: Int64 { summary.probablyUnusedBytes + summary.deleteIfAppUnusedBytes }
  private var showsDetail: Bool { hasScanned || isScanning }

  var body: some View {
    if showsDetail || disk != nil {
      VStack(alignment: .leading, spacing: 10) {
        if showsDetail {
          VStack(alignment: .leading, spacing: 2) {
            Text(detailLine)
            if let review = StoragePresentation.reviewLine(count: reviewCount), !isScanning {
              Text(review)
            }
          }
          .font(.callout)
          .foregroundStyle(BrandTheme.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
        }

        if let disk {
          DiskBar(disk: disk, safeBytes: summary.safeToDeleteBytes)
        }

        if isScanning {
          HStack(spacing: 6) {
            ProgressView().controlSize(.small)
            Text("Results appear as each location is checked.")
              .font(.callout)
              .foregroundStyle(BrandTheme.textSecondary)
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(20)
      .background(
        RoundedRectangle(cornerRadius: BrandTheme.radius, style: .continuous)
          .fill(BrandTheme.surfaceRaised)
      )
    }
  }

  private var detailLine: String {
    var parts = ["\(CountPhrase.make(safeCount, "safe item"))"]
    if reviewBytes > 0 {
      parts.append(
        "\(ByteCount.string(reviewBytes)) more to review")
    }
    return parts.joined(separator: " · ")
  }
}

/// Used vs. available space on the startup disk, with the safe-to-reclaim share of used
/// space marked inside it.
private struct DiskBar: View {
  var disk: AppModel.Disk
  var safeBytes: Int64

  private func fraction(_ bytes: Int64) -> CGFloat {
    guard disk.totalBytes > 0 else { return 0 }
    return CGFloat(min(max(Double(bytes) / Double(disk.totalBytes), 0), 1))
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      GeometryReader { geo in
        let width = geo.size.width
        ZStack(alignment: .leading) {
          RoundedRectangle(cornerRadius: 3).fill(BrandTheme.hairline.opacity(0.6))
          RoundedRectangle(cornerRadius: 3)
            .fill(BrandTheme.textSecondary.opacity(0.55))
            .frame(width: width * fraction(disk.usedBytes))
          RoundedRectangle(cornerRadius: 3)
            .fill(BrandTheme.safe)
            .frame(width: width * fraction(min(safeBytes, disk.usedBytes)))
            .offset(x: width * (fraction(disk.usedBytes) - fraction(min(safeBytes, disk.usedBytes))))
        }
      }
      .frame(height: 8)
      .frame(maxWidth: 420)
      .accessibilityHidden(true)

      Text(
        "\(ByteCount.string(disk.availableBytes)) available of \(ByteCount.string(disk.totalBytes))"
      )
      .font(.caption)
      .monospacedDigit()
      .foregroundStyle(BrandTheme.textSecondary)
    }
    .accessibilityElement(children: .combine)
  }
}
