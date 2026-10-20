/// The twelve modules of the 3D icon family. Each raw value is the file stem of the
/// rendered assets in `CleanScopeApp/Resources/Icons` (`<key>@2x.png`, `<key>-hover-00.png`).
public enum ModuleIconKey: String, CaseIterable, Sendable {
  case scan, cleanup, map, large, dev, downloads, leftovers, maintenance, memory, login,
    protection, privacy
}
