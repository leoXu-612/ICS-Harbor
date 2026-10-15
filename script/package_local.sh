#!/bin/bash
# Local preview only. This does not notarize, upload or publish anything.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
HARBOR_BUILD_CONFIGURATION=release ./script/build_and_run.sh --build-only
TEMP_STAGE="$(mktemp -d "$ROOT/dist/.harbor-package.XXXXXX")"
cleanup() {
  case "$TEMP_STAGE" in "$ROOT"/dist/.harbor-package.*) /bin/rm -r "$TEMP_STAGE" ;; esac
}
trap cleanup EXIT
STAGE="$TEMP_STAGE/Harbor-0.4.0-Preview"
ARCHIVE="$ROOT/dist/Harbor-0.4.0-Preview.zip"
mkdir -p "$STAGE"
ditto "$ROOT/dist/Harbor.app" "$STAGE/Harbor.app"
cp README.md THIRD_PARTY_NOTICES.md LICENSE "$STAGE/"
mkdir -p "$STAGE/docs"
cp docs/ARCHITECTURE.md "$STAGE/docs/"
cp docs/PARAMETERS.md "$STAGE/docs/"
cp docs/VALIDATION.md "$STAGE/docs/"
codesign --verify --strict "$STAGE/Harbor.app"
# Write a temporary complete archive before replacing the previous generated copy.
ditto -c -k --keepParent --norsrc "$STAGE" "$ARCHIVE.partial"
mv -f "$ARCHIVE.partial" "$ARCHIVE"
(cd "$ROOT/dist" && shasum -a 256 Harbor-0.4.0-Preview.zip) > "$ARCHIVE.sha256"
printf 'Local preview archive: %s\nNot notarized; no public release was performed.\n' "$ARCHIVE"
