#!/usr/bin/env bash
# Assertion tests for the session-economics segments: prompt-cache health,
# prompt-cache expiry countdown, session cost and lines changed.
#
# The rules under test:
#   - cache health appears only below CACHE_HEALTH_THRESHOLD (75%), or when cold
#   - the cache expiry countdown appears whenever expires_at is in the future
#   - cost appears only when billing looks per-token (no 5h/7d plan windows),
#     and then only above COST_MONTHLY_THRESHOLD (10%) if a monthly figure exists
#   - lines changed appear only when something actually changed

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pass=0; fail=0
now=$(date +%s)

render() {
  printf '%s' "$1" | bash "$SCRIPT_DIR/statusline.sh" | sed $'s/\033\[[0-9;]*m//g'
}

# $1 = JSON object merged over the base payload
payload() {
  jq -nc --argjson x "$1" --arg d "$SCRIPT_DIR" '{
    model: { id: "claude-opus-5", display_name: "Opus 5" },
    workspace: { current_dir: $d },
    session_id: "test-economics",
    context_window: { total_input_tokens: 219726, context_window_size: 1000000, used_percentage: 22 }
  } * $x'
}

assert_has() {
  if [[ "$2" == *"$3"* ]]; then
    echo "  PASS  $1"; pass=$((pass+1))
  else
    echo "  FAIL  $1"; echo "        expected to contain: [$3]"; echo "        got: [$2]"; fail=$((fail+1))
  fi
}
assert_lacks() {
  if [[ "$2" != *"$3"* ]]; then
    echo "  PASS  $1"; pass=$((pass+1))
  else
    echo "  FAIL  $1"; echo "        expected NOT to contain: [$3]"; echo "        got: [$2]"; fail=$((fail+1))
  fi
}

exp_far=$(( now + 2850 ))    # 47m out — most of a 1h window still to run
exp_near=$(( now + 630 ))    # 10m out — inside the final quarter
plan='{ "five_hour": { "used_percentage": 19 }, "seven_day": { "used_percentage": 37 } }'

echo ""
echo "Prompt cache health"

