import AppKit
import CleanScopeCore
import SwiftUI

struct ItemDetailView: View {
  var result: ScanResult
  @EnvironmentObject private var model: AppModel
  @Environment(\.dismiss) private var dismiss
  @State private var confirmsPermanent = false

  private var iconName: String {
    if result.itemType == .folder { return "folder.fill" }
    else if result.itemType == .symlink { return "link" }
    else { return "doc.fill" }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      // Header
      HStack(alignment: .center, spacing: 14) {
        Image(systemName: iconName)
          .font(.system(size: 24))
          .foregroundStyle(.white)
          .frame(width: 52, height: 52)
          .background(result.category.tintColor)
          .clipShape(RoundedRectangle(cornerRadius: BrandTheme.radius, style: .continuous))
          .shadow(color: result.category.tintColor.opacity(0.2), radius: 4, y: 2)

        VStack(alignment: .leading, spacing: 3) {
          Text(result.name)
            .font(.system(.title2, design: .rounded).bold())
            .lineLimit(1)
            .foregroundStyle(BrandTheme.bark)
          HStack(spacing: 8) {
            Text(ByteCount.string(result.sizeBytes))
              .font(.system(.headline, design: .rounded))
              .foregroundStyle(result.category.tintColor)
            Text("·").foregroundStyle(BrandTheme.warmGray)
            Text(result.itemType.rawValue.capitalized)
              .font(.system(.subheadline, design: .rounded))
              .foregroundStyle(BrandTheme.warmGray)
          }
        }
        Spacer()
        SafetyLabel(category: result.category)
      }

      // Safety banner
      warningBanner

      // Metadata sections
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          inspectorSection("Flagged Reason") {
            VStack(alignment: .leading, spacing: 6) {
              Text(result.reason)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(BrandTheme.bark)
              HStack(alignment: .top, spacing: 6) {
                Image(systemName: "info.circle")
                  .font(.caption).foregroundStyle(BrandTheme.sage).padding(.top, 2)
                Text(result.recommendedAction)
                  .font(.system(.caption, design: .rounded)).foregroundStyle(BrandTheme.sage)
              }
            }
          }

          inspectorSection("Details") {
            VStack(alignment: .leading, spacing: 12) {
              HStack(alignment: .top) {
                detail("Confidence", result.confidence.rawValue.capitalized)
                Spacer()
                detail("Consequence", result.riskNote)
              }
              Divider().background(BrandTheme.hairline)
              sizeThresholdGauge
            }
          }

          inspectorSection("Location") {
            VStack(alignment: .leading, spacing: 10) {
              detail("Path", result.path).help(result.path)
              if let modified = result.lastModified {
                Divider().background(BrandTheme.hairline)
                detail("Last Modified", modified.formatted(date: .long, time: .shortened))
              }
              if let owner = result.ownerTool ?? result.ownerApp {
                Divider().background(BrandTheme.hairline)
                detail("Associated App", owner)
              }
            }
          }
        }
      }

      // Action footer
      HStack(spacing: 10) {
        capsuleButton("Finder", icon: "folder") {
          NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: result.normalizedPath)])
        }

        capsuleButton(result.isExcluded ? "Excluded" : "Exclude", icon: "eye.slash") {
          model.exclude(result); dismiss()
        }
        .disabled(result.isExcluded)

        Spacer()

        if result.canDelete {
          capsuleButton(
            model.settings.deleteImmediately ? "Delete Permanently…" : "Move to Trash",
            icon: "trash", role: .destructive
          ) {
            if model.settings.deleteImmediately {
              confirmsPermanent = true
            } else {
              dismiss(); Task { await model.cleanup(result) }
            }
          }
        }

        Button("Close") { dismiss() }
          .keyboardShortcut(.cancelAction)
          .font(.system(.body, design: .rounded))
      }
      .padding(.top, 4)
    }
    .padding(24)
    .frame(width: 620, height: 600)
    .background(.ultraThinMaterial)
    .alert(
      "Delete \(result.name) (\(ByteCount.string(result.sizeBytes))) permanently?",
      isPresented: $confirmsPermanent
    ) {
      Button("Cancel", role: .cancel) {}
      Button("Delete Permanently", role: .destructive) {
        dismiss(); Task { await model.cleanup(result) }
      }
    } message: {
      Text("This can't be undone.")
    }
  }

  // MARK: - Warning Banner

  private var warningBanner: some View {
    HStack(spacing: 12) {
      Image(systemName: result.category.symbolName).font(.title3).foregroundStyle(result.category.warningTextColor)
      Text(result.category.warningText)
        .font(.system(.subheadline, design: .rounded)).foregroundStyle(result.category.warningTextColor)
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 0)
    }
    .padding(12)
    .background(result.category.warningBackground)
    .clipShape(RoundedRectangle(cornerRadius: BrandTheme.radius))
  }

  // MARK: - Size Gauge

  private var sizeThresholdGauge: some View {
    let ratio = CGFloat(result.sizeBytes) / CGFloat(model.settings.largeFileThresholdBytes)
    return VStack(alignment: .leading, spacing: 5) {
      HStack {
        Text("Size vs. Large File Threshold")
          .font(.system(.caption, design: .rounded)).foregroundStyle(BrandTheme.warmGray)
        Spacer()
        Text(ratio >= 1.0 ? String(format: "%.1f×", ratio) : String(format: "%.0f%%", ratio * 100))
          .font(.system(.caption, design: .rounded).weight(.semibold))
          .foregroundStyle(ratio >= 1.0 ? BrandTheme.terracotta : BrandTheme.sage)
      }
      GeometryReader { geo in
        ZStack(alignment: .leading) {
          Capsule().fill(BrandTheme.clay)
          Capsule()
            .fill(ratio >= 1.0 ? BrandTheme.terracotta : BrandTheme.sage)
            .frame(width: min(geo.size.width * CGFloat(min(ratio, 1.0)), geo.size.width))
        }
      }
      .frame(height: 6)
    }
    .padding(.top, 4)
  }

  // MARK: - Inspector Section

  private func inspectorSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.system(.headline, design: .rounded))
        .foregroundStyle(BrandTheme.bark)
      VStack(alignment: .leading, spacing: 8) {
        content()
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(12)
      .background(BrandTheme.clay)
      .overlay(RoundedRectangle(cornerRadius: BrandTheme.radius).stroke(BrandTheme.hairline))
      .clipShape(RoundedRectangle(cornerRadius: BrandTheme.radius))
    }
  }

  private func detail(_ title: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title).font(.system(.caption, design: .rounded)).foregroundStyle(BrandTheme.warmGray)
      Text(value).font(.system(.body, design: .rounded)).foregroundStyle(BrandTheme.bark).textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  // MARK: - Capsule Button

  private func capsuleButton(_ label: String, icon: String, role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
    Button(role: role, action: action) {
      Label(label, systemImage: icon)
        .font(.system(.subheadline, design: .rounded).weight(.medium))
    }
    .buttonStyle(.plain)
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .background(
      Capsule().fill(role == .destructive ? BrandTheme.terracotta.opacity(0.12) : BrandTheme.clay)
    )
    .foregroundStyle(role == .destructive ? BrandTheme.terracotta : BrandTheme.bark)
    .overlay(Capsule().stroke(BrandTheme.hairline))
  }
}
