// Signs CleanScope rule releases.
//
//   swift script/sign_rules.swift keygen <private-key-file>
//       Writes a new Ed25519 private key (base64) and prints the public key to embed in
//       RuleUpdateConfiguration.publicKey.
//
//   swift script/sign_rules.swift sign <private-key-file> <version> <min-app-version> \
//       <rules-url> <malware-url> <classification.json> <malware.json>
//       Prints a signed manifest.json.
//
// The payload must stay identical to RuleManifest.signingPayload() in
// Sources/CleanScopeCore/RuleUpdates.swift: sorted-key JSON of every field except the signature.
import CryptoKit
import Foundation

struct Payload: Encodable {
  var version: Int
  var minAppVersion: String
  var rules: URL
  var malware: URL
  var rulesSHA256: String
  var malwareSHA256: String
}

struct Manifest: Encodable {
  var version: Int
  var minAppVersion: String
  var rules: URL
  var malware: URL
  var rulesSHA256: String
  var malwareSHA256: String
  var signature: String
}

func sha256(_ data: Data) -> String {
  SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data((message + "\n").utf8))
  exit(1)
}

let args = CommandLine.arguments
guard args.count >= 3 else { fail("usage: sign_rules.swift keygen|sign …") }

switch args[1] {
case "keygen":
  let key = Curve25519.Signing.PrivateKey()
  let path = args[2]
  guard !FileManager.default.fileExists(atPath: path) else { fail("\(path) already exists") }
  try key.rawRepresentation.base64EncodedString().write(toFile: path, atomically: true, encoding: .utf8)
  try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
  print("Public key: \(key.publicKey.rawRepresentation.base64EncodedString())")

case "sign":
  guard args.count == 9, let version = Int(args[3]), let rulesURL = URL(string: args[5]),
    let malwareURL = URL(string: args[6])
  else { fail("usage: sign_rules.swift sign <key> <version> <min-app-version> <rules-url> <malware-url> <classification.json> <malware.json>") }
  let keyText = try String(contentsOfFile: args[2], encoding: .utf8)
    .trimmingCharacters(in: .whitespacesAndNewlines)
  guard let keyData = Data(base64Encoded: keyText),
    let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: keyData)
  else { fail("Could not read the private key") }
  let rules = try Data(contentsOf: URL(fileURLWithPath: args[7]))
  let malware = try Data(contentsOf: URL(fileURLWithPath: args[8]))
  let payload = Payload(
    version: version, minAppVersion: args[4], rules: rulesURL, malware: malwareURL,
    rulesSHA256: sha256(rules), malwareSHA256: sha256(malware))
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
  let signature = try key.signature(for: encoder.encode(payload)).base64EncodedString()
  encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes, .prettyPrinted]
  let manifest = Manifest(
    version: payload.version, minAppVersion: payload.minAppVersion, rules: payload.rules,
    malware: payload.malware, rulesSHA256: payload.rulesSHA256,
    malwareSHA256: payload.malwareSHA256, signature: signature)
  print(String(decoding: try encoder.encode(manifest), as: UTF8.self))

default:
  fail("unknown command \(args[1])")
}
