#!/usr/bin/env node
/**
 * free-antigravity zen-free adapter
 *
 * Exposes a local OpenAI-compatible endpoint (default 127.0.0.1:4011) that
 * proxies to the OpenCode Zen free tier (https://opencode.ai/zen/v1) injecting
 * the exact "fingerprint" the free-tier gate expects:
 *
 *   - User-Agent / x-opencode-client / x-opencode-project
 *   - structurally valid x-opencode-session / x-opencode-request / x-client-request-id
 *   - stream: true
 *   - tools containing shell (+ optionally bash) and read
 *
 * Without all of these the gate returns 403 "free tier can only be used from
 * within OpenCode"; with tools missing it also 403s. Models the free tier
 * currently serves: big-pickle, mimo-v2.5-free, nemotron-3.5-lightning-free
 * (do NOT prefix them with "opencode/" — that returns 401).
 *
 * Config via env vars:
 *   ZEN_PORT        port to listen on (default 4011)
 *   ZEN_BASE_URL    upstream (default https://opencode.ai/zen/v1/chat/completions)
 *   ZEN_USER_AGENT  override the injected User-Agent
 */
const http = require("http");
const { randomBytes, randomUUID } = require("crypto");

const PORT = Number(process.env.ZEN_PORT || 4011);
const ZEN_URL = process.env.ZEN_BASE_URL || "https://opencode.ai/zen/v1/chat/completions";

const BASE62 = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";
function b62(length) {
  let out = "";
  for (let i = 0; i < length; i++) out += BASE62[randomBytes(1)[0] % 62];
  return out;
}
function zenId(prefix) {
  return `${prefix}${randomBytes(6).toString("hex")}${b62(14)}`;
}

const DEFAULT_UA = "opencode/1.18.31 ai-sdk/provider-utils/4.0.40 runtime/bun/1.3.14 pi-opencode-direct/0.1.7";
const UA = process.env.ZEN_USER_AGENT || DEFAULT_UA;

const REQUIRED_TOOLS = [
  { type: "function", function: { name: "shell", description: "Run a shell command", parameters: { type: "object", properties: { command: { type: "string" } }, required: ["command"] } } },
  { type: "function", function: { name: "read", description: "Read a file", parameters: { type: "object", properties: { path: { type: "string" } }, required: ["path"] } } },
];

function mergeTools(body) {
  const existing = Array.isArray(body.tools) ? body.tools : [];
  const names = new Set(existing.filter((t) => t?.function?.name).map((t) => t.function.name));
  if (names.has("shell") || names.has("bash")) {
    return existing.length ? existing : REQUIRED_TOOLS;
  }
  return [...existing, ...REQUIRED_TOOLS.filter((t) => !names.has(t.function.name))];
}

function zenRequest(body) {
  const session = zenId("ses_");
  const headers = {
    "Content-Type": "application/json",
    "Authorization": "Bearer public",
    "User-Agent": UA,
    "x-opencode-client": "cli",
    "x-opencode-project": "global",
    "x-opencode-session": session,
    "x-opencode-request": zenId("msg_"),
    "x-client-request-id": session,
    "Accept": "text/event-stream",
  };
  const cleanModel = String(body.model || "big-pickle").replace(/^opencode\//, "");
  const payload = {
    ...body,
    model: cleanModel,
    stream: true,
    tools: mergeTools(body),
  };
  return { headers, payload, session };
}

function collectSse(text) {
  let content = "";
  for (const line of text.split(/\r?\n/)) {
    const l = line.trim();
    if (!l.startsWith("data:")) continue;
    const d = l.slice(5).trim();
    if (d === "[DONE]") break;
    try {
      const chunk = JSON.parse(d);
      const delta = chunk.choices?.[0]?.delta || {};
      for (const k of Object.keys(delta)) {
        if (typeof delta[k] === "string" && k.toLowerCase().includes("content")) content += delta[k];
      }
    } catch {}
  }
  return content;
}

const server = http.createServer(async (req, res) => {
  const url = req.url || "/";
  if (url === "/healthz" || url === "/") {
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ status: "ok", target: ZEN_URL, models: ["big-pickle", "mimo-v2.5-free", "nemotron-3.5-lightning-free"] }));
    return;
  }
  if (req.method === "GET") {
    res.writeHead(404, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: "not found" }));
    return;
  }

  let raw = "";
  for await (const chunk of req) raw += chunk;
  let body;
  try {
    body = JSON.parse(raw);
  } catch {
    res.writeHead(400, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: "invalid json" }));
    return;
  }

  const clientWantsStream = body.stream === true;
  const { headers, payload, session } = zenRequest(body);

  try {
    const upstream = await fetch(ZEN_URL, { method: "POST", headers, body: JSON.stringify(payload) });
    const text = await upstream.text();

    if (upstream.status !== 200) {
      res.writeHead(upstream.status, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ error: { type: "upstream", status: upstream.status, message: text.slice(0, 400) } }));
      return;
    }

    if (clientWantsStream) {
      res.writeHead(200, { "Content-Type": "text/event-stream", "Cache-Control": "no-cache", Connection: "keep-alive" });
      res.write(text);
      res.end();
      return;
    }

    const content = collectSse(text);
    const completion = {
      id: "chatcmpl-zen-" + randomUUID().slice(0, 8),
      object: "chat.completion",
      created: Math.floor(Date.now() / 1000),
      model: payload.model,
      choices: [{ index: 0, message: { role: "assistant", content: content || null }, finish_reason: "stop" }],
      usage: { prompt_tokens: 0, completion_tokens: 0, total_tokens: 0 },
    };
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify(completion));
  } catch (err) {
    res.writeHead(502, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: { message: "upstream error: " + err.message } }));
  }
});

server.listen(PORT, "127.0.0.1", () => {
  console.log(`[free-antigravity] zen-free adapter listening on 127.0.0.1:${PORT} -> ${ZEN_URL}`);
  if (process.env.ZEN_USER_AGENT) console.log(`[free-antigravity] custom User-Agent: ${UA}`);
});