import Foundation
import Testing

@testable import CleanScopeCore

@Suite struct StorageMapPresentationTests {
  private func result(_ id: String, _ category: SafetyCategory, size: Int64) -> ScanResult {
    var value = ScanResult.fixture(path: id, sizeBytes: size, category: category)
    value.id = id
    return value
  }

  private func leaf(_ path: String, _ size: Int64, resultId: String? = nil) -> ScanNode {
    ScanNode(path: path, name: path, sizeBytes: size, itemType: .folder, resultId: resultId)
  }

  @Test func nodeWithResultUsesItsCategory() {
    let r = result("r1", .probablyUnused, size: 100)
    let node = leaf("/a", 100, resultId: "r1")
    #expect(StorageMapPresentation.tone(for: node, results: ["r1": r]) == .category(.probablyUnused))
  }

  @Test func folderWithoutResultUsesDominantCategoryByBytes() {
    let safe = result("s", .safeToDelete, size: 300)
    let review = result("v", .probablyUnused, size: 200)
    let folder = ScanNode(
      path: "/f", name: "f", sizeBytes: 500, itemType: .folder,
      children: [leaf("/f/a", 300, resultId: "s"), leaf("/f/b", 200, resultId: "v")])
    #expect(
      StorageMapPresentation.tone(for: folder, results: ["s": safe, "v": review])
        == .category(.safeToDelete))
  }

  @Test func tiesGoToTheMoreCautiousCategory() {
    let safe = result("s", .safeToDelete, size: 100)
    let keep = result("k", .doNotBulkDelete, size: 100)
    let folder = ScanNode(
      path: "/f", name: "f", sizeBytes: 200, itemType: .folder,
      children: [leaf("/f/a", 100, resultId: "s"), leaf("/f/b", 100, resultId: "k")])
    #expect(
      StorageMapPresentation.tone(for: folder, results: ["s": safe, "k": keep])
        == .category(.doNotBulkDelete))
  }

  @Test func folderWithNoClassifiedDescendantsIsUnclassified() {
    let folder = ScanNode(
      path: "/f", name: "f", sizeBytes: 10, itemType: .folder, children: [leaf("/f/a", 10)])
    #expect(StorageMapPresentation.tone(for: folder, results: [:]) == .unclassified)
  }

  @Test func otherItemsNodeIsUnclassified() {
    let node = ScanNode(
      path: "/f#other", name: "Other items", sizeBytes: 10, itemType: .folder, resultId: "r1",
      isOtherItems: true)
    let r = result("r1", .safeToDelete, size: 10)
    #expect(StorageMapPresentation.tone(for: node, results: ["r1": r]) == .unclassified)
  }

  @Test func freeTileOnlyAtVolumeRoot() {
    let node = ScanNode(
      path: "/", name: "Macintosh HD", sizeBytes: 1_000, itemType: .folder,
      children: [leaf("/a", 600), leaf("/b", 400)])
    let atRoot = StorageMapPresentation.items(for: node, isVolumeRoot: true, freeBytes: 500)
    #expect(atRoot.contains { $0.id == "__free__" && $0.size == 500 })
    #expect(atRoot.count == 3)
    let elsewhere = StorageMapPresentation.items(for: node, isVolumeRoot: false, freeBytes: 500)
    #expect(elsewhere.contains { $0.id == "__free__" } == false)
    let none = StorageMapPresentation.items(for: node, isVolumeRoot: true, freeBytes: 0)
    #expect(none.contains { $0.id == "__free__" } == false)
    #expect(none.map(\.id) == ["/a", "/b"])
  }
}
