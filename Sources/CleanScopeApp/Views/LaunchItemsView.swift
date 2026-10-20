import AppKit
import CleanScopeCore
import SwiftUI

/// Apps that open when you log in. Older login items are read through System Events, which
/// asks for permission the first time; newer ones are managed in System Settings.
struct LoginItemsView: View {
  @State private var names: [String]?
  @State private var message: String?
  @State private var pendingRemoval: String?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        PageHeader(
          title: "Login Items",
          subtitle: "Manage the apps that open when you log in.")

        HStack(spacing: 10) {
          Button("Show Login Items") { load() }
            .buttonStyle(.borderedProminent)
            .tint(BrandTheme.accent)
          Button("Open Login Items Settings") {
            NSWorkspace.shared.open(LegacyLoginItems.settingsURL)
          }
        }
        Text(
          "CleanScope reads login items through System Events. macOS asks for permission the first time. Apps that register themselves the newer way are listed in System Settings."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

        if let message {
          Label(message, systemImage: "info.circle").foregroundStyle(.secondary)
        }

        if let names {
          if names.isEmpty {
            EmptyStateView(
              title: "No login items", systemImage: "checkmark.seal",
              message: "No apps are set to open when you log in this way.")
              .frame(minHeight: 200)
          } else {
            VStack(spacing: 6) {
              ForEach(names, id: \.self) { name in
                HStack {
                  Image(systemName: "app")
                  Text(name)
                  Spacer()
                  Button("Remove…") { pendingRemoval = name }
                }
                .padding(10)
                .background(BrandTheme.surfaceRaised)
                .clipShape(RoundedRectangle(cornerRadius: 10))
              }
            }
          }
        }
      }
      .padding(24)
      .frame(maxWidth: 980, alignment: .leading)
    }
    .background(BrandTheme.surface)
    .alert(
      "Stop opening \(pendingRemoval ?? "") at login?",
      isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } })
    ) {
      Button("Cancel", role: .cancel) {}
      Button("Remove") {
        if let name = pendingRemoval { remove(name) }
      }
    } message: {
      Text("The app stays installed. You can add it back in System Settings.")
    }
  }

  private func run(_ source: String) -> (String?, String?) {
    #if DEBUG
      // Snapshot runs must never raise the macOS Automation permission prompt.
      if DebugSnapshot.isActive { return (nil, "Skipped during a snapshot run.") }
    #endif
    var error: NSDictionary?
    let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
    if let error {
      return (nil, error[NSAppleScript.errorMessage] as? String ?? "System Events did not respond.")
    }
    return (result?.stringValue ?? "", nil)
  }

  private func load() {
    let (output, error) = run(LegacyLoginItems.listScript)
    if let error {
      message = "CleanScope couldn't read login items: \(error)"
      return
    }
    names = LegacyLoginItems.parseNames(output ?? "")
    message = nil
  }

  private func remove(_ name: String) {
    let (_, error) = run(LegacyLoginItems.deleteScript(name: name))
    message = error.map { "\(name) could not be removed: \($0)" } ?? "\(name) won't open at login."
    load()
  }
}

/// Launch agents and daemons installed by other apps.
struct BackgroundItemsView: View {
  @State private var items: [LaunchItem] = []
  @State private var isLoading = false
  @State private var message: String?
  @State private var pendingRemoval: LaunchItem?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        HStack(alignment: .bottom) {
          PageHeader(
            title: "Background Items",
            subtitle: "Manage the list of processes and applications that run in the background.")
          Spacer()
          if isLoading { ProgressView().controlSize(.small) }
          Button {
            Task { await reload() }
          } label: {
            Label("Refresh", systemImage: "arrow.clockwise")
          }
        }

        if let message {
          Label(message, systemImage: "info.circle").foregroundStyle(.secondary)
        }

        if items.isEmpty && !isLoading {
          EmptyStateView(
            title: "No background items", systemImage: "checkmark.seal",
            message: "No third-party launch agents or daemons are installed.")
            .frame(minHeight: 220)
        }

