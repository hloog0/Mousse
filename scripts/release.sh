#!/usr/bin/env bash
# Publishes a GitHub release with a downloadable Mousse.zip (Apple Silicon + Intel).
#   ./scripts/release.sh
# The version comes from CFBundleShortVersionString in Resources/Info.plist; bump it first.
# Needs the GitHub CLI (gh), logged in with push access, and a clean, pushed main branch.
#
# Releases are signed with the "Mousse Local" certificate when it's present, so people
# keep their Accessibility permission across updates. Keep that certificate (it's in your
# login keychain) to publish compatible updates.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
TAG="v$VERSION"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Commit or stash your changes first." >&2; exit 1
fi
git fetch -q origin
if [[ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]]; then
  echo "Push main first: releases are built from what's on GitHub." >&2; exit 1
fi
if gh release view "$TAG" >/dev/null 2>&1; then
  echo "$TAG already exists. Bump CFBundleShortVersionString in Resources/Info.plist." >&2; exit 1
fi

./build.sh --no-install

# Always named Mousse.zip, so .../releases/latest/download/Mousse.zip keeps working.
mkdir -p dist
ZIP="dist/Mousse.zip"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent ".build-release/app.noindex/Mousse.app" "$ZIP"

gh release create "$TAG" "$ZIP" --target "$(git rev-parse HEAD)" --title "Mousse $VERSION" --notes-file - <<'EOF'
Smooth, trackpad-style scrolling for notched mouse wheels. Runs on Apple Silicon and Intel Macs with macOS 15 or later.

## Install

1. Download **Mousse.zip** below and double-click it to unzip.
2. Drag **Mousse** into your **Applications** folder.
3. Open it. macOS will say it couldn't verify the app, because free apps like this aren't signed through Apple's paid developer program. Click **Done**, then go to **System Settings → Privacy & Security**, scroll down and click **Open Anyway**. You only need to do this once.
4. When asked, turn on **Mousse** under **System Settings → Privacy & Security → Accessibility**. That's what lets it smooth out the wheel.

Then click the mouse icon in the menu bar to adjust it.
EOF
echo "Published $TAG"
