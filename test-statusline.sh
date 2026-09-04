#!/usr/bin/env bash
# Test harness for statusline.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ""
echo -e "\033[1;36m================================================================\033[0m"
echo -e "\033[1m   ANTIGRAVITY & CLAUDE STATUSLINE BASH TEST HARNESS\033[0m"
echo -e "\033[1;36m================================================================\033[0m"
echo ""

run_test() {
  local title="$1"
  local json="$2"
  echo -e "\033[1mTest: $title\033[0m"
  printf '%s' "$json" | bash "$SCRIPT_DIR/statusline.sh"
  echo ""
}

run_test "Gemini 3.7 Flash - Clean Repo - Moderate Context" '{
  "model": { "id": "gemini-3.7-flash", "display_name": "Gemini 3.7 Flash" },
  "workspace": { "project_dir": "'"$SCRIPT_DIR"'" },
  "session_id": "test-1",
  "context_window": { "used_percentage": 34, "used_tokens": 340000, "total_tokens": 1000000 },
  "rate_limits": { "five_hour": { "used_percentage": 22 }, "seven_day": { "used_percentage": 14 } }
}'

run_test "Gemini 3.7 Pro - Heavy Context & High Rate Limits" '{
  "model": { "id": "gemini-3.7-pro", "display_name": "Gemini 3.7 Pro" },
  "workspace": { "project_dir": "'"$SCRIPT_DIR"'" },
  "session_id": "test-2",
  "context_window": { "used_percentage": 87.5, "used_tokens": 875000, "total_tokens": 1000000 },
  "rate_limits": { "five_hour": { "used_percentage": 84 }, "seven_day": { "used_percentage": 65 } }
}'

run_test "Antigravity Agent - 2M Token Window - Low Usage" '{
  "model": { "id": "antigravity-agent", "display_name": "Antigravity 2.0" },
  "workspace": { "project_dir": "'"$SCRIPT_DIR"'" },
  "session_id": "test-3",
  "context_window": { "used_percentage": 12, "used_tokens": 240000, "total_tokens": 2000000 },
  "rate_limits": { "five_hour": { "used_percentage": 8 }, "seven_day": { "used_percentage": 5 } }
}'

run_test "Claude Opus 4.7 - Sub-cell Precision Test (47% Context)" '{
  "model": { "id": "claude-opus-4-7", "display_name": "Claude Opus 4.7 (1M context)" },
  "workspace": { "project_dir": "'"$SCRIPT_DIR"'" },
  "session_id": "test-4",
  "context_window": { "used_percentage": 47, "used_tokens": 470000, "total_tokens": 1000000 },
  "rate_limits": { "five_hour": { "used_percentage": 42 }, "seven_day": { "used_percentage": 18 } }
}'

run_test "Claude Sonnet 3.7 - Critical Limit Test (96% Context)" '{
  "model": { "id": "claude-3-7-sonnet", "display_name": "Claude Sonnet 3.7" },
  "workspace": { "project_dir": "'"$SCRIPT_DIR"'" },
  "session_id": "test-5",
  "context_window": { "used_percentage": 96, "used_tokens": 192000, "total_tokens": 200000 },
  "rate_limits": { "five_hour": { "used_percentage": 92 }, "seven_day": { "used_percentage": 89 } }
}'

# --- Narrow-terminal degradation ---------------------------------------------
# Drives STATUSLINE_COLS the way the real Stop hook does, by writing the
# per-session cache file, then removes what it wrote. Each line prints under a
# ruler of the width it was rendered for, so an overrun is obvious.
CACHE_FILE="$HOME/.claude/.statusline-cols-degradation-test"
trap 'rm -f "$CACHE_FILE"' EXIT

ruler() {
  local n=$1 i out=""
  for ((i = 1; i <= n; i++)); do
    if [ $((i % 10)) -eq 0 ]; then out+="|"; else out+="-"; fi
  done
  printf '%s' "$out"
}

echo ""
echo -e "\033[1;36m================================================================\033[0m"
echo -e "\033[1m   NARROW TERMINAL DEGRADATION LADDER\033[0m"
echo -e "\033[1;36m================================================================\033[0m"
echo "  Token fraction goes first, then rate limits, then git ahead/behind,"
echo "  then the parent dir, then branch and dir truncate, then the bar drops."
echo "  Anything past the ruler would have wrapped in a real terminal."

for cols in 120 100 84 72 60 48 36; do
  printf '%s\n' "$cols" > "$CACHE_FILE"
  printf '\n\033[2m%s  (cols=%s)\033[0m\n' "$(ruler "$cols")" "$cols"
  printf '%s' '{
    "model": { "id": "gemini-3.7-flash", "display_name": "Gemini 3.7 Flash" },
    "workspace": { "project_dir": "'"$SCRIPT_DIR"'" },
    "session_id": "degradation-test",
    "context_window": { "used_percentage": 47, "used_tokens": 470000, "total_tokens": 1000000 },
    "rate_limits": { "five_hour": { "used_percentage": 42 }, "seven_day": { "used_percentage": 18 } }
  }' | bash "$SCRIPT_DIR/statusline.sh"
done
echo ""
