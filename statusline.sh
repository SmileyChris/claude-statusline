#!/usr/bin/env bash
# claude-statusline: folder, branch, context and model, prompt cache, usage limits.
# Claude Code pipes session JSON on stdin; see code.claude.com/docs/en/statusline.
#
# Settings (environment variables, usually set in the statusLine command):
#   STATUSLINE_ICONS   nerd (default; needs a Nerd Font) or plain (standard Unicode)
#   STATUSLINE_COLORS  auto (default: light or dark from your Claude Code theme),
#                      dark, light, or ansi (your terminal theme's own 16 colours)
#
# Runs on every reply and every refreshInterval, so the hot path is one jq call, one awk
# call and no subshells. Works on bash 3.2 (macOS) and later.
input=$(cat)
export GIT_OPTIONAL_LOCKS=0
rt=${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}; rt=${rt%/}

# Fields, separated by \x1f so empty ones survive `read`:
# now, folder, model, context %, cache seconds left (-1 cold, empty none), cache hit %,
# 5h used, 5h resets, 7d used, 7d resets ("-" when absent).
IFS=$'\x1f' read -r now dir model ctx csecs cpct u5 r5 u7 r7 < <(jq -r '
  def lim: if . and .used_percentage != null and .resets_at != null
           then [(.used_percentage | tostring), (.resets_at | floor | tostring)] else ["-", "-"] end;
  (now | floor) as $now
  | (.prompt_cache // null) as $pc
  | [ ($now | tostring), (.workspace.current_dir // ""), (.model.display_name // ""),
      (.context_window.used_percentage | if . == null then "" else (floor | tostring) end),
      (if $pc == null then ""
       elif $pc.warm and $pc.expires_at != null and ($pc.expires_at - $now) > 0
         then ($pc.expires_at - $now | floor | tostring)
       elif $pc.caching_observed then "-1" else "" end),
      (if $pc.hit_ratio != null then "\($pc.hit_ratio * 100 | floor)%" else "" end) ]
    + (.rate_limits.five_hour | lim) + (.rate_limits.seven_day | lim)
  | join("\u001f")' <<<"$input")

# Icons, as UTF-8 bytes (bash 3.2 has no \u escapes).
if [ "${STATUSLINE_ICONS:-nerd}" = plain ]; then
  FOLDER="" BRANCH=$'\xe2\x8e\x87' CHIP="" CLOCK=$'\xe2\x86\xba' CAL=$'\xe2\x9f\xb2'
  GLASS_FULL=$'\xe2\x97\x95' GLASS_HALF=$'\xe2\x97\x91' GLASS_LOW=$'\xe2\x97\x94' SNOW=$'\xe2\x9d\x84'
else
  FOLDER=$'\xef\x84\x95 ' BRANCH=$'\xef\x84\xa6' CHIP=$'\xef\x8b\x9b ' CLOCK=$'\xef\x80\x97' CAL=$'\xf3\xb0\x83\xad'
  GLASS_FULL=$'\xef\x89\x91' GLASS_HALF=$'\xef\x89\x92' GLASS_LOW=$'\xef\x89\x93' SNOW=$'\xef\x8b\x9c'
fi

# Colours. A status line has no terminal to ask for its background colour, so `auto`
# follows Claude Code's own theme setting (read at most once a minute), which you set to
# suit your terminal; it falls back to $COLORFGBG and then to dark.
colors=${STATUSLINE_COLORS:-auto}
if [ "$colors" = auto ]; then
  themecache="$rt/claude-statusline-theme"
  ts=0; [ -f "$themecache" ] && IFS=$'\x1f' read -r ts colors < "$themecache"
  if (( now - ${ts:-0} >= 60 )) || [ -z "$colors" ] || [ "$colors" = auto ]; then
    theme=$(jq -r '.theme // ""' "${CLAUDE_CONFIG_DIR:-$HOME}/.claude.json" 2>/dev/null)
    case $theme in
      *ansi*) colors=ansi ;;
      *light*) colors=light ;;
      *dark*) colors=dark ;;
      *) case ${COLORFGBG##*;} in 7|15) colors=light ;; *) colors=dark ;; esac ;;
    esac
    printf '%s\x1f%s\n' "$now" "$colors" > "$themecache"
  fi
fi
# TEXT: folder and plain numbers · DIM: icons, model, timers · SOFT: the cache countdown
# OK: clean branch · WARM: warm cache · WARN, BAD: running low · COLD: cache expired
case $colors in
  light) TEXT='38;5;240' DIM='38;5;246' SOFT='38;5;243' OK='38;5;28'  WARM='38;5;29'
         WARN='38;5;166' BAD='38;5;160' COLD='38;5;31' ;;
  ansi)  TEXT='39' DIM='2' SOFT='39' OK='32' WARM='32' WARN='33' BAD='31' COLD='36' ;;
  *)     TEXT='38;5;245' DIM='38;5;240' SOFT='38;5;246' OK='38;5;76'  WARM='38;5;114'
         WARN='38;5;214' BAD='38;5;196' COLD='38;5;117' ;;
