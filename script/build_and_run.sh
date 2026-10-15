#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
MODE="${1:-run}"
CONFIGURATION="${HARBOR_BUILD_CONFIGURATION:-debug}"
case "$CONFIGURATION" in debug|release) ;; *) printf 'Unsupported build configuration\n' >&2; exit 2 ;; esac
APP="$ROOT/dist/Harbor.app"
BINARY="$APP/Contents/MacOS/Harbor"
# A live Wine server can retain Harbor's macOS TCC attribution. Replacing this
# ad-hoc signed launcher underneath it invalidates removable-volume access.
# Refuse the update; never kill a game in order to complete a build.
if ps -axo comm= | awk '/\/SharedSupport\/wine\/.*\/wineserver$/ { found=1 } END { exit !found }'; then
  printf 'Harbor update stopped: a Sikarugir Wine environment is still running.\nSave and quit games, then stop their Wine environments before rebuilding or replacing Harbor.\nNo app or game was stopped.\n' >&2
  exit 3
fi
# Stop only this checkout's GUI, never a Wine/Steam process or another Harbor build.
while IFS= read -r app_pid; do
  [ -n "$app_pid" ] && kill -TERM "$app_pid"
done < <(ps -axo pid=,comm= | awk -v p="$BINARY" 'index($0,p) {print $1}')
swift build -c "$CONFIGURATION"
BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Harbor" "$BINARY"
cp "$ROOT/script/Info.plist" "$APP/Contents/Info.plist"
if [ -d "$BIN_DIR/Harbor_Harbor.bundle" ]; then
  ditto "$BIN_DIR/Harbor_Harbor.bundle" "$APP/Contents/Resources/Harbor_Harbor.bundle"
fi
if [ ! -f "$ROOT/dist/Harbor.icns" ] || [ "$ROOT/script/GenerateIcon.swift" -nt "$ROOT/dist/Harbor.icns" ]; then
  swift "$ROOT/script/GenerateIcon.swift" "$ROOT/dist/Harbor.iconset"
  iconutil -c icns "$ROOT/dist/Harbor.iconset" -o "$ROOT/dist/Harbor.icns"
fi
cp "$ROOT/dist/Harbor.icns" "$APP/Contents/Resources/Harbor.icns"
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
case "$MODE" in
  --build-only) printf 'Built: %s\n' "$APP" ;;
  run) open -n "$APP" ;;
  --verify) open -n "$APP"; sleep 2; pgrep -x Harbor >/dev/null; printf 'Harbor process is running. UI still requires visual verification.\n' ;;
  --debug) lldb -- "$BINARY" ;;
  --logs|--telemetry) open -n "$APP"; /usr/bin/log stream --info --style compact --predicate 'subsystem == "local.harbor.desktop"' ;;
  *) printf 'Usage: %s [--build-only|--verify|--debug|--logs|--telemetry]\n' "$0" >&2; exit 2 ;;
esac
