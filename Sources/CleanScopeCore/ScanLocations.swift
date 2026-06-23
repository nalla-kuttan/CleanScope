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
        "\(home)/Library/Application Support",
        "\(home)/Desktop",
        "\(home)/Documents",
      ]

    switch mode {
    case .limited: return limited
    case .developer: return developer
    case .full: return full
    }
  }
}
