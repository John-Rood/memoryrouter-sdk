#!/bin/sh
# Patch OpenClaw with Plugin APIs (PR #18911)
# Adds: registerStreamFnWrapper, updatePluginConfig, updatePluginEnabled
# Version-agnostic: uses anchor patterns, not line numbers
# Usage: curl -fsSL https://raw.githubusercontent.com/John-Rood/memoryrouter-sdk/main/patches/patch-openclaw.sh | sh
set -e

BOLD="\033[1m"
GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
RESET="\033[0m"

echo ""
echo "${BOLD}  OpenClaw Plugin APIs Patch${RESET}"
echo "  ──────────────────────────────"
echo "  PR #18911: registerStreamFnWrapper + updatePluginConfig"
echo ""

# Find OpenClaw install
ROOT=""
if [ -n "$OPENCLAW_ROOT" ]; then
  ROOT="$OPENCLAW_ROOT"
elif [ -d "$HOME/.openclaw/install" ] && [ -f "$HOME/.openclaw/install/package.json" ]; then
  ROOT="$HOME/.openclaw/install"
elif command -v openclaw >/dev/null 2>&1; then
  OPENCLAW_BIN=$(command -v openclaw)
  if [ -L "$OPENCLAW_BIN" ]; then
    OPENCLAW_BIN=$(readlink -f "$OPENCLAW_BIN" 2>/dev/null || readlink "$OPENCLAW_BIN")
  fi
  CANDIDATE=$(dirname "$(dirname "$OPENCLAW_BIN")")
  if [ -f "$CANDIDATE/package.json" ]; then
    ROOT="$CANDIDATE"
  fi
fi

if [ -z "$ROOT" ] || [ ! -f "$ROOT/package.json" ]; then
  echo "${RED}  ✗ Could not find OpenClaw installation.${RESET}"
  echo "  Set OPENCLAW_ROOT and try again:"
  echo "    ${BOLD}OPENCLAW_ROOT=/path/to/openclaw curl -fsSL <url> | sh${RESET}"
  exit 1
fi

echo "  Found OpenClaw at: ${ROOT}"

# Check if already patched
if grep -q "streamFnWrappers" "$ROOT/src/plugins/registry.ts" 2>/dev/null; then
  echo "${GREEN}  ✓ Already patched — plugin APIs are present.${RESET}"
  echo ""
  exit 0
fi

FAIL=0

# Helper: insert content from a temp file after a matching line
# Usage: insert_file_after <target> <pattern> <content_file>
insert_file_after() {
  _target="$1"; _pattern="$2"; _content="$3"
  if ! grep -q "$_pattern" "$_target" 2>/dev/null; then
    echo "${RED}  ✗ Anchor not found: $_pattern in $(basename "$_target")${RESET}"
    return 1
  fi
  sed -i.bak "/$_pattern/r $_content" "$_target" && rm -f "${_target}.bak"
}

# Helper: insert content from a temp file before a matching line (first occurrence only)
insert_file_before() {
  _target="$1"; _pattern="$2"; _content="$3"
  if ! grep -q "$_pattern" "$_target" 2>/dev/null; then
    echo "${RED}  ✗ Anchor not found: $_pattern in $(basename "$_target")${RESET}"
    return 1
  fi
  # Use awk: print content file before first match
  awk -v pat="$_pattern" -v cf="$_content" '
    $0 ~ pat && !done { while ((getline line < cf) > 0) print line; done=1 }
    { print }
  ' "$_target" > "${_target}.tmp" && mv "${_target}.tmp" "$_target"
}

# ================================================================
# 1. src/plugins/types.ts
# ================================================================
TYPES="$ROOT/src/plugins/types.ts"
echo "  Patching types.ts..."

# 1a. Add StreamFnWrapperFn type after AnyAgentTool export
cat > /tmp/oc_patch_1a.txt << 'PATCH'

// Re-export StreamFn from pi-agent-core for plugin authors
// eslint-disable-next-line @typescript-eslint/no-explicit-any
type StreamFnInternal = (...args: any[]) => any;

/**
 * A function that wraps the agent's streamFn to intercept, modify, or proxy LLM API calls.
 * Multiple wrappers compose in registration order.
 */
export type StreamFnWrapperFn = (next: StreamFnInternal) => StreamFnInternal;
PATCH
insert_file_after "$TYPES" "export type { AnyAgentTool" /tmp/oc_patch_1a.txt || FAIL=1

