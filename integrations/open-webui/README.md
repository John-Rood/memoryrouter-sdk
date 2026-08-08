# MemoryRouter × Open WebUI

Upload your Open WebUI conversation history to MemoryRouter so your AI remembers everything from day one.

## How It Works

**Two-part integration:**

1. **Provider connection** — Add `https://api.memoryrouter.ai/v1` as an OpenAI-compatible connection in Open WebUI. Memory injection and storage happens automatically on every conversation. Zero code.

2. **Upload plugin** (this file) — One-click upload of your entire chat history so your AI has memory from day one, not just from when you connected.

## Setup

### Step 1: Connect MemoryRouter as a Provider

1. Open WebUI → ⚙️ Admin Settings → Connections → OpenAI
2. Click ➕ **Add Connection**
3. URL: `https://api.memoryrouter.ai/v1`
4. API Key: Your MemoryRouter key (`mk_xxx`)
5. Save

Your AI now has persistent memory on every new conversation.

### Step 2: Upload Existing History

1. Open WebUI → Admin → Functions → **Add Function**
2. Paste the contents of `memoryrouter_upload.py`
3. In the function's **Valves** (settings), enter your `mk_xxx` API key
4. Enable the function globally or per-model
5. Click the **"Upload History to MemoryRouter"** button on any message

All your past conversations are now in your memory vault.

## Get Your API Key

Start a 14-day free trial at [memoryrouter.ai](https://memoryrouter.ai).

## What Gets Uploaded

- ✅ User messages
- ✅ Assistant messages  
- ✅ Timestamps (for temporal memory)
- ❌ System prompts (skipped)
- ❌ Messages under 20 characters (skipped)
- ❌ Tool calls / function results (skipped)

Messages over 8,000 characters are automatically chunked at natural boundaries.

## Technical Details

- Batches: 100 items per request, max 2MB, 150ms between batches
- Format: JSONL to `POST /v1/memory/upload`
- Auth: Bearer token (your `mk_xxx` key)
- Walks Open WebUI's message tree via `parentId` chain (active branch only)
