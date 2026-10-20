import Foundation

public enum ScanLocations {
  public static func recommended(mode: ScanMode, homeDirectory: String = NSHomeDirectory())
    -> [String]
  {
    let home = URL(fileURLWithPath: homeDirectory).standardizedFileURL.path
    let limited = [
      "\(home)/Library/Caches",
      "\(home)/Library/Logs",
      "\(home)/Downloads",
      "\(home)/.Trash",
      "/tmp",
    ]
    let developer =
      limited + [
        "\(home)/Library/Developer/Xcode/DerivedData",
        "\(home)/Library/Developer/CoreSimulator",
        "\(home)/.npm",
        "\(home)/.yarn",
        "\(home)/.pnpm-store",
        "\(home)/.gradle",
        "\(home)/.m2",
        "\(home)/.docker",
        "\(home)/.android",
        "\(home)/.pub-cache",
        "\(home)/.cargo",
      ]
    let full =
      developer + [
        "/Applications",
        "/Library",
        "/Users/Shared",
        "/private/var/folders",
        "/private/var/log",
        "/Library/Logs",
        "\(home)/Library/Logs/DiagnosticReports",
        "/Library/Logs/DiagnosticReports",
        "\(home)/Library/Application Support",
        "\(home)/Desktop",
        "\(home)/Documents",
      ]

    switch mode {
    case .limited: return limited
    case .developer:
      return removingNestedRoots(developer + containerCacheRoots(homeDirectory: home))
    case .full:
      return removingNestedRoots(full + containerCacheRoots(homeDirectory: home))
    }
  }

  /// Drops duplicate roots and roots inside an earlier root, so nothing is scanned twice.
  static func removingNestedRoots(_ roots: [String]) -> [String] {
    var kept: [String] = []
    for root in roots where !kept.contains(where: { root == $0 || root.hasPrefix($0 + "/") }) {
      kept.removeAll { $0.hasPrefix(root + "/") }
      kept.append(root)
    }
    return kept
  }

  /// Each sandboxed app's `Data/Library/Caches` folder that exists.
  public static func containerCacheRoots(homeDirectory: String = NSHomeDirectory()) -> [String] {
    let containers = URL(fileURLWithPath: homeDirectory).standardizedFileURL
      .appendingPathComponent("Library/Containers")
    let entries =
      (try? FileManager.default.contentsOfDirectory(
        at: containers, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
    return
      entries
      .map { $0.appendingPathComponent("Data/Library/Caches").standardizedFileURL.path }
      .filter { FileManager.default.fileExists(atPath: $0) }
      .sorted()
  }

  /// The bundle identifier of a container, read from its metadata when the folder is a UUID.
  public static func containerBundleIdentifier(containerURL: URL) -> String {
    let metadata = containerURL.appendingPathComponent(
      ".com.apple.containermanagerd.metadata.plist")
    if let data = try? Data(contentsOf: metadata),
      let plist = try? PropertyListSerialization.propertyList(from: data, format: nil)
        as? [String: Any],
      let identifier = plist["MCMMetadataIdentifier"] as? String, !identifier.isEmpty
    {
      return identifier
    }
    return containerURL.lastPathComponent
  }
}
