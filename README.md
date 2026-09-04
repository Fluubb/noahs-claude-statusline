# Statusline — Antigravity fork

A touch-up fork of **[noahbclarkson/noahs-claude-statusline](https://github.com/noahbclarkson/noahs-claude-statusline)**.

Read [the original README](https://github.com/noahbclarkson/noahs-claude-statusline#readme) for what the statusline is and how it works — particularly the Windows terminal-width probe, which is the hard part and is entirely Noah's. This file only covers what is different here.

```
Opus 5 │ Github/my-project │ main*↑2 │ 5h:19% 7d:37% │ cache:11m +142/-38 │ 22%(219k/1M) [███▌░░░░░░░░]
```

## What this fork adds

- **Antigravity / Gemini support** — reads either payload schema, and caches width under `~/.antigravity` and `~/.gemini` as well as `~/.claude`
- **More model palettes** — Gemini Flash/Pro, Antigravity and GPT alongside the Claude ones
- **Token counts** — `22%(219k/1M)`, so the percentage says how big the window is, not just how full
- **Rate-limit reset countdown** — `5h:103% ·3h56m`, once a window passes 80%
- **Session economics** — prompt-cache health and expiry, spend, lines changed; each part appears only when it has something to say
- **A native PowerShell port** — `statusline.ps1`, requires PowerShell 7 (`pwsh`); Windows PowerShell 5.1 cannot parse it

Everything drops in priority order as the terminal narrows, and the progress bar gives up its width as segments accumulate.

## Install

In `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash /c/Github/noahs-claude-statusline/statusline.sh"
  },
  "hooks": {
    "Stop": [
      { "matcher": "", "hooks": [
        { "type": "command", "command": "bash /c/Github/noahs-claude-statusline/width-hook.sh" }
      ]}
    ]
  }
}
```

Adjust the paths to wherever you cloned it. On Linux and macOS use `statusline-linux.sh` and skip the hook.

## Tests

```bash
bash test-countdown.sh    # 12 assertions — rate-limit countdown
bash test-economics.sh    # 26 assertions — cache, spend, churn
bash test-statusline.sh   # visual sweep across models, widths, edge cases
```

## Branches

`main` is this fork. `upstream-main` mirrors upstream untouched, so

```bash
git diff upstream-main main
```

shows everything that differs.

## Credits

[@noahbclarkson](https://github.com/noahbclarkson) wrote the original, including the process-tree `AttachConsole` walk that gets a real terminal width out of a Windows subprocess with no TTY, the sub-cell progress bar, the gradient ramp and the degradation ladder. This fork is a layer on top of his work.
