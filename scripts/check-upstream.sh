#!/usr/bin/env bash
# Report whether the upstream fix for the /bili/ URL rewrite has landed, so the
# local kiro-proxy-compat plugin can be retired when it is no longer needed.
set -uo pipefail

echo "== installed billion-context copies =="
found=0
while IFS= read -r pkg; do
  dir="$(dirname "$pkg")"
  version="$(node -e "try{console.log(require('$pkg').version)}catch(e){console.log('?')}" 2>/dev/null)"
  if grep -q "replaceRequestTarget" "$dir/dist/agent/opencode-native.js" 2>/dev/null; then
    rewrite="rewrite present (plugin will break Kiro)"
  else
    rewrite="no hook-payload rewrite (fixed)"
  fi
  printf '  %-8s %s\n           %s\n' "$version" "$pkg" "$rewrite"
  found=1
done < <(find "$HOME" -path '*/node_modules/billion-context/package.json' -not -path '*/.cache/*' 2>/dev/null | sort -u)
[[ $found -eq 0 ]] && echo "  (none found)"

echo
echo "== upstream tracking =="
for url in \
  "https://github.com/ranxianglei/billion-context/pull/5626" \
  "https://github.com/ranxianglei/billion-context/issues/5625" \
  "https://github.com/ranxianglei/billion-context/issues/7295" \
  "https://github.com/Servoy/opencode-kiro-auth/pull/5" \
  "https://github.com/tickernelz/opencode-kiro-auth/issues/133"; do
  printf '  %-70s ' "$url"
  if command -v gh >/dev/null 2>&1; then
    case "$url" in
      */pull/*) gh pr view "$url" --json state,mergeable --jq '"pr state=\(.state) mergeable=\(.mergeable)"' 2>/dev/null || echo "?" ;;
      *)       gh issue view "$url" --json state --jq '"issue state=\(.state)"' 2>/dev/null || echo "?" ;;
    esac
  else
    echo "(gh not installed)"
  fi
done

echo
echo "== local plugin state =="
PLUGIN_DIR="${OPENCODE_PLUGIN_DIR:-$HOME/.config/opencode/plugins}"
if [[ -f "$PLUGIN_DIR/kiro-proxy-compat.js" ]]; then
  echo "  installed: $PLUGIN_DIR/kiro-proxy-compat.js"
  shasum -a 256 "$PLUGIN_DIR/kiro-proxy-compat.js" | sed 's/^/  sha256:   /'
else
  echo "  not installed"
fi

LOG=/tmp/kiro-proxy-compat.log
if [[ -f "$LOG" ]]; then
  echo
  echo "== last compat-log lines =="
  tail -3 "$LOG" | sed 's/^/  /'
fi
