#!/bin/bash
# SessionStart hook for Claude Code cloud sessions: installs the Flutter SDK
# and this app's Dart packages so `flutter analyze` and `flutter test` work.
# iOS builds still need a Mac with Xcode; this only covers analysis and tests.
set -euo pipefail

# Only run in Claude Code cloud sessions, never on a developer's machine.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

FLUTTER_VERSION="3.47.9"
FLUTTER_HOME="/opt/flutter"
FLUTTER_URL="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"

cd "${CLAUDE_PROJECT_DIR:-.}"

# --- Flutter SDK (global tool, pinned) ---------------------------------------
installed_version="$(grep -o '"frameworkVersion": *"[^"]*"' "$FLUTTER_HOME/bin/cache/flutter.version.json" 2>/dev/null | grep -o '[0-9][0-9.]*' || true)"
if [ ! -x "$FLUTTER_HOME/bin/flutter" ] || [ "$installed_version" != "$FLUTTER_VERSION" ]; then
  echo "Installing Flutter $FLUTTER_VERSION into $FLUTTER_HOME..." >&2
  tmp="$(mktemp -d)"
  curl -fsSL --retry 4 --retry-delay 2 -o "$tmp/flutter.tar.xz" "$FLUTTER_URL"
  rm -rf "$FLUTTER_HOME"
  tar -xf "$tmp/flutter.tar.xz" -C "$(dirname "$FLUTTER_HOME")"
  rm -rf "$tmp"
fi

# Flutter is a git checkout; the container runs as root, so trust that checkout.
if ! git config --global --get-all safe.directory 2>/dev/null | grep -qx "$FLUTTER_HOME"; then
  git config --global --add safe.directory "$FLUTTER_HOME"
fi

export PATH="$FLUTTER_HOME/bin:$PATH"

# First-run setup: no analytics, iOS-only project, plain output. Re-runs are cheap.
if [ ! -f "$FLUTTER_HOME/.session-start-configured" ]; then
  flutter --disable-analytics >/dev/null 2>&1
  dart --disable-analytics >/dev/null 2>&1 || true
  flutter config --no-cli-animations --no-enable-android --no-enable-web \
    --no-enable-linux-desktop >/dev/null 2>&1
  flutter precache --universal >/dev/null 2>&1 || flutter precache >/dev/null 2>&1
  touch "$FLUTTER_HOME/.session-start-configured"
fi

# --- Dart packages -------------------------------------------------------------
# Run `flutter pub get` only if the pubspec, lockfile or this script changed since
# the last successful run, or if the package cache / package config is missing.
hashes=.dart_tool/.session-start.sha256
if ! sha256sum --check --status "$hashes" 2>/dev/null \
  || [ ! -f .dart_tool/package_config.json ] \
  || [ ! -d "${PUB_CACHE:-$HOME/.pub-cache}/hosted" ]; then
  rm -f "$hashes"
  flutter pub get
  mkdir -p .dart_tool
  sha256sum .claude/hooks/session-start.sh pubspec.yaml pubspec.lock > "$hashes" || rm -f "$hashes"
fi

# --- Every session ------------------------------------------------------------
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo "export PATH=\"$FLUTTER_HOME/bin:\$PATH\"" >> "$CLAUDE_ENV_FILE"
fi