esac

out=""
add() { printf -v _s '\033[%sm%s\033[0m' "$1" "$2"; out+=$_s; }

# Folder and branch. Git results are cached for 5 seconds per folder.
gitcache="$rt/claude-statusline-git${dir//\//_}"
ts=0 branch="" dirty=0
[ -f "$gitcache" ] && IFS=$'\x1f' read -r ts branch dirty < "$gitcache"
if (( now - ${ts:-0} >= 5 )); then
  branch=$(git -C "$dir" branch --show-current 2>/dev/null)
  dirty=0
  if [ -n "$branch" ]; then
    while IFS= read -r _; do dirty=$(( dirty + 1 )); done < <(git -C "$dir" status --porcelain 2>/dev/null)
  fi
  printf '%s\x1f%s\x1f%s\n' "$now" "$branch" "$dirty" > "$gitcache"
fi

add "$TEXT" "$FOLDER${dir##*/}"
if [ -n "$branch" ]; then
  out+=" "
  if (( ${dirty:-0} == 0 )); then add "$OK" "$BRANCH $branch"; else add "$WARN" "$BRANCH $branch+$dirty"; fi
fi

# Context window used, then the model. Orange from 80%.
if [ -n "$ctx" ]; then
  out+=" "; if (( ctx >= 80 )); then add "$WARN" "$ctx%"; else add "$DIM" "$ctx%"; fi
fi
out+=" "; add "$DIM" "$CHIP$model"

# Prompt cache: an hourglass and the hit ratio, coloured by time left.
#   40m+ full · 20-40m half · under 20m low (all green)
#   10m and under: orange, with a minutes countdown · 2m and under: red
#   cold: snowflake, blue
if [ -n "$csecs" ]; then
  s=$csecs
  if   (( s < 0 ));     then col=$COLD glass=$SNOW
  elif (( s <= 120 ));  then col=$BAD  glass=$GLASS_LOW
  elif (( s <= 600 ));  then col=$WARN glass=$GLASS_LOW
  elif (( s < 1200 ));  then col=$WARM glass=$GLASS_LOW
  elif (( s < 2400 ));  then col=$WARM glass=$GLASS_HALF
  else                       col=$WARM glass=$GLASS_FULL; fi
  out+=" "
  if (( s >= 0 && s <= 600 )); then
    if (( s < 60 )); then add "$SOFT" "<1m"; else add "$SOFT" "$(( s / 60 ))m"; fi
  fi
  add "$col" "$glass$cpct"
fi

