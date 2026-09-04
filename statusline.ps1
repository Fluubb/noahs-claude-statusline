<#
.SYNOPSIS
    Antigravity & Claude Code High-Fidelity Custom Statusline (PowerShell Native)
.DESCRIPTION
    Layout: [Model Gradient] │ [Parent/Dir] │ [Branch*↑↓] │ [5h/7d Rate Limits] │ [Tokens/Context% [██████▎░░░░░░░]]
#>

[CmdletBinding()]
param(
    [Parameter(ValueFromPipeline = $true)]
    [string]$InputObject
)

begin {
    $rawInput = [System.Text.StringBuilder]::new()
    $utf8 = [System.Text.UTF8Encoding]::new($false)
    [Console]::OutputEncoding = $utf8
    $OutputEncoding = $utf8
}

process {
    if ($InputObject) {
        [void]$rawInput.AppendLine($InputObject)
    }
}

end {
    $inputText = $rawInput.ToString().Trim()

    # ANSI formatting constants
    $ESC = [char]27
    $RESET = "$ESC[0m"
    $BOLD = "$ESC[1m"
    $DIM = "$ESC[2m"
    $FG_WHITE = "$ESC[97m"
    $FG_YELLOW = "$ESC[93m"
    $FG_DARK_ORANGE = "$ESC[38;5;172m"
    $FG_MUTED = "$ESC[38;5;244m"
    $BAR_EMPTY_COLOR = "$ESC[90m"
    $BAR_EMPTY_BG = "$ESC[48;5;236m"

    # Truncate helper
    function Truncate-String([string]$str, [int]$max) {
        if (-not $str) { return "" }
        if ($str.Length -le $max) { return $str }
        return $str.Substring(0, [Math]::Max(0, $max - 1)) + "…"
    }

    # Smooth green->yellow->orange->red gradient
    # Returns " ·4d2h" / " ·3h56m" / " ·47m" for a future Unix timestamp, or "" when
# the window is quiet, the timestamp is absent or malformed, or it has passed.
function Format-ResetCountdown {
    param($Epoch, [int]$Pct, [int]$Threshold)
    if ($null -eq $Epoch) { return "" }
    if ($Pct -lt $Threshold) { return "" }
    [long]$e = 0
    if (-not [long]::TryParse([string]$Epoch, [ref]$e)) { return "" }
    $secs = $e - [long][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    if ($secs -le 0) { return "" }
    $d = [math]::Floor($secs / 86400)
    $h = [math]::Floor(($secs % 86400) / 3600)
    $m = [math]::Floor(($secs % 3600) / 60)
    if ($d -gt 0) { return " ·${d}d${h}h" }
    if ($h -gt 0) { return " ·${h}h${m}m" }
    return " ·${m}m"
}

function Get-GradColor([double]$p) {
        if ($p -lt 0) { $p = 0 }
        if ($p -gt 100) { $p = 100 }
        $stops = @(
            @{ p = 0;   r = 80;  g = 200; b = 100 },
            @{ p = 55;  r = 222; g = 205; b = 35  },
            @{ p = 80;  r = 255; g = 140; b = 20  },
            @{ p = 100; r = 228; g = 55;  b = 45  }
        )
        for ($i = 0; $i -lt ($stops.Count - 1); $i++) {
            $s0 = $stops[$i]
            $s1 = $stops[$i + 1]
            if ($p -le $s1.p) {
                $span = [Math]::Max(1, ($s1.p - $s0.p))
                $t = ($p - $s0.p)
                $r = [int]($s0.r + ($s1.r - $s0.r) * $t / $span)
                $g = [int]($s0.g + ($s1.g - $s0.g) * $t / $span)
                $b = [int]($s0.b + ($s1.b - $s0.b) * $t / $span)
                return "$ESC[38;2;$r;$g;${b}m"
            }
        }
        return "$ESC[38;2;228;55;45m"
    }

    # Gradient text generator
    function Get-GradientText([string]$text, [array]$stops) {
        if (-not $text) { return "" }
        $n = $text.Length
        $numStops = [int]($stops.Count / 3)
        if ($numStops -lt 2 -or $n -le 1) {
            $r = $stops[0]; $g = $stops[1]; $b = $stops[2]
            return "$ESC[38;2;$r;$g;${b}m$text"
        }
        $numSegments = $numStops - 1
        $sb = [System.Text.StringBuilder]::new()
        for ($i = 0; $i -lt $n; $i++) {
            $ch = $text[$i]
            $globalPos = $i * $numSegments
            $segIdx = [int]($globalPos / ($n - 1))
            if ($segIdx -ge $numSegments) { $segIdx = $numSegments - 1 }
            
            $segStart = [int]($segIdx * ($n - 1) / $numSegments)
            $segEnd = [int](($segIdx + 1) * ($n - 1) / $numSegments)
            $span = [Math]::Max(1, ($segEnd - $segStart))
            $t = [Math]::Max(0, [Math]::Min($span, ($i - $segStart)))

            $idx0 = $segIdx * 3
            $idx1 = ($segIdx + 1) * 3
            $r0 = $stops[$idx0];   $g0 = $stops[$idx0 + 1]; $b0 = $stops[$idx0 + 2]
            $r1 = $stops[$idx1];   $g1 = $stops[$idx1 + 1]; $b1 = $stops[$idx1 + 2]

            $r = [int]($r0 + ($r1 - $r0) * $t / $span)
            $g = [int]($g0 + ($g1 - $g0) * $t / $span)
            $b = [int]($b0 + ($b1 - $b0) * $t / $span)

            [void]$sb.Append("$ESC[38;2;$r;$g;${b}m$ch")
        }
        return $sb.ToString()
    }

    # Format numbers (1000 -> 1k, 1000000 -> 1M)
    function Format-TokenK([long]$num) {
        if ($num -ge 1000000) { return "$([int]($num / 1000000))M" }
        if ($num -ge 1000) { return "$([int]($num / 1000))k" }
        return "$num"
    }

    # Parse JSON payload
    $payload = $null
    if ($inputText) {
        try {
            $payload = $inputText | ConvertFrom-Json -ErrorAction SilentlyContinue
        } catch {}
    }

    # Extract Fields
    $modelId = ""
    $modelDisplay = ""
    $projectDir = ""
    $sessionId = ""
    $usedPct = 0
    $usedTokens = 0
    $totalTokens = 0
    $fivePct = $null
    $weekPct = $null

    if ($payload) {
        $modelId = $payload.model.id ?? $payload.modelName ?? $payload.model_name ?? ""
        $modelDisplay = $payload.model.display_name ?? $payload.model_display ?? $payload.modelName ?? ""
        $projectDir = $payload.workspace.current_dir ?? $payload.cwd ?? $payload.workspace.project_dir ?? $payload.workspacePaths[0] ?? $payload.project_dir ?? ""
        $sessionId = $payload.session_id ?? $payload.conversationId ?? $payload.sessionId ?? ""
        
        $pctVal = $payload.context_window.used_percentage ?? $payload.contextWindow.usedPercentage ?? $payload.context_percent ?? $payload.used_percentage
        if ($null -ne $pctVal) { $usedPct = [double]$pctVal }

        $uTok = $payload.context_window.used_tokens ?? $payload.context_window.total_input_tokens ?? $payload.contextWindow.usedTokens ?? $payload.used_tokens
        if ($null -ne $uTok) { $usedTokens = [long]$uTok }

        $tTok = $payload.context_window.total_tokens ?? $payload.context_window.context_window_size ?? $payload.contextWindow.totalTokens ?? $payload.total_tokens ?? $payload.context_window_size
        if ($null -ne $tTok) { $totalTokens = [long]$tTok }

        $fiveVal = $payload.rate_limits.five_hour.used_percentage ?? $payload.rateLimits.fiveHour.usedPercentage ?? $payload.five_hour_percent
        if ($null -ne $fiveVal) { $fivePct = [double]$fiveVal }

        $weekVal = $payload.rate_limits.seven_day.used_percentage ?? $payload.rateLimits.sevenDay.usedPercentage ?? $payload.seven_day_percent
        if ($null -ne $weekVal) { $weekPct = [double]$weekVal }

        $fiveReset = $payload.rate_limits.five_hour.resets_at ?? $payload.rateLimits.fiveHour.resetsAt
        $weekReset = $payload.rate_limits.seven_day.resets_at ?? $payload.rateLimits.sevenDay.resetsAt
    }

    if (-not $projectDir) { $projectDir = (Get-Location).Path }
    if (-not $modelDisplay -and $modelId) { $modelDisplay = $modelId }
    if (-not $modelDisplay) { $modelDisplay = "Antigravity" }

    # Terminal width resolution
    $cols = 120
    $sessionKey = if ($sessionId) { $sessionId -replace '[^A-Za-z0-9_-]', '' } else { "" }
    if ($sessionKey) {
        $cachePaths = @(
            "$env:USERPROFILE\.antigravity\.statusline-cols-$sessionKey",
            "$env:USERPROFILE\.claude\.statusline-cols-$sessionKey",
            "$env:USERPROFILE\.gemini\.statusline-cols-$sessionKey"
        )
        foreach ($cp in $cachePaths) {
            if (Test-Path $cp) {
                $content = (Get-Content -Path $cp -Raw -ErrorAction SilentlyContinue)
                if ($content -and $content.Trim() -match '^\d+$') {
                    $val = [int]$content.Trim()
                    if ($val -ge 20) { $cols = $val; break }
                }
            }
        }
    }
    if ($cols -eq 120) {
        try {
            $w = [Console]::WindowWidth
            if ($w -ge 20) { $cols = $w }
        } catch {
            if ($Host.UI.RawUI.WindowSize.Width -ge 20) {
                $cols = $Host.UI.RawUI.WindowSize.Width
            }
        }
    }

    # Model cleanup & palettes
    $modelDisplay = $modelDisplay -replace '\s*\((1M|2M) context\)', ' ($1)'
    $modelDisplay = $modelDisplay -replace '\s*\(High\)', ''
    $modelDisplay = $modelDisplay -replace '\s*preview', ''
    $modelLower = ("$modelId $modelDisplay").ToLowerInvariant()

    $modelStops = switch -Regex ($modelLower) {
        'flash'             { @(66, 133, 244,  255, 190, 40,  0, 220, 180) }
        'pro|ultra'         { @(170, 70, 255,  78, 140, 255,  40, 220, 240) }
        'gemini'            { @(66, 133, 244,  160, 80, 255) }
        'opus'              { @(255, 95, 215,  115, 100, 255) }
        'sonnet'            { @(70, 230, 235,  105, 120, 255) }
        'haiku'             { @(175, 240, 90,   55, 205, 185) }
        'gpt|o1|o3|codex'   { @(16, 185, 129,  52, 211, 153) }
        'antigravity|agy'   { @(50, 225, 240,  180, 70, 255,  245, 60, 170) }
        default             { @(70, 230, 235,  105, 120, 255) }
    }

    # Project directory parsing
    $dirCurrent = "unknown"
    $dirParent = ""
    if ($projectDir) {
        try {
            $item = Get-Item -LiteralPath $projectDir -ErrorAction SilentlyContinue
            if ($item) {
                $dirCurrent = $item.Name
                if ($item.Parent) { $dirParent = $item.Parent.Name }
            } else {
                $p = $projectDir.Replace('\', '/').TrimEnd('/')
                $parts = $p.Split('/')
                if ($parts.Count -gt 0) { $dirCurrent = $parts[-1] }
                if ($parts.Count -gt 1) { $dirParent = $parts[-2] }
            }
        } catch {}
    }

    # Git status
    $branch = ""
    $gitDirty = ""
    $gitAb = ""
    $gitAbCells = 0

    $gitDir = $projectDir
    $inGit = $false
    for ($i = 0; $i -lt 10; $i++) {
        if (-not $gitDir) { break }
        if (Test-Path (Join-Path $gitDir ".git")) { $inGit = $true; break }
        $parent = Split-Path -Parent $gitDir
        if ($parent -eq $gitDir) { break }
        $gitDir = $parent
    }

    if ($inGit) {
        $branch = (git -C "$projectDir" --no-optional-locks branch --show-current 2>$null)
        if (-not $branch) {
            $branch = (git -C "$projectDir" --no-optional-locks rev-parse --short HEAD 2>$null)
        }
        if ($branch) {
            $status = (git -C "$projectDir" --no-optional-locks status --porcelain 2>$null)
            if ($status) { $gitDirty = "*" }

            $ab = (git -C "$projectDir" --no-optional-locks rev-list --left-right --count "@{upstream}...HEAD" 2>$null)
            if ($ab) {
                $parts = $ab.Trim() -split '\s+'
                if ($parts.Count -ge 2) {
                    $behind = [int]$parts[0]
                    $ahead = [int]$parts[1]
                    if ($ahead -gt 0) {
                        $gitAb += "↑$ahead"
                        $gitAbCells += (1 + "$ahead".Length)
                    }
                    if ($behind -gt 0) {
                        $gitAb += "↓$behind"
                        $gitAbCells += (1 + "$behind".Length)
                    }
                }
            }
        }
    }

    # Context & Token calculations
    $usedInt = [int][Math]::Round($usedPct)
    if ($usedInt -eq 0 -and $totalTokens -gt 0 -and $usedTokens -gt 0) {
        $usedInt = [int][Math]::Round(($usedTokens * 100.0 / $totalTokens))
    }
    $usedInt = [Math]::Max(0, [Math]::Min(100, $usedInt))

    $barFillColor = Get-GradColor $usedInt
    $tokenStr = ""
    if ($usedTokens -gt 0 -and $totalTokens -gt 0) {
        $tokenStr = "$(Format-TokenK $usedTokens)/$(Format-TokenK $totalTokens)"
    }

    # Rate limits formatting.
    # used_percentage is refreshed by the host on its own cadence and can sit
    # unchanged for minutes at a time. resets_at is the one datum that is live
    # every render, so a window at or above this threshold also shows time until
    # it clears.
    $RESET_COUNTDOWN_THRESHOLD = 80
    $rateStr = ""
    $plainRate = ""
    if ($null -ne $fivePct) {
        $fiveInt = [int][Math]::Round($fivePct)
        $fColor = Get-GradColor $fiveInt
        $fRe = Format-ResetCountdown $fiveReset $fiveInt $RESET_COUNTDOWN_THRESHOLD
        $rateStr += "${fColor}5h:${fiveInt}%${fRe}$RESET"
        $plainRate += "5h:${fiveInt}%${fRe}"
    }
    if ($null -ne $weekPct) {
        $weekInt = [int][Math]::Round($weekPct)
        $wColor = Get-GradColor $weekInt
        if ($rateStr) { $rateStr += " " }
        if ($plainRate) { $plainRate += " " }
        $wRe = Format-ResetCountdown $weekReset $weekInt $RESET_COUNTDOWN_THRESHOLD
        $rateStr += "${wColor}7d:${weekInt}%${wRe}$RESET"
        $plainRate += "7d:${weekInt}%${wRe}"
    }

    # Width Budgeting & Degradation
    $TARGET_MIN_BAR = 8
    $SEP_LEN = 3

    function Get-PrefixLen([bool]$incToken, [bool]$incRate, [bool]$incAb, [bool]$incPar, [int]$bMax, [int]$dMax) {
        $n = $modelDisplay.Length + $SEP_LEN
        if ($incPar -and $dirParent) { $n += ($dirParent.Length + 1) }

        $dLen = if ($dirCurrent) { $dirCurrent.Length } else { 7 }
        if ($dLen -gt $dMax) { $dLen = $dMax }
        $n += $dLen

        if ($branch) {
            $n += $SEP_LEN
            $bLen = $branch.Length
            if ($bLen -gt $bMax) { $bLen = $bMax }
            $n += $bLen + $gitDirty.Length
            if ($incAb) { $n += $gitAbCells }
        }

        if ($incRate -and $plainRate) {
            $n += ($SEP_LEN + $plainRate.Length)
        }

        $n += ($SEP_LEN + "$usedInt".Length + 1)
        if ($incToken -and $tokenStr) {
            $n += ($tokenStr.Length + 2)
        }
        $n += 1 # trailing space
        return $n
    }

    $incToken = $true
    $incRate = $true
    $incAb = $true
    $incPar = $true
    $bMax = 999
    $dMax = 999
    $dropBar = $false
    $budget = $cols - 2 - $TARGET_MIN_BAR

    while ($true) {
        $curLen = Get-PrefixLen $incToken $incRate $incAb $incPar $bMax $dMax
        if ($curLen -le $budget) { break }

        if ($incToken -and $tokenStr) { $incToken = $false }
        elseif ($incRate -and $plainRate) { $incRate = $false }
        elseif ($incAb -and $gitAb) { $incAb = $false }
        elseif ($incPar -and $dirParent) { $incPar = $false }
        elseif ($bMax -gt 14 -and $branch -and $branch.Length -gt 14) { $bMax = 14 }
        elseif ($dMax -gt 18 -and $dirCurrent.Length -gt 18) { $dMax = 18 }
        elseif ($bMax -gt 8 -and $branch -and $branch.Length -gt 8) { $bMax = 8 }
        elseif ($dMax -gt 10 -and $dirCurrent.Length -gt 10) { $dMax = 10 }
        else { $dropBar = $true; break }
    }

    # Assemble Output
    $sep = "${DIM}│$RESET"
    $gradModel = Get-GradientText $modelDisplay $modelStops
    $prefix = "${BOLD}${gradModel}${RESET} $sep "

    if ($incPar -and $dirParent) {
        $prefix += "${FG_DARK_ORANGE}${dirParent}${RESET}${DIM}/${RESET}"
    }
    $dirShow = Truncate-String $dirCurrent $dMax
    $prefix += "${BOLD}${FG_YELLOW}${dirShow}${RESET}"

    if ($branch) {
        $prefix += " $sep "
        $branchShow = Truncate-String $branch $bMax
        $gradBranch = Get-GradientText $branchShow @(185, 105, 255, 85, 160, 255)
        $prefix += "${gradBranch}${RESET}"
        if ($gitDirty) { $prefix += "${FG_YELLOW}${gitDirty}${RESET}" }
        if ($incAb -and $gitAb) { $prefix += "${FG_MUTED}${gitAb}${RESET}" }
    }

    if ($incRate -and $rateStr) {
        $prefix += " $sep $rateStr"
    }

    $prefix += " $sep ${barFillColor}${usedInt}%$RESET"
    if ($incToken -and $tokenStr) {
        $prefix += "${DIM}($tokenStr)$RESET"
    }
    $prefix += " "

    # Bar sizing
    $visibleLen = Get-PrefixLen $incToken $incRate $incAb $incPar $bMax $dMax
    $MAX_BAR_LEN = 60
    $barOuter = 2
    $available = $cols - $visibleLen - $barOuter

    if ($available -lt 1) {
        $dropBar = $true
        $available = 1
    } else {
        $available = [int]($available * 0.92 - 1)
        if ($available -gt $MAX_BAR_LEN) { $available = $MAX_BAR_LEN }
        if ($available -lt 1) { $available = 1 }
    }

    $totalEighths = $available * 8
    $filledEighths = [int]($totalEighths * $usedInt / 100.0)
    $fullCells = [int]($filledEighths / 8)
    $remainder = $filledEighths % 8
    $remAdd = 0
    if ($remainder -gt 0) { $remAdd = 1 }
    $emptyCells = [Math]::Max(0, ($available - $fullCells - $remAdd))

    $partialChar = switch ($remainder) {
        1 { "▏" }
        2 { "▎" }
        3 { "▍" }
        4 { "▌" }
        5 { "▋" }
        6 { "▊" }
        7 { "▉" }
        default { "" }
    }

    $barFilled = if ($fullCells -gt 0) { (-join (1..$fullCells | ForEach-Object { '█' })) } else { "" }
    $barEmptyStr = if ($emptyCells -gt 0) { (-join (1..$emptyCells | ForEach-Object { '░' })) } else { "" }

    $partialSegment = ""
    if ($partialChar) {
        $partialSegment = "${barFillColor}${BAR_EMPTY_BG}${partialChar}${RESET}"
    }

    if ($dropBar) {
        $bar = ""
    } else {
        $bar = "${DIM}[${RESET}${barFillColor}${barFilled}${RESET}${partialSegment}${BAR_EMPTY_COLOR}${barEmptyStr}${RESET}${DIM}]${RESET}"
    }

    Write-Output "$prefix$bar"
}
