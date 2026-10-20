import CleanScopeCore
import SwiftUI

struct SidebarView: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    List(selection: $model.destination) {
      ForEach(AppModel.Destination.sections, id: \.title) { section in
        Section(section.title) {
          ForEach(section.destinations) { destination in
            row(for: destination)
              .tag(destination)
          }
        }
      }
    }
    .listStyle(.sidebar)
    .safeAreaInset(edge: .top, spacing: 0) {
      HStack(spacing: 8) {
        BrandMarkView(size: 26, isDecorative: true)
        Text("CleanScope")
          .font(.headline)
          .foregroundStyle(BrandTheme.textPrimary)
        Spacer()
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 8)
      .accessibilityElement(children: .combine)
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      scanFooter
    }
  }

  @ViewBuilder
  private func row(for destination: AppModel.Destination) -> some View {
    let label = Label(destination.title, systemImage: destination.systemImage)
    if model.hasScanned || model.isScanning, let count = model.counts[destination] {
      label.badge(count)
    } else {
      label
    }
  }

  private var scanFooter: some View {
    VStack(alignment: .leading, spacing: 8) {
      if model.isScanning {
        Button {
          model.cancelScan()
        } label: {
          Label("Cancel Scan", systemImage: "xmark.circle")
            .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        .buttonStyle(.bordered)
      } else {
        Button {
          Task { await model.startScan() }
        } label: {
          Label(model.hasScanned ? "Scan Again" : "Start Scan", systemImage: "leaf.fill")
            .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        .buttonStyle(.borderedProminent)
        .tint(BrandTheme.accent)
      }

      HStack(spacing: 6) {
        if model.isScanning {
          ProgressView().controlSize(.small)
        }
        Text(status)
          .font(.caption)
          .foregroundStyle(BrandTheme.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(12)
  }

  private var status: String {
    if model.isScanning {
      return "Scanning… \(CountPhrase.make(model.summary.totalResults, "item")) found"
    }
    guard let completedAt = model.session?.completedAt else { return "Not scanned yet" }
    return "Last scan \(completedAt.formatted(.relative(presentation: .named)))"
  }
}
