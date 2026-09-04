#!/usr/bin/env bash
# ==============================================================================
# Stop Hook: Terminal Width Cache Updater
# ==============================================================================
# Executed on agent loop stops (or post tool use) to probe the true terminal
# window width using Win32 Console API via width-probe.ps1 and cache it per session.
# ==============================================================================

input=$(cat)

# Extract session key from Antigravity / Claude payload
session_key=$(printf '%s' "$input" | jq -r '(.session_id // .conversationId // .sessionId // "")' 2>/dev/null)
session_key="${session_key//[^A-Za-z0-9_-]/}"

[ -z "$session_key" ] && exit 0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PS_SCRIPT_WIN=$(cygpath -w "$SCRIPT_DIR/width-probe.ps1" 2>/dev/null || echo "$SCRIPT_DIR/width-probe.ps1")

cols=$(powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass \
  -File "$PS_SCRIPT_WIN" 2>/dev/null | tr -d '\r\n ')

if [[ "$cols" =~ ^[0-9]+$ ]] && [ "$cols" -ge 20 ] && [ "$cols" -le 1000 ]; then
  for dir in "$HOME/.antigravity" "$HOME/.claude" "$HOME/.gemini"; do
    mkdir -p "$dir" 2>/dev/null
    printf '%s\n' "$cols" > "$dir/.statusline-cols-$session_key" 2>/dev/null
  done
fi
