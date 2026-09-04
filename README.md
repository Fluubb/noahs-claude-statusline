# Antigravity & Claude Code High-Fidelity Custom Statusline

A custom statusline designed for **Google Antigravity** and **Claude Code** on Windows (PowerShell, MSYS2/Git Bash, Windows Terminal), Linux, and macOS.

Features real terminal-width detection, truecolor model gradients, two-tone directory rendering, live git branch and dirty tracking, 5h & 7d rate limit gradients with reset countdowns, token counters, and a sub-cell precision fractional progress bar that grows in eighths without visual gaps.

---

## 🎨 Visual Layout & Segments

```text
Gemini 3.7 Flash │ matis/antigravity-statusline │ main*↑2 │ 5h:22% 7d:14% │ 34%(340k/1M) [█████████▌░░░░░░░░░░░░░░░░░░]
```

```text
Claude Opus 4.7 (1M) │ Github/my-project │ feature-branch*↑1↓2 │ 5h:42% 7d:18% │ 47%(470k/1M) [███████████▎░░░░░░░░░░░░]
Claude Opus 5 │ Github/my-project │ main* │ 5h:103% ·3h56m 7d:23% │ 6%(58k/1M) [█▋░░░░░░░░░░░░░░░░░░░░]
```

### Key Components
1. **Model Name Gradient**: Per-model family 24-bit RGB gradients:
   - ⚡ **Gemini 3.7 Flash / Flash**: Google Blue → Amber Gold → Neon Cyan (`#4285F4` → `#FFBE28` → `#00DCB4`)
   - 🔮 **Gemini 3.7 Pro / Ultra**: Royal Violet → Electric Blue → Sky Cyan (`#AA46FF` → `#4E8CFF` → `#28DCF0`)
   - 🌌 **Antigravity Agent / 2.0**: Cosmic Cyan → Fuchsia Purple (`#32E1F0` → `#B446FF` → `#F53CAA`)
   - 💎 **Claude Opus 4.7**: Neon Magenta → Indigo Violet (`#FF5FD7` → `#7364FF`)
   - 🔷 **Claude Sonnet 3.7**: Cyan → Royal Indigo (`#46E6EB` → `#6978FF`)
   - 🌿 **Claude Haiku**: Lime Green → Vibrant Teal (`#AFF05A` → `#37CDB9`)
   - 🍃 **OpenAI / GPT-4 / o1 / o3 / Codex**: Mint Emerald → Aquamarine (`#10B981` → `#34D399`)
2. **Parent & Current Directory**: Two-tone styling (parent directory in muted dark orange `#D78700`, current project in bold bright yellow).
3. **Git Status & Branch**: Lilac-to-cyan gradient branch name with dirty worktree indicator (`*`) and ahead/behind counts (`↑N` `↓N`).
4. **Rate Limits (5h & 7d / Quota)**: Smooth continuous 24-bit RGB gradient (Green `0%` → Yellow `55%` → Orange `80%` → Red `100%`) using piecewise linear interpolation.
   - **Reset countdown**: `used_percentage` is refreshed by the host on its own cadence and can sit unchanged for minutes at a time, which makes a busy window look frozen. Each window's `resets_at` is live on every render, so once a window reaches `80%` it also shows the time until it clears — `5h:103% ·3h56m`. Below the threshold the segment stays bare (`5h:41%`) to keep the bar quiet. Rendered as `·4d2h` / `·3h56m` / `·47m`; omitted when `resets_at` is absent or already elapsed.
5. **Context Window Usage & Token Counts**:
   - Explicit percentage + token fraction (e.g. `34%(340k/1M)`)
   - **Sub-cell precision progress bar**: 1/8th cell block increments (`▏▎▍▌▋▊▉█`)
   - **Boundary background matching**: Shaded dark-gray background (`#303030`) behind the boundary partial block to eliminate terminal gap artifacts.
6. **Smart Responsive Degradation**: Gracefully adapts to narrow terminals by prioritizing essential info without ever wrapping lines:
   - Step 1: Hide secondary token fractions `(340k/1M)`
   - Step 2: Hide rate limits `5h:XX% 7d:XX%`
   - Step 3: Hide git ahead/behind `↑N ↓N` (keeps dirty `*`)
   - Step 4: Hide parent directory
   - Step 5: Truncate branch name (to 14, then 8 chars)
   - Step 6: Truncate current directory (to 18, then 10 chars)
   - Step 7: Shrink progress bar down to minimum or drop on ultra-narrow displays.

---

## 🚀 Installation & Setup

### Option A: Using with Claude Code

Update your `~/.claude/settings.json` (or `%USERPROFILE%\.claude\settings.json`):

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash /c/Users/matis/antigravity-statusline/statusline.sh"
  },
  "hooks": {
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bash /c/Users/matis/antigravity-statusline/width-hook.sh"
          }
        ]
      }
    ]
  }
}
```

> **Tip**: On Linux / macOS / WSL, you can use `statusline-linux.sh` directly without the Stop hook or PowerShell probe.

---

### Option B: Using with Antigravity / Gemini CLI (`agy`)

Add the statusline hook or configure it in `.agents/hooks.json` or `~/.gemini/config/hooks.json`:

```json
{
  "statusline": {
    "Stop": [
      {
        "type": "command",
        "command": "powershell -ExecutionPolicy Bypass -File C:\\Users\\matis\\antigravity-statusline\\statusline.ps1"
      }
    ]
  }
}
```

Or run via bash:
```json
{
  "statusline": {
    "Stop": [
      {
        "type": "command",
        "command": "bash /c/Users/matis/antigravity-statusline/statusline.sh"
      }
    ]
  }
}
```

---

### Option C: Pure PowerShell (No Bash or JQ Required)

If you're running directly in PowerShell (Windows Terminal, VS Code, pwsh):

```powershell
# Pipe JSON payload directly to the statusline
$json | & "C:\Users\matis\antigravity-statusline\statusline.ps1"
```

---

## 🧪 Testing & Verification

A test harness is included to simulate various models, context sizes, and git states:

```powershell
# Run both PowerShell and Bash test harnesses
& "C:\Users\matis\antigravity-statusline\test-statusline.ps1"
```

Or via Bash:
```bash
bash /c/Users/matis/antigravity-statusline/test-statusline.sh
```

---

## 📂 Repository Structure

- `statusline.sh` - Main Bash statusline script (Windows MSYS2, Git Bash, Linux, macOS)
- `statusline.ps1` - Pure native PowerShell implementation (Windows PowerShell 5.1+, PowerShell 7+)
- `statusline-linux.sh` - Standalone Linux / macOS script with `/proc` pts instant inline width detection
- `width-hook.sh` - Stop hook script to update cached terminal width on Windows
- `width-probe.ps1` - Win32 Console API process tree walker to resolve real terminal width
- `test-statusline.ps1` - PowerShell test runner with diverse model/token/rate-limit fixtures
- `test-statusline.sh` - Bash test runner
