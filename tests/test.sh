#!/usr/bin/env bash
# Runs statusline.sh against made-up session data and checks what it prints.
# Usage: tests/test.sh [path/to/bash]   (to test another bash, e.g. 3.2)
set -u
here=$(cd "$(dirname "$0")" && pwd)
script="$here/../statusline.sh"
shell=${1:-bash}
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
now=$(date +%s)
pass=0 fail=0

# Strip colours so the checks read as plain text; keep the colour of named pieces
# available through `colour_of`.
plain() { sed -e 's/\x1b\[[0-9;]*m//g'; }

run() { # run JSON [ENV=VALUE...] -> output (plain icons, dark colours, fresh runtime dir)
  local json=$1; shift
  env -i HOME="$tmp" PATH="$PATH" XDG_RUNTIME_DIR="$tmp/rt" STATUSLINE_ICONS=plain \
    STATUSLINE_COLORS=dark "$@" "$shell" "$script" <<<"$json"
}

check() { # check NAME EXPECTED ACTUAL
  if [ "$2" = "$3" ]; then pass=$((pass + 1)); else
    fail=$((fail + 1)); printf 'FAIL %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3"; fi
}

contains() { # contains NAME NEEDLE HAYSTACK
  case $3 in *"$2"*) pass=$((pass + 1)) ;; *)
    fail=$((fail + 1)); printf 'FAIL %s\n  wanted:   %s\n  in:       %s\n' "$1" "$2" "$3" ;; esac
}

session() { # session [prompt_cache JSON] [rate_limits JSON] [context %]
  printf '{"workspace":{"current_dir":"%s"},"model":{"display_name":"Opus"},"context_window":{"used_percentage":%s},"prompt_cache":%s,"rate_limits":%s}' \
    "$tmp/nogit" "${3:-null}" "${1:-null}" "${2:-null}"
}
cache() { printf '{"warm":true,"expires_at":%s,"hit_ratio":0.97,"caching_observed":true}' $((now + $1)); }
limits() { printf '{"five_hour":{"used_percentage":%s,"resets_at":%s},"seven_day":{"used_percentage":%s,"resets_at":%s}}' "$1" $((now + $2)) "$3" $((now + $4)); }
fresh() { rm -rf "$tmp/rt"; mkdir -p "$tmp/rt" "$tmp/nogit"; }

# --- basics
fresh
check "no data yet" "nogit Opus" "$(run "$(session)" | plain)"
check "context" "nogit 41% Opus" "$(run "$(session null null 41)" | plain)"

# --- cache bands (plain icons: ◕ full, ◑ half, ◔ low, ❄ cold)
check "cache 58m" "nogit Opus ◕97%"     "$(run "$(session "$(cache 3500)")" | plain)"
check "cache 33m" "nogit Opus ◑97%"     "$(run "$(session "$(cache 2000)")" | plain)"
check "cache 16m" "nogit Opus ◔97%"     "$(run "$(session "$(cache 1000)")" | plain)"
check "cache 8m"  "nogit Opus 8m◔97%"   "$(run "$(session "$(cache 500)")" | plain)"
check "cache 30s" "nogit Opus <1m◔97%"  "$(run "$(session "$(cache 30)")" | plain)"
check "cache cold" "nogit Opus ❄80%" \
  "$(run "$(session '{"warm":false,"hit_ratio":0.8,"caching_observed":true}')" | plain)"
contains "cache 8m is orange" $'\033[38;5;214m◔97%' "$(run "$(session "$(cache 500)")")"
contains "cache 90s is red"   $'\033[38;5;196m◔97%' "$(run "$(session "$(cache 90)")")"

# --- limits
fresh
check "limits, no history" "nogit Opus 62%↺2h10 70%⟲3d" \
  "$(run "$(session null "$(limits 62 7800 70 300000)")" | plain)"
fresh
awk -v now="$now" -v r5=$((now + 7800)) -v r7=$((now + 300000)) 'BEGIN {
  for (m = 60; m >= 2; m--) printf "%d %.2f %d 70 %d\n", now - m * 60, 62 - 22 * m / 60, r5, r7 }' \
  > "$tmp/rt/claude-statusline-limits"
check "5h projection from the last hour" "nogit Opus 62%→109%↺2h10 70%⟲3d" \
  "$(run "$(session null "$(limits 62 7800 70 300000)")" | plain)"
check "idle session shows the newest logged reading" "nogit Opus 62%→109%↺2h10 70%⟲3d" \
  "$(run "$(session null "$(limits 45 7800 70 300000)")" | plain)"
check "new 5h window ignores old readings" "nogit Opus 3%↺4h58 70%⟲3d" \
  "$(run "$(session null "$(limits 3 17900 70 300000)")" | plain)"
fresh
for m in $(seq 40 -1 1); do echo "$((now - m * 60)) 7 $((now + 12600)) 7 $((now + 500000))"; done > "$tmp/rt/claude-statusline-limits"
run "$(session null "$(limits 12 12600 7 500000)")" >/dev/null
check "a newer reading is logged at once" "12" "$(tail -n1 "$tmp/rt/claude-statusline-limits" | cut -d' ' -f2)"

# Weekly colour comes from the average since the week opened (reset - 7d), not the log.
week() { run "$(session null "$(limits 1 7800 "$1" "$2")")"; }
fresh
contains "7d on course for 86% is plain"  $'\033[38;5;245m21%'  "$(week 21 458320)"
fresh
contains "7d on course for 99% is orange" $'\033[38;5;214m50%'  "$(week 50 300000)"
fresh
contains "7d on course for 115% is orange" $'\033[38;5;214m58%'  "$(week 58 300000)"
fresh
contains "7d on course for 138% is red"   $'\033[38;5;196m70%'  "$(week 70 300000)"
fresh
contains "7d under 24h in is plain"       $'\033[38;5;245m30%'  "$(week 30 561600)"
fresh
contains "7d under 10% used is plain"     $'\033[38;5;245m9%'   "$(week 9 590000)"

# --- git
mkdir -p "$tmp/repo" && git -C "$tmp/repo" init -q -b main && touch "$tmp/repo/a" "$tmp/repo/b"
repo_json=$(printf '{"workspace":{"current_dir":"%s"},"model":{"display_name":"Opus"}}' "$tmp/repo")
check "dirty branch" "repo ⎇ main+2 Opus" "$(run "$repo_json" | plain)"

# --- colours and icons
fresh
contains "light palette" $'\033[38;5;240m' "$(run "$(session)" STATUSLINE_COLORS=light)"
contains "ansi palette uses faint for the model" $'\033[2mOpus' "$(run "$(session)" STATUSLINE_COLORS=ansi)"
printf '{"theme":"light"}' > "$tmp/.claude.json"
contains "auto follows a light Claude Code theme" $'\033[38;5;240mnogit' "$(run "$(session)" STATUSLINE_COLORS=auto)"
contains "nerd icons by default" $'\xef\x8b\x9b ' "$(run "$(session)" STATUSLINE_ICONS=nerd)"

printf '%d passed, %d failed (%s)\n' "$pass" "$fail" "$("$shell" -c 'echo bash $BASH_VERSION')"
[ "$fail" -eq 0 ]
