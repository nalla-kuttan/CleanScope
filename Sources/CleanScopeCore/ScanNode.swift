import Foundation

/// One folder or file in the storage tree built during a scan. Small entries are folded into
/// `otherBytes` so the tree stays small enough to keep in memory.
public struct ScanNode: Identifiable, Equatable, Sendable {
  public var id: String { path }
  public var path: String
  public var name: String
  public var sizeBytes: Int64
  public var itemType: ItemType
  public var children: [ScanNode]
  public var otherBytes: Int64
  public var resultId: String?
  public var lastModified: Date?
  public var isOtherItems: Bool

  public init(
    path: String,
    name: String,
    sizeBytes: Int64,
    itemType: ItemType,
    children: [ScanNode] = [],
    otherBytes: Int64 = 0,
    resultId: String? = nil,
    lastModified: Date? = nil,
    isOtherItems: Bool = false
  ) {
    self.path = path
    self.name = name
    self.sizeBytes = sizeBytes
    self.itemType = itemType
    self.children = children
    self.otherBytes = otherBytes
    self.resultId = resultId
    self.lastModified = lastModified
    self.isOtherItems = isOtherItems
  }

  /// Children at or above `minimumFraction` of this node, largest first, followed by one
  /// "Other items" node holding everything smaller plus `otherBytes`.
  public func displayChildren(minimumFraction: Double = 0.01) -> [ScanNode] {
    let cutoff = Int64(Double(sizeBytes) * minimumFraction)
    let sorted = children.sorted { $0.sizeBytes > $1.sizeBytes }
    let shown = sorted.filter { $0.sizeBytes >= cutoff && $0.sizeBytes > 0 }
    let hiddenBytes =
      sorted.filter { $0.sizeBytes < cutoff || $0.sizeBytes == 0 }.reduce(0) { $0 + $1.sizeBytes }
      + otherBytes
    guard hiddenBytes > 0 else { return shown }
    return shown + [
      ScanNode(
        path: path + "#other", name: "Other items", sizeBytes: hiddenBytes, itemType: .folder,
        isOtherItems: true)
    ]
  }

  /// The node at `path` in this subtree, if present.
  public func node(at path: String) -> ScanNode? {
    if self.path == path { return self }
    guard path.hasPrefix(self.path) else { return nil }
    for child in children {
      if let found = child.node(at: path) { return found }
    }
    return nil
  }
}
