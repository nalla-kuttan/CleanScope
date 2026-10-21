import AppKit
import CleanScopeCore
import SwiftUI

struct ContentView: View {
  @EnvironmentObject private var model: AppModel
  @EnvironmentObject private var motion: MotionPolicy
  @Environment(\.flightCenter) private var flights

  var body: some View {
    NavigationSplitView {
      SidebarView()
        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 300)
    } detail: {
      detailPane
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BrandTheme.surface)
        .overlay(alignment: .bottom) {
          if let undo = model.exclusionUndo {
            ExclusionUndoBar(undo: undo)
              .padding(16)
              .transition(motion.allowsTransitions ? .move(edge: .bottom).combined(with: .opacity) : .opacity)
          }
        }
        .animation(motion.animation(), value: model.exclusionUndo?.id)
    }
    .background(WindowAccessor { motion.attach(to: $0) })
    .onChange(of: model.selection) { old, new in flyNewSelections(old: old, new: new) }
    #if DEBUG
      .task { await DebugSnapshot.run(model: model) }
    #endif
    .alert(
      model.alert?.title ?? "",
      isPresented: Binding(get: { model.alert != nil }, set: { if !$0 { model.alert = nil } }),
      presenting: model.alert
    ) { _ in
      Button("OK", role: .cancel) {}
    } message: { alert in
      Text(alert.message)
    }
  }

  /// One chip flies into the basket for whatever was just selected; a deselection plays none.
  private func flyNewSelections(old: Set<String>, new: Set<String>) {
    let added = new.subtracting(old)
    guard !added.isEmpty, let flights, flights.hasBasket else { return }
    let items = model.streamedResults.filter { added.contains($0.id) }
    flights.fly(newlySelected: items, allowsMotion: motion.allowsTransitions)
  }

  @ViewBuilder
  private var detailPane: some View {
    switch model.destination ?? .dashboard {
    case .dashboard:
      DashboardView()
    case .storageMap:
      StorageMapView()
    case .maintenance:
      MaintenanceView()
    case .loginItems:
      LoginItemsView()
    case .backgroundItems:
      BackgroundItemsView()
    case .memory:
      MemoryView()
    case .protection:
      ProtectionView()
    case .privacy:
      PrivacyView()
    case .lastCleanup:
      CleanupReportView()
    case let destination:
      ResultsView(destination: destination)
        .id(destination)
    }
  }
}

private struct ExclusionUndoBar: View {
  @EnvironmentObject private var model: AppModel
  var undo: AppModel.ExclusionUndo

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: "eye.slash")
        .foregroundStyle(BrandTheme.textSecondary)
        .accessibilityHidden(true)
      Text("“\(undo.name)” is excluded from results and cleanup.")
        .foregroundStyle(BrandTheme.textPrimary)
        .lineLimit(2)
      Spacer(minLength: 8)
      Button("Undo") { model.undoExclusion(undo) }
      Button {
        model.exclusionUndo = nil
      } label: {
        Image(systemName: "xmark")
      }
      .buttonStyle(.borderless)
      .accessibilityLabel("Dismiss")
      .help("Dismiss")
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .frame(maxWidth: 560)
    .background(
      RoundedRectangle(cornerRadius: BrandTheme.radius, style: .continuous)
        .fill(BrandTheme.surfaceRaised)
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
    )
    .accessibilityElement(children: .contain)
  }
}

/// Hands the hosting `NSWindow` to `onWindow` once the view is in a window.
/// Reports the hosting window each time the view joins one, including a reopened window.
private struct WindowAccessor: NSViewRepresentable {
  var onWindow: (NSWindow) -> Void

  func makeNSView(context: Context) -> WindowReportingView {
    let view = WindowReportingView()
    view.onWindow = onWindow
    return view
  }

  func updateNSView(_ nsView: WindowReportingView, context: Context) {
    nsView.onWindow = onWindow
  }
}

private final class WindowReportingView: NSView {
  var onWindow: ((NSWindow) -> Void)?

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    if let window { onWindow?(window) }
  }
}
