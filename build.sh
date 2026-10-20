#!/usr/bin/env bash
# Builds SmoothWheel.app, signs it, installs it to ~/Applications and launches it.
#   ./build.sh            build, install, launch
#   ./build.sh --no-open  build and install only
#
# Signing: uses the self-signed code-signing identity "SmoothWheel Local" in the login keychain
# if present (keeps the Accessibility grant across rebuilds); otherwise signs ad hoc.
# It doesn't need to be trusted: macOS only checks that each build is signed by the same key.
set -euo pipefail
cd "$(dirname "$0")"

# Own build folder: sharing .build with `swift test` leaves a stale macro-plugin cache behind
# that makes the next test build fail to find Swift Testing's macros.
SCRATCH=".build-release"
swift build -c release --scratch-path "$SCRATCH"
BIN="$(swift build -c release --scratch-path "$SCRATCH" --show-bin-path)/SmoothWheel"

APP="build/SmoothWheel.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/SmoothWheel"
cp Resources/Info.plist "$APP/Contents/Info.plist"

IDENTITY="${SMOOTHWHEEL_SIGN_IDENTITY:-SmoothWheel Local}"
# Not `-v`: that lists trusted identities only. Sign by SHA-1 so the name can't be ambiguous.
HASH="$(security find-identity -p codesigning 2>/dev/null | awk -v n="\"$IDENTITY\"" 'index($0, n) { print $2; exit }')"
SIGN="${HASH:--}"
codesign --force --sign "$SIGN" --identifier com.steve.smoothwheel "$APP"

DEST="$HOME/Applications/SmoothWheel.app"
mkdir -p "$HOME/Applications"
pkill -x SmoothWheel 2>/dev/null && sleep 0.5 || true
rm -rf "$DEST"
cp -R "$APP" "$DEST"
if [[ "$SIGN" == "-" ]]; then SIGNED="ad hoc"; else SIGNED="$IDENTITY"; fi
echo "Installed $DEST (signed: $SIGNED)"

if [[ "${1:-}" != "--no-open" ]]; then
  open "$DEST"
fi
