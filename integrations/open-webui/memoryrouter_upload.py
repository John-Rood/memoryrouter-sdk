"""
MemoryRouter Upload — Open WebUI Action Function

One-time backfill: upload your Open WebUI conversation history to
MemoryRouter so your AI remembers everything from day one.

After this, MemoryRouter's proxy handles new conversations automatically —
no need to upload again.

Setup:
  1. Add this function in Open WebUI (Admin → Functions → Add)
  2. Enter your MemoryRouter API key (mk_xxx) in the Valves settings
  3. Click the "Upload History to MemoryRouter" button on any message

Get your API key at https://memoryrouter.ai (14-day free trial)
"""

import asyncio
import json
import time
import aiohttp
from typing import Optional
from pydantic import BaseModel, Field


# ── Constants (match mr-memory upload.ts) ──────────────────────────

MAX_ITEM_CHARS = 8000
TARGET_CHUNK_CHARS = 4000
MAX_BATCH_BYTES = 2_000_000
MAX_BATCH_COUNT = 100
BATCH_SLEEP_S = 0.15
MIN_MESSAGE_CHARS = 20


# ── Helpers ────────────────────────────────────────────────────────


def chunk_text(text: str, target_chars: int = TARGET_CHUNK_CHARS) -> list[str]:
    """Split oversized text at natural boundaries."""
    chunks = []
    remaining = text

    while len(remaining) > target_chars:
        split_at = remaining.rfind("\n\n", 0, target_chars)
        if split_at < target_chars * 0.5:
            split_at = remaining.rfind("\n", 0, target_chars)
        if split_at < target_chars * 0.5:
            split_at = remaining.rfind(" ", 0, target_chars)
        if split_at < target_chars * 0.3:
            split_at = target_chars

        chunks.append(remaining[:split_at].strip())
        remaining = remaining[split_at:].strip()

    if remaining:
        chunks.append(remaining)

    return chunks


def extract_content(msg: dict) -> str:
    """Extract text from a message, handling string and content block arrays."""
    content = msg.get("content", "")
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "\n".join(
            block.get("text", "")
            for block in content
            if isinstance(block, dict) and block.get("type") == "text"
        )
    return ""


def walk_message_tree(messages_map: dict, current_id: str) -> list[dict]:
    """Walk from currentId up through parentId chain, then reverse for chronological order."""
    chain = []
    msg_id = current_id
    visited = set()

    while msg_id and msg_id in messages_map and msg_id not in visited:
        visited.add(msg_id)
        chain.append(messages_map[msg_id])
        msg_id = messages_map[msg_id].get("parentId")

    chain.reverse()
    return chain


def messages_to_upload_lines(messages: list[dict]) -> list[dict]:
    """Convert ordered messages to MemoryRouter JSONL upload format."""
    lines = []

    for msg in messages:
        role = msg.get("role", "")
        if role not in ("user", "assistant"):
            continue

        text = extract_content(msg).strip()
        if not text or len(text) < MIN_MESSAGE_CHARS:
            continue

        ts = msg.get("timestamp")
        if isinstance(ts, (int, float)):
            timestamp = int(ts * 1000) if ts < 1e12 else int(ts)
        else:
            timestamp = int(time.time() * 1000)

        if len(text) > MAX_ITEM_CHARS:
            for chunk in chunk_text(text, TARGET_CHUNK_CHARS):
                if len(chunk.strip()) >= MIN_MESSAGE_CHARS:
                    lines.append({
                        "content": chunk.strip(),
                        "role": role,
                        "timestamp": timestamp,
                    })
        else:
            lines.append({"content": text, "role": role, "timestamp": timestamp})

    return lines


def batch_lines(lines: list[dict]) -> list[list[dict]]:
    """Group upload lines into batches respecting size and count limits."""
    batches = []
    current_batch = []
    current_bytes = 0

    for line in lines:
        line_bytes = len(json.dumps(line)) + 1
        if current_bytes + line_bytes > MAX_BATCH_BYTES or len(current_batch) >= MAX_BATCH_COUNT:
            if current_batch:
                batches.append(current_batch)
            current_batch = [line]
            current_bytes = line_bytes
        else:
            current_batch.append(line)
            current_bytes += line_bytes

    if current_batch:
        batches.append(current_batch)

    return batches


