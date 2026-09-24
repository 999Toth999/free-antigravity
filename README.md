<div align="center">
  <img src="https://raw.githubusercontent.com/999Toth999/free-antigravity/main/docs/banner.png" alt="free-antigravity — Antigravity CLI with OpenCode Zen free models" width="800">
</div>

<h1 align="center">free-antigravity</h1>

<p align="center">
  <b>Use the Antigravity CLI (<code>agy</code>) with <b>OpenCode Zen free models</b> — no paid key, no account, one command.</b>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-Linux%20%7C%20macOS-blue" alt="Platform">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="License">
  <img src="https://img.shields.io/badge/node-%3E%3D18-brightgreen" alt="Node.js >= 18">
</p>

<p align="center">
  Free AI models · OpenAI-compatible REST API · Local proxy adapter · OpenCode Zen free tier · CLI tutorial · Installation script
</p>

---

**free-antigravity** connects the official **Google Antigravity CLI** (`agy`) to the **OpenCode Zen free tier** through a tiny local adapter. It gives you **free AI coding models** (`big-pickle`, `mimo-v2.5-free`, `nemotron-3.5-lightning-free`) with a **plain OpenAI-compatible API** — perfect for AI agents, LLM gateways, and open-source tooling.

**No API key. No credits. No subscription.** Just a `bash install.sh` that does everything automatically.

---

## Table of Contents

