# claude-statusline

A one-line status line for [Claude Code](https://code.claude.com) that shows what Claude Code knows but doesn't show you: how long your prompt cache stays warm, and whether you'll run out of your usage limit before it resets.

```
pixlings ⎇ main+8 41% Opus 5.5 ◕97% 62%→109%↺2h09 20%⟲3d
```

(Shown with the plain icons; with a [Nerd Font](https://www.nerdfonts.com) you get folder, branch, chip, hourglass, clock and calendar glyphs.)

One bash script. It needs `jq` (and `git` for the branch), runs in about 13 ms, and works on bash 3.2 (the one macOS ships) and later.

## What it shows

| Piece | Example | Meaning |
|---|---|---|
| Folder | `pixlings` | The session's working folder. |
| Branch | `⎇ main+8` | Green when clean; orange with the number of changed files. |
| Context | `41%` | How full the context window is. Orange from 80%. |
| Model | `Opus 5.5` | |
| Prompt cache | `◕97%` | How much of this session's input was read from the cache, after an hourglass that drains as the cache runs down. |
| 5-hour limit | `62%→109%↺2h09` | Used so far → where your recent pace takes it by the reset, then the time until the reset. |
| Weekly limit | `20%⟲3d` | Used so far, then the time until the reset. |

### The prompt cache

Each message re-reads your conversation from Anthropic's prompt cache at a fraction of the normal price. Leave the session idle past the cache's lifetime (five minutes or an hour) and the next message writes the whole conversation again at full price. The hourglass tells you how long you have:

| Time left | Shows |
|---|---|
| 40 minutes or more | full hourglass, green |
| 20–40 minutes | half, green |
| under 20 minutes | low, green |
| 10 minutes or less | low, orange, with a countdown: `8m◔97%` |
| 2 minutes or less | red |
| expired | snowflake, blue |

### The usage limits

Only on a claude.ai subscription; with an API key this part doesn't appear.

The projection is from your **recent** rate, not the average since the window opened, so a busy first half hour or a long lunch doesn't skew it. It appears only once there is enough to go on:

| | Looks back | Shows a projection once there are | and you've used |
|---|---|---|---|
| 5-hour | 60 minutes | 20 minutes of readings | 10% |
| Weekly | 24 hours | 6 hours of readings | 10% (as the colour only) |

The numbers turn orange when you're on course for 90–110% by the reset, red beyond that.

The limits are shared across your account, so all your Claude Code windows share one log of readings. An idle window would otherwise keep showing the figure from its last reply; this way every window shows the newest one. Context and cache are per session, so those differ between windows, as they should.

## Install

```sh
git clone https://github.com/SmileyChris/claude-statusline.git
cd claude-statusline
./install.sh
```

It copies `statusline.sh` to `~/.claude/` and sets `statusLine` in `~/.claude/settings.json`, backing up anything it replaces. Options:

| Option | |
|---|---|
| `--icons nerd` or `plain` | `nerd` needs a [Nerd Font](https://www.nerdfonts.com) in your terminal. By default the installer looks for one and falls back to `plain`. |
| `--colors auto`, `dark`, `light` or `ansi` | See below. Default `auto`. |
| `--refresh N` | Redraw every N seconds while idle, so the countdowns move (default 15; `0` for off). |
| `--link` | Symlink instead of copy, so `git pull` updates it. |

### Colours

A status line can't ask the terminal what colour its background is, so:

- `auto` follows your Claude Code theme (`/config` → Theme): a light theme gets the light palette, an ANSI theme the `ansi` palette, anything else the dark one.
- `ansi` uses your terminal theme's own 16 colours and the faint attribute, so it suits whatever background your theme has, at the cost of the finer shades.
- `dark` and `light` force a palette.

### Plain icons

Without a Nerd Font, `--icons plain` uses standard Unicode instead: `⎇` for the branch, `◕ ◑ ◔ ❄` for the cache, `↺` and `⟲` for the limits, and no folder or model icon.

## Files it keeps

In `$XDG_RUNTIME_DIR` (or `$TMPDIR`), all small and safe to delete:

- `claude-statusline-limits`: the shared usage readings, at most one line a minute, trimmed to 25 hours.
- `claude-statusline-git…`: each folder's branch and changed-file count, refreshed at most every 5 seconds.
- `claude-statusline-theme`: your Claude Code theme, re-read at most once a minute.

It sends nothing anywhere.

## Tests

```sh
tests/test.sh                 # with your bash
tests/test.sh /bin/bash       # with another one, e.g. macOS's 3.2
```

## License

MIT
