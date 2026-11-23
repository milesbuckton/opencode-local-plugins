# opencode-local-plugins

[![Lint](https://github.com/milesbuckton/opencode-local-plugins/actions/workflows/lint.yml/badge.svg)](https://github.com/milesbuckton/opencode-local-plugins/actions/workflows/lint.yml)

Local OpenCode plugins, config overrides and a plugin fork that work around
upstream problems, plus small helpers to keep them in sync and to check whether
the upstream fix has landed.

## kiro-proxy-compat

**Problem.** The `billion-context` OpenCode plugin rewrites every model request
URL to `<bili-proxy>/bili/<original-url>` inside its *unscoped* `http.request`
hook (`createNativeRoute` →
``replaceRequestTarget(e, `${target}/bili/${url}`)`` in
`dist/agent/opencode-native.js`). The `@servoy/opencode-kiro-auth` plugin then
inspects that rewritten URL in its `http.response` hook and rejects it, because
its pattern is anchored to the host:

```js
const KIRO_API_PATTERN = /^(https?:\/\/)?(q\.[a-z0-9-]+\.amazonaws\.com|runtime\.[a-z0-9-]+\.kiro\.dev)/
```

The proxy URL does not match, so Kiro never handles the request. The raw
`POST /chat/completions` then reaches AWS and returns
`{"Output":{"__type":"com.amazon.coral.service#UnknownOperationException",...}}`,
which OpenCode reports as *"upstream stream ended before a completion event"* and
finally as the silent `Step interrupted` (empty assistant message), followed by
a storm of retries against AWS.

**Fix.** This plugin registers a Kiro-scoped `http.request` hook that restores
the upstream URL before any other hook sees it. It only touches
`providerID: "kiro"` requests to Kiro hosts, and it rewrites the model path to a
neutral one so `billion-context` does not re-proxy it.

**Status / removal criteria.** Remove this plugin once the upstream fix is in a
released `billion-context` and the Kiro plugin is updated:

- billion-context PR
  [#5626](https://github.com/ranxianglei/billion-context/pull/5626), for issue
  [#5625](https://github.com/ranxianglei/billion-context/issues/5625). It reworks
  the reverted [#4280](https://github.com/ranxianglei/billion-context/pull/4280) / [#4276](https://github.com/ranxianglei/billion-context/issues/4276) and routes model traffic at fetch time, so provider
  plugins see the original URL.
- Kiro plugin PR [#5](https://github.com/Servoy/opencode-kiro-auth/pull/5)
  (handles rewritten URLs directly)
- Kiro plugin issue
  [tickernelz/opencode-kiro-auth#133](https://github.com/tickernelz/opencode-kiro-auth/issues/133)

Run `scripts/check-upstream.sh` to see the current state of both.

## billion-context rate limit governor bypass

**Problem.** Free models on the `opencode` provider return HTTP 429 with
`Retry-After: ~600`. `billion-context`'s default egress governor
(`network.throttle429Enabled: true`, introduced for
[#4204](https://github.com/ranxianglei/billion-context/issues/4204)) arms on the
first 429 and honours that `Retry-After`, holding the whole `opencode.ai`
credential (every session and model) for ~10 minutes
(`bili is holding outbound sends … zero egress while held`). The streak only
resets on a success, so 429s from separate sessions add up, and after 5 the hold
turns terminal (local 424, `resend manually`). Reported as
[anomalyco/opencode#64754](https://github.com/anomalyco/opencode/issues/64754)
before being traced to billion-context.

**Fix.** `configs/billion-context.json` sets
`"network": { "throttle429Enabled": false }` in
`~/.config/billion-context/billion-context.json`, so upstream 429s pass straight
through to OpenCode's own retry handling. The free tier is still rate-limited
upstream; this only removes the account-wide local hold and the terminal state.

**Status / removal criteria.** Remove once billion-context scopes free-tier 429
holds more narrowly and resets the streak:
[#7295](https://github.com/ranxianglei/billion-context/issues/7295) (related:
[#6639](https://github.com/ranxianglei/billion-context/issues/6639),
[#5853](https://github.com/ranxianglei/billion-context/issues/5853)).

## antigravity-auth fork (Claude 4.6)

**Problem.** Upstream `@cortexkit/opencode-antigravity-auth` retired
`claude-sonnet-4-6` and `claude-opus-4-6-thinking` because the agy CLI server
catalog no longer lists them, although Antigravity still serves them and the IDE
still offers them ([cortexkit/antigravity-auth#64](https://github.com/cortexkit/antigravity-auth/issues/64),
closed as not planned).

**Fix.** OpenCode loads the plugin from the local fork
[milesbuckton/antigravity-auth](https://github.com/milesbuckton/antigravity-auth)
(`~/Developer/antigravity-auth/packages/opencode`), which restores both routes.
OpenCode runs the fork's built `dist`, so rebuild after every change. The build
requires Bun 1.4.2 exactly; `scripts/antigravity-fork.sh` installs it into
`~/.local/share/bun-1.4.2` without touching the system Bun.

```bash
./scripts/antigravity-fork.sh status    # active plugin, build date, upstream lag, agy catalog, #64 state
./scripts/antigravity-fork.sh use       # build and switch OpenCode to the fork
./scripts/antigravity-fork.sh update    # rebase the fork onto upstream, build, force-push
./scripts/antigravity-fork.sh upstream  # switch back to the npm package
```

Restart OpenCode after `use`, `update` or `upstream`. Both switches back up
`opencode.json` to `opencode.json.bak.antigravity-fork`. Accounts and logins are
shared, so switching needs no new sign-in.

**Status / removal criteria.** Retire the fork once an upstream release lists the
4.6 routes again, or when Antigravity stops serving them. Run
`./scripts/antigravity-fork.sh status` to see the state of
cortexkit/antigravity-auth#64, whether `agy models` lists the 4.6 routes again
(upstream's condition for reopening #64), and how far the fork is behind
upstream.

## openchamber fork

Helper script to build, link, and update the local OpenChamber fork (`~/Developer/openchamber`).

```bash
./scripts/openchamber-fork.sh status         # fork commit date and CLI symlink status
./scripts/openchamber-fork.sh build          # build web and server packages
./scripts/openchamber-fork.sh build-desktop  # build electron desktop app and sync to /Applications
./scripts/openchamber-fork.sh use            # build web and symlink ~/.local/bin/openchamber -> packages/web/bin/cli.js
./scripts/openchamber-fork.sh update         # rebase onto upstream/main, rebuild web, force-push, restart daemon
```

## Scripts

| Script | Purpose |
| --- | --- |
| `scripts/install.sh` | Copy `plugins/*` to `~/.config/opencode/plugins/` and `configs/*` to `~/.config/billion-context/`. `--check` verifies installed copies match. |
| `scripts/antigravity-fork.sh` | Build the antigravity-auth fork with Bun 1.4.2, switch OpenCode between the fork and the npm package, rebase the fork onto upstream, and report #64. |
| `scripts/openchamber-fork.sh` | Build web/desktop, link CLI (`~/.local/bin/openchamber`), and rebase/update the local OpenChamber fork. |
| `scripts/check-upstream.sh` | Report the installed `billion-context` copies, whether the `/bili/` rewrite is still present, and the state of the tracked upstream issues/PRs. |

### Paths

The scripts default to the layout below. Override any path with its environment
variable.

| Variable | Default | Used by |
| --- | --- | --- |
| `OPENCODE_PLUGIN_DIR` | `~/.config/opencode/plugins` | `install.sh`, `check-upstream.sh` |
| `BILI_CONFIG_DIR` | `~/.config/billion-context` | `install.sh` |
| `OPENCODE_CONFIG_FILE` | `~/.config/opencode/opencode.json` | `antigravity-fork.sh` |
| `ANTIGRAVITY_FORK_DIR` | `~/Developer/antigravity-auth` | `antigravity-fork.sh` |
| `ANTIGRAVITY_BUN_HOME` | `~/.local/share/bun-1.4.2` | `antigravity-fork.sh` |
| `AGY_BIN` | `agy` on `PATH`, else `~/.local/bin/agy` | `antigravity-fork.sh` |
| `OPENCHAMBER_FORK_DIR` | `~/Developer/openchamber` | `openchamber-fork.sh` |
| `OPENCHAMBER_BIN_TARGET` | `~/.local/bin/openchamber` | `openchamber-fork.sh` |

For example, with the fork cloned elsewhere:

```bash
ANTIGRAVITY_FORK_DIR=~/src/antigravity-auth ./scripts/antigravity-fork.sh use
```

## Linting

CI runs [ShellCheck](https://www.shellcheck.net/) on `scripts/*.sh` and
[Biome](https://biomejs.dev/) on `plugins/`. To run the same checks locally:

```bash
shellcheck scripts/*.sh
npx @biomejs/biome@2.6.8 lint plugins
```

## Contributing

This is a personal repository and does not accept issues or pull requests. See
[docs/CONTRIBUTING.md](docs/CONTRIBUTING.md).

## License

[MIT](LICENSE)
