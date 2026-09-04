#!/usr/bin/env bash

# ==============================================================================
# Antigravity & Claude Code High-Fidelity Custom Statusline
# ==============================================================================
# Layout:
#   [Model Gradient] │ [Parent/Dir] │ [Branch*↑↓] │ [5h/7d Rate Limits] │ [Tokens/Context% [██████▎░░░░░░░]]
#
# Features:
#   - Per-model family truecolor gradients (Gemini Flash/Pro/Ultra, Antigravity, Claude Opus/Sonnet/Haiku, GPT)
#   - Two-tone workspace directory (subtle parent, highlighted current)
#   - Git branch with lilac/blue gradient, dirty status (*), and ahead/behind (↑N ↓N) counts
#   - Rate limit indicators (5h / 7d / quota) with smooth green→yellow→orange→red continuous gradient
#   - Sub-cell precision context progress bar rendered in 1/8th increments (▏▎▍▌▋▊▉█)
#   - Background fill behind boundary partial block to eliminate terminal gap artifacts
#   - Multi-tier dynamic terminal width detection for Windows (Win32 Console API via Stop hook),
#     Linux (/proc pts walk & stty), and macOS
#   - Intelligent multi-stage responsive degradation to fit narrow terminals cleanly without wrapping
# ==============================================================================

STATUSLINE_COLS=120

# Read full stdin input
input=$(cat)

# --- ANSI Color & Formatting Constants ---
RESET=$'\033[0m'
BOLD=$'\033[1m'
DIM=$'\033[2m'
FG_WHITE=$'\033[97m'
FG_YELLOW=$'\033[93m'
FG_CYAN=$'\033[96m'
FG_DARK_ORANGE=$'\033[38;5;172m'
FG_MUTED=$'\033[38;5;244m'
FG_GREEN=$'\033[38;5;114m'
FG_RED=$'\033[38;5;167m'

