import Foundation

/// What the toolbar basket shows when items are selected.
public enum BasketPresentation {
  /// The chips that fly into the basket for `newlySelected`: one for a single new selection,
  /// and still just one (the first) for a bulk select, so selecting 2,709 items plays a single
  /// flight. A deselection selects nothing new, so it plays none.
  public static func flights(newlySelected: [ScanResult]) -> [ScanResult] {
    newlySelected.first.map { [$0] } ?? []
  }

  /// The text on a flying chip: the item's name, with "+N" when the flight stands for more.
  public static func chipLabel(for flight: ScanResult, totalNewlySelected: Int) -> String {
    totalNewlySelected > 1
      ? "\(flight.name) +\((totalNewlySelected - 1).formatted())" : flight.name
  }
}
