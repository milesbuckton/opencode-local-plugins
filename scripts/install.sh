#!/usr/bin/env bash
# Install the local workaround plugins and config overrides into place.
#
#   ./scripts/install.sh          # copy plugins and configs into place
#   ./scripts/install.sh --check  # only report differences
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${OPENCODE_PLUGIN_DIR:-$HOME/.config/opencode/plugins}"
BILI_DEST="${BILI_CONFIG_DIR:-$HOME/.config/billion-context}"
CHECK_ONLY=0
[[ "${1:-}" == "--check" ]] && CHECK_ONLY=1

mkdir -p "$DEST"
mkdir -p "$BILI_DEST"
status=0

# Plugins
for src in "$ROOT"/plugins/*.{js,ts}; do
  [[ -e "$src" ]] || continue
  name="$(basename "$src")"
  dest="$DEST/$name"

  if [[ ! -e "$dest" ]]; then
    if [[ $CHECK_ONLY -eq 1 ]]; then
      echo "MISSING  $dest"
      status=1
    else
      cp "$src" "$dest"
      echo "INSTALLED $dest"
    fi
    continue
  fi

  if cmp -s "$src" "$dest"; then
    echo "OK       $dest"
  else
    if [[ $CHECK_ONLY -eq 1 ]]; then
      echo "DIFFERS  $dest"
      status=1
    else
      cp "$src" "$dest"
      echo "UPDATED  $dest"
    fi
  fi
done

# Configs
for src in "$ROOT"/configs/*.json; do
  [[ -e "$src" ]] || continue
  name="$(basename "$src")"
  dest="$BILI_DEST/$name"

  if [[ ! -e "$dest" ]]; then
    if [[ $CHECK_ONLY -eq 1 ]]; then
      echo "MISSING  $dest"
      status=1
    else
      cp "$src" "$dest"
      echo "INSTALLED $dest"
    fi
    continue
  fi

  if cmp -s "$src" "$dest"; then
    echo "OK       $dest"
  else
    if [[ $CHECK_ONLY -eq 1 ]]; then
      echo "DIFFERS  $dest"
      status=1
    else
      cp "$src" "$dest"
      echo "UPDATED  $dest"
    fi
  fi
done

exit $status
