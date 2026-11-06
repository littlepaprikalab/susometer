#!/bin/bash
# Type-checks the app's native Swift (ios/Runner) on Linux against small
# stand-in modules for UIKit, AVFoundation, Speech, Flutter and SmartSpectra.
# The SmartSpectra stand-in mirrors the public interface of SmartSpectra-Swift
# 3.4.0 for every API the app uses. This catches syntax, type and actor-
# isolation mistakes early; it is not a substitute for an Xcode build.
#
# Needs a Swift toolchain (swift.org, 6.2.x to match Xcode 26) on PATH.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/mods" "$work/src"

build() { # module name, file
  swiftc -emit-module -parse-as-library -swift-version 5 -enable-library-evolution \
    -module-name "$1" "$2" -emit-module-path "$work/mods/$1.swiftmodule" -I "$work/mods" \
    2>&1 | grep -v 'not compiled with library evolution' | grep -E 'error' && exit 1 || true
}
build UIKit "$here/stubs/UIKit.swift"
build AVFoundation "$here/stubs/AVFoundation.swift"
build Flutter "$here/stubs/Flutter.swift"
build Speech "$here/stubs/Speech.swift"
build SmartSpectra "$here/stubs/SmartSpectra.swift"

runner="$repo/ios/Runner"
find "$runner" -name '*.swift' ! -name 'KeychainStore.swift' ! -name 'SceneDelegate.swift' \
  -exec cp {} "$work/src/" \;
# @objc needs the Objective-C runtime, which Linux doesn't have.
sed -i 's/^@objc class AppDelegate/class AppDelegate/' "$work/src/AppDelegate.swift"
cp "$here/Shims.swift" "$work/src/"

echo "Type-checking (Swift 5 mode, as the Xcode project builds)..."
swiftc -typecheck -swift-version 5 -I "$work/mods" "$work/src"/*.swift 2>&1 \
  | grep -v 'not compiled with library evolution' | tee "$work/out.txt" || true
echo "Syntax-checking KeychainStore.swift..."
swiftc -parse "$runner/Presage/KeychainStore.swift"
if grep -qE 'error:|warning:' "$work/out.txt"; then
  echo "FAILED: see diagnostics above."
  exit 1
fi
echo "OK: no errors or warnings."
