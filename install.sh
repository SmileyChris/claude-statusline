#!/usr/bin/env bash
# Installs claude-statusline into Claude Code.
#
#   ./install.sh [--icons nerd|plain] [--colors auto|dark|light|ansi] [--refresh SECONDS] [--link]
#
#   --icons    nerd needs a Nerd Font in your terminal; by default the installer looks for one
#   --colors   auto (default) follows your Claude Code theme
#   --refresh  how often the line redraws while idle, for the countdowns (default 15; 0 = off)
#   --link     symlink instead of copying, so a `git pull` here updates it
#
# Copies statusline.sh to ~/.claude/statusline.sh (or $CLAUDE_CONFIG_DIR) and points the
# statusLine setting at it. Anything it replaces is backed up next to it with .bak.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
config=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
icons="" colors=auto refresh=15 link=no

while [ $# -gt 0 ]; do
  case $1 in
    --icons) icons=$2; shift ;;
    --colors) colors=$2; shift ;;
    --refresh) refresh=$2; shift ;;
    --link) link=yes ;;
    -h|--help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1 (see --help)" >&2; exit 1 ;;
  esac
  shift
done

case $icons in ""|nerd|plain) ;; *) echo "--icons must be nerd or plain" >&2; exit 1 ;; esac
case $colors in auto|dark|light|ansi) ;; *) echo "--colors must be auto, dark, light or ansi" >&2; exit 1 ;; esac
case $refresh in ''|*[!0-9]*) echo "--refresh must be a whole number of seconds" >&2; exit 1 ;; esac
command -v jq >/dev/null || { echo "claude-statusline needs jq: https://jqlang.org/download/" >&2; exit 1; }
command -v git >/dev/null || echo "Note: git isn't installed, so the branch won't show."

if [ -z "$icons" ]; then
  if { command -v fc-list >/dev/null && fc-list 2>/dev/null | grep -qi 'nerd font'; } ||
     ls "$HOME/Library/Fonts" /Library/Fonts 2>/dev/null | grep -qi 'nerd'; then
    icons=nerd
  else
    icons=plain
    echo "No Nerd Font found, so using plain icons. Install one and rerun with --icons nerd for the full set."
  fi
fi

mkdir -p "$config"
dest="$config/statusline.sh"
if [ -e "$dest" ] && ! [ "$dest" -ef "$here/statusline.sh" ] && ! cmp -s "$dest" "$here/statusline.sh"; then
  cp -f "$dest" "$dest.bak"; echo "Backed up your existing $dest to $dest.bak"
fi
if [ $link = yes ]; then ln -sf "$here/statusline.sh" "$dest"; else rm -f "$dest"; cp "$here/statusline.sh" "$dest"; fi
chmod +x "$here/statusline.sh" "$dest"

# The command Claude Code runs. Only settings that differ from the defaults are spelled out.
path=$dest; [ "$config" = "$HOME/.claude" ] && path="~/.claude/statusline.sh"
cmd=$path
[ "$colors" != auto ] && cmd="STATUSLINE_COLORS=$colors $cmd"
[ "$icons" != nerd ] && cmd="STATUSLINE_ICONS=$icons $cmd"

settings="$config/settings.json"
[ -s "$settings" ] || echo '{}' > "$settings"
if jq -e '.statusLine' "$settings" >/dev/null 2>&1; then
  cp -f "$settings" "$settings.bak"; echo "Backed up $settings to $settings.bak (it had a statusLine already)"
fi
# Write through the existing file rather than replacing it, so a symlinked settings.json
# (dotfiles) and its permissions survive.
tmp=$(mktemp); trap 'rm -f "$tmp"' EXIT
jq --arg cmd "$cmd" --argjson refresh "$refresh" '
  .statusLine = ({type: "command", command: $cmd}
    + (if $refresh > 0 then {refreshInterval: $refresh} else {} end))' "$settings" > "$tmp"
cat "$tmp" > "$settings"

echo "Installed. statusLine runs: $cmd"
echo "It appears on Claude Code's next redraw; restart open sessions to pick up refreshInterval."
