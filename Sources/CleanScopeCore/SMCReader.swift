import Foundation
import IOKit

/// Experimental CPU temperature through the AppleSMC user client. Keys differ between chips and
/// macOS releases, so every failure returns nil and the UI hides the row. Kept self-contained so
/// it can be removed if it breaks.
public enum SMCReader {
  /// Intel keys first, then Apple Silicon performance-core keys.
  static let temperatureKeys = [
    "TC0P", "TC0D", "TC0E", "TC0F", "Tp09", "Tp0T", "Tp01", "Tp05", "Tp0D", "Tp0H", "Tp0L",
    "Tp0P", "Tp0X", "Tp0b", "Tp0f", "Tp0j",
  ]

  public static func cpuTemperature() -> Double? {
    let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
    guard service != 0 else { return nil }
    defer { IOObjectRelease(service) }
    var connection: io_connect_t = 0
    guard IOServiceOpen(service, mach_task_self_, 0, &connection) == KERN_SUCCESS else {
      return nil
    }
    defer { IOServiceClose(connection) }

    let readings = temperatureKeys.compactMap { read(key: $0, connection: connection) }
      .filter { (10...115).contains($0) }
    guard !readings.isEmpty else { return nil }
    return readings.reduce(0, +) / Double(readings.count)
  }

  // MARK: Decoding

  static func fourCC(_ key: String) -> UInt32 {
    key.utf8.prefix(4).reduce(0) { ($0 << 8) | UInt32($1) }
  }

  static func decode(type: UInt32, bytes: [UInt8]) -> Double? {
    switch type {
    case fourCC("sp78"):
      guard bytes.count >= 2 else { return nil }
      return Double(Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))) / 256
    case fourCC("flt "):
      guard bytes.count >= 4 else { return nil }
      let bits = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
      return Double(Float(bitPattern: bits))
    default:
      return nil
    }
  }

  // MARK: User client

  private struct Version {
    var major: UInt8 = 0, minor: UInt8 = 0, build: UInt8 = 0, reserved: UInt8 = 0
    var release: UInt16 = 0
  }

  private struct PLimitData {
    var version: UInt16 = 0, length: UInt16 = 0
    var cpuPLimit: UInt32 = 0, gpuPLimit: UInt32 = 0, memPLimit: UInt32 = 0
  }

  private struct KeyInfo {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
  }

  private struct Param {
    var key: UInt32 = 0
    var version = Version()
    var pLimitData = PLimitData()
    var keyInfo = KeyInfo()
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: (
      UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
      UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
      UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
    ) = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
  }

  private static let handleEvent: UInt32 = 2
  private static let readKeyCommand: UInt8 = 5
  private static let keyInfoCommand: UInt8 = 9

  private static func call(_ input: inout Param, connection: io_connect_t) -> Param? {
    var output = Param()
    var outputSize = MemoryLayout<Param>.stride
    let status = IOConnectCallStructMethod(
      connection, handleEvent, &input, MemoryLayout<Param>.stride, &output, &outputSize)
    guard status == KERN_SUCCESS, output.result == 0 else { return nil }
    return output
  }

  private static func read(key: String, connection: io_connect_t) -> Double? {
    var info = Param()
    info.key = fourCC(key)
    info.data8 = keyInfoCommand
    guard let infoOutput = call(&info, connection: connection) else { return nil }

    var request = Param()
    request.key = fourCC(key)
    request.keyInfo.dataSize = infoOutput.keyInfo.dataSize
    request.data8 = readKeyCommand
    guard let output = call(&request, connection: connection) else { return nil }
    let size = Int(min(infoOutput.keyInfo.dataSize, 32))
    let bytes = withUnsafeBytes(of: output.bytes) { Array($0.prefix(size)) }
    return decode(type: infoOutput.keyInfo.dataType, bytes: bytes)
  }
}
