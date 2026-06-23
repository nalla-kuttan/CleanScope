#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVELOPER_DIR="$(xcode-select -p)"
MANIFEST_API="$DEVELOPER_DIR/usr/lib/swift/pm/ManifestAPI"
PACKAGE_MODULE="$MANIFEST_API/PackageDescription.swiftmodule"
PUBLIC_INTERFACE="$PACKAGE_MODULE/arm64-apple-macos.swiftinterface"
PRIVATE_INTERFACE="$PACKAGE_MODULE/arm64-apple-macos.private.swiftinterface"

if [[ -f "$PUBLIC_INTERFACE" ]] \
  && grep -q "swiftLanguageModes" "$PUBLIC_INTERFACE" \
  && [[ -f "$PRIVATE_INTERFACE" ]] \
  && ! grep -q "swiftLanguageModes" "$PRIVATE_INTERFACE"; then
  TOOLCHAIN_CACHE="$ROOT_DIR/.build/cleanscope-toolchain"
  LOCAL_MANIFEST_API="$TOOLCHAIN_CACHE/ManifestAPI"
  MANIFEST_COMPILER="$TOOLCHAIN_CACHE/swiftc-manifest"

  rm -rf "$LOCAL_MANIFEST_API"
  mkdir -p "$LOCAL_MANIFEST_API"
  cp -R "$PACKAGE_MODULE" "$LOCAL_MANIFEST_API/"
  if [[ -d "$MANIFEST_API/CompilerPluginSupport.swiftmodule" ]]; then
    cp -R "$MANIFEST_API/CompilerPluginSupport.swiftmodule" "$LOCAL_MANIFEST_API/"
  fi
  find "$LOCAL_MANIFEST_API" -name "*.private.swiftinterface" -delete

  cat >"$MANIFEST_COMPILER" <<SCRIPT
#!/usr/bin/env bash
exec "$DEVELOPER_DIR/usr/bin/swiftc" -I "$LOCAL_MANIFEST_API" "\$@"
SCRIPT
  chmod +x "$MANIFEST_COMPILER"
  export SWIFT_EXEC_MANIFEST="$MANIFEST_COMPILER"
fi

if [[ "${1:-}" == "test" ]]; then
  FRAMEWORKS="$DEVELOPER_DIR/Library/Developer/Frameworks"
  TESTING_LIB="$DEVELOPER_DIR/Library/Developer/usr/lib"
  if [[ -d "$FRAMEWORKS/Testing.framework" ]]; then
    exec swift "$@" \
      -Xswiftc -F \
      -Xswiftc "$FRAMEWORKS" \
      -Xlinker "-F$FRAMEWORKS" \
      -Xlinker -rpath \
      -Xlinker "$FRAMEWORKS" \
      -Xlinker -rpath \
      -Xlinker "$TESTING_LIB"
  fi
fi

exec swift "$@"
