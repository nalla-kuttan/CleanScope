import AppKit
import CleanScopeCore
import SwiftUI
import UniformTypeIdentifiers

/// Finder-style icons looked up by type, not by path, so table rows never touch the disk.
@MainActor
enum FileIcon {
  private static var cache: [String: NSImage] = [:]

  static func image(for result: ScanResult) -> NSImage {
    let type: UTType
    switch result.itemType {
    case .folder: type = .folder
    case .symlink: type = .symbolicLink
    case .file:
      type = result.fileExtension.flatMap { UTType(filenameExtension: $0) } ?? .data
    }
    if let cached = cache[type.identifier] { return cached }
    let image = NSWorkspace.shared.icon(for: type)
    cache[type.identifier] = image
    return image
  }
}