        ForEach(items) { item in
          row(item)
        }
      }
      .padding(24)
      .frame(maxWidth: 980, alignment: .leading)
    }
    .background(BrandTheme.surface)
    .task { await reload() }
    .alert(
      "Remove \(pendingRemoval?.displayName ?? "")?",
      isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } })
    ) {
      Button("Cancel", role: .cancel) {}
      Button("Move to Trash", role: .destructive) {
        if let item = pendingRemoval { Task { await remove(item) } }
      }
    } message: {
      Text(
        "CleanScope stops \(pendingRemoval?.label ?? "this item") and moves its launch file to the Trash. The app that installed it may add it back."
      )
    }
  }

  private func row(_ item: LaunchItem) -> some View {
    HStack(alignment: .top, spacing: 12) {
      icon(for: item)
        .frame(width: 32, height: 32)
      VStack(alignment: .leading, spacing: 3) {
        HStack(spacing: 6) {
          Text(item.displayName).font(.headline).foregroundStyle(BrandTheme.textPrimary)
          if item.isBroken {
            Label("Broken", systemImage: "exclamationmark.triangle")
              .font(.caption.weight(.semibold))
              .foregroundStyle(BrandTheme.destructive)
              .help("The program this item starts no longer exists.")
          }
        }
        Text(item.label).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
        HStack(spacing: 10) {
          Text(item.state.title)
          Text(item.scope.title)
          Text(item.teamID.map { "Team ID \($0)" } ?? "Unsigned or unknown signer")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
      }
      Spacer()
      Menu {
        Button("Disable") { Task { await disable(item) } }
          .disabled(item.state == .disabled)
        Button("Remove…") { pendingRemoval = item }
        Divider()
        Button("Show in Finder") {
          NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.plistPath)])
        }
      } label: {
        Text("Actions")
      }
      .fixedSize()
    }
    .padding(12)
    .background(BrandTheme.surfaceRaised)
    .clipShape(RoundedRectangle(cornerRadius: BrandTheme.radius))
    .accessibilityElement(children: .combine)
  }

  private func icon(for item: LaunchItem) -> some View {
    Group {
      if let app = item.owningAppPath, FileManager.default.fileExists(atPath: app) {
        Image(nsImage: NSWorkspace.shared.icon(forFile: app)).resizable()
      } else {
        Image(systemName: "gearshape").font(.title2).foregroundStyle(BrandTheme.textSecondary)
      }
    }
    .accessibilityHidden(true)
  }

  private func reload() async {
    isLoading = true
    let status = await LaunchItemService.currentStatus()
    items = await Task.detached {
      LaunchItemService().items(in: LaunchItemService.standardDirectories(), status: status)
    }.value
    isLoading = false
  }

  private func disable(_ item: LaunchItem) async {
    do {
      if item.requiresAdmin {
        _ = try await AppleScriptPrivilegedRunner().run(command: LaunchItemCommands.adminDisable(item))
      } else {
        let runner = ProcessRunner()
        let bootout = LaunchItemCommands.bootout(item, uid: getuid())
        _ = try? await runner.run(bootout[0], Array(bootout.dropFirst()), timeout: 10)
        let disable = LaunchItemCommands.disable(item, uid: getuid())
        _ = try await runner.run(disable[0], Array(disable.dropFirst()), timeout: 10)
      }
      message = "\(item.displayName) is disabled."
    } catch PrivilegedRunnerError.cancelled {
      message = "You didn't authorize this change."
    } catch {
      message = "\(item.displayName) could not be disabled."
    }
    await reload()
  }

  private func remove(_ item: LaunchItem) async {
    do {
      if item.requiresAdmin {
        _ = try await AppleScriptPrivilegedRunner().run(command: LaunchItemCommands.adminRemove(item))
      } else {
        let bootout = LaunchItemCommands.bootout(item, uid: getuid())
        _ = try? await ProcessRunner().run(bootout[0], Array(bootout.dropFirst()), timeout: 10)
        try FileManager.default.trashItem(
          at: URL(fileURLWithPath: item.plistPath), resultingItemURL: nil)
      }
      message = "\(item.displayName) was moved to the Trash."
    } catch PrivilegedRunnerError.cancelled {
      message = "You didn't authorize this change."
    } catch {
      message = "\(item.displayName) could not be removed."
    }
    await reload()
  }
}

/// Title and subtitle used at the top of the newer destinations.
struct PageHeader: View {
  var title: String
  var subtitle: String

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(title)
        .font(.system(size: 26, weight: .bold, design: .rounded))
        .foregroundStyle(BrandTheme.textPrimary)
      Text(subtitle)
        .font(.system(.subheadline, design: .rounded))
        .foregroundStyle(BrandTheme.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}
