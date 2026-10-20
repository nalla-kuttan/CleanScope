import CoreGraphics
import Foundation

/// Squarified treemap layout (Bruls, Huizing and van Wijk), as a pure function.
public enum TreemapLayout {
  public static func squarify(
    items: [(id: String, size: Int64)],
    in rect: CGRect
  ) -> [(id: String, rect: CGRect)] {
    let positive = items.filter { $0.size > 0 }.sorted { $0.size > $1.size }
    let total = positive.reduce(0.0) { $0 + Double($1.size) }
    guard total > 0, rect.width > 0, rect.height > 0 else { return [] }

    let scale = Double(rect.width * rect.height) / total
    var remaining = positive.map { (id: $0.id, area: Double($0.size) * scale) }
    var free = rect
    var output: [(id: String, rect: CGRect)] = []

    while !remaining.isEmpty {
      let side = Double(min(free.width, free.height))
      var row: [(id: String, area: Double)] = [remaining.removeFirst()]
      while let next = remaining.first,
        worst(row + [next], side: side) <= worst(row, side: side)
      {
        row.append(remaining.removeFirst())
      }
      free = place(row, in: free, output: &output)
    }
    return output
  }

  /// The largest aspect ratio in a row laid along a side of length `side`.
  private static func worst(_ row: [(id: String, area: Double)], side: Double) -> Double {
    let sum = row.reduce(0) { $0 + $1.area }
    guard sum > 0, side > 0 else { return .infinity }
    let largest = row.map(\.area).max() ?? 0
    let smallest = row.map(\.area).min() ?? 0
    let sideSquared = side * side
    return max(sideSquared * largest / (sum * sum), (sum * sum) / (sideSquared * smallest))
  }

  /// Lays a row along the shorter side of `rect` and returns the space left over.
  private static func place(
    _ row: [(id: String, area: Double)],
    in rect: CGRect,
    output: inout [(id: String, rect: CGRect)]
  ) -> CGRect {
    let sum = row.reduce(0) { $0 + $1.area }
    if rect.width >= rect.height {
      let width = CGFloat(sum / Double(rect.height))
      var y = rect.minY
      for item in row {
        let height = CGFloat(item.area) / width
        output.append((item.id, CGRect(x: rect.minX, y: y, width: width, height: height)))
        y += height
      }
      return CGRect(
        x: rect.minX + width, y: rect.minY, width: max(0, rect.width - width),
        height: rect.height)
    } else {
      let height = CGFloat(sum / Double(rect.width))
      var x = rect.minX
      for item in row {
        let width = CGFloat(item.area) / height
        output.append((item.id, CGRect(x: x, y: rect.minY, width: width, height: height)))
        x += width
      }
      return CGRect(
        x: rect.minX, y: rect.minY + height, width: rect.width,
        height: max(0, rect.height - height))
    }
  }
}
