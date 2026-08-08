# MemoryRouter

**One memory for every AI you use.** MemoryRouter lets people carry approved context from ChatGPT to Claude and other AI tools, while giving product teams private, persistent memory for every user through APIs and MCP.

[Homepage](https://memoryrouter.ai) · [Start free](https://app.memoryrouter.ai/signup) · [Documentation](https://docs.memoryrouter.ai) · [Pricing](https://memoryrouter.ai/pricing) · [Security](https://memoryrouter.ai/security) · [Releases](https://github.com/John-Rood/memoryrouter-sdk/releases)

## Choose your path

| I want to… | Start here |
| --- | --- |
| Move useful context from ChatGPT to Claude | [Transfer your memories](https://memoryrouter.ai) |
| Connect Claude, ChatGPT, Codex, OpenClaw, or another MCP client | [MCP and connector guide](https://memoryrouter.ai/mcp) |
| Give OpenClaw automatic persistent memory | [OpenClaw setup](https://docs.memoryrouter.ai/openclaw) |
| Add user-scoped memory to an AI product | [Developer quickstart](https://docs.memoryrouter.ai/quickstart) |
| Install the MemoryRouter CLI | [Latest CLI release](https://github.com/John-Rood/memoryrouter-sdk/releases/latest) |

## Connect AI tools with MCP

MemoryRouter exposes a remote MCP server at:

```text
https://mcp.memoryrouter.ai/mcp
```

Connect supported hosts through OAuth, choose a vault and permissions, then verify access with the host's visible MemoryRouter tools. Hosted connectors are model-directed: connecting does not automatically import old conversations or guarantee a memory call on every turn.

See the [MCP overview](https://memoryrouter.ai/mcp) for exact setup and host-specific behavior.

## OpenClaw plugin

Install the current audited npm package:

```bash
openclaw plugins install npm:mr-memory@3.7.8
openclaw mr <your-memory-key>
openclaw mr status
```

The plugin provides relay-based recall and capture while inference and provider credentials stay inside OpenClaw. Historical workspace and session upload is a separate, explicit operation:

```bash
openclaw mr upload
```

Read the [OpenClaw documentation](https://docs.memoryrouter.ai/openclaw) before enabling it, especially if you use multiple agents or custom paths.

## API quickstart

MemoryRouter supports two production patterns:

- **Proxy mode:** send the model request through MemoryRouter; it retrieves memory, calls the provider, and stores the completed exchange.
- **Local inference mode:** keep the provider call in your app and use `/v1/memory/prepare` plus `/v1/memory/ingest` for retrieval and storage only.

One stable Memory Key identifies one private user vault. Here is the OpenAI-compatible proxy path:

```bash
curl https://api.memoryrouter.ai/v1/chat/completions \
  -H "Authorization: Bearer $MEMORYROUTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "openai/gpt-5.5",
    "messages": [
      {"role": "user", "content": "Remember that I prefer concise answers."}
    ]
  }'
```

For per-user key provisioning, local inference, native Anthropic and Google endpoints, imports, and deletion, use the [developer quickstart](https://docs.memoryrouter.ai/quickstart) and [API reference](https://docs.memoryrouter.ai/api-reference).

## CLI releases

The [Releases page](https://github.com/John-Rood/memoryrouter-sdk/releases) publishes MemoryRouter CLI binaries for macOS and Linux. Install the current release with:

```bash
curl -fsSL https://memoryrouter.ai/install.sh | sh
memoryrouter auth <your-memory-key>
memoryrouter status
```

The `patches/` directory contains legacy OpenClaw plugin-API patch helpers for historical builds. Current OpenClaw users should follow the published npm installation path above instead of applying a legacy patch.

## Pricing

MemoryRouter pricing and allowances vary by product path and can change. Use the live [pricing page](https://memoryrouter.ai/pricing) and the relevant integration guide rather than older README quota claims.

## Support and trust

- Product and account help: [hello@memoryrouter.ai](mailto:hello@memoryrouter.ai)
- Security policy: [SECURITY.md](SECURITY.md)
- Support policy: [SUPPORT.md](SUPPORT.md)
- Contribution guide: [CONTRIBUTING.md](CONTRIBUTING.md)
- Privacy: [memoryrouter.ai/privacy](https://memoryrouter.ai/privacy)
- Terms: [memoryrouter.ai/terms](https://memoryrouter.ai/terms)

Never post a live Memory Key, provider credential, or private memory content in a GitHub issue.

## License

The public files in this repository are available under the [MIT License](LICENSE).
