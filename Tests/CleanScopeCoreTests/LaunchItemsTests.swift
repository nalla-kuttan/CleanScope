import Foundation
import Testing

@testable import CleanScopeCore

@Suite struct LaunchItemsTests {
  private func writePlist(_ dict: [String: Any], name: String, in folder: URL) throws -> URL {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let url = folder.appendingPathComponent(name)
    try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0).write(to: url)
    return url
  }

  private var folder: URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  }

  @Test func parsesProgramForm() throws {
    let url = try writePlist(
      ["Label": "com.example.agent", "Program": "/Applications/Example.app/Contents/MacOS/agent",
       "RunAtLoad": true, "KeepAlive": true],
      name: "com.example.agent.plist", in: folder)
    let item = try #require(
      LaunchItemParser.parse(plistURL: url, scope: .userAgent, fileExists: { _ in true }))
    #expect(item.label == "com.example.agent")
    #expect(item.program == "/Applications/Example.app/Contents/MacOS/agent")
    #expect(item.runAtLoad && item.keepAlive)
    #expect(!item.isBroken)
    #expect(item.owningAppPath == "/Applications/Example.app")
  }

  @Test func parsesProgramArgumentsFormAndBrokenProgram() throws {
    let url = try writePlist(
      ["Label": "com.example.helper", "ProgramArguments": ["/usr/local/bin/helper", "--daemon"],
       "Disabled": true],
      name: "com.example.helper.plist", in: folder)
    let item = try #require(
      LaunchItemParser.parse(plistURL: url, scope: .systemDaemon, fileExists: { _ in false }))
    #expect(item.program == "/usr/local/bin/helper")
    #expect(item.isBroken)
    #expect(item.disabled)
    #expect(item.owningAppPath == nil)
  }

  @Test func missingLabelIsIgnored() throws {
    let url = try writePlist(["Program": "/bin/true"], name: "x.plist", in: folder)
    #expect(LaunchItemParser.parse(plistURL: url, scope: .userAgent, fileExists: { _ in true }) == nil)
  }

  @Test func appleItemsAreFiltered() throws {
    let dir = folder
    _ = try writePlist(["Label": "com.apple.thing", "Program": "/bin/true"], name: "a.plist", in: dir)
    _ = try writePlist(["Label": "org.signed.byapple", "Program": "/bin/apple"], name: "b.plist", in: dir)
    _ = try writePlist(["Label": "com.vendor.tool", "Program": "/bin/vendor"], name: "c.plist", in: dir)
    let items = LaunchItemService(
      fileExists: { _ in true },
      signer: { path in
        path == "/bin/apple" ? SignerInfo(teamID: nil, isApple: true) : SignerInfo(teamID: "TEAM123456", isApple: false)
      }
    ).items(in: [(dir, .userAgent)], status: LaunchctlStatus())
    #expect(items.map(\.label) == ["com.vendor.tool"])
    #expect(items.first?.teamID == "TEAM123456")
  }

  @Test func parsesLaunchctlListAndDisabledOutput() {
    let list = """
      PID\tStatus\tLabel
      123\t0\tcom.vendor.running
      -\t0\tcom.vendor.loaded
      """
    let disabled = """
      disabled services = {
      \t"com.vendor.off" => disabled
      \t"com.vendor.on" => enabled
      \t"com.vendor.legacy" => true
      }
      """
    let status = LaunchctlStatus(listOutput: list, disabledOutput: disabled)
    #expect(status.state(for: "com.vendor.running", plistDisabled: false) == .running)
    #expect(status.state(for: "com.vendor.loaded", plistDisabled: false) == .loaded)
    #expect(status.state(for: "com.vendor.off", plistDisabled: false) == .disabled)
    #expect(status.state(for: "com.vendor.legacy", plistDisabled: false) == .disabled)
    #expect(status.state(for: "com.vendor.on", plistDisabled: true) == .notLoaded)
    #expect(status.state(for: "com.vendor.other", plistDisabled: true) == .disabled)
  }

  @Test func commandsForUserAndSystemItems() {
    let user = LaunchItem(
      label: "com.vendor.agent", program: "/bin/x", plistPath: "/Users/me/Library/LaunchAgents/a b.plist",
      scope: .userAgent)
    #expect(LaunchItemCommands.disable(user, uid: 501) == ["/bin/launchctl", "disable", "gui/501/com.vendor.agent"])
    #expect(LaunchItemCommands.bootout(user, uid: 501) == ["/bin/launchctl", "bootout", "gui/501", "/Users/me/Library/LaunchAgents/a b.plist"])
    #expect(!user.requiresAdmin)

    let system = LaunchItem(
      label: "com.vendor.daemon", program: "/bin/x", plistPath: "/Library/LaunchDaemons/it's.plist",
      scope: .systemDaemon)
    #expect(system.requiresAdmin)
    #expect(
      LaunchItemCommands.adminDisable(system)
        == "/bin/launchctl bootout system '/Library/LaunchDaemons/it'\\''s.plist'; /bin/launchctl disable system/com.vendor.daemon")
    #expect(
      LaunchItemCommands.adminRemove(system)
        == "/bin/launchctl bootout system '/Library/LaunchDaemons/it'\\''s.plist'; /usr/bin/trash '/Library/LaunchDaemons/it'\\''s.plist'")
  }

  @Test func loginItemScriptsEscapeNames() {
    #expect(LegacyLoginItems.listScript == #"tell application "System Events" to get the name of every login item"#)
    #expect(
      LegacyLoginItems.deleteScript(name: #"My "App""#)
        == #"tell application "System Events" to delete login item "My \"App\"""#)
    #expect(LegacyLoginItems.parseNames("Dropbox, Bartender 5") == ["Dropbox", "Bartender 5"])
  }
}
