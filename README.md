# MemoryRouter

**Persistent memory for any AI model.** One API that adds long-term memory to ChatGPT, Claude, Gemini, Grok, and 90+ other models.

🌐 [Homepage](https://memoryrouter.ai) · 📚 [Documentation](https://docs.memoryrouter.ai) · 🎮 [Dashboard](https://app.memoryrouter.ai/)

---

## mr-memory — OpenClaw Plugin

Using OpenClaw? Install the **mr-memory OpenClaw plugin** in one command:

```bash
openclaw plugins install mr-memory
openclaw mr <your-memory-key>   # Get a key at memoryrouter.ai
```

Your agent gets persistent semantic memory that survives compaction, session resets, and restarts. Every conversation builds on the last one — automatically.

- **One command install** — `openclaw plugins install mr-memory`
- **Full fidelity recall** — stores raw conversations, not lossy summaries
- **Continuous** — injects relevant context on every message, not just session start
- **BYOK** — your provider API keys never leave OpenClaw
- **50M tokens free** — no credit card required

---

## API — Direct Integration

Not using OpenClaw? Use the API directly with any app or framework.

### 1. Get your Memory Key

Sign up at [memoryrouter.ai](https://memoryrouter.ai) and grab your memory key from the dashboard.

### 2. Make a request

```bash
curl https://api.memoryrouter.ai/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_MEMORY_KEY" \
  -d '{
    "model": "openai/gpt-4o",
    "messages": [{"role": "user", "content": "Remember that my favorite color is blue."}]
  }'
```

### 3. It remembers

```bash
curl https://api.memoryrouter.ai/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_MEMORY_KEY" \
  -d '{
    "model": "openai/gpt-4o",
    "messages": [{"role": "user", "content": "What is my favorite color?"}]
  }'
```

The AI now remembers your favorite color is blue — across sessions, devices, and even different models.

---

## Features

- **Drop-in replacement** — Works with your existing code, just change the base URL
- **Works with any model** — OpenAI, Anthropic, Google, xAI (90+ models)
- **Automatic memory** — No manual embedding or retrieval code
- **Cross-model memory** — Start with GPT, continue with Claude
- **Bring your own keys** — Use your existing API keys, we just add memory

---

## Supported Providers

| Provider | Prefix | Example Models |
|----------|--------|----------------|
| OpenAI | `openai/` | gpt-4o, gpt-4-turbo, o1, o3 |
| Anthropic | `anthropic/` | claude-sonnet-4, claude-opus-4 |
| Google | `google/` | gemini-2.0-flash, gemini-2.5-pro |
| xAI | `x-ai/` | grok-2, grok-3 |

See the [full model list](https://docs.memoryrouter.ai/api-reference#supported-models) in our docs.

---

## Use Cases

- **AI Assistants** — Build assistants that remember user preferences
- **Customer Support** — Bots that know customer history
- **Personal AI** — Apps that learn and adapt over time
- **Multi-session Apps** — Maintain context across conversations
- **OpenClaw Agents** — Install the **mr-memory OpenClaw plugin** for persistent agent memory

---

## Links

- 🌐 **Website:** [memoryrouter.ai](https://memoryrouter.ai)
- 📚 **Docs:** [docs.memoryrouter.ai](https://docs.memoryrouter.ai)
- 🎮 **Dashboard:** [memoryrouter.ai/dashboard](https://memoryrouter.ai/dashboard)
- 📧 **Support:** john@memoryrouter.ai

---

## License

MIT
