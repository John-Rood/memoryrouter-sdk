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

is_openclaw_root() {
  [ -n "$1" ] && [ -f "$1/package.json" ] && { [ -d "$1/dist" ] || [ -d "$1/src/plugins" ]; }
}

resolve_dir() {
  # Best-effort path normalization that works in sh across macOS/Linux/Git Bash.
  if [ -d "$1" ]; then
    (cd "$1" 2>/dev/null && pwd) || echo "$1"
  else
    echo "$1"
  fi
}

try_root() {
  CANDIDATE="$1"
  if is_openclaw_root "$CANDIDATE"; then
    ROOT=$(resolve_dir "$CANDIDATE")
    return 0
  fi
  return 1
}

if [ -n "$OPENCLAW_ROOT" ]; then
  try_root "$OPENCLAW_ROOT" || true
fi

if [ -z "$ROOT" ] && [ -d "$HOME/.openclaw/install" ] && [ -f "$HOME/.openclaw/install/package.json" ]; then
  try_root "$HOME/.openclaw/install" || true
fi

if [ -z "$ROOT" ]; then
  # npm global roots (works for npm installs across macOS/Linux/Windows Git Bash)
  for NPM_CMD in npm /opt/homebrew/bin/npm /usr/local/bin/npm npm.cmd; do
    if command -v "$NPM_CMD" >/dev/null 2>&1; then
      NPM_ROOT=$($NPM_CMD root -g 2>/dev/null | tr -d '\r')
      if [ -n "$NPM_ROOT" ]; then
        try_root "$NPM_ROOT/openclaw" && break
      fi
    fi
  done
fi

if [ -z "$ROOT" ] && command -v openclaw >/dev/null 2>&1; then
  OPENCLAW_BIN=$(command -v openclaw)

  # Resolve symlink target when available.
  if [ -L "$OPENCLAW_BIN" ]; then
    OPENCLAW_BIN=$(readlink -f "$OPENCLAW_BIN" 2>/dev/null || readlink "$OPENCLAW_BIN" 2>/dev/null || echo "$OPENCLAW_BIN")
  fi

  BIN_DIR=$(dirname "$OPENCLAW_BIN")

  # Common layouts:
  # - /opt/homebrew/bin/openclaw -> /opt/homebrew/lib/node_modules/openclaw/...
  # - %APPDATA%/npm/openclaw(.cmd) -> %APPDATA%/npm/node_modules/openclaw
  # - direct /.../node_modules/openclaw/dist/entry.js
  try_root "$(resolve_dir "$BIN_DIR/../lib/node_modules/openclaw")" || true
  if [ -z "$ROOT" ]; then
    try_root "$(resolve_dir "$BIN_DIR/../node_modules/openclaw")" || true
  fi
  if [ -z "$ROOT" ]; then
    try_root "$(resolve_dir "$(dirname "$(dirname "$OPENCLAW_BIN")")")" || true
  fi
fi

if [ -z "$ROOT" ] && command -v openclaw.cmd >/dev/null 2>&1; then
  OPENCLAW_CMD_BIN=$(command -v openclaw.cmd)
  CMD_BIN_DIR=$(dirname "$OPENCLAW_CMD_BIN")
  try_root "$(resolve_dir "$CMD_BIN_DIR/../node_modules/openclaw")" || true
  if [ -z "$ROOT" ]; then
    try_root "$(resolve_dir "$CMD_BIN_DIR/../lib/node_modules/openclaw")" || true
  fi
fi

