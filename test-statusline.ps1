# Test harness for Antigravity & Claude Statusline
param(
    [ValidateSet("all", "ps1", "sh")]
    [string]$Target = "all"
)

$ESC = [char]27
$BOLD = "$ESC[1m"
$RESET = "$ESC[0m"
$CYAN = "$ESC[36m"

$testCases = @(
    @{
        Title = "Gemini 3.7 Flash - Clean Repo - Moderate Context"
        Payload = @{
            model = @{ id = "gemini-3.7-flash"; display_name = "Gemini 3.7 Flash" }
            workspace = @{ project_dir = "C:/Users/matis/antigravity-statusline" }
            session_id = "test-session-1"
            context_window = @{ used_percentage = 34; used_tokens = 340000; total_tokens = 1000000 }
            rate_limits = @{ five_hour = @{ used_percentage = 22 }; seven_day = @{ used_percentage = 14 } }
        }
    },
    @{
        Title = "Gemini 3.7 Pro - Heavy Context & High Rate Limits"
        Payload = @{
            model = @{ id = "gemini-3.7-pro"; display_name = "Gemini 3.7 Pro" }
            workspace = @{ project_dir = "C:/Users/matis/antigravity-statusline" }
            session_id = "test-session-2"
            context_window = @{ used_percentage = 87.5; used_tokens = 875000; total_tokens = 1000000 }
            rate_limits = @{ five_hour = @{ used_percentage = 84 }; seven_day = @{ used_percentage = 65 } }
        }
    },
    @{
        Title = "Antigravity Agent - 2M Token Window - Low Usage"
        Payload = @{
            model = @{ id = "antigravity-agent"; display_name = "Antigravity 2.0" }
            workspace = @{ project_dir = "C:/Users/matis/antigravity-statusline" }
            session_id = "test-session-3"
            context_window = @{ used_percentage = 12; used_tokens = 240000; total_tokens = 2000000 }
            rate_limits = @{ five_hour = @{ used_percentage = 8 }; seven_day = @{ used_percentage = 5 } }
        }
    },
    @{
        Title = "Claude Opus 4.7 - Sub-cell Precision Test (47% Context)"
        Payload = @{
            model = @{ id = "claude-opus-4-7"; display_name = "Claude Opus 4.7 (1M context)" }
            workspace = @{ project_dir = "C:/Users/matis/antigravity-statusline" }
            session_id = "test-session-4"
            context_window = @{ used_percentage = 47; used_tokens = 470000; total_tokens = 1000000 }
            rate_limits = @{ five_hour = @{ used_percentage = 42 }; seven_day = @{ used_percentage = 18 } }
        }
    },
    @{
        Title = "Claude Sonnet 3.7 - Critical Limit Test (96% Context)"
        Payload = @{
            model = @{ id = "claude-3-7-sonnet"; display_name = "Claude Sonnet 3.7" }
            workspace = @{ project_dir = "C:/Users/matis/antigravity-statusline" }
            session_id = "test-session-5"
            context_window = @{ used_percentage = 96; used_tokens = 192000; total_tokens = 200000 }
            rate_limits = @{ five_hour = @{ used_percentage = 92 }; seven_day = @{ used_percentage = 89 } }
        }
    }
)

Write-Host "`n${BOLD}${CYAN}================================================================${RESET}"
Write-Host "${BOLD}   ANTIGRAVITY & CLAUDE STATUSLINE VISUAL TEST HARNESS${RESET}"
Write-Host "${BOLD}${CYAN}================================================================${RESET}`n"

$scriptDir = $PSScriptRoot
$bashPath = "C:\Program Files\Git\bin\bash.exe"

foreach ($tc in $testCases) {
    Write-Host "${BOLD}Test: $($tc.Title)${RESET}"
    $json = $tc.Payload | ConvertTo-Json -Compress

    if ($Target -eq "all" -or $Target -eq "ps1") {
        Write-Host "${CYAN}[PowerShell Script Output]${RESET}"
        $json | & "$scriptDir\statusline.ps1"
    }

    if ($Target -eq "all" -or $Target -eq "sh") {
        if (Test-Path $bashPath) {
            Write-Host "${CYAN}[Bash Script Output]${RESET}"
            $shPath = "$scriptDir\statusline.sh".Replace('\', '/')
            $json | & $bashPath "$shPath"
        }
    }
    Write-Host ""
}
