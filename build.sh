#!/usr/bin/env bash
# Builds SmoothWheel.app (Apple Silicon + Intel), signs it, installs it and launches it.
#   ./build.sh               build, install, launch
#   ./build.sh --no-open     build and install only
#   ./build.sh --no-install  build only (the app is left in .build-release/app.noindex)
#
# Installs to /Applications when you can write to it (admin accounts can), else ~/Applications.
#
# Signing: uses the self-signed code-signing identity "SmoothWheel Local" in the login keychain
# if present (keeps the Accessibility grant across rebuilds); otherwise signs ad hoc.
# It doesn't need to be trusted: macOS only checks that each build is signed by the same key.
set -euo pipefail
cd "$(dirname "$0")"

OPEN=1 INSTALL=1
for arg in "$@"; do
  case "$arg" in
    --no-open) OPEN=0 ;;
    --no-install) INSTALL=0 OPEN=0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

# Own build folder: sharing .build with `swift test` leaves a stale macro-plugin cache behind
# that makes the next test build fail to find Swift Testing's macros.
SCRATCH=".build-release"
ARCHS=(--arch arm64 --arch x86_64)
swift build -c release "${ARCHS[@]}" --scratch-path "$SCRATCH"
BIN="$(swift build -c release "${ARCHS[@]}" --scratch-path "$SCRATCH" --show-bin-path)/SmoothWheel"

# Staged in a .noindex folder so Spotlight doesn't list it as a second copy of the app.
APP="$SCRATCH/app.noindex/SmoothWheel.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/SmoothWheel"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

IDENTITY="${SMOOTHWHEEL_SIGN_IDENTITY:-SmoothWheel Local}"
# Not `-v`: that lists trusted identities only. Sign by SHA-1 so the name can't be ambiguous.
HASH="$(security find-identity -p codesigning 2>/dev/null | awk -v n="\"$IDENTITY\"" 'index($0, n) { print $2; exit }')"
SIGN="${HASH:--}"
codesign --force --sign "$SIGN" --identifier com.steve.smoothwheel "$APP"
if [[ "$SIGN" == "-" ]]; then SIGNED="ad hoc"; else SIGNED="$IDENTITY"; fi

if [[ $INSTALL == 0 ]]; then
  echo "Built $APP (signed: $SIGNED)"
  exit 0
fi

if [[ -w /Applications ]]; then DIR="/Applications"; else DIR="$HOME/Applications"; fi
DEST="$DIR/SmoothWheel.app"
mkdir -p "$DIR"
pkill -x SmoothWheel 2>/dev/null && sleep 0.5 || true
rm -rf "$DEST"
cp -R "$APP" "$DEST"
# Earlier versions installed to ~/Applications; don't leave a second copy behind.
if [[ "$DIR" == "/Applications" && -d "$HOME/Applications/SmoothWheel.app" ]]; then
  rm -rf "$HOME/Applications/SmoothWheel.app"
fi
echo "Installed $DEST (signed: $SIGNED)"

if [[ $OPEN == 1 ]]; then
  open "$DEST"
fi
