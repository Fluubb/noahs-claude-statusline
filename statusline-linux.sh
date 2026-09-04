#!/usr/bin/env bash

# ==============================================================================
# Antigravity & Claude Code High-Fidelity Custom Statusline (Linux / macOS / WSL)
# ==============================================================================
# Resolves terminal window width directly by inspecting ancestor file descriptors
# in /proc without requiring PowerShell hooks or cache files.
# ==============================================================================

STATUSLINE_COLS=120

# Inline /proc pts terminal width detector
detect_linux_cols() {
  local pid=$$ ppid="" fd pts target
  while [ -n "$pid" ] && [ "$pid" -gt 1 ] 2>/dev/null; do
    for fd in 0 1 2 255; do
      target=$(readlink "/proc/$pid/fd/$fd" 2>/dev/null)
      if [[ "$target" =~ ^/dev/pts/[0-9]+$ ]]; then
        local sz
        sz=$(stty size < "$target" 2>/dev/null)
        if [ -n "$sz" ]; then
          local c="${sz#* }"
          if [[ "$c" =~ ^[0-9]+$ ]] && [ "$c" -ge 20 ]; then
            echo "$c"
            return
          fi
        fi
      fi
    done
    ppid=$(awk '{print $4}' "/proc/$pid/stat" 2>/dev/null)
    [ "$ppid" = "$pid" ] && break
    pid="$ppid"
  done
  
  if [ -n "$COLUMNS" ] && [ "$COLUMNS" -ge 20 ] 2>/dev/null; then
    echo "$COLUMNS"
  elif command -v tput >/dev/null 2>&1; then
    local tc
    tc=$(tput cols 2>/dev/null)
    [[ "$tc" =~ ^[0-9]+$ ]] && [ "$tc" -ge 20 ] && echo "$tc"
  fi
}

detected=$(detect_linux_cols 2>/dev/null)
[[ "$detected" =~ ^[0-9]+$ ]] && STATUSLINE_COLS="$detected"

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

truncate_str() {
  local s="$1" max="$2"
  if [ "${#s}" -le "$max" ]; then
    printf '%s' "$s"
  else
    printf '%s…' "${s:0:$((max - 1))}"
  fi
}

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

if [ -n "$input" ]; then
  eval "$(printf '%s' "$input" | jq -r '
    @sh "model_id=\(.model.id // .modelName // .model_name // "")",
    @sh "model_display=\(.model.display_name // .model_display // .modelName // "")",
    @sh "project_dir=\(.workspace.project_dir // .workspacePaths[0] // .project_dir // .cwd // "")",
    @sh "session_id=\(.session_id // .conversationId // .sessionId // "")",
    @sh "used_pct_raw=\(.context_window.used_percentage // .contextWindow.usedPercentage // .context_percent // .used_percentage // "")",
    @sh "used_tokens_raw=\(.context_window.used_tokens // .contextWindow.usedTokens // .used_tokens // "")",
    @sh "total_tokens_raw=\(.context_window.total_tokens // .contextWindow.totalTokens // .total_tokens // .context_window_size // "")",
    @sh "five_pct_raw=\(.rate_limits.five_hour.used_percentage // .rateLimits.fiveHour.usedPercentage // .five_hour_percent // "")",
    @sh "week_pct_raw=\(.rate_limits.seven_day.used_percentage // .rateLimits.sevenDay.usedPercentage // .seven_day_percent // "")",
    @sh "day_pct_raw=\(.rate_limits.daily.used_percentage // .rateLimits.daily.usedPercentage // "")",
    @sh "five_reset_raw=\(.rate_limits.five_hour.resets_at // .rateLimits.fiveHour.resetsAt // "")",
    @sh "week_reset_raw=\(.rate_limits.seven_day.resets_at // .rateLimits.sevenDay.resetsAt // "")",
    @sh "day_reset_raw=\(.rate_limits.daily.resets_at // .rateLimits.daily.resetsAt // "")"
  ' 2>/dev/null)"
fi

[ -z "$project_dir" ] && project_dir="$(pwd)"
[ -z "$model_display" ] && [ -n "$model_id" ] && model_display="$model_id"
[ -z "$model_display" ] && model_display="Antigravity"