# ── Open WebUI Action Function ─────────────────────────────────────


class Action:
    class Valves(BaseModel):
        memoryrouter_api_key: str = Field(
            default="",
            description="Your MemoryRouter API key (mk_xxx). Get one at memoryrouter.ai (14-day free trial)",
        )
        memoryrouter_endpoint: str = Field(
            default="https://api.memoryrouter.ai",
            description="MemoryRouter API endpoint",
        )
        history_uploaded: bool = Field(
            default=False,
            description="(Auto-set) Whether history has already been uploaded. Reset to false to re-upload.",
        )

    def __init__(self):
        self.valves = self.Valves()

    async def action(
        self,
        body: dict,
        __user__: Optional[dict] = None,
        __event_emitter__=None,
        __event_call__=None,
    ) -> Optional[dict]:
        """One-time upload of all conversation history to MemoryRouter."""

        # ── Validate config ──

        api_key = self.valves.memoryrouter_api_key.strip()
        if not api_key or not api_key.startswith("mk"):
            if __event_emitter__:
                await __event_emitter__(
                    {
                        "type": "status",
                        "data": {
                            "description": "❌ No MemoryRouter API key configured. Go to Function settings and enter your mk_xxx key.",
                            "done": True,
                        },
                    }
                )
            return

        endpoint = self.valves.memoryrouter_endpoint.rstrip("/")

        # ── Already uploaded? ──

        if self.valves.history_uploaded:
            if __event_call__:
                response = await __event_call__(
                    {
                        "type": "confirmation",
                        "data": {
                            "title": "History Already Uploaded",
                            "message": "Your conversation history has already been uploaded to MemoryRouter. New conversations are handled automatically by the proxy.\n\nDo you want to re-upload everything? (Only needed if you reset your memory.)",
                        },
                    }
                )
                if not response or (isinstance(response, str) and response.lower() in ("no", "cancel")):
                    if __event_emitter__:
                        await __event_emitter__(
                            {
                                "type": "status",
                                "data": {
                                    "description": "✅ Already uploaded. MemoryRouter's proxy is handling new conversations automatically.",
                                    "done": True,
                                },
                            }
                        )
                    return
            else:
                if __event_emitter__:
                    await __event_emitter__(
                        {
                            "type": "status",
                            "data": {
                                "description": "✅ Already uploaded. MemoryRouter's proxy is handling new conversations automatically. To re-upload, set 'history_uploaded' to false in Function settings.",
                                "done": True,
                            },
                        }
                    )
                return

        # ── Confirm with user ──

        if __event_call__:
            response = await __event_call__(
                {
                    "type": "confirmation",
                    "data": {
                        "title": "Upload History to MemoryRouter",
                        "message": "This will upload all your conversation history to MemoryRouter so your AI remembers everything from day one.\n\nAfter this, new conversations are stored automatically — you won't need to do this again.\n\nContinue?",
                    },
                }
            )
            if not response or (isinstance(response, str) and response.lower() in ("no", "cancel")):
                if __event_emitter__:
                    await __event_emitter__(
                        {
                            "type": "status",
                            "data": {"description": "Upload cancelled.", "done": True},
                        }
                    )
                return

        # ── Fetch all chats ──

        if __event_emitter__:
            await __event_emitter__(
                {
                    "type": "status",
                    "data": {"description": "📚 Reading conversation history..."},
                }
            )

        try:
            from open_webui.models.chats import Chats
        except ImportError:
            if __event_emitter__:
                await __event_emitter__(
                    {
                        "type": "status",
                        "data": {
                            "description": "❌ Could not access Open WebUI chat database. This function must run inside Open WebUI.",
                            "done": True,
                        },
                    }
                )
            return

        user_id = __user__.get("id", "") if __user__ else ""
        if not user_id:
            if __event_emitter__:
                await __event_emitter__(
                    {
                        "type": "status",
                        "data": {"description": "❌ Could not determine user ID.", "done": True},
                    }
                )
            return

        try:
            chats = Chats.get_chats_by_user_id(user_id)
        except Exception as e:
            if __event_emitter__:
                await __event_emitter__(
                    {
                        "type": "status",
                        "data": {"description": f"❌ Failed to read chats: {str(e)[:200]}", "done": True},
                    }
                )
            return

        if not chats:
            if __event_emitter__:
                await __event_emitter__(
                    {
                        "type": "status",
                        "data": {"description": "No conversations found to upload.", "done": True},
                    }
                )
            return

        # ── Extract messages from all chats ──

        all_lines = []
        total_chats = len(chats)

        for i, chat in enumerate(chats):
            if __event_emitter__ and i % 25 == 0:
                pct = int((i / total_chats) * 50)
                await __event_emitter__(
                    {
                        "type": "status",
                        "data": {"description": f"📖 Processing conversations... {i}/{total_chats} ({pct}%)"},
                    }
                )

            try:
                chat_data = chat.chat if hasattr(chat, "chat") else chat.get("chat", {})
                if isinstance(chat_data, str):
                    chat_data = json.loads(chat_data)

                history = chat_data.get("history", {})
                messages_map = history.get("messages", {})
                current_id = history.get("currentId")

                if not messages_map or not current_id:
                    continue

                ordered = walk_message_tree(messages_map, current_id)
                lines = messages_to_upload_lines(ordered)
                all_lines.extend(lines)
            except Exception:
                continue

        if not all_lines:
            if __event_emitter__:
                await __event_emitter__(
                    {
                        "type": "status",
                        "data": {
                            "description": "No messages found to upload (all conversations were empty or too short).",
                            "done": True,
                        },
                    }
                )
            return

        # ── Batch and upload ──

        batches = batch_lines(all_lines)
        total_stored = 0
        total_failed = 0
        upload_url = f"{endpoint}/v1/memory/upload"

        if __event_emitter__:
            await __event_emitter__(
                {
                    "type": "status",
                    "data": {"description": f"🚀 Uploading {len(all_lines)} messages in {len(batches)} batches..."},
                }
            )

        async with aiohttp.ClientSession() as session:
            for batch_idx, batch in enumerate(batches):
                if batch_idx > 0:
                    await asyncio.sleep(BATCH_SLEEP_S)

                jsonl_body = "\n".join(json.dumps(line) for line in batch)

                try:
                    async with session.post(
                        upload_url,
                        headers={
                            "Authorization": f"Bearer {api_key}",
                            "Content-Type": "text/plain",
                        },
                        data=jsonl_body,
                        timeout=aiohttp.ClientTimeout(total=30),
                    ) as resp:
                        if resp.status == 200:
                            result = await resp.json()
                            stored = (
                                result.get("stats", {}).get("stored")
                                or result.get("stats", {}).get("inputItems")
                                or len(batch)
                            )
                            failed = result.get("stats", {}).get("failed", 0)
                            total_stored += stored
                            total_failed += failed
                        else:
                            total_failed += len(batch)
                except Exception:
                    total_failed += len(batch)

                if __event_emitter__ and (batch_idx + 1) % 5 == 0:
                    pct = int(((batch_idx + 1) / len(batches)) * 100)
                    await __event_emitter__(
                        {
                            "type": "status",
                            "data": {"description": f"🚀 Uploading... batch {batch_idx + 1}/{len(batches)} ({pct}%)"},
                        }
                    )

        # ── Mark as done & report ──

        self.valves.history_uploaded = True

        try:
            from open_webui.models.functions import Functions
            Functions.update_function_valves_by_id(
                body.get("function_id", "memoryrouter_upload"),
                {
                    "memoryrouter_api_key": self.valves.memoryrouter_api_key,
                    "memoryrouter_endpoint": self.valves.memoryrouter_endpoint,
                    "history_uploaded": True,
                }
            )
        except Exception:
            pass  # Best-effort persist; in-memory flag still prevents re-upload this session

        if total_failed == 0:
            msg = f"✅ Done! {total_stored} memories uploaded from {total_chats} conversations. Your AI now remembers everything. New conversations are handled automatically — you won't need to do this again."
        else:
            msg = f"✅ Uploaded {total_stored} memories ({total_failed} failed) from {total_chats} conversations. New conversations are handled automatically going forward."

        if __event_emitter__:
            await __event_emitter__(
                {"type": "status", "data": {"description": msg, "done": True}}
            )

        return {"content": msg}