if [ -z "$ROOT" ]; then
  # Fixed-path fallbacks for common package manager install locations.
  for CAND in \
    /opt/homebrew/lib/node_modules/openclaw \
    /usr/local/lib/node_modules/openclaw \
    "$HOME/.npm-global/lib/node_modules/openclaw" \
    "$HOME/AppData/Roaming/npm/node_modules/openclaw" \
    "$APPDATA/npm/node_modules/openclaw"
  do
    try_root "$CAND" && break
  done
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

  # Check if already patched (both entry.js AND attempt runner must have the patch)
  ATTEMPT_FILE=$(grep -l "streamFnWrappers.*attempt runner" "$DIST"/pi-embedded-*.js 2>/dev/null | head -1)
  if grep -q "streamFnWrappers" "$ENTRY" 2>/dev/null && [ -n "$ATTEMPT_FILE" ]; then
    echo "${GREEN}  ✓ Already patched — plugin APIs are present (both locations).${RESET}"
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
	const _readWriteConfig = async (mutate) => {
		const cfgPath = resolveConfigPath();
		const fs$1 = await import("node:fs");
		const path$1 = await import("node:path");
		let current = {};
		try { current = JSON.parse(fs$1.readFileSync(cfgPath, "utf-8")); } catch {}
		mutate(current);
		fs$1.mkdirSync(path$1.dirname(cfgPath), { recursive: true });
		fs$1.writeFileSync(cfgPath, JSON.stringify(current, null, 2) + "\\n");
	};
	const updatePluginConfig = async (record, newConfig) => {
		await _readWriteConfig((cfg) => {
			if (!cfg.plugins) cfg.plugins = {};
			if (!cfg.plugins.entries) cfg.plugins.entries = {};
			if (!cfg.plugins.entries[record.id]) cfg.plugins.entries[record.id] = {};
			cfg.plugins.entries[record.id].config = newConfig;
		});
	};
	const updatePluginEnabled = async (record, enabled) => {
		await _readWriteConfig((cfg) => {
			if (!cfg.plugins) cfg.plugins = {};
			if (!cfg.plugins.entries) cfg.plugins.entries = {};
			if (!cfg.plugins.entries[record.id]) cfg.plugins.entries[record.id] = {};
			cfg.plugins.entries[record.id].enabled = enabled;
		});
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

  # Now patch ALL attempt runner files (there can be multiple pi-embedded-*.js)
  echo "  Finding attempt runner(s)..."
  ATTEMPT_FILES=$(grep -l "createOpenAIResponsesStoreWrapper\|sanitizeSessionHistory" "$DIST"/pi-embedded-*.js 2>/dev/null | sort -u)

  if [ -z "$ATTEMPT_FILES" ]; then
    echo "${YELLOW}  ⚠ Could not find attempt runner — streamFn wrappers won't apply at runtime${RESET}"
    echo "${YELLOW}    Plugin will load but won't intercept LLM calls${RESET}"
  else
    for ATTEMPT_FILE in $ATTEMPT_FILES; do
    # Skip files that are already patched
    if grep -q "openclaw.pluginRegistryState" "$ATTEMPT_FILE" 2>/dev/null; then
      echo "  $(basename "$ATTEMPT_FILE"): already patched ✓"
      continue
    fi
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

# Patch Location 1: after createOpenAIResponsesStoreWrapper (one-time agent setup)
anchor = "agent.streamFn = createOpenAIResponsesStoreWrapper(agent.streamFn);\n}"
if anchor in code:
    code = code.replace(anchor, anchor + wrapper_block, 1)
    print("  location 1: patched (after createOpenAIResponsesStoreWrapper)")
else:
    print("  location 1: anchor not found (may be OK if version differs)")

# Patch Location 2: after anthropicPayloadLogger (per-turn attempt runner — THIS IS THE CRITICAL ONE)
import re
pattern = r'(if \(anthropicPayloadLogger\) activeSession\.agent\.streamFn = anthropicPayloadLogger\.wrapStreamFn\(activeSession\.agent\.streamFn\);)'
wrapper_block2 = """
			// [OpenClaw Plugin APIs Patch] Apply plugin-registered streamFn wrappers (attempt runner)
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
    print("  location 2: patched (after anthropicPayloadLogger — attempt runner)")
else:
    print("  WARNING: Could not find attempt runner anchor (anthropicPayloadLogger)")
    sys.exit(1)

with open(attempt_path, "w") as f:
    f.write(code)
PYEOF
    done
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

  # ================================================================
  # Bust Node compile cache (critical for dist patches)
  # Node caches compiled bytecode and will silently serve the
  # pre-patch version even though the JS files changed on disk.
  # ================================================================
  if [ "$MODE" = "dist" ]; then
    echo "  Clearing Node compile cache..."

    # 1. Touch patched files to invalidate mtime-based caches
    touch "$ROOT/dist/entry.js" 2>/dev/null
    ATTEMPT_FILE=$(grep -l "streamFnWrappers" "$ROOT"/dist/pi-embedded-*.js 2>/dev/null | head -1)
    if [ -n "$ATTEMPT_FILE" ]; then
      touch "$ATTEMPT_FILE" 2>/dev/null
    fi

    # 2. Clear Node's V8 compile cache directories
    rm -rf "$HOME/.cache/node" 2>/dev/null
    rm -rf "$ROOT/.cache" 2>/dev/null
    rm -rf /tmp/node-compile-cache* 2>/dev/null

    # 3. Inject NODE_DISABLE_COMPILE_CACHE into LaunchAgent plist if present
    PLIST="$HOME/Library/LaunchAgents/ai.openclaw.gateway.plist"
    if [ -f "$PLIST" ]; then
      if ! grep -q "NODE_DISABLE_COMPILE_CACHE" "$PLIST" 2>/dev/null; then
        # Insert before the closing </dict> of EnvironmentVariables
        python3 -c "
import re
with open('$PLIST', 'r') as f:
    content = f.read()
inject = '    <key>NODE_DISABLE_COMPILE_CACHE</key>\n    <string>1</string>\n'
# Find the last </dict> inside EnvironmentVariables (before the outer closing </dict>)
# Insert before OPENCLAW_SERVICE_KIND or before the inner closing </dict>
anchor = '    <key>OPENCLAW_SERVICE_KIND</key>'
if anchor in content:
    content = content.replace(anchor, inject + anchor, 1)
else:
    # Fallback: insert before the second-to-last </dict>
    idx = content.rfind('</dict>', 0, content.rfind('</dict>'))
    if idx > 0:
        content = content[:idx] + inject + content[idx:]
with open('$PLIST', 'w') as f:
    f.write(content)
print('    Updated LaunchAgent plist')
" 2>/dev/null
      fi
    fi

    # 4. Also handle systemd (Linux)
    SYSTEMD_UNIT="/etc/systemd/system/openclaw-gateway.service"
    if [ -f "$SYSTEMD_UNIT" ]; then
      if ! grep -q "NODE_DISABLE_COMPILE_CACHE" "$SYSTEMD_UNIT" 2>/dev/null; then
        sudo sed -i '/^\[Service\]/a Environment="NODE_DISABLE_COMPILE_CACHE=1"' "$SYSTEMD_UNIT" 2>/dev/null && \
          echo "    Updated systemd unit" || true
      fi
    fi

    echo "${GREEN}  ✓ Compile cache cleared${RESET}"
    echo ""
    echo "  ${YELLOW}⚠ Restart your OpenClaw gateway to load the patched code:${RESET}"
    echo "    openclaw gateway restart"
    echo ""
  fi

  # ================================================================
  # Install mr-memory plugin
  # ================================================================
  echo "  Installing MemoryRouter plugin..."

  # Remove existing extension dir if present (handles upgrade case)
  MR_EXT="$HOME/.openclaw/extensions/mr-memory"
  if [ -d "$MR_EXT" ]; then
    rm -rf "$MR_EXT" 2>/dev/null
    echo "    Removed existing mr-memory extension"
  fi

  # Temporarily remove mr-memory from config if present (avoids "plugin not found" loop)
  OPENCLAW_CFG="$HOME/.openclaw/openclaw.json"
  MR_BACKUP=""
  if [ -f "$OPENCLAW_CFG" ] && grep -q "mr-memory" "$OPENCLAW_CFG" 2>/dev/null; then
    MR_BACKUP=$(python3 -c "
import json
with open('$OPENCLAW_CFG') as f:
    cfg = json.load(f)
entries = cfg.get('plugins', {}).get('entries', {})
mr = entries.pop('mr-memory', None)
if mr:
    print(json.dumps(mr))
    with open('$OPENCLAW_CFG', 'w') as f:
        json.dump(cfg, f, indent=2)
" 2>/dev/null)
    if [ -n "$MR_BACKUP" ]; then
      echo "    Preserved existing mr-memory config"
    fi
  fi

  # Install the plugin
  if command -v openclaw >/dev/null 2>&1; then
    openclaw plugins install mr-memory 2>&1 | grep -v "^\[" | grep -v "Doctor" | grep -v "migration" | grep -v "^│" | grep -v "^├" | grep -v "^◇" | tail -5
  else
    echo "${YELLOW}    ⚠ openclaw not in PATH — run manually: openclaw plugins install mr-memory${RESET}"
  fi

  # Restore mr-memory config (preserves user's key)
  if [ -n "$MR_BACKUP" ]; then
    python3 -c "
import json
with open('$OPENCLAW_CFG') as f:
    cfg = json.load(f)
if 'plugins' not in cfg: cfg['plugins'] = {}
if 'entries' not in cfg['plugins']: cfg['plugins']['entries'] = {}
cfg['plugins']['entries']['mr-memory'] = json.loads('$MR_BACKUP')
with open('$OPENCLAW_CFG', 'w') as f:
    json.dump(cfg, f, indent=2)
print('    Restored mr-memory config (key preserved)')
" 2>/dev/null
  fi

  echo ""
  echo "${GREEN}  ✅ MemoryRouter plugin installed!${RESET}"
  echo ""
  echo "  ${YELLOW}⚠ Restart your OpenClaw gateway:${RESET}"
  echo "    openclaw gateway restart"
  echo ""
  echo "  Then enable with your memory key:"
  echo "    openclaw mr <your-memory-key>"
  echo ""
  echo "  Get a free key at: ${BOLD}https://app.memoryrouter.ai${RESET}"
  echo ""
else
  echo "${RED}  ✗ Patch verification failed${RESET}"
  exit 1
fi