model_display="${model_display/ (1M context)/ (1M)}"
model_display="${model_display/ (2M context)/ (2M)}"
model_display="${model_display/ (High)/}"
model_display="${model_display/ preview/}"
model_display="${model_display/ Preview/}"

model_lower=$(echo "${model_id:-$model_display}" | tr '[:upper:]' '[:lower:]')

case "$model_lower" in
  *flash*)
    model_rgb=(66 133 244  255 190 40  0 220 180)
    ;;
  *pro*|*ultra*)
    model_rgb=(170 70 255  78 140 255  40 220 240)
    ;;
  *gemini*)
    model_rgb=(66 133 244  160 80 255)
    ;;
  *opus*)
    model_rgb=(255 95 215  115 100 255)
    ;;
  *sonnet*)
    model_rgb=(70 230 235  105 120 255)
    ;;
  *haiku*)
    model_rgb=(175 240 90   55 205 185)
    ;;
  *gpt*|*o1*|*o3*|*codex*)
    model_rgb=(16 185 129  52 211 153)
    ;;
  *antigravity*|*agy*)
    model_rgb=(50 225 240  180 70 255  245 60 170)
    ;;
  *)
    model_rgb=(70 230 235  105 120 255)
    ;;
esac

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

rate_str=""
plain_rate=""
# used_percentage is refreshed by the host on its own cadence and can sit
# unchanged for minutes at a time. resets_at is the one datum that is live every
# render, so a window at or above this threshold also shows time until it clears.
RESET_COUNTDOWN_THRESHOLD=80

# Sets reset_str to " ·4d2h" / " ·3h56m" / " ·47m", or "" when the window is
# quiet, the timestamp is absent or malformed, or the reset has already passed.
reset_str=""
fmt_reset() {
  local epoch=$1 pct=$2 secs d h m
  reset_str=""
  [ -z "$epoch" ] && return
  [[ "$epoch" =~ ^[0-9]+$ ]] || return
  [ "$pct" -lt "$RESET_COUNTDOWN_THRESHOLD" ] && return
  secs=$(( epoch - $(date +%s) ))
  [ "$secs" -le 0 ] && return
  d=$(( secs / 86400 ))
  h=$(( secs % 86400 / 3600 ))
  m=$(( secs % 3600 / 60 ))
  if [ "$d" -gt 0 ]; then
    reset_str=" ·${d}d${h}h"
  elif [ "$h" -gt 0 ]; then
    reset_str=" ·${h}h${m}m"
  else
    reset_str=" ·${m}m"
  fi
}

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

cols=$STATUSLINE_COLS
TARGET_MIN_BAR=8
SEP_LEN=3

prefix_visible_len() {
  local inc_token=$1 inc_rate=$2 inc_ab=$3 inc_par=$4 b_max=$5 d_max=$6
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
    n=$((n + SEP_LEN + ${#plain_rate}))
  fi

  n=$((n + SEP_LEN + ${#used_int} + 1))

  if [ "$inc_token" -eq 1 ] && [ -n "$token_str" ]; then
    n=$((n + ${#token_str} + 2))
  fi

  n=$((n + 1))
  echo "$n"
}

inc_token=1
inc_rate=1
inc_ab=1
inc_par=1
b_max=999
d_max=999
drop_bar=0
budget=$((cols - 2 - TARGET_MIN_BAR))

while :; do
  cur_len=$(prefix_visible_len "$inc_token" "$inc_rate" "$inc_ab" "$inc_par" "$b_max" "$d_max")
  [ "$cur_len" -le "$budget" ] && break

  if [ "$inc_token" -eq 1 ] && [ -n "$token_str" ]; then
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

colored_prefix+=" ${sep} "
colored_prefix+="${bar_fill_color}${used_int}%${RESET}"
if [ "$inc_token" -eq 1 ] && [ -n "$token_str" ]; then
  colored_prefix+="${DIM}(${token_str})${RESET}"
fi
colored_prefix+=" "

visible_len=$(prefix_visible_len "$inc_token" "$inc_rate" "$inc_ab" "$inc_par" "$b_max" "$d_max")
MAX_BAR_LEN=60
bar_outer=2
available=$((cols - visible_len - bar_outer))

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
