---
name: llm-apis
description: "Credentials and call patterns for external LLM APIs — OpenAI (GPT-5.x, codex), xAI Grok, Google Gemini via Vertex AI, z.ai GLM, OpenRouter. Load before calling any foreign model: oracle question, review panel, benchmark, smoke test."
---

# External LLM APIs — router

**Read only the file you actually need.** Each one has the key, endpoint, model list, pricing,
curl and Python patterns, and the known traps.

⚠️ In the public `one-rulebook` export the `references/` directory is absent — those files carry
credentials and live git-crypt-encrypted in the private source. Keep your own
`references/<provider>.md` next to this file, one per provider, with the key, the endpoint, the
model ids you use, and the traps you paid for.

| You need | Read |
|---|---|
| OpenAI — GPT-5.6-sol/terra/luna, gpt-5.3-codex, true pro models, Responses vs Chat API | `references/openai.md` |
| xAI Grok — grok-build-0.1, grok-4.5, grok-code-fast-1, code-review benchmark | `references/xai-grok.md` |
| Google Gemini — Vertex AI OAuth2, regional vs global endpoint | `references/gemini-vertex.md` |
| z.ai / Zhipu GLM — glm-5.2, thinking toggle | `references/zai-glm.md` |
| OpenRouter — MiniMax M3 and 200+ models from other providers | `references/openrouter.md` |

## Cross-cutting rules — don't wait to discover these in a reference file

- 🛡️ **Cloudflare blocks the UA string `Python-urllib`, not a missing UA.** `urllib` inserts it
  by itself, so every Python script hitting `api.x.ai`, Groq or your own Cloudflare-fronted hosts must set a
  browser-like `User-Agent` or get HTTP 403 / error 1010. `curl` passes. Enforced by the
  `grok-user-agent.sh` hook.
- 🌐 **Gemini via Vertex AI; AI Studio is an emergency fallback** (AI Studio has outages).
  Preview / 3.x models answer on the **global** endpoint; the regional one returns 404. The
  `gemini-vertex-only.sh` hook warns about an AI Studio call, it does not block it.
- 💸 **Pro models are opt-in.** The review default is `gpt-5.6-sol` over the Codex CLI (on the
  subscription; CLAUDE.md "Which model reviews", since 20.7.2026) — `gpt-5.3-codex` (~$0.12) is
  the cheap parallel slot in an audit panel and the tool-less optic. True pro `gpt-5.5-pro`
  (~$1.53) and `gpt-6-astra` on explicit request alone. A week of careless pro-model use once
  cost ~$70.
- 🔑 **Never put secrets in a prompt.** The `check-secrets-in-llm.sh` hook matches patterns, not
  everything — sanitize anyway (absolute paths, `.env`, tokens).
- 📏 **Don't skimp on `max_tokens`** — 16384+ for reasoning models; a truncated answer costs more
  than a long one. The parameter is named differently everywhere: `max_tokens` (xAI, OpenRouter,
  z.ai) · `max_completion_tokens` (OpenAI chat) · `max_output_tokens` (OpenAI Responses) ·
  `maxOutputTokens` (Vertex).
- ⏳ **Model lists rot.** Before relying on a specific ID, run a smoke test rather than trusting
  `GET /models` — presence in the list is no guarantee (xAI `grok-4.5` was listed while
  geo-blocked).
