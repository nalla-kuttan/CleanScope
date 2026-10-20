import Darwin
import Foundation

/// BSD file flags read with `lstat`, for cloud placeholders and SIP-protected items.
public struct FileFlags: Equatable, Sendable {
  /// `SF_DATALESS`: a cloud placeholder whose content is not on disk.
  public static let datalessMask: UInt32 = 0x4000_0000
  /// `SF_RESTRICTED`: protected by System Integrity Protection.
  public static let restrictedMask: UInt32 = 0x0008_0000

  public var isDataless: Bool
  public var isRestricted: Bool

  public init(rawFlags: UInt32) {
    isDataless = rawFlags & Self.datalessMask != 0
    isRestricted = rawFlags & Self.restrictedMask != 0
  }

  public static func read(path: String) -> FileFlags? {
    var info = stat()
    guard lstat(path, &info) == 0 else { return nil }
    return FileFlags(rawFlags: info.st_flags)
  }
}
