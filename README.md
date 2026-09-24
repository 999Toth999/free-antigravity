# free-antigravity

Use the **official Antigravity CLI** (`agy`) with **OpenCode Zen free models** — fully automated setup, no paid keys, no account needed for the free models.

This repo contains:

- `install.sh` — one script that installs **everything** (Node.js, OpenCode CLI, official Antigravity CLI, `free-antigravity-cli`) and wires up the adapter + models.
- `server.js` — a small local adapter that speaks the exact "fingerprint" the OpenCode Zen free tier expects, so the free models respond over a plain OpenAI-compatible API.
- `models.json` — the three known free model entries, ready to drop into `~/.free-antigravity/`.
- `start.sh` — (re)starts the adapter when systemd is not available.

## Quick start

```bash
git clone https://github.com/djeliteglobal/free-antigravity.git
cd free-antigravity
bash install.sh
free-antigravity
```

Then pick a **"Zen Free: ..."** model in the selector.

## What it does

| Step | Command (run automatically) |
|---|---|
| Install Node.js ≥ 18 | via distro/brew package manager |
| Install OpenCode CLI | `curl -fsSL https://opencode.ai/install \| bash` |
| Install official Antigravity CLI | `curl -fsSL https://antigravity.google/cli/install.sh \| bash` |
| Install `free-antigravity-cli` | `npm install -g free-antigravity-cli` |
| Install adapter + models | copies `server.js` and merges `models.json` into `~/.free-antigravity/` |
| Start adapter | systemd user service (auto-start on login) or background fallback |

## How it works

The official Antigravity CLI talks to Google Cloud Code endpoints. `free-antigravity-cli` patches `agy` to route through a local proxy and injects your custom models into the model list. Those custom models point at `http://127.0.0.1:4011`, where `server.js` proxies to the **OpenCode Zen free tier**.

To pass the free-tier gate, the adapter injects the exact request fingerprint OpenCode checks server-side:

- `User-Agent`, `x-opencode-client: cli`, `x-opencode-project: global`
- structurally valid `x-opencode-session`, `x-opencode-request`, `x-client-request-id`
- `stream: true`
- tools declaring `shell` + `read`

Without **all** of those, Zen returns `403 "free tier can only be used from within OpenCode"`; missing tools also 403; a wrong (`opencode/<name>`) model name returns 401.

## Free models (Sept 2026)

| name in selector | model id | notes |
|---|---|---|
| **Zen Free: big-pickle** | `big-pickle` | the standard opencode free model |
| Zen Free: Mimo V2.5 | `mimo-v2.5-free` | also stable |
| Zen Free: Nemotron 3.5 Lightning | `nemotron-3.5-lightning-free` | intermittent (per-IP rate limits) |

The list may change; Zen currently serves these on the free tier without `opencode/` prefix.

## Test the adapter directly

```bash
curl http://127.0.0.1:4011/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"big-pickle","messages":[{"role":"user","content":"hi"}],"stream":true}'
```

Health check: `curl http://127.0.0.1:4011/healthz`

## Prerequisites / notes

- Linux or macOS (Windows: run inside WSL2 / Git Bash).
- Node.js ≥ 18 (auto-installed by `install.sh`).
- **Google sign-in is required by the official Antigravity CLI** (it reuses the desktop app's auth). The zen-free models themselves need no paid key.
- The free tier has per-IP rate limits; heavy multi-turn agent use may hit `429` / connection termination. `big-pickle` and `mimo-v2.5-free` are the most reliable.

## Layout

```
~/.free-antigravity/
├── models.json        # your model list (merges existing ones)
└── zen-adapter/
    ├── server.js      # the fingerprint adapter
    └── adapter.log    # adapter logs
```

## Troubleshooting

- **`403` from upstream** — the fingerprint changed (OpenCode updates it). Check `~/.free-antigravity/zen-adapter/adapter.log`. `server.js` honors `ZEN_USER_AGENT`, `ZEN_BASE_URL`, `ZEN_PORT` env vars if a fix is needed.
- **`401 Model not supported`** — use bare model names (`big-pickle`), **not** `opencode/big-pickle`.
- **Empty/adapter not reachable** — run `bash ~/.free-antigravity/zen-adapter/start.sh`, or check the systemd unit: `systemctl --user status free-antigravity-adapter`.

## License

MIT