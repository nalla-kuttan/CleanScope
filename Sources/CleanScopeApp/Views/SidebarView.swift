import AppKit
import SwiftUI

struct SidebarView: View {
  @EnvironmentObject private var model: AppModel
  @State private var hoveredDest: AppModel.Destination?

  var body: some View {
    VStack(spacing: 0) {
      // Brand header
      HStack(spacing: 10) {
        BrandMarkView(size: 34, isDecorative: true)
        VStack(alignment: .leading, spacing: 1) {
          Text("CleanScope")
            .font(.system(.headline, design: .rounded).bold())
            .foregroundStyle(BrandTheme.bark)
          Text("Greenhouse")
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(BrandTheme.sage)
        }
        Spacer()
      }
      .padding(.horizontal, 16)
      .padding(.top, 18)
      .padding(.bottom, 14)

      // Navigation rows
      ScrollView {
        VStack(alignment: .leading, spacing: 3) {
          ForEach(AppModel.Destination.Section.allCases) { section in
            let destinations = AppModel.Destination.allCases.filter { $0.section == section }
            if !destinations.isEmpty {
              Text(section.rawValue)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(BrandTheme.warmGray)
                .textCase(.uppercase)
                .padding(.horizontal, 10)
                .padding(.top, section == .storage ? 0 : 10)
                .padding(.bottom, 2)
                .accessibilityAddTraits(.isHeader)
              ForEach(destinations) { dest in
                SidebarRow(
                  destination: dest,
                  isActive: model.destination == dest,
                  isHovered: hoveredDest == dest
                ) {
                  model.destination = dest
                }
                .onHover { over in hoveredDest = over ? dest : nil }
              }
            }
          }
        }
        .padding(.horizontal, 10)
      }

      Spacer(minLength: 0)

      // Scan action footer
      VStack(spacing: 10) {
        Button {
          Task {
            if model.isScanning {
              model.cancelScan()
            } else {
              await model.startScan(
                mode: model.settings.scanDeveloperFolders ? .developer : .limited)
            }
          }
        } label: {
          HStack(spacing: 6) {
            Image(systemName: model.isScanning ? "xmark.circle.fill" : "leaf.fill")
              .font(.system(size: 13, weight: .semibold))
            Text(model.isScanning ? "Cancel" : "Start Scan")
              .font(.system(.subheadline, design: .rounded).bold())
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .background(
          Capsule()
            .fill(model.isScanning ? BrandTheme.terracotta : BrandTheme.sage)
        )

        Text(model.isScanning ? "Scanning greenhouse…" : model.permissionSummary.message)
          .font(.system(size: 10, design: .rounded))
          .foregroundStyle(BrandTheme.warmGray)
          .fixedSize(horizontal: false, vertical: true)
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 12)
    }
    .frame(width: 210)
    .background(.ultraThinMaterial)
  }
}

// MARK: - Sidebar Row

private struct SidebarRow: View {
  let destination: AppModel.Destination
  let isActive: Bool
  let isHovered: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 8) {
        Image(systemName: destination.systemImage)
          .font(.system(size: 13))
          .foregroundStyle(isActive ? .white : (isHovered ? BrandTheme.bark : BrandTheme.warmGray))
          .frame(width: 20)

        Text(destination.rawValue)
          .font(.system(.subheadline, design: .rounded).weight(isActive ? .semibold : .regular))
          .foregroundStyle(isActive ? .white : (isHovered ? BrandTheme.bark : BrandTheme.warmGray))

        Spacer()
      }
      .padding(.vertical, 7)
      .padding(.horizontal, 10)
      .background(
        Capsule()
          .fill(isActive ? BrandTheme.sage : (isHovered ? BrandTheme.clay : Color.clear))
      )
    }
    .buttonStyle(.plain)
    .scaleEffect(isHovered && !isActive ? 1.02 : 1.0)
    .animation(.easeOut(duration: 0.15), value: isHovered)
  }
}
