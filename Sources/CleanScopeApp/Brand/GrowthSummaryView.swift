import CleanScopeCore
import SwiftUI

struct GrowthSummaryView: View {
  var cleanableBytes: Int64
  var resultCount: Int
  var isScanning: Bool
  var reduceMotion: Bool

  private var stage: Int {
    StoragePresentation.growthStage(resultCount: resultCount, isScanning: isScanning)
  }

  var body: some View {
    HStack(spacing: 24) {
      VStack(alignment: .leading, spacing: 8) {
        Text(isScanning ? "Room discovered so far" : "Ready to reclaim")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(BrandTheme.scopeForest)
        Text(ByteCount.string(cleanableBytes))
          .font(.system(size: 36, weight: .bold, design: .rounded))
          .foregroundStyle(BrandTheme.deepInk)
          .monospacedDigit()
        Text(StoragePresentation.reclaimCopy(bytes: cleanableBytes))
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)

        if isScanning {
          HStack(spacing: 8) {
            ProgressView()
              .controlSize(.small)
            Text("\(resultCount) items checked in")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      }

      Spacer(minLength: 12)

      GrowthPlant(stage: stage)
        .frame(width: 152, height: 108)
        .accessibilityHidden(true)
        .animation(
          reduceMotion ? nil : .easeOut(duration: BrandTheme.motionDuration),
          value: stage
        )
    }
    .padding(20)
    .background(BrandTheme.openMint)
    .clipShape(RoundedRectangle(cornerRadius: BrandTheme.radius, style: .continuous))
  }
}

private struct GrowthPlant: View {
  var stage: Int

  var body: some View {
    ZStack(alignment: .bottom) {
      Capsule()
        .fill(BrandTheme.scopeForest.opacity(0.16))
        .frame(width: 120, height: 12)

      Capsule()
        .fill(BrandTheme.scopeForest)
        .frame(width: 8, height: stage == 0 ? 20 : CGFloat(34 + stage * 16))
        .offset(y: -6)

      if stage >= 1 {
        leaf(rotation: -30)
          .offset(x: -22, y: -42)
      }
      if stage >= 2 {
        leaf(rotation: 28)
          .scaleEffect(x: -1)
          .offset(x: 21, y: -63)
      }
      if stage >= 3 {
        Circle()
          .fill(BrandTheme.sunToken)
          .frame(width: 13, height: 13)
          .offset(x: 2, y: -96)
      }
    }
  }

  private func leaf(rotation: Double) -> some View {
    Capsule()
      .fill(BrandTheme.freshLeaf)
      .frame(width: 46, height: 21)
      .rotationEffect(.degrees(rotation))
  }
}