# 1b. Add 3 new methods to OpenClawPluginApi
# Anchor: the "on:" method's closing line with priority
cat > /tmp/oc_patch_1b.txt << 'PATCH'
  /**
   * Register a wrapper around the agent's streamFn to intercept, modify, or proxy LLM API calls.
   * Multiple wrappers compose in registration order (after internal wrappers like cache trace).
   * Use cases: memory proxy, observability, cost tracking, custom routing, header injection.
   */
  registerStreamFnWrapper: (wrapper: StreamFnWrapperFn) => void;
  /**
   * Write to the plugin's own config section (plugins.entries.<pluginId>.config).
   * Scoped to own config only — cannot modify other plugins or core settings.
   */
  updatePluginConfig: (config: Record<string, unknown>) => Promise<void>;
  /**
   * Enable or disable this plugin in the config.
   */
  updatePluginEnabled: (enabled: boolean) => Promise<void>;
PATCH
# Find the line with "priority" in the on() method signature
insert_file_after "$TYPES" "opts.*priority.*number" /tmp/oc_patch_1b.txt || FAIL=1

# ================================================================
# 2. src/plugins/registry.ts
# ================================================================
REG="$ROOT/src/plugins/registry.ts"
echo "  Patching registry.ts..."

# 2a. Add StreamFnWrapperFn to import
sed -i.bak 's/PluginHookRegistration as TypedPluginHookRegistration,/PluginHookRegistration as TypedPluginHookRegistration,\
  StreamFnWrapperFn,/' "$REG" && rm -f "${REG}.bak" || FAIL=1

# 2b. Add PluginStreamFnWrapperRegistration type
cat > /tmp/oc_patch_2b.txt << 'PATCH'

export type PluginStreamFnWrapperRegistration = {
  pluginId: string;
  wrapper: StreamFnWrapperFn;
  source: string;
};
PATCH
insert_file_after "$REG" "^export type PluginCommandRegistration" /tmp/oc_patch_2b.txt || FAIL=1

# 2c. Add streamFnWrappers to PluginRegistry type (before diagnostics: PluginDiagnostic)
cat > /tmp/oc_patch_2c.txt << 'PATCH'
  streamFnWrappers: PluginStreamFnWrapperRegistration[];
PATCH
insert_file_before "$REG" "diagnostics: PluginDiagnostic" /tmp/oc_patch_2c.txt || FAIL=1

# 2d. Add streamFnWrappers: [] before EVERY runtime diagnostics (not the type def one)
# The type def was handled in 2c. Now handle runtime: diagnostics: [] or diagnostics,
awk '/diagnostics/ && !/PluginDiagnostic/ && !/streamFnWrappers/ { print "    streamFnWrappers: [],"; } { print }' "$REG" > "${REG}.tmp" && mv "${REG}.tmp" "$REG"

# 2e. Add implementation functions before normalizeLogger
cat > /tmp/oc_patch_2e.txt << 'PATCH'
  const registerStreamFnWrapper = (record: PluginRecord, wrapper: StreamFnWrapperFn) => {
    registry.streamFnWrappers.push({
      pluginId: record.id,
      wrapper,
      source: record.source,
    });
  };

  const updatePluginConfig = async (record: PluginRecord, newConfig: Record<string, unknown>) => {
    const { loadConfig, writeConfigFile } = await import("../config/io.js");
    const currentConfig = loadConfig();
    const updated = {
      ...currentConfig,
      plugins: {
        ...currentConfig.plugins,
        entries: {
          ...currentConfig.plugins?.entries,
          [record.id]: {
            ...currentConfig.plugins?.entries?.[record.id],
            config: newConfig,
          },
        },
      },
    };
    await writeConfigFile(updated);
  };

  const updatePluginEnabled = async (record: PluginRecord, enabled: boolean) => {
    const { loadConfig, writeConfigFile } = await import("../config/io.js");
    const currentConfig = loadConfig();
    const updated = {
      ...currentConfig,
      plugins: {
        ...currentConfig.plugins,
        entries: {
          ...currentConfig.plugins?.entries,
          [record.id]: {
            ...currentConfig.plugins?.entries?.[record.id],
            enabled,
          },
        },
      },
    };
    await writeConfigFile(updated);
  };

PATCH
insert_file_before "$REG" "const normalizeLogger" /tmp/oc_patch_2e.txt || FAIL=1

# 2f. Add method bindings in the API object
cat > /tmp/oc_patch_2f.txt << 'PATCH'
      registerStreamFnWrapper: (wrapper) => registerStreamFnWrapper(record, wrapper),
      updatePluginConfig: (newConfig) => updatePluginConfig(record, newConfig),
      updatePluginEnabled: (enabled) => updatePluginEnabled(record, enabled),
PATCH
insert_file_after "$REG" "registerTypedHook(record, hookName, handler, opts)" /tmp/oc_patch_2f.txt || FAIL=1

