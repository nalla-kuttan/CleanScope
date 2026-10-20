import Foundation
import Security

public struct SignerInfo: Equatable, Sendable {
  public var teamID: String?
  public var isApple: Bool

  public init(teamID: String?, isApple: Bool) {
    self.teamID = teamID
    self.isApple = isApple
  }
}

public enum CodeSigning {
  /// Team ID and whether Apple signed the code at `path`, or nil when it is unsigned or missing.
  public static func signer(path: String) -> SignerInfo? {
    var staticCode: SecStaticCode?
    guard
      SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &staticCode)
        == errSecSuccess,
      let code = staticCode
    else { return nil }

    var information: CFDictionary?
    guard
      SecCodeCopySigningInformation(
        code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
      let info = information as? [String: Any]
    else { return nil }
    let teamID = info[kSecCodeInfoTeamIdentifier as String] as? String

    var requirement: SecRequirement?
    var isApple = false
    if SecRequirementCreateWithString("anchor apple" as CFString, [], &requirement)
      == errSecSuccess, let requirement
    {
      isApple = SecStaticCodeCheckValidity(code, [], requirement) == errSecSuccess
    }
    if teamID == nil && !isApple && info[kSecCodeInfoIdentifier as String] == nil { return nil }
    return SignerInfo(teamID: teamID, isApple: isApple)
  }
}