# Visible cell count of a string. ${#s} is byte-based here (the statusline
# subprocess inherits no UTF-8 locale), so "·47m" measures 5 and "↑2" measures
# 4. Dropping UTF-8 continuation bytes leaves one byte per character, and every
# glyph this script emits is single-width, so characters == cells. Sets a global
# rather than echoing, to avoid a subshell fork per call.
cells_result=0
cells() {
  local s=${1//[$'\200'-$'\277']/}
  cells_result=${#s}
}

# Truncate string to max visible characters, appending '…' if cut.
truncate_str() {
  local s="$1" max="$2"
  if [ "${#s}" -le "$max" ]; then
    printf '%s' "$s"
  else
    printf '%s…' "${s:0:$((max - 1))}"
  fi
}

# Smooth green→yellow→orange→red gradient for percentage (0-100).
grad_result=""
grad_color() {
  local p=$1
  [ -z "$p" ] && p=0
  [ "$p" -lt 0 ] && p=0
  [ "$p" -gt 100 ] && p=100

  local stops=(0 80 200 100  55 222 205 35  80 255 140 20  100 228 55 45)
  local i p0 r0 g0 b0 p1 r1 g1 b1 span t
  for ((i = 0; i + 7 < ${#stops[@]}; i += 4)); do
    p1=${stops[i+4]}
    [ "$p" -gt "$p1" ] && continue
    p0=${stops[i]};   r0=${stops[i+1]}; g0=${stops[i+2]}; b0=${stops[i+3]}
    r1=${stops[i+5]}; g1=${stops[i+6]}; b1=${stops[i+7]}
    span=$((p1 - p0))
    t=$((p - p0))
    [ "$span" -le 0 ] && span=1
    printf -v grad_result '\033[38;2;%d;%d;%dm' \
      "$(( r0 + (r1 - r0) * t / span ))" \
      "$(( g0 + (g1 - g0) * t / span ))" \
      "$(( b0 + (b1 - b0) * t / span ))"
    return
  done
}

# Multi-stop linear gradient text generator.
grad_text=""
gradient_text() {
  local text="$1"; shift
  local stops=("$@")
  local n=${#text}
  local num_stops=$(( ${#stops[@]} / 3 ))

  if [ "$n" -le 0 ]; then
    grad_text=""
    return
  fi

  if [ "$num_stops" -lt 2 ]; then
    grad_text="$text"
    return
  fi

  local out="" i ch r g b seg_idx t span
  local num_segments=$(( num_stops - 1 ))

  for ((i = 0; i < n; i++)); do
    ch=${text:i:1}
    if [ "$n" -eq 1 ]; then
      r=${stops[0]}; g=${stops[1]}; b=${stops[2]}
    else
      local global_pos=$(( i * num_segments ))
      seg_idx=$(( global_pos / (n - 1) ))
      [ "$seg_idx" -ge "$num_segments" ] && seg_idx=$(( num_segments - 1 ))
      
      local seg_start=$(( seg_idx * (n - 1) / num_segments ))
      local seg_end=$(( (seg_idx + 1) * (n - 1) / num_segments ))
      span=$(( seg_end - seg_start ))
      [ "$span" -le 0 ] && span=1
      t=$(( i - seg_start ))
      [ "$t" -lt 0 ] && t=0
      [ "$t" -gt "$span" ] && t=$span

      local idx0=$(( seg_idx * 3 ))
      local idx1=$(( (seg_idx + 1) * 3 ))
      local r0=${stops[idx0]}   g0=${stops[idx0+1]}   b0=${stops[idx0+2]}
      local r1=${stops[idx1]}   g1=${stops[idx1+1]}   b1=${stops[idx1+2]}

      r=$(( r0 + (r1 - r0) * t / span ))
      g=$(( g0 + (g1 - g0) * t / span ))
      b=$(( b0 + (b1 - b0) * t / span ))
    fi
    out+=$'\033'"[38;2;${r};${g};${b}m${ch}"
  done
  grad_text="$out"
}

# --- Parse JSON Input (Unified for Antigravity & Claude schemas) ---
if [ -n "$input" ]; then
  eval "$(printf '%s' "$input" | jq -r '
    @sh "model_id=\(.model.id // .modelName // .model_name // "")",
    @sh "model_display=\(.model.display_name // .model_display // .modelName // "")",
    @sh "project_dir=\(.workspace.current_dir // .cwd // .workspace.project_dir // .workspacePaths[0] // .project_dir // "")",
    @sh "session_id=\(.session_id // .conversationId // .sessionId // "")",
    @sh "used_pct_raw=\(.context_window.used_percentage // .contextWindow.usedPercentage // .context_percent // .used_percentage // "")",
    @sh "used_tokens_raw=\(.context_window.used_tokens // .context_window.total_input_tokens // .contextWindow.usedTokens // .used_tokens // "")",
    @sh "total_tokens_raw=\(.context_window.total_tokens // .context_window.context_window_size // .contextWindow.totalTokens // .total_tokens // .context_window_size // "")",
    @sh "five_pct_raw=\(.rate_limits.five_hour.used_percentage // .rateLimits.fiveHour.usedPercentage // .five_hour_percent // "")",
    @sh "week_pct_raw=\(.rate_limits.seven_day.used_percentage // .rateLimits.sevenDay.usedPercentage // .seven_day_percent // "")",
    @sh "day_pct_raw=\(.rate_limits.daily.used_percentage // .rateLimits.daily.usedPercentage // "")",
    @sh "five_reset_raw=\(.rate_limits.five_hour.resets_at // .rateLimits.fiveHour.resetsAt // "")",
    @sh "week_reset_raw=\(.rate_limits.seven_day.resets_at // .rateLimits.sevenDay.resetsAt // "")",
    @sh "day_reset_raw=\(.rate_limits.daily.resets_at // .rateLimits.daily.resetsAt // "")",
    @sh "month_pct_raw=\(.rate_limits.monthly.used_percentage // .rateLimits.monthly.usedPercentage // "")",
    @sh "has_plan_limits=\(if (.rate_limits.five_hour // .rate_limits.seven_day // .rateLimits.fiveHour // .rateLimits.sevenDay) then "1" else "" end)",
    @sh "cache_hit_pct=\(if (.prompt_cache.hit_ratio != null) then ((.prompt_cache.hit_ratio * 100) | floor) else "" end)",
    @sh "cache_warm_raw=\(if (.prompt_cache.warm != null) then (.prompt_cache.warm | tostring) else "" end)",
    @sh "cache_expires_raw=\(.prompt_cache.expires_at // "")",
    @sh "cache_ttl_raw=\(.prompt_cache.ttl // "")",
    @sh "cost_usd_raw=\(.cost.total_cost_usd // "")",
    @sh "lines_added_raw=\(.cost.total_lines_added // "")",
    @sh "lines_removed_raw=\(.cost.total_lines_removed // "")"
  ' 2>/dev/null)"
fi

[ -z "$project_dir" ] && project_dir="$(pwd)"
[ -z "$model_display" ] && [ -n "$model_id" ] && model_display="$model_id"
[ -z "$model_display" ] && model_display="Antigravity"

# --- Terminal Width Detection ---
# 1. Check session-specific cache file written by Windows width probe hook
session_key="${session_id//[^A-Za-z0-9_-]/}"
cached_found=0
if [ -n "$session_key" ]; then
  for cache_dir in "$HOME/.antigravity" "$HOME/.claude" "$HOME/.gemini"; do
    if [ -r "$cache_dir/.statusline-cols-$session_key" ]; then
      cached_cols=$(< "$cache_dir/.statusline-cols-$session_key")
      if [[ "$cached_cols" =~ ^[0-9]+$ ]] && [ "$cached_cols" -ge 20 ]; then
        STATUSLINE_COLS="$cached_cols"
        cached_found=1
        break
      fi
    fi
  done
fi

# 2. On Unix (Linux / macOS), query $COLUMNS or stty/tput if no cache
if [ "$cached_found" -eq 0 ]; then
  case "$(uname -s 2>/dev/null)" in
    Linux*|Darwin*)
      if [ -n "$COLUMNS" ] && [ "$COLUMNS" -ge 20 ] 2>/dev/null; then
        STATUSLINE_COLS="$COLUMNS"
      elif command -v tput >/dev/null 2>&1; then
        tput_cols=$(tput cols 2>/dev/null)
        [[ "$tput_cols" =~ ^[0-9]+$ ]] && [ "$tput_cols" -ge 20 ] && STATUSLINE_COLS="$tput_cols"
      fi
      ;;
    *)
      # Windows MSYS2 / MINGW: maintain 120 fallback until first Stop hook fires
      STATUSLINE_COLS=120
      ;;
  esac
fi

# --- Model Display Formatting & Gradient Selection ---
model_display="${model_display/ (1M context)/ (1M)}"
model_display="${model_display/ (2M context)/ (2M)}"
model_display="${model_display/ (High)/}"
model_display="${model_display/ preview/}"
model_display="${model_display/ Preview/}"

model_lower=$(echo "${model_id:-$model_display}" | tr '[:upper:]' '[:lower:]')

case "$model_lower" in
  *flash*)
    # Gemini Flash: Vibrant Blue → Gold → Neon Cyan
    model_rgb=(66 133 244  255 190 40  0 220 180)
    ;;
  *pro*|*ultra*)
    # Gemini Pro / Ultra: Royal Purple → Google Blue → Electric Cyan
    model_rgb=(170 70 255  78 140 255  40 220 240)
    ;;
  *gemini*)
    # Gemini General: Electric Blue → Orchid Purple
    model_rgb=(66 133 244  160 80 255)
    ;;
  *opus*)
    # Claude Opus: Neon Magenta → Indigo Violet
    model_rgb=(255 95 215  115 100 255)
    ;;
  *sonnet*)
    # Claude Sonnet: Cyan → Royal Indigo
    model_rgb=(70 230 235  105 120 255)
    ;;
  *haiku*)
    # Claude Haiku: Lime Green → Vibrant Teal
    model_rgb=(175 240 90   55 205 185)
    ;;
  *gpt*|*o1*|*o3*|*codex*)
    # OpenAI GPT: Mint Emerald → Aqua Marine
    model_rgb=(16 185 129  52 211 153)
    ;;
  *antigravity*|*agy*)
    # Antigravity Gradient: Cosmic Cyan → Fuchsia Purple
    model_rgb=(50 225 240  180 70 255  245 60 170)
    ;;
  *)
    # Default fallback gradient
    model_rgb=(70 230 235  105 120 255)
    ;;