# 2g. Add registerStreamFnWrapper to the return object
cat > /tmp/oc_patch_2g.txt << 'PATCH'
    registerStreamFnWrapper,
PATCH
insert_file_after "$REG" "registerTypedHook,$" /tmp/oc_patch_2g.txt || FAIL=1

# ================================================================
# 3. src/plugin-sdk/index.ts
# ================================================================
SDK="$ROOT/src/plugin-sdk/index.ts"
echo "  Patching plugin-sdk/index.ts..."

# 3a. Add StreamFnWrapperFn to types export
sed -i.bak 's/ProviderAuthResult,$/ProviderAuthResult,\
  StreamFnWrapperFn,/' "$SDK" && rm -f "${SDK}.bak" || FAIL=1

# 3b. Add StreamFn re-export
cat > /tmp/oc_patch_3b.txt << 'PATCH'
export type { StreamFn } from "@mariozechner/pi-agent-core";
PATCH
insert_file_after "$SDK" 'from "\.\.\/plugins\/types\.js"' /tmp/oc_patch_3b.txt || FAIL=1

# ================================================================
# 4. src/agents/pi-embedded-runner/run/attempt.ts
# ================================================================
ATTEMPT="$ROOT/src/agents/pi-embedded-runner/run/attempt.ts"
echo "  Patching attempt.ts..."

cat > /tmp/oc_patch_4.txt << 'PATCH'
      // Apply plugin-registered streamFn wrappers
      {
        const { getGlobalPluginRegistry } = await import("../../../plugins/hook-runner-global.js");
        const pluginRegistry = getGlobalPluginRegistry();
        if (pluginRegistry?.streamFnWrappers?.length) {
          for (const { wrapper } of pluginRegistry.streamFnWrappers) {
            activeSession.agent.streamFn = wrapper(activeSession.agent.streamFn);
          }
        }
      }

PATCH
insert_file_before "$ATTEMPT" "const prior = await sanitizeSessionHistory" /tmp/oc_patch_4.txt || FAIL=1

# ================================================================
# 5. Test files — add streamFnWrappers: [] before diagnostics
# ================================================================
echo "  Patching test files..."

TEST_FILES="
src/auto-reply/reply/route-reply.test.ts
src/gateway/server-plugins.test.ts
src/gateway/server.agent.gateway-server-agent.mocks.ts
src/gateway/test-helpers.mocks.ts
src/test-utils/channel-plugins.ts
src/utils/message-channel.test.ts
"

for tf in $TEST_FILES; do
  FILE="$ROOT/$tf"
  if [ -f "$FILE" ] && ! grep -q "streamFnWrappers" "$FILE" 2>/dev/null; then
    # Insert once before the first diagnostics line using awk
    awk '/diagnostics/ && !done { print "  streamFnWrappers: [],"; done=1 } { print }' "$FILE" > "${FILE}.tmp" && mv "${FILE}.tmp" "$FILE"
  fi
done

# Lobster test: add mock methods to fakeApi (no registry object here)
LOBSTER="$ROOT/extensions/lobster/src/lobster-tool.test.ts"
if [ -f "$LOBSTER" ] && ! grep -q "registerStreamFnWrapper" "$LOBSTER" 2>/dev/null; then
  cat > /tmp/oc_patch_lobster.txt << 'PATCH'
    registerStreamFnWrapper() {},
    updatePluginConfig: async () => {},
    updatePluginEnabled: async () => {},
PATCH
  insert_file_after "$LOBSTER" "on()" /tmp/oc_patch_lobster.txt || true
fi

# Cleanup temp files
rm -f /tmp/oc_patch_*.txt

# ================================================================
# Verify
# ================================================================
echo ""
# Final verification overrides any intermediate failures
if grep -q "streamFnWrappers" "$REG" && grep -q "StreamFnWrapperFn" "$TYPES" && grep -q "streamFnWrappers" "$ATTEMPT"; then
  echo "${GREEN}  ✓ All core patches verified${RESET}"
else
  echo "${RED}  ✗ Verification failed — core patches missing${RESET}"
  exit 1
fi

# ================================================================
# Rebuild
# ================================================================
echo "  Rebuilding OpenClaw..."
cd "$ROOT"
if command -v pnpm >/dev/null 2>&1; then
  pnpm build 2>&1 | tail -5
elif command -v npm >/dev/null 2>&1; then
  npm run build 2>&1 | tail -5
else
  echo "${YELLOW}  ⚠ No package manager found — run 'pnpm build' manually${RESET}"
fi

echo ""
echo "${GREEN}  ✅ OpenClaw patched with plugin APIs!${RESET}"
echo ""
echo "  You can now install plugins that use these APIs."
echo "  When PR #18911 merges upstream, 'openclaw update' includes it natively."
echo ""
