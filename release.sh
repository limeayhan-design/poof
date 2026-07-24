#!/usr/bin/env bash
#
# One-shot Poof release script.
#
#   ./release.sh v0.1.1 "Bug fixes + faster LAN discovery"
#
# What it does:
#   1. Bumps version in tauri.conf.json and Cargo.toml
#   2. Commits, tags, pushes
#   3. Rebuilds Poof.app (macOS ARM64) + signs the updater tarball
#   4. Creates the GitHub Release
#   5. Uploads .dmg, .app.tar.gz, .sig, and latest.json (updater manifest)
#
# Requires:
#   - Tauri signing key at ~/.tauri/poof.key (created once via `tauri signer generate`)
#   - GitHub PAT in macOS Keychain: internet-password, service=github.com, account=limeayhan-design
#
set -euo pipefail

REPO="limeayhan-design/poof"
PROJECT_DIR="/Users/Uras/Desktop/Poof"
DESKTOP_DIR="$PROJECT_DIR/desktop"
KEY_PATH="$HOME/.tauri/poof.key"

TAG="${1:-}"
NOTES="${2:-New release.}"

if [[ -z "$TAG" || ! "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Usage: $0 vMAJOR.MINOR.PATCH \"release notes\""
  echo "Example: $0 v0.1.1 \"Faster LAN discovery\""
  exit 1
fi

VERSION="${TAG#v}"
BUNDLE_DIR="$DESKTOP_DIR/src-tauri/target/release/bundle"
DMG_NAME="Poof_${VERSION}_aarch64.dmg"
TGZ_NAME="Poof_${VERSION}_aarch64.app.tar.gz"

echo "==> Bumping to $VERSION"

# tauri.conf.json — replace the first occurrence of  "version": "x.y.z"
python3 - "$DESKTOP_DIR/src-tauri/tauri.conf.json" "$VERSION" <<'PY'
import json, sys, pathlib
p = pathlib.Path(sys.argv[1])
d = json.loads(p.read_text())
d["version"] = sys.argv[2]
p.write_text(json.dumps(d, indent=2) + "\n")
PY

# Cargo.toml — replace the [package] version line
python3 - "$DESKTOP_DIR/src-tauri/Cargo.toml" "$VERSION" <<'PY'
import re, sys, pathlib
p = pathlib.Path(sys.argv[1])
txt = p.read_text()
txt = re.sub(r'(?m)^version = "\d+\.\d+\.\d+"', f'version = "{sys.argv[2]}"', txt, count=1)
p.write_text(txt)
PY

echo "==> Git commit + tag"
cd "$PROJECT_DIR"
git add desktop/src-tauri/tauri.conf.json desktop/src-tauri/Cargo.toml
git commit -m "Release $TAG" || echo "(nothing to commit)"
git tag -a "$TAG" -m "Poof $TAG — $NOTES"
git push origin main
git push origin "$TAG"

echo "==> Rebuilding + signing (~3 min)"
cd "$DESKTOP_DIR"
TAURI_SIGNING_PRIVATE_KEY_PATH="$KEY_PATH" \
TAURI_SIGNING_PRIVATE_KEY_PASSWORD="" \
  npx tauri build

# Manual re-sign of the updater tarball (Tauri v2 sometimes skips signing at build time)
TAURI_SIGNING_PRIVATE_KEY_PATH="$KEY_PATH" \
TAURI_SIGNING_PRIVATE_KEY_PASSWORD="" \
  npx @tauri-apps/cli signer sign "$BUNDLE_DIR/macos/Poof.app.tar.gz"

# Rename artifacts to include version
cp "$BUNDLE_DIR/macos/Poof.app.tar.gz"     "$BUNDLE_DIR/macos/$TGZ_NAME"
cp "$BUNDLE_DIR/macos/Poof.app.tar.gz.sig" "$BUNDLE_DIR/macos/${TGZ_NAME}.sig"

echo "==> Creating GitHub Release"
TOKEN=$(security find-internet-password -s github.com -a limeayhan-design -w)

RELEASE_JSON=$(curl -sS -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/$REPO/releases" \
  -d "$(python3 -c "import json,sys;print(json.dumps({'tag_name':'$TAG','name':'Poof $TAG','body':'''$NOTES''','draft':False,'prerelease':False}))")")

RELEASE_ID=$(echo "$RELEASE_JSON" | python3 -c "import sys,json;print(json.load(sys.stdin)['id'])")
UPLOAD_URL="https://uploads.github.com/repos/$REPO/releases/$RELEASE_ID/assets"
echo "   Release ID: $RELEASE_ID"

echo "==> Uploading assets"
for FILE_PATH in \
  "$BUNDLE_DIR/dmg/$DMG_NAME" \
  "$BUNDLE_DIR/macos/$TGZ_NAME" \
  "$BUNDLE_DIR/macos/${TGZ_NAME}.sig"
do
  NAME=$(basename "$FILE_PATH")
  echo "   -> $NAME"
  curl -sS -X POST \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/octet-stream" \
    --data-binary @"$FILE_PATH" \
    "$UPLOAD_URL?name=$NAME" > /dev/null
done

echo "==> Building latest.json"
SIG=$(cat "$BUNDLE_DIR/macos/${TGZ_NAME}.sig")
PUB_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

python3 - "$VERSION" "$NOTES" "$PUB_DATE" "$REPO" "$TAG" "$TGZ_NAME" "$SIG" > /tmp/latest.json <<'PY'
import json, sys
version, notes, pub, repo, tag, tgz, sig = sys.argv[1:]
print(json.dumps({
  "version": version,
  "notes": notes,
  "pub_date": pub,
  "platforms": {
    "darwin-aarch64": {
      "signature": sig,
      "url": f"https://github.com/{repo}/releases/download/{tag}/{tgz}"
    }
  }
}, indent=2))
PY

echo "==> Uploading latest.json"
curl -sS -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  --data-binary @/tmp/latest.json \
  "$UPLOAD_URL?name=latest.json" > /dev/null

echo ""
echo "✅ Poof $TAG shipped."
echo "   https://github.com/$REPO/releases/tag/$TAG"
echo ""
echo "Existing installs will show \"Poof $VERSION ready — Restart\" on next launch."
