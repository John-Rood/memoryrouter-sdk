#!/bin/sh
# Patch OpenClaw with Plugin APIs (PR #18911)
# Adds: registerStreamFnWrapper, updatePluginConfig, updatePluginEnabled
# Usage: curl -fsSL https://raw.githubusercontent.com/John-Rood/memoryrouter-sdk/main/patches/patch-openclaw.sh | sh
set -e

BOLD="\033[1m"
GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
RESET="\033[0m"

PATCH_URL="https://raw.githubusercontent.com/John-Rood/memoryrouter-sdk/main/patches/openclaw-plugin-apis.patch"

echo ""
echo "${BOLD}  OpenClaw Plugin APIs Patch${RESET}"
echo "  ──────────────────────────────"
echo "  PR #18911: registerStreamFnWrapper + updatePluginConfig"
echo ""

# Find OpenClaw install
if [ -n "$OPENCLAW_ROOT" ]; then
  ROOT="$OPENCLAW_ROOT"
elif [ -d "$HOME/.openclaw/install" ]; then
  ROOT="$HOME/.openclaw/install"
elif command -v openclaw >/dev/null 2>&1; then
  # Try to find from the binary
  OPENCLAW_BIN=$(which openclaw)
  ROOT=$(dirname $(dirname "$OPENCLAW_BIN"))
  if [ ! -f "$ROOT/package.json" ]; then
    ROOT=""
  fi
fi

if [ -z "$ROOT" ] || [ ! -f "$ROOT/package.json" ]; then
  echo "${RED}  ✗ Could not find OpenClaw installation.${RESET}"
  echo ""
  echo "  Set OPENCLAW_ROOT and try again:"
  echo "    ${BOLD}OPENCLAW_ROOT=/path/to/openclaw curl -fsSL ... | sh${RESET}"
  exit 1
fi

echo "  Found OpenClaw at: ${ROOT}"

# Check if already patched
if grep -q "streamFnWrappers" "$ROOT/src/plugins/registry.ts" 2>/dev/null; then
  echo "${GREEN}  ✓ Already patched — plugin APIs are present.${RESET}"
  echo ""
  exit 0
fi

# Download patch
echo "  Downloading patch..."
curl -fsSL -o /tmp/openclaw-plugin-apis.patch "$PATCH_URL" || {
  echo "${RED}  ✗ Failed to download patch${RESET}"
  exit 1
}

# Apply
cd "$ROOT"
echo "  Applying patch..."

if git apply --check /tmp/openclaw-plugin-apis.patch 2>/dev/null; then
  git apply /tmp/openclaw-plugin-apis.patch
  echo "${GREEN}  ✓ Patch applied cleanly${RESET}"
elif git apply --3way /tmp/openclaw-plugin-apis.patch 2>/dev/null; then
  echo "${GREEN}  ✓ Patch applied with 3-way merge${RESET}"
else
  echo "${YELLOW}  Trying with --reject to see what fails...${RESET}"
  git apply --reject /tmp/openclaw-plugin-apis.patch 2>&1 || true
  echo "${RED}  ✗ Patch could not be applied automatically.${RESET}"
  echo "    Your OpenClaw version may be too different from the PR base."
  echo "    Check .rej files for conflicts."
  rm -f /tmp/openclaw-plugin-apis.patch
  exit 1
fi

rm -f /tmp/openclaw-plugin-apis.patch

# Rebuild
echo "  Rebuilding OpenClaw..."
if command -v pnpm >/dev/null 2>&1; then
  pnpm build 2>&1 | tail -3
elif command -v npm >/dev/null 2>&1; then
  npm run build 2>&1 | tail -3
else
  echo "${YELLOW}  ⚠ No package manager found — run 'pnpm build' manually${RESET}"
fi

echo ""
echo "${GREEN}  ✅ OpenClaw patched with plugin APIs!${RESET}"
echo ""
echo "  You can now install plugins that use these APIs."
echo "  When PR #18911 merges upstream, this patch becomes a no-op."
echo ""
