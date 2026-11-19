#!/usr/bin/env bash
# Run OpenCode against the local antigravity-auth fork (Claude 4.6 routes,
# cortexkit/antigravity-auth#64) instead of the upstream npm package.
#
#   ./scripts/antigravity-fork.sh status    # active plugin, build state, agy catalog, #64 state
#   ./scripts/antigravity-fork.sh build     # build the fork with the pinned Bun
#   ./scripts/antigravity-fork.sh use       # build, then point OpenCode at the fork
#   ./scripts/antigravity-fork.sh update    # rebase the fork onto upstream, build, force-push
#   ./scripts/antigravity-fork.sh upstream  # point OpenCode back at the npm package
#
# Restart OpenCode after `use`, `update` or `upstream`.
set -euo pipefail

FORK="${ANTIGRAVITY_FORK_DIR:-$HOME/Developer/antigravity-auth}"
PLUGIN_PATH="$FORK/packages/opencode"
NPM_SPEC='@cortexkit/opencode-antigravity-auth'
UPSTREAM_URL='https://github.com/cortexkit/antigravity-auth.git'
CONFIG="${OPENCODE_CONFIG_FILE:-$HOME/.config/opencode/opencode.json}"
NPM_CACHE="$HOME/.cache/opencode/npm/$NPM_SPEC@latest"
ISSUE='https://github.com/cortexkit/antigravity-auth/issues/64'
# The fork's build refuses any Bun but this exact version.
BUN_VERSION='1.4.2'
BUN_HOME="${ANTIGRAVITY_BUN_HOME:-$HOME/.local/share/bun-$BUN_VERSION}"

bun_bin() {
  if [[ ! -x "$BUN_HOME/bin/bun" ]]; then
    echo "Installing Bun $BUN_VERSION into $BUN_HOME" >&2
    curl -fsSL https://bun.sh/install | BUN_INSTALL="$BUN_HOME" bash -s "bun-v$BUN_VERSION" >/dev/null
  fi
  echo "$BUN_HOME/bin/bun"
}

build() {
  local bun
  bun="$(bun_bin)"
  echo "Building $FORK with Bun $("$bun" --version)"
  (cd "$FORK" && PATH="$(dirname "$bun"):$PATH" bun install --frozen-lockfile >/dev/null && PATH="$(dirname "$bun"):$PATH" bun run build >/dev/null)
  echo "Built $PLUGIN_PATH/dist"
}

# Replace one plugin entry with another in opencode.json (plain JSON).
set_plugin() {
  local from="$1" to="$2"
  cp "$CONFIG" "$CONFIG.bak.antigravity-fork"
  python3 - "$CONFIG" "$from" "$to" <<'EOF'
import json, sys
path, old, new = sys.argv[1:]
config = json.load(open(path))
plugins = config.get('plugin', [])
if new in plugins:
    print(f'Already using {new}')
elif old in plugins:
    config['plugin'] = [new if p == old else p for p in plugins]
    with open(path, 'w') as f:
        json.dump(config, f, indent=2)
        f.write('\n')
    print(f'plugin: {old} -> {new}')
else:
    sys.exit(f'Neither {old} nor {new} is in {path} "plugin"; edit it by hand.')
EOF
}

active() {
  python3 -c 'import json,sys; print("\n".join(json.load(open(sys.argv[1])).get("plugin", [])))' "$CONFIG" |
    grep -E "antigravity-auth" || echo "(no antigravity plugin)"
}

case "${1:-status}" in
  build)
    build
    ;;
  use)
    build
    set_plugin "$NPM_SPEC" "$PLUGIN_PATH"
    rm -rf "$NPM_CACHE"
    echo "Restart OpenCode."
    ;;
  upstream)
    set_plugin "$PLUGIN_PATH" "$NPM_SPEC"
    echo "Restart OpenCode; it reinstalls the npm package."
    ;;
  update)
    cd "$FORK"
    [[ -z "$(git status --porcelain)" ]] || { echo "Fork has uncommitted changes; commit or stash first." >&2; exit 1; }
    git remote get-url upstream >/dev/null 2>&1 || git remote add upstream "$UPSTREAM_URL"
    git fetch -q upstream
    if ! git rebase upstream/main; then
      echo "Rebase stopped on a conflict. Resolve it, run 'git rebase --continue', then rerun update." >&2
      exit 1
    fi
    build
    git push --force-with-lease origin main
    echo "Restart OpenCode."
    ;;
  status)
    echo "== active plugin ($CONFIG) =="
    active | sed 's/^/  /'
    echo
    echo "== fork ($FORK) =="
    (cd "$FORK" && git log -1 --format='  %s (%ad)' --date=short)
    if [[ -f "$PLUGIN_PATH/dist/server.js" ]]; then
      echo "  dist built $(date -r "$PLUGIN_PATH/dist/server.js" '+%Y-%m-%d %H:%M')"
    else
      echo "  dist missing: run build"
    fi
    if (cd "$FORK" && { git remote get-url upstream >/dev/null 2>&1 || git remote add upstream "$UPSTREAM_URL"; } && git fetch -q upstream 2>/dev/null); then
      behind="$(cd "$FORK" && git rev-list --count HEAD..upstream/main)"
      echo "  $behind upstream commit(s) not in the fork (run update)"
    fi
    echo
    echo "== agy models (Antigravity CLI server catalog) =="
    agy="${AGY_BIN:-$(command -v agy || echo "$HOME/.local/bin/agy")}"
    if [[ -x "$agy" ]] && models="$("$agy" models 2>/dev/null)"; then
      listed=0
      for id in claude-sonnet-4-6 claude-opus-4-6-thinking; do
        if grep -q "^${id}[[:space:]]" <<<"$models"; then
          echo "  $id listed"
          listed=1
        else
          echo "  $id not listed"
        fi
      done
      if [[ $listed -eq 1 ]]; then
        echo "  4.6 is in the CLI catalog: comment on $ISSUE so upstream rechecks"
      fi
    else
      echo "  agy not found or 'agy models' failed (set AGY_BIN)"
    fi
    echo
    echo "== $ISSUE =="
    if command -v gh >/dev/null 2>&1; then
      gh issue view "$ISSUE" --json state,stateReason --jq '"  state=\(.state) reason=\(.stateReason)"' 2>/dev/null || echo "  ?"
    else
      echo "  (gh not installed)"
    fi
    ;;
  *)
    sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
    ;;
esac
