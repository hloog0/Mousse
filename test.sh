#!/usr/bin/env bash
# Runs the tests. With only the Command Line Tools installed, SwiftPM's dependency scan
# sometimes fails to resolve Swift Testing's macro plugin, so load it explicitly.
set -euo pipefail
cd "$(dirname "$0")"

PLUGIN="$(xcode-select -p)/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"
if [[ -f "$PLUGIN" ]]; then
  swift test -Xswiftc -load-plugin-library -Xswiftc "$PLUGIN" "$@"
else
  swift test "$@"
fi
