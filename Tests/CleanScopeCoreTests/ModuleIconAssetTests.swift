import Foundation
import ImageIO
import Testing

@testable import CleanScopeCore

@Suite struct ModuleIconAssetTests {
  private static let iconsDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("../../Sources/CleanScopeApp/Resources/Icons")
    .standardizedFileURL

  private static func pixelWidth(of url: URL) -> Int? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    else { return nil }
    return properties[kCGImagePropertyPixelWidth] as? Int
  }

  @Test func everyIconHasStillsAndHoverFrames() {
    let fileManager = FileManager.default
    for key in ModuleIconKey.allCases {
      for (scale, width) in [(1, 64), (2, 128), (3, 192)] {
        let url = Self.iconsDirectory.appendingPathComponent("\(key.rawValue)@\(scale)x.png")
        #expect(fileManager.fileExists(atPath: url.path), "missing \(url.lastPathComponent)")
        #expect(
          Self.pixelWidth(of: url) == width, "\(url.lastPathComponent) should be \(width) px wide")
      }
      for frame in 0..<18 {
        let name = String(format: "%@-hover-%02d.png", key.rawValue, frame)
        let url = Self.iconsDirectory.appendingPathComponent(name)
        #expect(fileManager.fileExists(atPath: url.path), "missing \(name)")
      }
    }
  }
}
