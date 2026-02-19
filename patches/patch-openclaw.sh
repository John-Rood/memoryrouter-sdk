#!/bin/sh
# Patch OpenClaw with Plugin APIs (PR #18911)
# Adds: registerStreamFnWrapper, updatePluginConfig, updatePluginEnabled
# Version-agnostic: targets compiled dist/ JS bundles (npm installs)
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

# Determine if this is a source install (has src/) or npm install (dist/ only)
if [ -d "$ROOT/src/plugins" ]; then
  MODE="source"
  echo "  Mode: source (TypeScript)"
elif [ -d "$ROOT/dist" ]; then
  MODE="dist"
  echo "  Mode: compiled (dist/)"
else
  echo "${RED}  ✗ Cannot find src/ or dist/ directory${RESET}"
  exit 1
fi

# ================================================================
# DIST MODE — Patch compiled JavaScript bundles
# ================================================================
patch_dist() {
  DIST="$ROOT/dist"

  # Find entry.js
  ENTRY="$DIST/entry.js"
  if [ ! -f "$ENTRY" ]; then
    echo "${RED}  ✗ entry.js not found${RESET}"
    return 1
  fi

  # Check if already patched
  if grep -q "streamFnWrappers" "$ENTRY" 2>/dev/null; then
    echo "${GREEN}  ✓ Already patched — plugin APIs are present.${RESET}"
    return 0
  fi

  echo "  Patching entry.js..."

  # Use Python for reliable multiline insertions (works on macOS + Linux)
  python3 << 'PYEOF'
import sys, re, os

entry_path = os.environ.get("ENTRY_PATH")
with open(entry_path, "r") as f:
    code = f.read()

changes = 0

# 1. Add streamFnWrappers: [] to createEmptyPluginRegistry before diagnostics: []
old = "\t\tdiagnostics: []\n\t};\n}\nfunction createPluginRegistry"
new = "\t\tstreamFnWrappers: [],\n\t\tdiagnostics: []\n\t};\n}\nfunction createPluginRegistry"
if old in code:
    code = code.replace(old, new, 1)
    changes += 1
else:
    # Try with spaces instead of tabs
    old2 = old.replace("\t", "  ")
    new2 = new.replace("\t", "  ")
    if old2 in code:
        code = code.replace(old2, new2, 1)
        changes += 1
    else:
        print("  WARNING: Could not find createEmptyPluginRegistry anchor")

# 2. Add implementation functions before normalizeLogger
fn_block = """	const registerStreamFnWrapper = (record, wrapper) => {
		registry.streamFnWrappers.push({
			pluginId: record.id,
			wrapper,
			source: record.source
		});
	};
	const updatePluginConfig = async (record, newConfig) => {
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
						config: newConfig
					}
				}
			}
		};
		await writeConfigFile(updated);
	};
	const updatePluginEnabled = async (record, enabled) => {
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
						enabled
					}
				}
			}
		};
		await writeConfigFile(updated);
	};
"""
anchor_norm = "\tconst normalizeLogger = (logger) =>"
if anchor_norm in code:
    code = code.replace(anchor_norm, fn_block + anchor_norm, 1)
    changes += 1
else:
    anchor_norm2 = anchor_norm.replace("\t", "  ")
    if anchor_norm2 in code:
        code = code.replace(anchor_norm2, fn_block.replace("\t", "  ") + anchor_norm2, 1)
        changes += 1
    else:
        print("  WARNING: Could not find normalizeLogger anchor")

# 3. Add method bindings to createApi return object (after the on: line)
old_on = "on: (hookName, handler, opts) => registerTypedHook(record, hookName, handler, opts)\n\t\t};"
new_on = """on: (hookName, handler, opts) => registerTypedHook(record, hookName, handler, opts),
			registerStreamFnWrapper: (wrapper) => registerStreamFnWrapper(record, wrapper),
			updatePluginConfig: (newConfig) => updatePluginConfig(record, newConfig),
			updatePluginEnabled: (enabled) => updatePluginEnabled(record, enabled)
		};"""
if old_on in code:
    code = code.replace(old_on, new_on, 1)
    changes += 1
else:
    old_on2 = old_on.replace("\t", "  ")
    new_on2 = new_on.replace("\t", "  ")
    if old_on2 in code:
        code = code.replace(old_on2, new_on2, 1)
        changes += 1
    else:
        print("  WARNING: Could not find createApi on: anchor")

# 4. Add registerStreamFnWrapper to the return object of createPluginRegistry
old_ret = "registerTypedHook\n\t};\n}"
new_ret = "registerTypedHook,\n\t\tregisterStreamFnWrapper\n\t};\n}"
if old_ret in code:
    code = code.replace(old_ret, new_ret, 1)
    changes += 1
else:
    old_ret2 = old_ret.replace("\t", "  ")
    new_ret2 = new_ret.replace("\t", "  ")
    if old_ret2 in code:
        code = code.replace(old_ret2, new_ret2, 1)
        changes += 1
    else:
        print("  WARNING: Could not find return object anchor")

with open(entry_path, "w") as f:
    f.write(code)

print(f"  entry.js: {changes}/4 patches applied")
if changes < 4:
    sys.exit(1)
PYEOF

  # Now patch the attempt runner
  echo "  Finding attempt runner..."
  # Find the pi-embedded file that has the streamFn wrappers
  ATTEMPT_FILE=$(grep -l "createOpenAIResponsesStoreWrapper" "$DIST"/pi-embedded-*.js 2>/dev/null | head -1)

  if [ -z "$ATTEMPT_FILE" ]; then
    # Try alternate anchor
    ATTEMPT_FILE=$(grep -l "sanitizeSessionHistory" "$DIST"/pi-embedded-*.js 2>/dev/null | head -1)
  fi

  if [ -z "$ATTEMPT_FILE" ]; then
    echo "${YELLOW}  ⚠ Could not find attempt runner — streamFn wrappers won't apply at runtime${RESET}"
    echo "${YELLOW}    Plugin will load but won't intercept LLM calls${RESET}"
  else
    echo "  Patching $(basename "$ATTEMPT_FILE")..."

    ATTEMPT_PATH="$ATTEMPT_FILE" python3 << 'PYEOF'
import sys, os

attempt_path = os.environ.get("ATTEMPT_PATH")
with open(attempt_path, "r") as f:
    code = f.read()

# The wrapper block to inject — uses the global registry symbol
wrapper_block = """
	// [OpenClaw Plugin APIs Patch] Apply plugin-registered streamFn wrappers
	{
		const _regSym = Symbol.for("openclaw.pluginRegistryState");
		const _regState = globalThis[_regSym];
		if (_regState?.registry?.streamFnWrappers?.length) {
			for (const { wrapper } of _regState.registry.streamFnWrappers) {
				agent.streamFn = wrapper(agent.streamFn);
			}
		}
	}
"""

# Insert after createOpenAIResponsesStoreWrapper line
anchor = "agent.streamFn = createOpenAIResponsesStoreWrapper(agent.streamFn);\n}"
if anchor in code:
    code = code.replace(anchor, anchor + wrapper_block, 1)
    print("  attempt runner: patched (after createOpenAIResponsesStoreWrapper)")
else:
    # Try second code path — after anthropicPayloadLogger wrapper, before sanitizeSessionHistory
    # Look for the pattern: activeSession.agent.streamFn = anthropicPayloadLogger...
    # followed by try { const prior = await sanitizeSessionHistory
    import re
    pattern = r'(if \(anthropicPayloadLogger\) activeSession\.agent\.streamFn = anthropicPayloadLogger\.wrapStreamFn\(activeSession\.agent\.streamFn\);)'
    wrapper_block2 = """
			// [OpenClaw Plugin APIs Patch] Apply plugin-registered streamFn wrappers
			{
				const _regSym = Symbol.for("openclaw.pluginRegistryState");
				const _regState = globalThis[_regSym];
				if (_regState?.registry?.streamFnWrappers?.length) {
					for (const { wrapper } of _regState.registry.streamFnWrappers) {
						activeSession.agent.streamFn = wrapper(activeSession.agent.streamFn);
					}
				}
			}"""
    match = re.search(pattern, code)
    if match:
        code = code.replace(match.group(0), match.group(0) + wrapper_block2, 1)
        print("  attempt runner: patched (after anthropicPayloadLogger)")
    else:
        print("  WARNING: Could not find attempt runner anchor")
        sys.exit(1)

with open(attempt_path, "w") as f:
    f.write(code)
PYEOF
  fi

  # Clear Node compile cache
  if [ -d "$ROOT/.cache" ]; then
    rm -rf "$ROOT/.cache" 2>/dev/null
  fi

  return 0
}

