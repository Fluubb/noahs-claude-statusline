$ErrorActionPreference = 'SilentlyContinue'
$log = Join-Path $env:USERPROFILE '.antigravity\.statusline-width-debug.log'
$logDir = [System.IO.Path]::GetDirectoryName($log)
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }

$logLines = [System.Collections.Generic.List[string]]::new()
function LogMsg($msg) { [void]$logLines.Add([string]$msg) }
$sw = [System.Diagnostics.Stopwatch]::StartNew()
LogMsg "===== $(Get-Date -Format o) ====="

$csharpCode = @'
[DllImport("kernel32.dll", SetLastError=true)] public static extern bool AttachConsole(uint dwProcessId);
[DllImport("kernel32.dll", SetLastError=true)] public static extern bool FreeConsole();
[DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Auto)] public static extern IntPtr CreateFile(string lpFileName, uint dwDesiredAccess, uint dwShareMode, IntPtr lpSecurityAttributes, uint dwCreationDisposition, uint dwFlagsAndAttributes, IntPtr hTemplateFile);
[DllImport("kernel32.dll", SetLastError=true)] public static extern bool CloseHandle(IntPtr hObject);
[StructLayout(LayoutKind.Sequential)] public struct COORD { public short X; public short Y; }
[StructLayout(LayoutKind.Sequential)] public struct SMALL_RECT { public short Left; public short Top; public short Right; public short Bottom; }
[StructLayout(LayoutKind.Sequential)] public struct CONSOLE_SCREEN_BUFFER_INFO {
  public COORD dwSize;
  public COORD dwCursorPosition;
  public ushort wAttributes;
  public SMALL_RECT srWindow;
  public COORD dwMaximumWindowSize;
}
[DllImport("kernel32.dll", SetLastError=true)] public static extern bool GetConsoleScreenBufferInfo(IntPtr hConsoleOutput, out CONSOLE_SCREEN_BUFFER_INFO lpConsoleScreenBufferInfo);
'@

Add-Type -Name Win32Console -Namespace Antigravity -MemberDefinition $csharpCode

LogMsg "baseline Host.WindowSize.Width = $($Host.UI.RawUI.WindowSize.Width)"

$procTable = @{}
Get-CimInstance Win32_Process -Property ProcessId, ParentProcessId, Name -ErrorAction SilentlyContinue |
  ForEach-Object { $procTable[[int]$_.ProcessId] = $_ }

function Get-ParentPid($processId) {
  $p = $procTable[[int]$processId]
  if ($p) { $p.ParentProcessId }
}
function Get-ProcName($processId) {
  $p = $procTable[[int]$processId]
  if ($p) { $p.Name }
}

$GENERIC_READ     = [uint32]'0x80000000'
$GENERIC_WRITE    = [uint32]'0x40000000'
$FILE_SHARE_READ  = [uint32]1
$FILE_SHARE_WRITE = [uint32]2
$OPEN_EXISTING    = [uint32]3
$INVALID_HANDLE   = [IntPtr]::new(-1)

function Try-GetWidth {
  $h = [Antigravity.Win32Console]::CreateFile("CONOUT$", ($GENERIC_READ -bor $GENERIC_WRITE), ($FILE_SHARE_READ -bor $FILE_SHARE_WRITE), [IntPtr]::Zero, $OPEN_EXISTING, 0, [IntPtr]::Zero)
  if ($h -eq $INVALID_HANDLE) {
    return @{ ok=$false; err="CreateFile CONOUT$ failed" }
  }
  try {
    $info = New-Object Antigravity.Win32Console+CONSOLE_SCREEN_BUFFER_INFO
    if ([Antigravity.Win32Console]::GetConsoleScreenBufferInfo($h, [ref]$info)) {
      $w = $info.srWindow.Right - $info.srWindow.Left + 1
      $bw = $info.dwSize.X
      return @{ ok=$true; window=$w; buffer=$bw }
    } else {
      return @{ ok=$false; err="GetConsoleScreenBufferInfo failed" }
    }
  } finally {
    [void][Antigravity.Win32Console]::CloseHandle($h)
  }
}

$bestWidth = $null
$cur = $PID
LogMsg "current PID = $cur ($(Get-ProcName $cur))"

for ($i = 0; $i -lt 14; $i++) {
  $parent = Get-ParentPid $cur
  if (-not $parent -or $parent -eq 0) { LogMsg "  no parent - stop"; break }
  $name = Get-ProcName $parent
  LogMsg "  ancestor[$i]: PID=$parent name=$name"

  [void][Antigravity.Win32Console]::FreeConsole()
  $ok = [Antigravity.Win32Console]::AttachConsole([uint32]$parent)
  if ($ok) {
    $r = Try-GetWidth
    if ($r.ok) {
      LogMsg "    attached OK: window width=$($r.window)  buffer width=$($r.buffer)"
      if ($r.window -gt 0) { $bestWidth = $r.window }
    } else {
      LogMsg "    attached but $($r.err)"
    }
    [void][Antigravity.Win32Console]::FreeConsole()
  } else {
    LogMsg "    AttachConsole failed"
  }

  $cur = $parent
}

if ($bestWidth) {
  LogMsg "best width = $bestWidth"
} else {
  LogMsg "no width found"
}
LogMsg "elapsed = $($sw.ElapsedMilliseconds)ms"
$logLines | Out-File -FilePath $log -Encoding utf8

if ($bestWidth) { Write-Output $bestWidth }