# Usage limits. Rate limits are account-wide, so every session shares one log of readings,
# written once a minute (or at once when a session has a newer reading) and trimmed to the
# last 25 hours.
#  - An idle session keeps the limits from its last reply, but usage only rises within a
#    window, so each session shows the highest reading logged for the same window (same
#    reset time, give or take two minutes).
#  - The 5h projection uses the recent rate: the change since the oldest reading in the
#    last 60m; it needs 20m of readings and 10% used.
#  - The 7d projection uses the average since the week opened (reset - 7d); it needs 24h of
#    the week gone and 10% used, and sets the colour only.
#    Plain under 90% projected, orange to 120%, red beyond; plain with no projection.
log="$rt/claude-statusline-limits"
if [ "$u5" != - ] || [ "$u7" != - ]; then
  : >> "$log"
  read -r u5 p5 u7 p7 last lines newer < <(awk -v now="$now" -v u5="$u5" -v r5="$r5" -v u7="$u7" -v r7="$r7" '
    function near(a, b) { return a - b < 120 && b - a < 120 }
    function week(u, r,   gone) {
      gone = now - (r - 604800)
      return gone < 86400 || u < 10 ? -1 : int(u * 604800 / gone)
    }
    function proj(u, t0, u0, r, span,   rate) {
      if (t0 == "" || now - t0 < span || u < 10) return -1
      rate = (u - u0) / (now - t0); if (rate < 0) rate = 0
      return int(u + rate * (r > now ? r - now : 0))
    }
    BEGIN { m5 = u5 + 0; m7 = u7 + 0; l5 = -1; l7 = -1 }
    { last = $1; n++ }
    u5 != "-" && $2 != "-" && near($3, r5) {
      if ($2 + 0 > m5) m5 = $2 + 0
      if ($2 + 0 > l5) l5 = $2 + 0
      if ($1 >= now - 3600 && t5 == "") { t5 = $1; v5 = $2 }
    }
    u7 != "-" && $4 != "-" && near($5, r7) {
      if ($4 + 0 > m7) m7 = $4 + 0
      if ($4 + 0 > l7) l7 = $4 + 0
    }
    END {
      # newer: this session knows a higher reading than the log holds for the window.
      newer = (u5 != "-" && u5 + 0 > l5) || (u7 != "-" && u7 + 0 > l7)
      print (u5 == "-" ? "-" : m5), (u5 == "-" ? -1 : proj(m5, t5, v5, r5, 1200)),
            (u7 == "-" ? "-" : m7), (u7 == "-" ? -1 : week(m7, r7)),
            last + 0, n + 0, newer
    }' "$log")
  # Log once a minute, or straight away when this session has a newer reading. Without
  # the second rule, idle sessions take every slot and the active one's reading never lands.
  if (( now - last >= 60 || newer )); then
    echo "$now $u5 $r5 $u7 $r7" >> "$log"
    if (( lines > 1600 )); then
      awk -v cut=$(( now - 90000 )) '$1 >= cut' "$log" > "$log.$$" && mv "$log.$$" "$log"
    fi
  fi
fi

pace() { if (( $1 > 120 )); then col=$BAD; elif (( $1 >= 90 )); then col=$WARN; else col=$TEXT; fi; }

if [ "$u5" != - ] && (( r5 > now )); then
  u=${u5%.*}; left=$(( r5 - now ))
  if (( left >= 3600 )); then printf -v t '%dh%02d' $(( left / 3600 )) $(( left % 3600 / 60 ))
  else t="$(( (left + 59) / 60 ))m"; fi
  txt="$u%"; (( p5 >= 0 && u < 100 )) && txt+="→$(( p5 > 999 ? 999 : p5 ))%"
  pace "$p5"; out+=" "; add "$col" "$txt"; add "$DIM" "$CLOCK$t"
fi

if [ "$u7" != - ] && (( r7 > now )); then
  left=$(( r7 - now ))
  if (( left >= 86400 )); then t="$(( left / 86400 ))d"; else t="$(( (left + 3599) / 3600 ))h"; fi
  pace "$p7"; out+=" "; add "$col" "${u7%.*}%"; add "$DIM" "$CAL$t"
fi

printf '%s' "$out"
