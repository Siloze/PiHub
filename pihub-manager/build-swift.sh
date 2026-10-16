#!/bin/zsh
# ══════════════════════════════════════════════════
# build-swift.sh — Compile l'app PiHubManager
# ══════════════════════════════════════════════════

set -euo pipefail

ROOT=${0:A:h:h}
SWIFT_SRC="$ROOT/pihub-manager/swift/HubApp.swift"
APP_PATH="$ROOT/PiHubManager.app"
BINARY="$APP_PATH/Contents/MacOS/PiHubManager"

if [[ ! -f "$SWIFT_SRC" ]]; then
  echo "Erreur: source Swift introuvable: $SWIFT_SRC"
  exit 1
fi

echo "═══════════════════════════════════════════════"
echo "  Compilation de PiHubManager"
echo "  Source: $SWIFT_SRC"
echo "═══════════════════════════════════════════════"

BUILD_DIR=$(mktemp -d "${TMPDIR:-/tmp}/pihub-build.XXXXXX")
# Compiler le Swift
swiftc -O -target arm64-apple-macosx13.0 \
  "$ROOT/pihub-manager/swift/HubModels.swift" \
  "$ROOT/pihub-manager/swift/HubViews.swift" \
  "$ROOT/pihub-manager/swift/HubEditors.swift" \
  "$ROOT/pihub-manager/swift/HubCompact.swift" \
  "$ROOT/pihub-manager/swift/IntegrationActions.swift" \
  "$ROOT/pihub-manager/swift/ModelChangePrompt.swift" \
  "$ROOT/pihub-manager/swift/HubWorkspace.swift" \
  "$ROOT/pihub-manager/swift/HubCatalog.swift" \
  "$ROOT/pihub-manager/swift/ManifestEditor.swift" \
  "$SWIFT_SRC" -o "$BUILD_DIR/PiHubManager" 2>&1
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$ROOT/pihub-manager/templates/Info.plist" "$APP_PATH/Contents/Info.plist"
mv "$BUILD_DIR/PiHubManager" "$BINARY"
rmdir "$BUILD_DIR"
mkdir -p "$APP_PATH/Contents/Resources/backend"
rsync -a --delete --delete-excluded --exclude '__pycache__' --exclude '*.pyc' \
  "$ROOT/pihub-manager/src/pihub_manager/" "$APP_PATH/Contents/Resources/backend/pihub_manager/"
/usr/libexec/PlistBuddy -c 'Set :CFBundleShortVersionString 2.0.0' "$APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleVersion 2' "$APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :LSMinimumSystemVersion 13.0' "$APP_PATH/Contents/Info.plist"
codesign --force --deep --sign - "$APP_PATH"
chmod +x "$BINARY"

if [[ -f "$BINARY" ]]; then
  echo ""
  echo "═══════════════════════════════════════════════"
  echo "  ✓ PiHubManager compilé avec succès!"
  echo "  Emplacement: $APP_PATH"
  echo ""
  echo "  Pour lancer:"
  echo "    open '$APP_PATH' --background"
  echo ""
  echo "  Ou via make:"
  echo "    make manager"
  echo "═══════════════════════════════════════════════"
else
  echo "✗ Échec de compilation."
  exit 1
fi