esac

# --- Project Directory Formatting ---
if [ -n "$project_dir" ]; then
  project_dir="${project_dir//\\//}"
  dir_current=$(basename "$project_dir")
  dir_parent_path=$(dirname "$project_dir")
  dir_parent=$(basename "$dir_parent_path")
  [ "$dir_parent" = "." ] || [ "$dir_parent" = "/" ] && dir_parent=""
else
  dir_current="unknown"
  dir_parent=""
fi

# --- Git Repository & Branch Status ---
branch=""
git_dirty=""
git_ab=""
git_ab_cells=0
in_git_repo=""

if [ -n "$project_dir" ] && [ -d "$project_dir" ]; then
  check_dir="$project_dir"
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    [ -z "$check_dir" ] || [ "$check_dir" = "/" ] && break
    if [ -e "$check_dir/.git" ]; then
      in_git_repo=1
      break
    fi
    parent_dir="${check_dir%/*}"
    [ "$parent_dir" = "$check_dir" ] && break
    check_dir="$parent_dir"
  done
fi

if [ -n "$in_git_repo" ] && command -v git >/dev/null 2>&1; then
  branch=$(git -C "$project_dir" --no-optional-locks branch --show-current 2>/dev/null)
  if [ -z "$branch" ]; then
    branch=$(git -C "$project_dir" --no-optional-locks rev-parse --short HEAD 2>/dev/null)
  fi

  if [ -n "$branch" ]; then
    if [ -n "$(git -C "$project_dir" --no-optional-locks status --porcelain 2>/dev/null)" ]; then
      git_dirty="*"
    fi

    ab_counts=$(git -C "$project_dir" --no-optional-locks rev-list --left-right --count "@{upstream}...HEAD" 2>/dev/null)
    if [ -n "$ab_counts" ]; then
      behind=$(echo "$ab_counts" | awk '{print $1}')
      ahead=$(echo "$ab_counts"  | awk '{print $2}')
      if [ "$ahead" -gt 0 ] 2>/dev/null; then
        git_ab+="↑${ahead}"
        git_ab_cells=$((git_ab_cells + 1 + ${#ahead}))
      fi
      if [ "$behind" -gt 0 ] 2>/dev/null; then
        git_ab+="↓${behind}"
        git_ab_cells=$((git_ab_cells + 1 + ${#behind}))
      fi
    fi
  fi
fi

# --- Context Percentage & Token Math ---
used_int=0
if [ -n "$used_pct_raw" ]; then
  used_int=$(printf '%.0f' "$used_pct_raw" 2>/dev/null || echo 0)
elif [ -n "$used_tokens_raw" ] && [ -n "$total_tokens_raw" ] && [ "$total_tokens_raw" -gt 0 ] 2>/dev/null; then
  used_int=$(( used_tokens_raw * 100 / total_tokens_raw ))
fi
[ "$used_int" -lt 0 ] && used_int=0
[ "$used_int" -gt 100 ] && used_int=100

grad_color "$used_int"
bar_fill_color="$grad_result"
bar_empty_color=$'\033[90m'
bar_empty_bg=$'\033[48;5;236m'

token_str=""
format_token_k() {
  local num=$1
  if [ "$num" -ge 1000000 ]; then
    printf '%dM' "$(( num / 1000000 ))"
  elif [ "$num" -ge 1000 ]; then
    printf '%dk' "$(( num / 1000 ))"
  else
    printf '%d' "$num"
  fi
}

if [ -n "$used_tokens_raw" ] && [ -n "$total_tokens_raw" ] && [ "$total_tokens_raw" -gt 0 ] 2>/dev/null; then
  u_fmt=$(format_token_k "$used_tokens_raw")
  t_fmt=$(format_token_k "$total_tokens_raw")
  token_str="${u_fmt}/${t_fmt}"
fi

# --- Rate Limit Segments ---
# used_percentage is refreshed by the host on its own cadence and can sit
# unchanged for minutes at a time. resets_at is the one datum that is live every
# render, so a window at or above this threshold also shows time until it clears.
RESET_COUNTDOWN_THRESHOLD=80

# Sets dur_str to "4d2h" / "3h56m" / "47m" for an epoch in the future, or ""
# when it is absent, malformed, or already elapsed.
dur_str=""
dur_secs=0
fmt_duration() {
  local epoch=$1 secs d h m
  dur_str=""
  dur_secs=0
  [ -z "$epoch" ] && return
  [[ "$epoch" =~ ^[0-9]+$ ]] || return
  secs=$(( epoch - $(date +%s) ))
  [ "$secs" -le 0 ] && return
  dur_secs=$secs
  d=$(( secs / 86400 ))
  h=$(( secs % 86400 / 3600 ))
  m=$(( secs % 3600 / 60 ))
  if [ "$d" -gt 0 ]; then
    dur_str="${d}d${h}h"
  elif [ "$h" -gt 0 ]; then
    dur_str="${h}h${m}m"
  else
    dur_str="${m}m"
  fi
}

# Sets reset_str to " ·3h56m", or "" while the window is still below the
# threshold — a quiet window does not need a countdown.
reset_str=""
fmt_reset() {
  local epoch=$1 pct=$2
  reset_str=""
  [ "$pct" -lt "$RESET_COUNTDOWN_THRESHOLD" ] && return
  fmt_duration "$epoch"
  [ -n "$dur_str" ] && reset_str=" ·${dur_str}"
}
rate_str=""
plain_rate=""
if [ -n "$five_pct_raw" ] && five_int=$(printf '%.0f' "$five_pct_raw" 2>/dev/null); then
  grad_color "$five_int"
  fmt_reset "$five_reset_raw" "$five_int"
  rate_str+="${grad_result}5h:${five_int}%${reset_str}${RESET}"
  plain_rate+="5h:${five_int}%${reset_str}"
fi
if [ -n "$week_pct_raw" ] && week_int=$(printf '%.0f' "$week_pct_raw" 2>/dev/null); then
  grad_color "$week_int"
  [ -n "$rate_str" ] && rate_str+=" "
  [ -n "$plain_rate" ] && plain_rate+=" "
  fmt_reset "$week_reset_raw" "$week_int"
  rate_str+="${grad_result}7d:${week_int}%${reset_str}${RESET}"
  plain_rate+="7d:${week_int}%${reset_str}"
fi
if [ -n "$day_pct_raw" ] && [ -z "$week_pct_raw" ] && day_int=$(printf '%.0f' "$day_pct_raw" 2>/dev/null); then
  grad_color "$day_int"
  [ -n "$rate_str" ] && rate_str+=" "
  [ -n "$plain_rate" ] && plain_rate+=" "
  fmt_reset "$day_reset_raw" "$day_int"
  rate_str+="${grad_result}1d:${day_int}%${reset_str}${RESET}"
  plain_rate+="1d:${day_int}%${reset_str}"
fi

# --- Session Economics: cache health, cache expiry, cost, churn ---
# A warm, high-hit prompt cache is the ordinary case and says nothing worth
# reading, so the hit ratio only appears once it drops below this.
CACHE_HEALTH_THRESHOLD=75

# The expiry countdown is only news near the end of the window: it appears once
# the remaining time falls below this fraction of the cache's own TTL, and takes
# its color from how far through that final stretch it is — green as it appears,
# red as it runs out. When the window lapses the next request re-sends the whole
# conversation at full price.
CACHE_TIMER_THRESHOLD=25

# Used when the payload omits prompt_cache.ttl, so the gate still has a window
# to measure against. Matches the 1h TTL Claude Code reports today.
CACHE_TTL_FALLBACK_SECS=3600

# total_cost_usd is reported whether or not you are billed per token, and on a
# subscription it is a notional figure that would only mislead. Plan membership
# is read from the 5h/7d windows specifically — a monthly quota is not by itself
# a subscription, and per-token accounts can carry one — so the segment stays
# hidden while those windows are present, unless STATUSLINE_SHOW_COST forces it.
# Where a monthly figure does exist, the spend only appears once it passes this,
# keeping the line quiet early in a billing period.
COST_MONTHLY_THRESHOLD=10

cache_plain=""
cache_color=""
cache_sev=0
cache_health=""
if [ -n "$cache_hit_pct" ] && [ "$cache_hit_pct" -lt "$CACHE_HEALTH_THRESHOLD" ] 2>/dev/null; then
  cache_health="${cache_hit_pct}%"
  cache_sev=$(( 100 - cache_hit_pct ))
fi
if [ "$cache_warm_raw" = "false" ]; then
  cache_health="cold"
  cache_sev=100
fi
# TTL arrives as "1h" / "45m" / "30s"; anything unparseable falls back.
cache_ttl_secs=$CACHE_TTL_FALLBACK_SECS
if [[ "$cache_ttl_raw" =~ ^([0-9]+)([smhd])$ ]]; then
  case "${BASH_REMATCH[2]}" in
    s) cache_ttl_secs=${BASH_REMATCH[1]} ;;
    m) cache_ttl_secs=$(( BASH_REMATCH[1] * 60 )) ;;
    h) cache_ttl_secs=$(( BASH_REMATCH[1] * 3600 )) ;;
    d) cache_ttl_secs=$(( BASH_REMATCH[1] * 86400 )) ;;
  esac
fi
[ "$cache_ttl_secs" -le 0 ] && cache_ttl_secs=$CACHE_TTL_FALLBACK_SECS

fmt_duration "$cache_expires_raw"
cache_timer=""
if [ -n "$dur_str" ]; then
  cache_remain_pct=$(( dur_secs * 100 / cache_ttl_secs ))
  if [ "$cache_remain_pct" -lt "$CACHE_TIMER_THRESHOLD" ]; then
    cache_timer="$dur_str"
    # Ramp across the visible stretch only: green the moment it appears at the
    # threshold, red as it reaches zero.
    timer_sev=$(( 100 - cache_remain_pct * 100 / CACHE_TIMER_THRESHOLD ))
    [ "$timer_sev" -lt 0 ] && timer_sev=0
    [ "$timer_sev" -gt 100 ] && timer_sev=100
    [ "$timer_sev" -gt "$cache_sev" ] && cache_sev=$timer_sev
  fi
fi

cache_body="$cache_health"
if [ -n "$cache_timer" ]; then
  if [ -n "$cache_body" ]; then cache_body="$cache_body $cache_timer"; else cache_body="$cache_timer"; fi
fi
if [ -n "$cache_body" ]; then
  cache_plain="cache:${cache_body}"
  grad_color "$cache_sev"
  cache_color="${grad_result}${cache_plain}${RESET}"
fi

cost_plain=""
cost_color=""
if [ -n "$cost_usd_raw" ]; then
  show_cost=0
  if [ -n "${STATUSLINE_SHOW_COST:-}" ]; then
    show_cost=1
  elif [ -z "$has_plan_limits" ]; then
    if [ -n "$month_pct_raw" ] && month_int=$(printf '%.0f' "$month_pct_raw" 2>/dev/null); then
      [ "$month_int" -ge "$COST_MONTHLY_THRESHOLD" ] && show_cost=1
    else
      show_cost=1
    fi
  fi
  if [ "$show_cost" -eq 1 ] && cost_plain=$(printf '$%.2f' "$cost_usd_raw" 2>/dev/null); then
    # Nothing spent yet is not worth a segment.
    if [ "$cost_plain" = '$0.00' ]; then
      cost_plain=""
    else
      cost_color="${FG_MUTED}${cost_plain}${RESET}"
    fi
  else
    cost_plain=""
  fi
fi

lines_plain=""
lines_color=""
lines_added=${lines_added_raw:-0}
lines_removed=${lines_removed_raw:-0}
if [[ "$lines_added" =~ ^[0-9]+$ ]] && [[ "$lines_removed" =~ ^[0-9]+$ ]] &&
   { [ "$lines_added" -gt 0 ] || [ "$lines_removed" -gt 0 ]; }; then
  lines_plain="+${lines_added}/-${lines_removed}"
  lines_color="${FG_GREEN}+${lines_added}${RESET}${DIM}/${RESET}${FG_RED}-${lines_removed}${RESET}"
fi

# The three share one separator, so together they cost 3 cells rather than 9.
# Rebuilt on every measurement because the ladder switches them off one at a
# time and the group collapses entirely once all three are gone.
econ_plain=""
econ_color=""
build_econ() {
  econ_plain=""
  econ_color=""
  local part p c
  for part in cache cost lines; do
    case $part in
      cache) [ "$inc_cache" -eq 1 ] || continue; p=$cache_plain; c=$cache_color ;;
      cost)  [ "$inc_cost"  -eq 1 ] || continue; p=$cost_plain;  c=$cost_color  ;;
      lines) [ "$inc_lines" -eq 1 ] || continue; p=$lines_plain; c=$lines_color ;;
    esac
    [ -z "$p" ] && continue
    if [ -n "$econ_plain" ]; then econ_plain+=" "; econ_color+=" "; fi
    econ_plain+="$p"
    econ_color+="$c"
  done
}

