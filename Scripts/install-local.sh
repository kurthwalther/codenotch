#!/bin/bash
# Build this fork of Codenotch on whatever Mac this is, and put it in
# /Applications.
#
#   Scripts/install-local.sh            build Release and install
#   Scripts/install-local.sh --build    build only, say where the app is
#   Scripts/install-local.sh --test     run the unit tests
#
# The committed project pins the original author's Developer ID, which only
# his Mac has. This signs with the first Apple Development identity in the
# login keychain — the free kind, made by signing into Xcode with any Apple
# ID — or, failing that, ad hoc. Either way the app runs here; a signed one
# keeps macOS's keychain permission across rebuilds, an ad-hoc one asks again
# after each.
#
# Needs: Xcode (or Xcode-beta), and `brew install xcodegen`.
set -euo pipefail
cd "$(dirname "$0")/.."

ACTION="${1:-install}"

command -v xcodegen >/dev/null 2>&1 || { echo "xcodegen is missing: brew install xcodegen" >&2; exit 1; }
export DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p)}"

# Signing identity: the hash of the first valid Apple Development certificate.
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
  | grep 'Apple Development' | grep -v REVOKED | head -1 | awk '{print $2}' || true)
if [ -n "$IDENTITY" ]; then
  SIGN=(CODE_SIGN_IDENTITY="$IDENTITY" DEVELOPMENT_TEAM="" CODE_SIGN_STYLE=Manual)
  echo "signing with Apple Development $IDENTITY"
else
  SIGN=(CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM="" CODE_SIGN_STYLE=Manual)
  echo "no Apple Development certificate found: signing ad hoc"
fi

CONFIG=Release
[ "$ACTION" = "--test" ] && CONFIG=Debug
XB=(xcodebuild -project Codenotch.xcodeproj -scheme Codenotch
    -destination 'platform=macOS,arch=arm64' -configuration "$CONFIG")

xcodegen generate --quiet

case "$ACTION" in
  --test)
    "${XB[@]}" test "${SIGN[@]}" | grep -E 'Test Suite .All tests.|Executed|error:|\*\* TEST' | tail -5 ;;
  --build|install)
    "${XB[@]}" build "${SIGN[@]}" -quiet
    APP="$("${XB[@]}" -showBuildSettings "${SIGN[@]}" 2>/dev/null \
      | awk -F' = ' '/ BUILT_PRODUCTS_DIR/ {print $2; exit}')/Codenotch.app"
    echo "built: $APP"
    if [ "$ACTION" = install ]; then
      # Only the copy being replaced, found by its exact executable path. A
      # name pattern handed to pkill can match far more than it looks like.
      PID=$(pgrep -f '^/Applications/Codenotch.app/Contents/MacOS/Codenotch$' || true)
      if [ -n "$PID" ]; then
        kill $PID
        for _ in $(seq 1 100); do kill -0 $PID 2>/dev/null || break; sleep 0.05; done
      fi
      if [ -d /Applications/Codenotch.app ]; then
        mv /Applications/Codenotch.app ~/.Trash/"Codenotch-replaced-$(date +%H%M%S).app"
      fi
      ditto "$APP" /Applications/Codenotch.app
      # Launch Services caches Info.plist keys such as LSUIElement per path;
      # re-registering makes it read the new bundle's, not the old one's.
      /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/Codenotch.app
      open /Applications/Codenotch.app
      echo "installed and launched /Applications/Codenotch.app"
      echo "next: Settings > General > Open Codenotch at login"
    fi ;;
  *) echo "usage: $0 [install|--build|--test]" >&2; exit 2 ;;
esac
