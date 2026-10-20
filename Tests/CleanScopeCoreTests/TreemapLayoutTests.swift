import CoreGraphics
import Foundation
import Testing

@testable import CleanScopeCore

@Suite struct TreemapLayoutTests {
  let rect = CGRect(x: 0, y: 0, width: 600, height: 400)
  let items: [(id: String, size: Int64)] = [
    ("a", 6_000), ("b", 6_000), ("c", 4_000), ("d", 3_000), ("e", 2_000), ("f", 2_000),
    ("g", 1_000),
  ]

  @Test func squarifyPreservesArea() {
    let laid = TreemapLayout.squarify(items: items, in: rect)
    let area = laid.reduce(0.0) { $0 + Double($1.rect.width * $1.rect.height) }
    #expect(laid.count == items.count)
    #expect(abs(area - Double(rect.width * rect.height)) / Double(rect.width * rect.height) < 0.005)
  }

  @Test func squarifyHasNoOverlapsOrNegativeRects() {
    let laid = TreemapLayout.squarify(items: items, in: rect)
    for item in laid {
      #expect(item.rect.width >= 0 && item.rect.height >= 0)
      #expect(rect.insetBy(dx: -0.01, dy: -0.01).contains(item.rect))
    }
    for (i, lhs) in laid.enumerated() {
      for rhs in laid[(i + 1)...] {
        let overlap = lhs.rect.intersection(rhs.rect)
        #expect(overlap.isNull || overlap.width * overlap.height < 0.01)
      }
    }
  }

  @Test func squarifyIsProportional() {
    let laid = TreemapLayout.squarify(items: [("a", 3), ("b", 1)], in: rect)
    let a = try! #require(laid.first { $0.id == "a" })
    #expect(abs(Double(a.rect.width * a.rect.height) - 180_000) < 1)
  }

  @Test func squarifyIgnoresZeroSizesAndEmptyRect() {
    #expect(TreemapLayout.squarify(items: [("a", 0)], in: rect).isEmpty)
    #expect(TreemapLayout.squarify(items: items, in: .zero).isEmpty)
  }

  @Test func otherItemsAggregatesSmallChildren() {
    let node = ScanNode(
      path: "/r", name: "r", sizeBytes: 1_000, itemType: .folder,
      children: [
        ScanNode(path: "/r/a", name: "a", sizeBytes: 900, itemType: .folder),
        ScanNode(path: "/r/b", name: "b", sizeBytes: 50, itemType: .folder),
        ScanNode(path: "/r/c", name: "c", sizeBytes: 5, itemType: .file),
        ScanNode(path: "/r/d", name: "d", sizeBytes: 5, itemType: .file),
      ],
      otherBytes: 40)
    let shown = node.displayChildren()
    #expect(shown.map(\.name) == ["a", "b", "Other items"])
    #expect(shown.last?.sizeBytes == 50)
    #expect(shown.last?.isOtherItems == true)
  }

  @Test func nodeLookupDescendsFromSyntheticRoot() {
    let leaf = ScanNode(path: "/a/b", name: "b", sizeBytes: 1, itemType: .folder)
    let root = ScanNode(
      path: "scan://locations", name: "Scanned locations", sizeBytes: 1, itemType: .folder,
      children: [ScanNode(path: "/a", name: "a", sizeBytes: 1, itemType: .folder, children: [leaf])])
    #expect(root.node(at: "/a/b") == leaf)
    #expect(root.node(at: "/ab") == nil)
  }
}
