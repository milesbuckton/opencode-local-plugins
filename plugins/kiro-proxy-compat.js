/**
 * kiro-proxy-compat
 *
 * Fixes the Kiro provider (@servoy/opencode-kiro-auth) failing to respond when the
 * billion-context plugin is active.
 *
 * How the failure happens:
 *
 *   1. The Kiro plugin registers a scoped session `http.response` hook and only handles a
 *      request when the URL matches its Kiro API pattern:
 *
 *        /^(https?:\/\/)?(q\.[a-z0-9-]+\.amazonaws\.com|runtime\.[a-z0-9-]+\.kiro\.dev)/
 *
 *   2. The billion-context plugin registers an UNSCOPED session `http.request` hook that
 *      rewrites every "model API" URL to `<bili-proxy>/bili/<original-url>`. Because the
 *      opencode host passes the (already rewritten) request to the `http.response` hook,
 *      the Kiro plugin no longer recognises its own request and bails out.
 *
 *   3. The raw OpenAI-shaped POST then reaches https://q.us-east-1.amazonaws.com/chat/completions,
 *      which answers HTTP 200 with a coral `UnknownOperationException` body. The AI SDK sees
 *      no SSE completion event, so opencode reports "upstream stream ended before a completion
 *      event" - surfaced in the UI as an empty assistant message and "Step interrupted".
 *
 * What this plugin does:
 *
 *   It repairs the request URL at `http.request` time, i.e. before the response hook runs:
 *
 *   1. unwrap billion-context's `<proxy>/bili/<url>` form back to the original upstream URL
 *   2. neutralise the path on the same host (e.g. /chat/completions -> /__kiro_openai_compat__)
 *      so billion-context does not treat the request as a generic model API call again
 *      (it matches on the path suffix, and the host name is all the Kiro plugin looks at)
 *
 *   The Kiro plugin still matches the host, so it replaces the response with its real
 *   streaming Kiro response, and the request works.
 *
 * Only requests for the `kiro` provider are touched; every other provider keeps flowing
 * through the billion-context proxy unchanged.
 */

import { appendFileSync, statSync } from "node:fs"

const KIRO_HOST = /^(?:q\.[a-z0-9-]+\.amazonaws\.com|runtime\.[a-z0-9-]+\.kiro\.dev)$/i
const BILI_PROXY_FORM = /^https?:\/\/[^/]+\/bili\/(?:responses\/)?(https?:\/\/.+)$/i
const MODEL_API_PATH = /(?:^|\/)(?:v\d+\/)?(?:messages|chat\/completions|completions|responses|conversations)\/?$/i
const NEUTRAL_PATH = "/__kiro_openai_compat__"
const LOG_FILE = "/tmp/kiro-proxy-compat.log"
const LOG_MAX_BYTES = 512 * 1024

function log(message) {
  try {
    if (statSync(LOG_FILE).size > LOG_MAX_BYTES) appendFileSync(LOG_FILE, "")
    appendFileSync(LOG_FILE, `${new Date().toISOString()} ${message}\n`)
  } catch {}
}

export default {
  id: "kiro-proxy-compat",
  setup: async (ctx) => {
    const registration = await ctx.session.hook(
      "http.request",
      async (event) => {
        const request = event?.request
        if (!request || typeof request.url !== "string") return

        let url = request.url
        const proxied = BILI_PROXY_FORM.exec(url)
        if (proxied) url = proxied[1]

        let parsed
        try {
          parsed = new URL(url)
        } catch {
          return
        }
        if (!KIRO_HOST.test(parsed.hostname)) return

        if (MODEL_API_PATH.test(parsed.pathname)) parsed.pathname = NEUTRAL_PATH

        const target = parsed.toString()
        if (target === request.url) return

        try {
          event.request = new Request(target, request)
        } catch (error) {
          log(`could not rewrite ${request.url}: ${error instanceof Error ? error.message : String(error)}`)
          return
        }
        log(`rewrote ${request.url} -> ${target}`)
      },
      { providerID: "kiro" },
    )

    log(`hook registered: ${registration ? "ok" : "no-op"}`)
    return async () => {}
  },
}
