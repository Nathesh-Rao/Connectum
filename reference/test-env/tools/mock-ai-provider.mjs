// A stand-in AI provider for the mobile app's automated tests: an OpenAI-compatible address that answers a canned summary, or any error class on demand, so every state of
// the AI summary can be tested without a real key, a real credit balance or a real provider.
//
//   node tools/mobile-test/mock-ai-provider.mjs --port 9777 [--key some-test-key]
//
// Make an agent that uses it (Admin console > AI agents, or `admin.ai.save` over the socket):
//   provider: "custom", baseUrl: "http://<where the mock runs>:9777", key: any text of 8 to 400 characters (the mock checks it only when started with --key), model: any name, alias: e.g. "mock"
// The Connectum server calls `<baseUrl>/chat/completions`. A private address (127.0.0.1, 10.x) is refused unless the server runs with CONNECTUM_API_ALLOW_PRIVATE=1.
//
// WHAT IT ANSWERS depends on a marker anywhere in the LAST user message (the question or the text sent with it); no marker gives the canned answer:
//   [mock:ok]        200, the canned summary (the default)
//   [mock:slow]      200 after 5 s
//   [mock:empty]     200 with an empty answer (the app says it could not answer)
//   [mock:bad_key]   401, the key is refused           -> class bad_key
//   [mock:no_credit] 402, no credit left               -> class no_credit
//   [mock:rate]      429, the provider's own limit     -> class rate
//   [mock:model]     404, model not available          -> class model
//   [mock:too_large] 413                               -> class too_large
//   [mock:busy]      503, provider down                -> class busy
//   [mock:bad]       400, request refused              -> class bad
//   [mock:timeout]   no answer for 30 s (the server gives up at 20 s) -> upstream_timeout
// The class names are those of chat-app/features/connectumChat/services/assistantErrors.js. Errors of Connectum's own server (rate_limited, no_agent, no_access, not_found,
// too_large over 200 KB) need no mock: see docs/MOBILE_TEST_ENVIRONMENT.md.
import http from "node:http";
import { pathToFileURL } from "node:url";

export const CANNED = "Mock summary (canned): the team agreed to ship the report on Friday. Still open: the numbers from finance. Action: Asha confirms by 3 pm.";
const ERRORS = {
    bad_key: [401, { error: { message: "Incorrect API key provided.", type: "invalid_request_error", code: "invalid_api_key" } }],
    no_credit: [402, { error: { message: "You exceeded your current quota, please check your plan and billing details.", type: "insufficient_quota", code: "insufficient_quota" } }],
    rate: [429, { error: { message: "Rate limit reached for requests. Please try again in 20s.", type: "requests", code: "rate_limit_exceeded" } }],
    model: [404, { error: { message: "The model `mock-model` does not exist or you do not have access to it.", type: "invalid_request_error", code: "model_not_found" } }],
    too_large: [413, { error: { message: "Request too large.", type: "invalid_request_error" } }],
    busy: [503, { error: { message: "The server is overloaded or not ready yet.", type: "server_error" } }],
    bad: [400, { error: { message: "Bad request (mock).", type: "invalid_request_error" } }],
};
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// the text of the last message that is not the assistant's, whatever shape the content has (a text, or a list of parts)
function lastUserText(body) {
    const messages = Array.isArray(body?.messages) ? body.messages : [];
    for (let i = messages.length - 1; i >= 0; i -= 1) {
        const m = messages[i];
        if (m?.role === "assistant") continue;
        const c = m?.content;
        return typeof c === "string" ? c : Array.isArray(c) ? c.map((p) => (typeof p === "string" ? p : p?.text || "")).join(" ") : "";
    }
    return "";
}

export function startMockProvider({ port = 0, key = "" } = {}) {
    const seen = [];
    const server = http.createServer((req, res) => {
        let raw = "";
        req.on("data", (c) => { raw += c; if (raw.length > 5_000_000) req.destroy(); });
        req.on("end", async () => {
            const send = (status, obj) => { res.writeHead(status, { "content-type": "application/json" }); res.end(JSON.stringify(obj)); };
            let body = null;
            try { body = JSON.parse(raw); } catch { /* answered below */ }
            seen.push({ url: req.url, auth: req.headers.authorization || "", body });
            if (req.method !== "POST" || !/\/chat\/completions$/.test(req.url)) return send(404, { error: { message: "no such route (the mock serves POST /chat/completions)" } });
            if (key && req.headers.authorization !== `Bearer ${key}`) return send(...ERRORS.bad_key.slice(0, 2));
            if (!body) return send(...ERRORS.bad);
            const text = lastUserText(body);
            const marker = /\[mock:([a-z_]+)\]/.exec(text)?.[1] || "ok";
            if (ERRORS[marker]) return send(...ERRORS[marker]);
            if (marker === "timeout") { await sleep(30000); return send(200, { choices: [{ message: { role: "assistant", content: CANNED } }] }); }
            if (marker === "slow") await sleep(5000);
            const content = marker === "empty" ? "" : CANNED;
            return send(200, { id: "mock-1", object: "chat.completion", model: body.model || "mock-model", choices: [{ index: 0, message: { role: "assistant", content }, finish_reason: "stop" }], usage: { prompt_tokens: 1, completion_tokens: 1, total_tokens: 2 } });
        });
    });
    return new Promise((resolve) => server.listen(port, "0.0.0.0", () => resolve({ server, port: server.address().port, seen, close: () => new Promise((r) => { server.closeAllConnections?.(); server.close(r); }) })));
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
    const a = process.argv.slice(2);
    const get = (n, d) => (a.includes(n) ? a[a.indexOf(n) + 1] : d);
    const m = await startMockProvider({ port: Number(get("--port", 9777)), key: get("--key", "") });
    console.log(`mock AI provider on port ${m.port}${get("--key", "") ? " (checks the key)" : ""}: POST /chat/completions; add [mock:<class>] to the question for an error (see the top of this file)`);
}