out=$(render "$(payload "{\"prompt_cache\":{\"warm\":true,\"hit_ratio\":0.987,\"ttl\":\"1h\",\"expires_at\":$exp_far}}")")
assert_lacks "healthy cache well inside its window is silent" "$out" "cache:"

out=$(render "$(payload "{\"prompt_cache\":{\"warm\":true,\"hit_ratio\":0.62,\"ttl\":\"1h\",\"expires_at\":$exp_far}}")")
assert_has   "degraded cache shows the hit ratio"      "$out" "cache:62%"
assert_lacks "degraded cache far from expiry: no timer" "$out" "47m"

out=$(render "$(payload "{\"prompt_cache\":{\"warm\":true,\"hit_ratio\":0.75,\"ttl\":\"1h\",\"expires_at\":$exp_far}}")")
assert_lacks "at threshold 75% stays quiet"            "$out" "75%"
out=$(render "$(payload "{\"prompt_cache\":{\"warm\":true,\"hit_ratio\":0.74,\"ttl\":\"1h\",\"expires_at\":$exp_far}}")")
assert_has   "just under threshold speaks up"          "$out" "cache:74%"

out=$(render "$(payload "{\"prompt_cache\":{\"warm\":false,\"hit_ratio\":0.99,\"ttl\":\"1h\",\"expires_at\":$exp_far}}")")
assert_has   "cold cache overrides a high ratio"       "$out" "cache:cold"

echo ""
echo "Prompt cache expiry countdown (below 25% of TTL)"

out=$(render "$(payload "{\"prompt_cache\":{\"warm\":true,\"hit_ratio\":0.99,\"ttl\":\"1h\",\"expires_at\":$(( now + 1000 ))}}")")
assert_lacks "16m of a 1h window: above the gate"      "$out" "cache:"

out=$(render "$(payload "{\"prompt_cache\":{\"warm\":true,\"hit_ratio\":0.99,\"ttl\":\"1h\",\"expires_at\":$exp_near}}")")
assert_has   "10m of a 1h window: countdown appears"   "$out" "cache:10m"

out=$(render "$(payload "{\"prompt_cache\":{\"warm\":true,\"hit_ratio\":0.99,\"ttl\":\"5m\",\"expires_at\":$exp_near}}")")
assert_lacks "same 10m against a 5m TTL: not near expiry" "$out" "cache:"

out=$(render "$(payload "{\"prompt_cache\":{\"warm\":true,\"hit_ratio\":0.99,\"ttl\":\"5m\",\"expires_at\":$(( $(date +%s) + 70 ))}}")")
assert_has   "1m of a 5m window: countdown appears"    "$out" "cache:1m"

out=$(render "$(payload "{\"prompt_cache\":{\"warm\":true,\"hit_ratio\":0.99,\"expires_at\":$exp_near}}")")
assert_has   "missing ttl falls back to a 1h window"   "$out" "cache:10m"

out=$(render "$(payload "{\"prompt_cache\":{\"warm\":true,\"hit_ratio\":0.62,\"ttl\":\"1h\",\"expires_at\":$exp_near}}")")
assert_has   "ratio and countdown share one segment"   "$out" "cache:62% 10m"

out=$(render "$(payload '{"prompt_cache":{"warm":true,"hit_ratio":0.99,"ttl":"1h"}}')")
assert_lacks "no expires_at: no cache segment"         "$out" "cache:"

out=$(render "$(payload "{\"prompt_cache\":{\"warm\":true,\"hit_ratio\":0.99,\"ttl\":\"1h\",\"expires_at\":$(( now - 60 ))}}")")
assert_lacks "elapsed expires_at: no countdown"        "$out" "cache:"

out=$(render "$(payload "{\"prompt_cache\":{\"warm\":false,\"hit_ratio\":0.4,\"ttl\":\"1h\",\"expires_at\":$(( now - 60 ))}}")")
assert_has   "cold with elapsed expiry still warns"    "$out" "cache:cold"

echo ""
echo "Session cost"

out=$(render "$(payload "{\"rate_limits\":$plan,\"cost\":{\"total_cost_usd\":11.2187}}")")
assert_lacks "hidden on a subscription (5h/7d present)" "$out" "11.22"

out=$(render "$(payload '{"cost":{"total_cost_usd":11.2187}}')")
assert_has   "shown per-token with no monthly figure"   "$out" "\$11.22"

out=$(render "$(payload '{"rate_limits":{"monthly":{"used_percentage":4}},"cost":{"total_cost_usd":11.2187}}')")
assert_lacks "per-token below 10% monthly stays quiet"  "$out" "11.22"

out=$(render "$(payload '{"rate_limits":{"monthly":{"used_percentage":10}},"cost":{"total_cost_usd":11.2187}}')")
assert_has   "per-token at 10% monthly appears"         "$out" "\$11.22"

out=$(STATUSLINE_SHOW_COST=1 render "$(payload "{\"rate_limits\":$plan,\"cost\":{\"total_cost_usd\":11.2187}}")")
assert_has   "STATUSLINE_SHOW_COST forces it on a plan" "$out" "\$11.22"

out=$(render "$(payload '{"cost":{"total_cost_usd":0.5}}')")
assert_has   "rounded to two decimals"                  "$out" "\$0.50"

out=$(render "$(payload '{"cost":{"total_cost_usd":0}}')")
assert_lacks "nothing spent yet: segment hidden"        "$out" "$0.00"

echo ""
echo "Lines changed"

out=$(render "$(payload '{"cost":{"total_lines_added":142,"total_lines_removed":38}}')")
assert_has   "churn renders as +added/-removed"         "$out" "+142/-38"

out=$(render "$(payload '{"cost":{"total_lines_added":0,"total_lines_removed":0}}')")
assert_lacks "no churn yet: segment hidden"             "$out" "+0/-0"

out=$(render "$(payload '{"cost":{"total_lines_added":9,"total_lines_removed":0}}')")
assert_has   "additions only still render"              "$out" "+9/-0"

out=$(render "$(payload '{}')")
assert_lacks "empty cost object: nothing rendered"      "$out" "+0"

echo ""
if [ "$fail" -eq 0 ]; then
  echo "  $pass passed, 0 failed"
else
  echo "  $pass passed, $fail failed"
fi
[ "$fail" -eq 0 ]
