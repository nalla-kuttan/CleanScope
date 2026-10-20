import CleanScopeCore
import SwiftUI

struct GrowthSummaryView: View {
  var cleanableBytes: Int64
  var resultCount: Int
  var isScanning: Bool
  var reduceMotion: Bool

  // Simulated total disk for gauge display
  private var totalDiskBytes: Int64 { 500_000_000_000 } // 500 GB placeholder
  private var reclaimFraction: Double {
    guard totalDiskBytes > 0 else { return 0 }
    return min(Double(cleanableBytes) / Double(totalDiskBytes), 1.0)
  }

  @State private var gaugeProgress: Double = 0

  var body: some View {
    HStack(spacing: 28) {
      // Radial Arc Gauge
      ZStack {
        // Background arc (full track)
        Circle()
          .trim(from: 0, to: 0.75)
          .stroke(BrandTheme.clay, style: StrokeStyle(lineWidth: 12, lineCap: .round))
          .rotationEffect(.degrees(135))

        // Reclaimable segment
        Circle()
          .trim(from: 0, to: gaugeProgress * 0.75)
          .stroke(BrandTheme.sageGradient, style: StrokeStyle(lineWidth: 12, lineCap: .round))
          .rotationEffect(.degrees(135))

        // Center text
        VStack(spacing: 2) {
          Text(ByteCount.string(cleanableBytes))
            .font(.system(size: 22, weight: .bold, design: .rounded))
            .foregroundStyle(BrandTheme.bark)
            .monospacedDigit()
          Text("reclaimable")
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .foregroundStyle(BrandTheme.warmGray)
        }
      }
      .frame(width: 120, height: 120)
      .padding(.vertical, 6)
      .onAppear {
        if reduceMotion {
          gaugeProgress = reclaimFraction
        } else {
          withAnimation(.easeOut(duration: 1.0).delay(0.2)) {
            gaugeProgress = reclaimFraction
          }
        }
      }
      .onChange(of: cleanableBytes) { _ in
        withAnimation(.easeOut(duration: 0.6)) {
          gaugeProgress = reclaimFraction
        }
      }

      // Text summary
      VStack(alignment: .leading, spacing: 6) {
        Text(isScanning ? "Discovering space…" : "Ready to reclaim")
          .font(.system(.subheadline, design: .rounded).weight(.semibold))
          .foregroundStyle(BrandTheme.sage)

        Text("\(resultCount) items found")
          .font(.system(size: 30, weight: .bold, design: .rounded))
          .foregroundStyle(BrandTheme.bark)

        Text(statusLine)
          .font(.system(.caption, design: .rounded))
          .foregroundStyle(BrandTheme.warmGray)
          .fixedSize(horizontal: false, vertical: true)

        if isScanning {
          HStack(spacing: 6) {
            ProgressView()
              .controlSize(.small)
            Text("scanning…")
              .font(.system(.caption, design: .rounded))
              .foregroundStyle(BrandTheme.warmGray)
          }
          .padding(.top, 2)
        }
      }

      Spacer(minLength: 0)
    }
    .padding(20)
    .background(
      RoundedRectangle(cornerRadius: BrandTheme.radius, style: .continuous)
        .fill(BrandTheme.clay)
    )
    .overlay(
      RoundedRectangle(cornerRadius: BrandTheme.radius, style: .continuous)
        .stroke(BrandTheme.hairline)
    )
  }

  private var statusLine: String {
    if isScanning {
      return "Results stream in as locations are checked."
    }
    if cleanableBytes == 0 {
      return "Run a scan to discover reclaimable space."
    }
    return "Your greenhouse is ready for pruning."
  }
}
