#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
APP_DIR="$ROOT_DIR/.build/NetScope.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"

swift build --product NetScopeMenuBar -c release --package-path "$ROOT_DIR"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
cp "$ROOT_DIR/.build/release/NetScopeMenuBar" "$MACOS_DIR/NetScopeMenuBar"
cp "$ROOT_DIR/Resources/AppBundle/Info.plist" "$CONTENTS_DIR/Info.plist"

echo "$APP_DIR"