# --- Responsive Width Sizing & Segment Layout ---
cols=$STATUSLINE_COLS
TARGET_MIN_BAR=8
SEP_LEN=3

# Reads the inc_* / b_max / d_max globals and writes $prefix_len, rather than
# echoing into $( ) — build_econ below sets globals of its own, which a
# subshell would discard.
prefix_len=0
prefix_visible_len() {
  local n=${#model_display}
  n=$((n + SEP_LEN))

  if [ "$inc_par" -eq 1 ] && [ -n "$dir_parent" ]; then
    n=$((n + ${#dir_parent} + 1))
  fi

  local d_eff_len=${#dir_current}
  [ -z "$dir_current" ] && d_eff_len=7
  [ "$d_eff_len" -gt "$d_max" ] && d_eff_len=$d_max
  n=$((n + d_eff_len))

  if [ -n "$branch" ]; then
    n=$((n + SEP_LEN))
    local b_eff_len=${#branch}
    [ "$b_eff_len" -gt "$b_max" ] && b_eff_len=$b_max
    n=$((n + b_eff_len))
    n=$((n + ${#git_dirty}))
    [ "$inc_ab" -eq 1 ] && n=$((n + git_ab_cells))
  fi

  if [ "$inc_rate" -eq 1 ] && [ -n "$plain_rate" ]; then
    cells "$plain_rate"
    n=$((n + SEP_LEN + cells_result))
  fi

  build_econ
  if [ -n "$econ_plain" ]; then
    cells "$econ_plain"
    n=$((n + SEP_LEN + cells_result))
  fi

  n=$((n + SEP_LEN + ${#used_int} + 1))

  if [ "$inc_token" -eq 1 ] && [ -n "$token_str" ]; then
    n=$((n + ${#token_str} + 2))
  fi

  n=$((n + 1))
  prefix_len=$n
}

inc_token=1
inc_rate=1
inc_cache=1
inc_cost=1
inc_lines=1
inc_ab=1
inc_par=1
b_max=999
d_max=999
drop_bar=0
budget=$((cols - 2 - TARGET_MIN_BAR))

while :; do
  prefix_visible_len
  [ "$prefix_len" -le "$budget" ] && break

  if [ "$inc_lines" -eq 1 ] && [ -n "$lines_plain" ]; then
    inc_lines=0
  elif [ "$inc_cost" -eq 1 ] && [ -n "$cost_plain" ]; then
    inc_cost=0
  elif [ "$inc_cache" -eq 1 ] && [ -n "$cache_plain" ]; then
    inc_cache=0
  elif [ "$inc_token" -eq 1 ] && [ -n "$token_str" ]; then
    inc_token=0
  elif [ "$inc_rate" -eq 1 ] && [ -n "$plain_rate" ]; then
    inc_rate=0
  elif [ "$inc_ab" -eq 1 ] && [ -n "$git_ab" ]; then
    inc_ab=0
  elif [ "$inc_par" -eq 1 ] && [ -n "$dir_parent" ]; then
    inc_par=0
  elif [ "$b_max" -gt 14 ] && [ -n "$branch" ] && [ "${#branch}" -gt 14 ]; then
    b_max=14
  elif [ "$d_max" -gt 18 ] && [ "${#dir_current}" -gt 18 ]; then
    d_max=18
  elif [ "$b_max" -gt 8 ] && [ -n "$branch" ] && [ "${#branch}" -gt 8 ]; then
    b_max=8
  elif [ "$d_max" -gt 10 ] && [ "${#dir_current}" -gt 10 ]; then
    d_max=10
  else
    drop_bar=1
    break
  fi
done

# --- Assemble Colored Output ---
sep="${DIM}│${RESET}"

gradient_text "$model_display" "${model_rgb[@]}"
colored_prefix="${BOLD}${grad_text}${RESET}"
colored_prefix+=" ${sep} "

if [ "$inc_par" -eq 1 ] && [ -n "$dir_parent" ]; then
  colored_prefix+="${FG_DARK_ORANGE}${dir_parent}${RESET}${DIM}/${RESET}"
fi
dir_show=$(truncate_str "${dir_current:-unknown}" "$d_max")
colored_prefix+="${BOLD}${FG_YELLOW}${dir_show}${RESET}"

if [ -n "$branch" ]; then
  colored_prefix+=" ${sep} "
  branch_show=$(truncate_str "$branch" "$b_max")
  gradient_text "$branch_show" 185 105 255  85 160 255
  colored_prefix+="${grad_text}${RESET}"
  [ -n "$git_dirty" ] && colored_prefix+="${FG_YELLOW}${git_dirty}${RESET}"
  if [ "$inc_ab" -eq 1 ] && [ -n "$git_ab" ]; then
    colored_prefix+="${FG_MUTED}${git_ab}${RESET}"
  fi
fi

if [ "$inc_rate" -eq 1 ] && [ -n "$rate_str" ]; then
  colored_prefix+=" ${sep} "
  colored_prefix+="${rate_str}"
fi

build_econ
if [ -n "$econ_color" ]; then
  colored_prefix+=" ${sep} "
  colored_prefix+="${econ_color}"
fi

colored_prefix+=" ${sep} "
colored_prefix+="${bar_fill_color}${used_int}%${RESET}"
if [ "$inc_token" -eq 1 ] && [ -n "$token_str" ]; then
  colored_prefix+="${DIM}(${token_str})${RESET}"
fi
colored_prefix+=" "

# --- Progress Bar Rendering ---
prefix_visible_len

# The bar is the one elastic thing on the line, so it gives up its ceiling as
# optional segments accumulate rather than pushing everything to the edge. With
# nothing else on it the bar may run to 60 cells; each surviving segment takes
# 6 off that, down to a floor of 18 where it stops being readable.
bar_extras=0
[ "$inc_rate"  -eq 1 ] && [ -n "$plain_rate"  ] && bar_extras=$((bar_extras + 1))
[ "$inc_cache" -eq 1 ] && [ -n "$cache_plain" ] && bar_extras=$((bar_extras + 1))
[ "$inc_cost"  -eq 1 ] && [ -n "$cost_plain"  ] && bar_extras=$((bar_extras + 1))
[ "$inc_lines" -eq 1 ] && [ -n "$lines_plain" ] && bar_extras=$((bar_extras + 1))
[ "$inc_token" -eq 1 ] && [ -n "$token_str"   ] && bar_extras=$((bar_extras + 1))
MAX_BAR_LEN=$(( 60 - 6 * bar_extras ))
[ "$MAX_BAR_LEN" -lt 18 ] && MAX_BAR_LEN=18

bar_outer=2
available=$((cols - prefix_len - bar_outer))

if [ "$available" -lt 1 ]; then
  drop_bar=1
  available=1
else
  available=$(( available * 92 / 100 - 1 ))
  [ "$available" -gt "$MAX_BAR_LEN" ] && available=$MAX_BAR_LEN
  [ "$available" -lt 1 ] && available=1
fi

total_eighths=$(( available * 8 ))
filled_eighths=$(( total_eighths * used_int / 100 ))
full_cells=$(( filled_eighths / 8 ))
remainder=$(( filled_eighths % 8 ))
empty_cells=$(( available - full_cells - (remainder > 0 ? 1 : 0) ))
[ "$empty_cells" -lt 0 ] && empty_cells=0

partial_char=""
case "$remainder" in
  1) partial_char="▏" ;;
  2) partial_char="▎" ;;
  3) partial_char="▍" ;;
  4) partial_char="▌" ;;
  5) partial_char="▋" ;;
  6) partial_char="▊" ;;
  7) partial_char="▉" ;;
esac

bar_filled=""
bar_empty_str=""
for ((i = 0; i < full_cells; i++)); do bar_filled+="█"; done
for ((i = 0; i < empty_cells; i++)); do bar_empty_str+="░"; done

partial_segment=""
if [ -n "$partial_char" ]; then
  partial_segment="${bar_fill_color}${bar_empty_bg}${partial_char}${RESET}"
fi

if [ "$drop_bar" -eq 1 ]; then
  bar=""
else
  bar="${DIM}[${RESET}${bar_fill_color}${bar_filled}${RESET}${partial_segment}${bar_empty_color}${bar_empty_str}${RESET}${DIM}]${RESET}"
fi

printf '%s%s\n' "$colored_prefix" "$bar"