- [Features](#features)
- [Quick Start](#quick-start)
- [What it does](#what-it-does)
- [How it works](#how-it-works)
- [Free models](#free-models)
- [Test the adapter directly](#test-the-adapter-directly)
- [Prerequisites](#prerequisites)
- [Directory layout](#directory-layout)
- [Configuration](#configuration)
- [Troubleshooting](#troubleshooting)
- [FAQ](#faq)
- [Related projects](#related-projects)
- [License](#license)

---

## Features

| Feature | Description |
|---|---|
| ⚡ **One-command setup** | `install.sh` installs Node.js, OpenCode CLI, Antigravity CLI, `free-antigravity-cli` and wires everything |
| 🆓 **Free models** | Uses the OpenCode Zen free tier — no paid key, no credits |
| 🔌 **OpenAI-compatible API** | `POST /v1/chat/completions` on `127.0.0.1:4011`; drop-in for OpenAI SDK clients |
| 🤖 **Tool calling ready** | Injects the `shell` + `read` tools that the free-tier gate requires |
| 🚀 **Autostart** | systemd user service (auto-start on login) or background fallback |
| 🌍 **Cross-platform** | Linux and macOS (Windows via WSL2 / Git Bash) |
| 🔧 **Configurable** | `ZEN_PORT`, `ZEN_BASE_URL`, `ZEN_USER_AGENT` env vars |

---

## Quick Start

```bash
git clone https://github.com/999Toth999/free-antigravity.git
cd free-antigravity
bash install.sh
free-antigravity
```

Then select a **"Zen Free: ..."** model from the model picker:

- **Zen Free: big-pickle** (default / best)
- **Zen Free: Mimo V2.5**
- **Zen Free: Nemotron 3.5 Lightning**

---

## What it does

| Step | Command (run automatically) |
|---|---|
| Install Node.js ≥ 18 | via distro/brew package manager |
| Install OpenCode CLI | `curl -fsSL https://opencode.ai/install \| bash` |
| Install official Antigravity CLI | `curl -fsSL https://antigravity.google/cli/install.sh \| bash` |
| Install `free-antigravity-cli` | `npm install -g free-antigravity-cli` |
| Install adapter + models | copies `server.js` and merges `models.json` into `~/.free-antigravity/` |
| Start adapter | systemd user service (auto-start on login) or background fallback |

---

## How it works

The official Antigravity CLI talks to Google Cloud Code endpoints. [`free-antigravity-cli`](https://www.npmjs.com/package/free-antigravity-cli) patches `agy` to route through a local proxy and injects your **custom models** into the model list. Those custom models point to `http://127.0.0.1:4011`, where `server.js` proxies to the **OpenCode Zen free tier**.

To pass the free-tier gate, the adapter injects the exact request **fingerprint** that OpenCode validates server-side:

```
User-Agent: opencode/1.18.31 ai-sdk/provider-utils/4.0.40 runtime/bun/1.3.14
x-opencode-client: cli
x-opencode-project: global
x-opencode-session: ses_<12 hex><14 base62>        # structurally valid
x-opencode-request: msg_<12 hex><14 base62>         # structurally valid
x-client-request-id: <same session id>
Authorization: Bearer public                         # anonymous free tier
stream: true
tools: [{shell}, {read}]                             # required by the gate
```

Without **all** of the above, Zen returns `403 "free tier can only be used from within OpenCode"`; missing tools also produce 403; a wrong model name (e.g. `opencode/big-pickle`) returns `401`.

> The fingerprint logic is based on the real OpenCode client identity observed from the `pi-opencode-direct` npm package; it is transparent and configurable through the `ZEN_*` environment variables.

---

## Free models

| Name in selector | Model ID | Reliability |
|---|---|---|
| **Zen Free: big-pickle** | `big-pickle` | ✅ Most stable / recommended |
| **Zen Free: Mimo V2.5** | `mimo-v2.5-free` | ✅ Stable |
| **Zen Free: Nemotron 3.5 Lightning** | `nemotron-3.5-lightning-free` | ⚠️ Intermittent (per-IP rate limits) |

> The free model list may change over time. Use the **bare** model name (`big-pickle`) — prepending `opencode/` returns `401 Model not supported`.

---

## Test the adapter directly

```bash
curl http://127.0.0.1:4011/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"big-pickle","messages":[{"role":"user","content":"hello"}],"stream":true}'
```

Health check: `curl http://127.0.0.1:4011/healthz`

Or use an OpenAI SDK:

```python
from openai import OpenAI
client = OpenAI(base_url="http://127.0.0.1:4011/v1", api_key="none")
r = client.chat.completions.create(model="big-pickle", messages=[{"role":"user","content":"hi"}])
print(r.choices[0].message.content)
```

```js
const OpenAI = require("openai");
const client = new OpenAI({ baseURL: "http://127.0.0.1:4011/v1", apiKey: "none" });
const r = await client.chat.completions.create({ model: "big-pickle", messages: [{ role: "user", content: "hi" }] });
console.log(r.choices[0].message.content);
```

---

## Prerequisites

- **Linux** or **macOS** (Windows: run inside WSL2 / Git Bash).
- **Node.js ≥ 18** (auto-installed by `install.sh`).
- **Google sign-in is required by the official Antigravity CLI** (it reuses the desktop app's auth). The zen-free models themselves need **no paid key**.

---

## Directory layout

```
~/.free-antigravity/
├── models.json        # your model list (merges existing ones)
└── zen-adapter/
    ├── server.js      # the fingerprint adapter
    └── adapter.log    # adapter logs
```

---

## Configuration

The adapter reads these environment variables:

| Variable | Default | Description |
|---|---|---|
| `ZEN_PORT` | `4011` | Local port the adapter listens on |
| `ZEN_BASE_URL` | `https://opencode.ai/zen/v1/chat/completions` | Upstream Zen endpoint |
| `ZEN_USER_AGENT` | opencode client identity | Overrides the injected User-Agent |

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `403` from upstream | The fingerprint changed — inspect `~/.free-antigravity/zen-adapter/adapter.log` and adjust `ZEN_USER_AGENT` or `ZEN_BASE_URL` |
| `401 Model not supported` | Use the bare model name (`big-pickle`), not `opencode/big-pickle` |
| Adapter not reachable | `bash ~/.free-antigravity/zen-adapter/start.sh` or `systemctl --user status free-antigravity-adapter` |
| `429` / connection reset | Per-IP rate limiting on the free tier — wait and retry, or switch to `big-pickle` |

---

## FAQ

**Is this free?**
Yes. The OpenCode Zen free tier serves the models anonymously (`Bearer public`). No API key, no credits, no subscription.

**Do I need an OpenCode account?**
No. The adapter uses the anonymous free tier identity.

**Do I need a Google account?**
Only the official Antigravity **CLI** needs a sign-in (it reuses desktop app auth). The free models themselves do not.

**Why does the adapter inject custom headers?**
OpenCode validates an exact client "fingerprint" server-side before serving the free tier. The adapter reproduces that identity automatically so plain OpenAI-compatible requests work.

**Can I use it as a REST API for my own agents?**
Yes — it is a standard OpenAI-compatible endpoint on `127.0.0.1:4011`.

**Which model is best?**
`big-pickle` is the most reliable on the current free tier.

**Is this stable for production?**
The free tier has per-IP rate limits; it's designed for lightweight / development / agentic use, not high-throughput production traffic.

---

## Related projects

- [`free-antigravity-cli`](https://www.npmjs.com/package/free-antigravity-cli) — the npm CLI this project wires up
- [OpenCode](https://opencode.ai) — the open-source AI coding agent that provides the Zen free tier
- [Antigravity](https://antigravity.google) — Google's official CLI (agy)

---

## License

[MIT](./LICENSE)