# ================================================================
# SOURCE MODE — Patch TypeScript source files
# ================================================================
patch_source() {
  # Check if already patched
  if grep -q "streamFnWrappers" "$ROOT/src/plugins/registry.ts" 2>/dev/null; then
    echo "${GREEN}  ✓ Already patched — plugin APIs are present.${RESET}"
    return 0
  fi

  TYPES="$ROOT/src/plugins/types.ts"
  REG="$ROOT/src/plugins/registry.ts"
  SDK="$ROOT/src/plugin-sdk/index.ts"
  ATTEMPT="$ROOT/src/agents/pi-embedded-runner/run/attempt.ts"

  echo "  Patching TypeScript source..."

  python3 << 'PYEOF'
import sys, os

root = os.environ.get("PATCH_ROOT")
changes = 0

# --- types.ts ---
types_path = os.path.join(root, "src/plugins/types.ts")
with open(types_path, "r") as f:
    code = f.read()

# Add StreamFnWrapperFn type after AnyAgentTool export
anchor = 'export type { AnyAgentTool } from "../agents/tools/common.js";'
insert_type = '''
// eslint-disable-next-line @typescript-eslint/no-explicit-any
type StreamFnInternal = (...args: any[]) => any;

export type StreamFnWrapperFn = (next: StreamFnInternal) => StreamFnInternal;
'''
if anchor in code and "StreamFnWrapperFn" not in code:
    code = code.replace(anchor, anchor + insert_type, 1)
    changes += 1

# Add methods to OpenClawPluginApi (after opts?: { priority )
api_anchor = "opts?: { priority?: number },"
api_insert = """  ) => void;
  registerStreamFnWrapper: (wrapper: StreamFnWrapperFn) => void;
  updatePluginConfig: (config: Record<string, unknown>) => Promise<void>;
  updatePluginEnabled: (enabled: boolean) => Promise<void>;"""
if api_anchor in code and "registerStreamFnWrapper" not in code:
    # Find the line with priority and the ) => void; after it
    import re
    pattern = r"opts\?\: \{ priority\?\: number \},\s*\) => void;"
    match = re.search(pattern, code)
    if match:
        code = code[:match.start()] + api_anchor + "\n" + api_insert + code[match.end():]
        changes += 1

with open(types_path, "w") as f:
    f.write(code)

# --- registry.ts ---
reg_path = os.path.join(root, "src/plugins/registry.ts")
with open(reg_path, "r") as f:
    code = f.read()

if "streamFnWrappers" not in code:
    # Add StreamFnWrapperFn import
    code = code.replace(
        'PluginHookRegistration as TypedPluginHookRegistration,',
        'PluginHookRegistration as TypedPluginHookRegistration,\n  StreamFnWrapperFn,', 1)

    # Add type
    code = code.replace(
        'export type PluginCommandRegistration = {',
        '''export type PluginStreamFnWrapperRegistration = {
  pluginId: string;
  wrapper: StreamFnWrapperFn;
  source: string;
};

export type PluginCommandRegistration = {''', 1)

    # Add to PluginRegistry type
    code = code.replace(
        '  diagnostics: PluginDiagnostic[];',
        '  streamFnWrappers: PluginStreamFnWrapperRegistration[];\n  diagnostics: PluginDiagnostic[];', 1)

    # Add to createEmptyPluginRegistry
    code = code.replace(
        '    diagnostics: [],\n  };\n}\n',
        '    streamFnWrappers: [],\n    diagnostics: [],\n  };\n}\n', 1)

    # Add functions before normalizeLogger
    fn_block = '''  const registerStreamFnWrapper = (record: PluginRecord, wrapper: StreamFnWrapperFn) => {
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

'''
    code = code.replace('  const normalizeLogger', fn_block + '  const normalizeLogger', 1)

    # Add to API object
    code = code.replace(
        'on: (hookName, handler, opts) => registerTypedHook(record, hookName, handler, opts),',
        '''on: (hookName, handler, opts) => registerTypedHook(record, hookName, handler, opts),
      registerStreamFnWrapper: (wrapper) => registerStreamFnWrapper(record, wrapper),
      updatePluginConfig: (newConfig) => updatePluginConfig(record, newConfig),
      updatePluginEnabled: (enabled) => updatePluginEnabled(record, enabled),''', 1)

    # Add to return
    code = code.replace('    registerTypedHook,\n  };\n}', '    registerTypedHook,\n    registerStreamFnWrapper,\n  };\n}', 1)

    changes += 1

with open(reg_path, "w") as f:
    f.write(code)

# --- plugin-sdk/index.ts ---
sdk_path = os.path.join(root, "src/plugin-sdk/index.ts")
with open(sdk_path, "r") as f:
    code = f.read()

if "StreamFnWrapperFn" not in code:
    code = code.replace('ProviderAuthResult,\n} from "../plugins/types.js";',
        'ProviderAuthResult,\n  StreamFnWrapperFn,\n} from "../plugins/types.js";\nexport type { StreamFn } from "@mariozechner/pi-agent-core";', 1)
    changes += 1

with open(sdk_path, "w") as f:
    f.write(code)

# --- attempt.ts ---
attempt_path = os.path.join(root, "src/agents/pi-embedded-runner/run/attempt.ts")
with open(attempt_path, "r") as f:
    code = f.read()

if "streamFnWrappers" not in code:
    wrapper = '''      // Apply plugin-registered streamFn wrappers
      {
        const { getGlobalPluginRegistry } = await import("../../../plugins/hook-runner-global.js");
        const pluginRegistry = getGlobalPluginRegistry();
        if (pluginRegistry?.streamFnWrappers?.length) {
          for (const { wrapper } of pluginRegistry.streamFnWrappers) {
            activeSession.agent.streamFn = wrapper(activeSession.agent.streamFn);
          }
        }
      }

'''
    code = code.replace('        const prior = await sanitizeSessionHistory({', wrapper + '        const prior = await sanitizeSessionHistory({', 1)
    changes += 1

with open(attempt_path, "w") as f:
    f.write(code)

print(f"  Source patches: {changes}/4 applied")
PYEOF

  PATCH_ROOT="$ROOT" python3 -c "pass"  # validate env

  # Rebuild
  echo "  Rebuilding OpenClaw..."
  cd "$ROOT"
  if command -v pnpm >/dev/null 2>&1; then
    pnpm build 2>&1 | tail -5
  elif command -v npm >/dev/null 2>&1; then
    npm run build 2>&1 | tail -5
  else
    echo "${YELLOW}  ⚠ No package manager found — run 'pnpm build' manually${RESET}"
  fi
}

# ================================================================
# Run the appropriate mode
# ================================================================
if [ "$MODE" = "dist" ]; then
  ENTRY_PATH="$ROOT/dist/entry.js" patch_dist
else
  PATCH_ROOT="$ROOT" patch_source
fi

RESULT=$?

# Final verification
if [ "$MODE" = "dist" ]; then
  CHECK_FILE="$ROOT/dist/entry.js"
else
  CHECK_FILE="$ROOT/src/plugins/registry.ts"
fi

echo ""
if grep -q "streamFnWrappers" "$CHECK_FILE" 2>/dev/null; then
  echo "${GREEN}  ✅ OpenClaw patched with plugin APIs!${RESET}"
  echo ""
  echo "  You can now install plugins that use these APIs."
  echo "  When PR #18911 merges upstream, 'openclaw update' includes it natively."
  echo ""
else
  echo "${RED}  ✗ Patch verification failed${RESET}"
  exit 1
fi
