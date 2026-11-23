#!/usr/bin/env bash
set -euo pipefail

FORK="${OPENCHAMBER_FORK_DIR:-$HOME/Developer/openchamber}"
UPSTREAM_URL="https://github.com/openchamber/openchamber.git"
BIN_TARGET="${OPENCHAMBER_BIN_TARGET:-$HOME/.local/bin/openchamber}"
CLI_SRC="$FORK/packages/web/bin/cli.js"

status() {
  echo "== fork ($FORK) =="
  (cd "$FORK" && git log -1 --format='  %s (%ad)' --date=short)
  echo
  echo "== cli target ($BIN_TARGET) =="
  if [[ -L "$BIN_TARGET" ]]; then
    echo "  Symlinked -> $(readlink "$BIN_TARGET")"
  elif [[ -f "$BIN_TARGET" ]]; then
    echo "  Binary present (not a symlink)"
  else
    echo "  Not linked"
  fi
}

build_web() {
  echo "Building OpenChamber web and server..."
  (cd "$FORK" && bun install && bun run build:web)
}

build_electron() {
  echo "Building OpenChamber Desktop app..."
  (cd "$FORK" && bun install && bun run electron:build)
  echo "Syncing OpenChamber (Dev).app to /Applications..."
  local dev_app="/Applications/OpenChamber (Dev).app"
  rm -rf "$dev_app"
  cp -pPR "$FORK/packages/electron/dist/mac-arm64/OpenChamber.app" "$dev_app"
  codesign --force --deep -s - "$dev_app"
  echo "Installed $dev_app"
}

use() {
  build_web
  mkdir -p "$(dirname "$BIN_TARGET")"
  ln -sf "$CLI_SRC" "$BIN_TARGET"
  chmod +x "$CLI_SRC"
  echo "Linked $BIN_TARGET -> $CLI_SRC"
}

update() {
  cd "$FORK"
  if [[ -n "$(git status --porcelain)" ]]; then
    echo "Fork has uncommitted changes; commit or stash first." >&2
    exit 1
  fi
  git remote get-url upstream >/dev/null 2>&1 || git remote add upstream "$UPSTREAM_URL"
  git fetch -q upstream
  if ! git rebase upstream/main; then
    echo "Rebase stopped on a conflict. Resolve it, run 'git rebase --continue', then rerun update." >&2
    exit 1
  fi
  build_web
  git push --force-with-lease origin main
  echo "Rebased onto upstream/main and pushed to origin."
  if "$BIN_TARGET" status -p 3000 >/dev/null 2>&1; then
    echo "Restarting daemon on port 3000..."
    "$BIN_TARGET" restart -p 3000
  fi
}

case "${1:-status}" in
  status)
    status
    ;;
  build)
    build_web
    ;;
  build-desktop)
    build_electron
    ;;
  use)
    use
    ;;
  update)
    update
    ;;
  *)
    echo "Usage: $0 {status|build|build-desktop|use|update}" >&2
    exit 1
    ;;
esac
