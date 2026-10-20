import Foundation

/// How a tile on the storage map is coloured.
public enum MapTone: Equatable, Sendable {
  case category(SafetyCategory)
  case unclassified
  case free
}

/// Pure presentation rules for the storage map: tile colour and the items fed to the layout.
public enum StorageMapPresentation {
  /// Id of the free-space tile at a volume root.
  public static let freeItemId = "__free__"

  /// The node's own category when it has a result, otherwise the category covering the most
  /// bytes among its descendants (ties go to the more cautious category).
  public static func tone(for node: ScanNode, results: [String: ScanResult]) -> MapTone {
    if node.isOtherItems { return .unclassified }
    if let id = node.resultId, let result = results[id] { return .category(result.category) }

    var bytesByCategory: [SafetyCategory: Int64] = [:]
    accumulate(node.children, results: results, into: &bytesByCategory)
    let dominant = bytesByCategory.max { lhs, rhs in
      lhs.value != rhs.value ? lhs.value < rhs.value : lhs.key < rhs.key
    }
    return dominant.map { .category($0.key) } ?? .unclassified
  }

  /// Layout items for the node's displayed children, plus a free-space tile at a volume root.
  public static func items(
    for node: ScanNode,
    isVolumeRoot: Bool,
    freeBytes: Int64
  ) -> [(id: String, size: Int64)] {
    var items = node.displayChildren().map { (id: $0.id, size: $0.sizeBytes) }
    if isVolumeRoot, freeBytes > 0 { items.append((id: freeItemId, size: freeBytes)) }
    return items.filter { $0.size > 0 }
  }

  /// A node with a result already counts its children, so the walk stops there.
  private static func accumulate(
    _ nodes: [ScanNode],
    results: [String: ScanResult],
    into totals: inout [SafetyCategory: Int64]
  ) {
    for node in nodes {
      if let id = node.resultId, let result = results[id] {
        totals[result.category, default: 0] += node.sizeBytes
      } else {
        accumulate(node.children, results: results, into: &totals)
      }
    }
  }
}
