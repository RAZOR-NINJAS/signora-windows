# ==============================================================================
# Signora — one-shot Windows setup, build, and launch
#
# Classic:
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\setup-windows.ps1
#
# Pixel edition (animated, farm-style installer):
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\setup-windows.ps1 -Pixel
#   or double-click Pixel-Install.cmd
#
# Non-admin. Provisions a user-local Python 3.11 (via uv), CPU PyTorch,
# MediaPipe, OpenCV, Piper, the model assets, a user-local .NET 8 SDK, then
# publishes and launches the native WinUI 3 app.
#
# Re-running is safe and cheap: installed dependencies, verified models, and an
# up-to-date app build are detected and skipped.
# ==============================================================================

[CmdletBinding()]
param(
    [switch]$NoLaunch,
    [switch]$NoShortcut,
    [switch]$SkipModels,
    [switch]$Rebuild,
    [switch]$Pixel,
    [switch]$Ascii,
    [switch]$Silent
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$script:PixelMode = [bool]$Pixel
$script:Quiet = [bool]$Silent
$script:Ansi = $false
$script:Ascii = [bool]$Ascii
$script:QuestIndex = 0
$script:QuestTotal = 0
$script:Palette = @{}
$script:Glyph = @{}

$Root = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = (Get-Location).Path
}

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
} catch {
    # Older .NET Framework may already default to a usable protocol.
}

# --------------------------------------------------------------- pixel helpers

function Initialize-PixelConsole {
    if (-not $script:PixelMode) { return }

    try {
        [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
    } catch {
        $script:Ascii = $true
    }

    try {
        $source = @'
using System;
using System.Runtime.InteropServices;

public static class SignoraConsole
{
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr GetStdHandle(int handle);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GetConsoleMode(IntPtr handle, out uint mode);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool SetConsoleMode(IntPtr handle, uint mode);

    public static bool EnableVirtualTerminal()
    {
        IntPtr handle = GetStdHandle(-11);
        uint mode;
        if (!GetConsoleMode(handle, out mode)) return false;
        return SetConsoleMode(handle, mode | 0x0004);
    }
}
'@
        if (-not ("SignoraConsole" -as [type])) {
            Add-Type -TypeDefinition $source -ErrorAction Stop
        }
        $script:Ansi = [SignoraConsole]::EnableVirtualTerminal()
    } catch {
        $script:Ansi = $false
    }

    if ($script:Ascii -or $env:SIGNORA_ASCII -eq "1") {
        $script:Ascii = $true
        $script:Glyph = @{
            Full  = "#"
            Dark  = "%"
            Mid   = ":"
            Light = "."
            Upper = "^"
            Lower = "_"
        }
    } else {
        $script:Glyph = @{
            Full  = [string][char]0x2588
            Dark  = [string][char]0x2593
            Mid   = [string][char]0x2592
            Light = [string][char]0x2591
            Upper = [string][char]0x2580
            Lower = [string][char]0x2584
        }
    }

    $e = [char]27
    $script:Palette = @{
        Reset    = "$e[0m"
        Ink      = "$e[38;2;58;42;26m"
        Dim      = "$e[38;2;120;104;84m"
        Cream    = "$e[38;2;255;243;214m"
        White    = "$e[38;2;255;255;255m"
        Parch    = "$e[38;2;246;231;193m"
        ParchDim = "$e[38;2;214;192;150m"
        Gold     = "$e[38;2;244;196;48m"
        GoldDark = "$e[38;2;191;144;0m"
        Wood     = "$e[38;2;107;66;38m"
        WoodLite = "$e[38;2;201;150;106m"
        Green    = "$e[38;2;106;176;76m"
        GreenDk  = "$e[38;2;62;123;39m"
        Sky      = "$e[38;2;126;200;227m"
        SkyDk    = "$e[38;2;74;144;217m"
        Red      = "$e[38;2;214;72;54m"
        BgInk    = "$e[48;2;43;29;20m"
        BgWood   = "$e[48;2;107;66;38m"
        BgWoodDk = "$e[48;2;74;45;26m"
        BgParch  = "$e[48;2;246;231;193m"
        BgSky    = "$e[48;2;126;200;227m"
        BgSkyDk  = "$e[48;2;74;144;217m"
        BgGreen  = "$e[48;2;106;176;76m"
        BgGreenDk = "$e[48;2;62;123;39m"
        BgGold   = "$e[48;2;244;196;48m"
        BgRed    = "$e[48;2;192;57;43m"
    }
}

function ConvertTo-PxArt {
    param([string]$Art)
    $g = $script:Glyph
    return $Art.Replace("@", $g.Full).Replace("#", $g.Full).Replace("^", $g.Upper).Replace("*", $g.Mid).Replace(".", $g.Mid)
}

function Write-PxParts {
    param(
        [object[]]$Parts,
        [switch]$NoNewline
    )

    if (-not $script:PixelMode) {
        $flat = ($Parts | ForEach-Object { $_.T }) -join ""
        if ($NoNewline) { Write-Host $flat -NoNewline } else { Write-Host $flat }
        return
    }

    foreach ($part in $Parts) {
        $text = [string]$part.T
        $tone = [string]$part.F
        $back = [string]$part.B

        if ($script:Quiet -and $tone -ne "Red") { continue }
        if ([string]::IsNullOrEmpty($text)) { continue }

        if ($script:Ansi) {
            $fg = $script:Palette[$tone]
            $bg = $script:Palette[$back]
            if (-not $fg) { $fg = $script:Palette.Text }
            [Console]::Write("$fg$bg$text$($script:Palette.Reset)")
        } else {
            $color = if ($tone) { $tone } else { "White" }
            switch ($tone) {
                "Ink"      { $color = "Black" }
                "Cream"    { $color = "White" }
                "Parch"    { $color = "White" }
                "ParchDim" { $color = "Gray" }
                "Dim"      { $color = "DarkGray" }
                "Gold"     { $color = "Yellow" }
                "GoldDark" { $color = "DarkYellow" }
                "Wood"     { $color = "DarkYellow" }
                "WoodLite" { $color = "Yellow" }
                "Green"    { $color = "Green" }
                "GreenDk"  { $color = "DarkGreen" }
                "Sky"      { $color = "Cyan" }
                "SkyDk"    { $color = "DarkCyan" }
                "Red"      { $color = "Red" }
                default    { $color = "White" }
            }
            Write-Host $text -ForegroundColor $color -NoNewline
        }
    }

    if ($NoNewline) { return }
    if ($script:Ansi) { [Console]::WriteLine() } else { Write-Host "" }
}

function Write-PxSolid {
    param(
        [string]$Text = "",
        [string]$Fg = "Ink",
        [string]$Bg = "BgParch",
        [int]$Width = 0,
        [string]$Align = "Left"
    )

    if ($Width -gt $Text.Length) {
        $gap = $Width - $Text.Length
        switch ($Align) {
            "Center" {
                $left = [int][Math]::Floor($gap / 2)
                $Text = (" " * $left) + $Text + (" " * ($gap - $left))
            }
            "Right" {
                $Text = (" " * $gap) + $Text
            }
            default {
                $Text = $Text + (" " * $gap)
            }
        }
    }

    Write-PxParts -Parts @(@{ T = $Text; F = $Fg; B = $Bg })
}

function Write-PxPanel {
    param(
        [string[]]$Lines,
        [int]$Width = 62,
        [string]$Fg = "Ink",
        [string]$Bg = "BgParch",
        [int]$PadX = 2
    )

    $frame = $script:Glyph.Dark
    $field = $Width - ($PadX * 2)

    Write-PxParts -Parts @(@{ T = (" " * 2); F = "Cream"; B = "" }, @{ T = ($frame * ($Width + 2)); F = "WoodLite"; B = "BgWood" })
    foreach ($line in $Lines) {
        $text = $line
        if ($text.Length -gt $field) { $text = $text.Substring(0, $field) }
        $gap = $field - $text.Length
        $left = [int][Math]::Floor($gap / 2)
        Write-PxParts -Parts @(
            @{ T = (" " * 2); F = "Cream"; B = "" },
            @{ T = $frame; F = "WoodLite"; B = "BgWood" },
            @{ T = (" " * $PadX); F = $Fg; B = $Bg },
            @{ T = ((" " * $left) + $text + (" " * ($gap - $left))); F = $Fg; B = $Bg },
            @{ T = (" " * $PadX); F = $Fg; B = $Bg },
            @{ T = $frame; F = "WoodLite"; B = "BgWood" }
        )
    }
    Write-PxParts -Parts @(@{ T = (" " * 2); F = "Cream"; B = "" }, @{ T = ($frame * ($Width + 2)); F = "WoodLite"; B = "BgWood" })
}

function Write-Px {
    param(
        [string]$Text = "",
        [string]$Tone = "Cream",
        [switch]$NoNewline
    )

    if (-not $script:PixelMode) {
        if ($NoNewline) { Write-Host $Text -NoNewline } else { Write-Host $Text }
        return
    }

    if ($script:Quiet -and $Tone -ne "Red") { return }

    if ($script:Ansi) {
        if ([string]::IsNullOrEmpty($Text)) {
            if (-not $NoNewline) { [Console]::WriteLine() }
            return
        }
        $out = "$($script:Palette[$Tone])$Text$($script:Palette.Reset)"
        if ($NoNewline) { [Console]::Write($out) } else { [Console]::WriteLine($out) }
        return
    }

    $color = "White"
    switch ($Tone) {
        "Ink"      { $color = "Black" }
        "Cream"    { $color = "White" }
        "Parch"    { $color = "White" }
        "ParchDim" { $color = "Gray" }
        "Dim"      { $color = "DarkGray" }
        "Gold"     { $color = "Yellow" }
        "GoldDark" { $color = "DarkYellow" }
        "Wood"     { $color = "DarkYellow" }
        "WoodLite" { $color = "Yellow" }
        "Green"    { $color = "Green" }
        "GreenDk"  { $color = "DarkGreen" }
        "Sky"      { $color = "Cyan" }
        "SkyDk"    { $color = "DarkCyan" }
        "Red"      { $color = "Red" }
    }
    if ($NoNewline) {
        Write-Host $Text -ForegroundColor $color -NoNewline
    } else {
        Write-Host $Text -ForegroundColor $color
    }
}

function Write-Typewriter {
    param(
        [string]$Text,
        [string]$Tone = "Cream",
        [int]$DelayMs = 4
    )

    if (-not $script:PixelMode -or $script:Quiet) { return }

    if (-not $script:Ansi) {
        Write-Px $Text $Tone
        return
    }

    foreach ($ch in $Text.ToCharArray()) {
        [Console]::Write("$($script:Palette[$Tone])$ch")
        if ($DelayMs -gt 0) { Start-Sleep -Milliseconds $DelayMs }
    }
    [Console]::WriteLine("$($script:Palette.Reset)")
}

function Invoke-PixelBeep {
    param(
        [int]$Frequency = 880,
        [int]$Milliseconds = 60
    )

    if (-not $script:PixelMode -or $script:Quiet) { return }
    try {
        [Console]::Beep($Frequency, $Milliseconds)
    } catch {
        # No console beep on this host.
    }
}

function Invoke-PixelChime {
    if (-not $script:PixelMode -or $script:Quiet) { return }
    foreach ($note in @(392, 523, 659, 784, 1047)) {
        try {
            [Console]::Beep($note, 85)
        } catch {
            return
        }
        Start-Sleep -Milliseconds 12
    }
}

function Write-PixelScene {
    if (-not $script:PixelMode -or $script:Quiet) { return }

    $rows = @(
        @{ A = "                                                                "; F = "Cream";   B = "BgSky" },
        @{ A = "                              @@@@                              "; F = "Gold";    B = "BgSky" },
        @{ A = "                    **        @@@@@@        **                  "; F = "White";   B = "BgSky" },
        @{ A = "     ^^^^^^       ^^^^^^^^^@   @@@@   ^^^^^^^^^^^^               "; F = "GreenDk"; B = "BgSky" },
        @{ A = " ###############  ##################  ####################      "; F = "Green";   B = "BgSky" },
        @{ A = "################################################################"; F = "GreenDk"; B = "BgGreenDk" }
    )

    foreach ($row in $rows) {
        $art = $row.A.PadRight(64)
        if ($art.Length -gt 64) { $art = $art.Substring(0, 64) }
        $art = ConvertTo-PxArt $art
        Write-PxParts -Parts @(
            @{ T = "  "; F = "Cream"; B = "" },
            @{ T = $art; F = $row.F; B = $row.B }
        )
    }
}

function Write-PixelLogo {
    if (-not $script:PixelMode -or $script:Quiet) { return }

    $letters = @(
        @("#####", "#    ", "#### ", "    #", "#####"),
        @("#####", "  #  ", "  #  ", "  #  ", "#####"),
        @(" ####", "#    ", "# ###", "#   #", " ### "),
        @("#   #", "##  #", "# # #", "#  ##", "#   #"),
        @(" ### ", "#   #", "#   #", "#   #", " ### "),
        @("#### ", "#   #", "#### ", "#  # ", "#   #"),
        @(" ### ", "#   #", "#####", "#   #", "#   #")
    )

    $lines = @()
    for ($row = 0; $row -lt 5; $row++) {
        $lines += (($letters | ForEach-Object { $_[$row] }) -join " ")
    }
    $lines += ""
    $lines += "~ PIXEL FARM EDITION ~"
    $lines += "OFFLINE SIGN LANGUAGE   -   WINDOWS"

    Write-PxPanel -Lines $lines -Width 62 -Fg "Wood" -Bg "BgParch"
}

function Show-PixelBoot {
    if (-not $script:PixelMode) { return }
    if ($script:Quiet) { return }

    try { Clear-Host } catch { }

    $width = 64
    $frame = $script:Glyph.Dark
    Write-PxSolid (" " * $width) "Cream" "BgSky"
    Write-PixelScene
    Write-Px ""
    Write-PixelLogo
    Write-Px ""

    $os = "UNKNOWN"
    try { $os = [Environment]::OSVersion.VersionString.ToUpper() } catch { }
    $ps = $PSVersionTable.PSVersion.ToString()

    Write-Typewriter "  > SIGNORA SETUP CORE v2.0" "Gold"
    Write-Typewriter "  > HOST ..................... $os" "Dim"
    Write-Typewriter "  > SHELL .................... POWERSHELL $ps" "Dim"
    Write-Typewriter "  > MODE ..................... NON-ADMIN, USER-LOCAL" "Dim"
    Write-Typewriter "  > SAFETY ................... ONLY THIS FOLDER + %LOCALAPPDATA% SIGNORA" "Dim"
    Write-Typewriter "  > Your documents and photos are never touched." "Green"
    Write-Typewriter "  > Reruns check what is already installed and skip it." "Green"
    Write-Px ""
    Invoke-PixelBeep -Frequency 523 -Milliseconds 45
    Invoke-PixelBeep -Frequency 659 -Milliseconds 45
    Start-Sleep -Milliseconds 200
}

function Write-PixelQuest {
    param([string]$Text)

    if (-not $script:PixelMode -or $script:Quiet) { return }

    $label = " QUEST {0}/{1} " -f $script:QuestIndex, $script:QuestTotal
    $body = " " + $Text.ToUpper()
    $used = $label.Length + $body.Length
    $pad = [Math]::Max(1, 64 - $used)

    Write-Px ""
    Write-PxParts -Parts @(
        @{ T = "  "; F = "Cream"; B = "" },
        @{ T = $label; F = "Gold"; B = "BgWood" },
        @{ T = $body; F = "Cream"; B = "BgWood" },
        @{ T = (" " * $pad); F = "Cream"; B = "BgWood" }
    )
    Write-PixelBar -Done ($script:QuestIndex - 1) -Total $script:QuestTotal
    Invoke-PixelBeep -Frequency 784 -Milliseconds 30
}

function Write-PixelBar {
    param(
        [int]$Done,
        [int]$Total,
        [int]$Width = 55
    )

    if (-not $script:PixelMode -or $script:Quiet -or $Total -le 0) { return }

    $ratio = [Math]::Min(1.0, [Math]::Max(0.0, $Done / [double]$Total))
    $filled = [int][Math]::Round($Width * $ratio)
    $empty = $Width - $filled
    $pct = [int][Math]::Round($ratio * 100)

    Write-PxParts -Parts @(
        @{ T = "   "; F = "Cream"; B = "" },
        @{ T = ">"; F = "GoldDark"; B = "" },
        @{ T = ($script:Glyph.Full * $filled); F = "Gold"; B = "" },
        @{ T = ($script:Glyph.Light * $empty); F = "Wood"; B = "" },
        @{ T = "<"; F = "GoldDark"; B = "" },
        @{ T = ("  {0,3}%" -f $pct); F = "Cream"; B = "" }
    )
}

function Show-PixelVictory {
    param(
        [string]$AppExe,
        [string]$PythonExe,
        [string]$RootPath,
        [string]$LogPath
    )

    if (-not $script:PixelMode) { return }
    if ($script:Quiet) { return }

    Write-Px ""
    Write-PxSolid (" " * 66) "Cream" "BgGold"
    Write-PxSolid ("  *  M I S S I O N   C O M P L E T E  *" ) "Ink" "BgGold" 66 "Center"
    Write-PxSolid (" " * 66) "Cream" "BgGold"
    Write-Px ""

    $lines = @(
        "SIGNORA IS ONLINE.",
        "",
        "APP     $AppExe",
        "PYTHON  $PythonExe",
        "ROOT    $RootPath",
        "LOG     $LogPath",
        "",
        "SAFE RUN - NOTHING OUTSIDE THESE FOLDERS WAS MODIFIED",
        "HIGH SCORE $($script:QuestTotal) / $($script:QuestTotal) QUESTS"
    )
    Write-PxPanel -Lines $lines -Width 62 -Fg "Ink" -Bg "BgParch"

    Write-Px ""
    Write-PxParts -Parts @(
        @{ T = "  "; F = "Cream"; B = "" },
        @{ T = ($script:Glyph.Full * 64); F = "Green"; B = "" }
    )
    Write-Px "   Press any key in the other window to close the installer." "Dim"
    Invoke-PixelChime
}

# ------------------------------------------------------------------- utilities

function Get-LogTail {
    param([string]$Path, [int]$Lines = 25)
    if (-not (Test-Path $Path)) { return "" }
    try {
        return ((Get-Content $Path -Tail $Lines) -join "`r`n")
    } catch {
        return ""
    }
}

function Write-Step([string]$Text) {
    if ($script:PixelMode) {
        $script:QuestIndex++
        Write-PixelQuest -Text $Text
        return
    }
    Write-Host ""
    Write-Host "==> $Text" -ForegroundColor Cyan
}

function Write-Ok([string]$Text) {
    if ($script:PixelMode) {
        Write-PxParts -Parts @(
            @{ T = "   "; F = "Cream"; B = "" },
            @{ T = "["; F = "GoldDark"; B = "" },
            @{ T = "+"; F = "Green"; B = "" },
            @{ T = "]"; F = "GoldDark"; B = "" },
            @{ T = " $Text"; F = "Green"; B = "" }
        )
        return
    }
    Write-Host "  [OK] $Text" -ForegroundColor Green
}

function Write-Warn([string]$Text) {
    if ($script:PixelMode) {
        Write-PxParts -Parts @(
            @{ T = "   "; F = "Cream"; B = "" },
            @{ T = "["; F = "GoldDark"; B = "" },
            @{ T = "!"; F = "Gold"; B = "" },
            @{ T = "]"; F = "GoldDark"; B = "" },
            @{ T = " $Text"; F = "Gold"; B = "" }
        )
        Invoke-PixelBeep -Frequency 320 -Milliseconds 60
        return
    }
    Write-Host "  [!] $Text" -ForegroundColor Yellow
}

function Write-Fail([string]$Text) {
    if ($script:PixelMode) {
        Write-PxParts -Parts @(
            @{ T = "   "; F = "Cream"; B = "" },
            @{ T = "["; F = "GoldDark"; B = "" },
            @{ T = "X"; F = "Red"; B = "" },
            @{ T = "]"; F = "GoldDark"; B = "" },
            @{ T = " $Text"; F = "Red"; B = "" }
        )
        Invoke-PixelBeep -Frequency 180 -Milliseconds 200
        return
    }
    Write-Host "  [ERROR] $Text" -ForegroundColor Red
}

function Invoke-Download([string]$Uri, [string]$OutFile) {
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing `
                -Headers @{ "User-Agent" = "Signora-Setup/1.0" }
            return
        } catch {
            if ($attempt -eq 3) {
                throw
            }
            Start-Sleep -Seconds (2 * $attempt)
        }
    }
}

function Assert-Native([string]$What) {
    if ($LASTEXITCODE -ne 0) {
        throw "$What failed with exit code $LASTEXITCODE."
    }
}

trap {
    $failure = $_
    $detail = @(
        "Signora setup failure",
        "Time:       $(Get-Date -Format o)",
        "Message:    $($failure.Exception.Message)",
        "Type:       $($failure.Exception.GetType().FullName)",
        "Line:       $($failure.InvocationInfo.ScriptLineNumber)",
        "Command:    $($failure.InvocationInfo.MyCommand)",
        "Root:       $Root",
        "PowerShell: $($PSVersionTable.PSVersion)",
        "OS:         $([Environment]::OSVersion.VersionString)",
        "",
        "Position:",
        $failure.InvocationInfo.PositionMessage,
        "",
        "Stack:",
        $failure.ScriptStackTrace
    ) -join "`r`n"

    $fetchTail = Get-LogTail (Join-Path $Root "model-fetch.log") 30
    if ($fetchTail) {
        $detail += "`r`n`r`nModel fetch tail:`r`n$fetchTail"
    }

    $errorLog = Join-Path $Root "install-error.log"
    try {
        Set-Content -Path $errorLog -Value $detail -Encoding UTF8
    } catch {
        $errorLog = "(could not write a log)"
    }

    Write-Host ""
    Write-Fail "$($failure.Exception.Message)"
    if ($failure.InvocationInfo.ScriptLineNumber) {
        Write-Host "  At line $($failure.InvocationInfo.ScriptLineNumber)." -ForegroundColor DarkGray
    }
    Write-Host "  Details: $errorLog" -ForegroundColor DarkGray
    Write-Host "  Setup stopped. Fix the issue above and rerun." -ForegroundColor DarkGray
    exit 1
}

# ------------------------------------------------------------------- preflight

$project = Join-Path $Root "windows\Signora.Windows\Signora.Windows.csproj"
if (-not (Test-Path (Join-Path $Root "pyproject.toml"))) {
    Write-Fail "pyproject.toml not found. Run this script from the Signora repository root."
    exit 1
}
if (-not (Test-Path $project)) {
    Write-Fail "WinUI project not found at $project"
    exit 1
}

$script:QuestTotal = 5
if (-not $SkipModels) { $script:QuestTotal++ }
if (-not $NoShortcut) { $script:QuestTotal++ }
if (-not $NoLaunch) { $script:QuestTotal++ }

if ($script:PixelMode) {
    Initialize-PixelConsole
    Show-PixelBoot
} else {
    Write-Host ""
    Write-Host "  Signora Windows setup" -ForegroundColor White
    Write-Host "  Root: $Root" -ForegroundColor DarkGray
    Write-Host ""
}

$toolsDir = Join-Path $env:LOCALAPPDATA "Signora\tools"
New-Item -ItemType Directory -Path $toolsDir -Force | Out-Null

# ------------------------------------------------------------------ VC++ runtime
Write-Step "Visual C++ runtime"
$vcKey = $null
try {
    $vcKey = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\X64" -ErrorAction SilentlyContinue
} catch {
    $vcKey = $null
}

if ($vcKey -and $vcKey.Installed) {
    Write-Ok "Visual C++ 2015-2022 runtime present."
} else {
    Write-Warn "Visual C++ runtime not detected. Trying a quiet install (may prompt for permission)."
    $vcInstaller = Join-Path $env:TEMP "signora-vc_redist.x64.exe"
    try {
        Invoke-Download "https://aka.ms/vs/17/release/vc_redist.x64.exe" $vcInstaller
        Start-Process -FilePath $vcInstaller -ArgumentList "/install", "/quiet", "/norestart" -Wait
        Write-Ok "Visual C++ runtime install completed."
    } catch {
        Write-Warn "Could not install the VC++ runtime automatically: $_"
        Write-Warn "If Python fails to start later, install vc_redist.x64.exe from Microsoft."
    } finally {
        Remove-Item $vcInstaller -Force -ErrorAction SilentlyContinue
    }
}

# ------------------------------------------------------------------------- uv
Write-Step "Python 3.11 environment"
$uvExe = $null
$uvCmd = Get-Command uv -ErrorAction SilentlyContinue
if ($uvCmd) {
    $uvExe = $uvCmd.Source
}

$localUv = Join-Path $toolsDir "uv.exe"
if (-not $uvExe -and (Test-Path $localUv)) {
    $uvExe = $localUv
}

if (-not $uvExe) {
    Write-Host "  Downloading uv..." -ForegroundColor DarkGray
    $uvZip = Join-Path $env:TEMP "signora-uv.zip"
    $uvExtract = Join-Path $env:TEMP "signora-uv"
    Invoke-Download "https://github.com/astral-sh/uv/releases/latest/download/uv-x86_64-pc-windows-msvc.zip" $uvZip

    if (Test-Path $uvExtract) {
        Remove-Item $uvExtract -Recurse -Force
    }
    Expand-Archive -Path $uvZip -DestinationPath $uvExtract -Force
    $uvFound = Get-ChildItem $uvExtract -Recurse -Filter uv.exe | Select-Object -First 1
    if (-not $uvFound) {
        throw "uv.exe was not found in the downloaded archive."
    }

    Copy-Item $uvFound.FullName $localUv -Force
    $uvExe = $localUv
    Remove-Item $uvZip -Force -ErrorAction SilentlyContinue
    Remove-Item $uvExtract -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Ok "uv: $uvExe"

$venvDir = Join-Path $Root ".venv"
$venvPy = Join-Path $venvDir "Scripts\python.exe"
$createdVenv = $false

if (-not (Test-Path $venvPy)) {
    & $uvExe python install 3.11
    Assert-Native "uv python install"

    & $uvExe venv --python 3.11 $venvDir
    Assert-Native "uv venv"
    $createdVenv = $true
}

if (-not (Test-Path $venvPy)) {
    Write-Fail "Python environment was not created at $venvDir"
    exit 1
}

if ($createdVenv) {
    Write-Ok "Python: $venvPy (created)"
} else {
    Write-Ok "Python: $venvPy (existing, reused)"
}

$torchReady = $false
$stackReady = $false
if (-not $createdVenv) {
    & $venvPy -c "import torch, torchvision" 2>$null
    if ($LASTEXITCODE -eq 0) { $torchReady = $true }

    & $venvPy -c "import signora, mediapipe, cv2" 2>$null
    if ($LASTEXITCODE -eq 0) { $stackReady = $true }
}

if ($torchReady -and $stackReady) {
    Write-Ok "Python dependencies already installed; skipping download."
} else {
    if (-not $torchReady) {
        Write-Host "  Installing PyTorch (CPU) and vision dependencies..." -ForegroundColor DarkGray
        & $uvExe pip install --python $venvPy torch torchvision --index-url https://download.pytorch.org/whl/cpu
        Assert-Native "PyTorch install"
    } else {
        Write-Ok "PyTorch already installed."
    }

    if (-not $stackReady) {
        & $uvExe pip install --python $venvPy -e $Root
        Assert-Native "Signora install"
    } else {
        Write-Ok "Signora package already installed."
    }
    Write-Ok "Python dependencies ready."
}

# ---------------------------------------------------------------------- models
if (-not $SkipModels) {
    Write-Step "Model assets"
    $modelsDir = Join-Path $Root "models"
    $fetchScript = Join-Path $Root "scripts\fetch_models.py"
    $fetchLog = Join-Path $Root "model-fetch.log"

    & $venvPy $fetchScript --target-dir $modelsDir --verify-only *> $null
    if ($LASTEXITCODE -eq 0) {
        Write-Ok "All model assets present and verified."
    } else {
        Write-Host "  Downloading missing model assets..." -ForegroundColor DarkGray
        & $venvPy $fetchScript --target-dir $modelsDir 2>&1 | Tee-Object -FilePath $fetchLog
        if ($LASTEXITCODE -ne 0) {
            $tail = Get-LogTail $fetchLog 20
            throw "Model download failed.`r`n$tail"
        }
        Write-Ok "Model assets downloaded and verified."
    }

    $spatialModel = Join-Path $modelsDir "isl_spatial_mlp.pt"
    if (-not (Test-Path $spatialModel)) {
        Write-Warn "Spatial ISL checkpoint not found. The engine will use the 164-D baseline."
        Write-Warn "Train a spatial model from the app's Train page once samples are ready."
    } else {
        Write-Ok "Spatial ISL checkpoint present."
    }
}

# ----------------------------------------------------------------------- .NET
Write-Step ".NET 8 SDK"
$dotnetDir = Join-Path $Root ".dotnet"
$dotnetExe = Join-Path $dotnetDir "dotnet.exe"
$dotnetCmd = Get-Command dotnet -ErrorAction SilentlyContinue

if ($dotnetCmd) {
    $sdks = & $dotnetCmd.Source --list-sdks 2>$null
    if ($sdks -match '(?m)^8\.') {
        $dotnetExe = $dotnetCmd.Source
    }
}

if (-not (Test-Path $dotnetExe)) {
    Write-Host "  Provisioning a user-local .NET 8 SDK..." -ForegroundColor DarkGray
    $dotnetInstaller = Join-Path $env:TEMP "signora-dotnet-install.ps1"
    Invoke-Download "https://dot.net/v1/dotnet-install.ps1" $dotnetInstaller
    & $dotnetInstaller -Channel 8.0 -InstallDir $dotnetDir -NoPath
    Remove-Item $dotnetInstaller -Force -ErrorAction SilentlyContinue
}

if (-not (Test-Path $dotnetExe)) {
    Write-Fail ".NET 8 SDK could not be provisioned."
    exit 1
}

if (Test-Path $dotnetDir) {
    $env:DOTNET_ROOT = $dotnetDir
    $env:PATH = "$dotnetDir;$env:PATH"
}
$env:DOTNET_CLI_TELEMETRY_OPTOUT = "1"
$env:DOTNET_NOLOGO = "1"
Write-Ok ".NET: $dotnetExe"

# -------------------------------------------------------------------- publish
Write-Step "Publishing the native WinUI 3 app"
$appDir = Join-Path $Root "app"
New-Item -ItemType Directory -Path $appDir -Force | Out-Null
$publishLog = Join-Path $Root "publish.log"
$appExe = Join-Path $appDir "Signora.Windows.exe"

$needsPublish = $true
if ((Test-Path $appExe) -and -not $Rebuild) {
    $exeTime = (Get-Item $appExe).LastWriteTimeUtc
    $newest = Get-ChildItem (Join-Path $Root "windows") -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in ".cs", ".xaml", ".csproj", ".manifest" } |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1
    if (-not $newest -or $newest.LastWriteTimeUtc -le $exeTime) {
        $needsPublish = $false
    }
}

if (-not $needsPublish) {
    Write-Ok "App already built and up to date; skipping publish."
} else {
    & $dotnetExe publish $project `
        -c Release `
        -r win-x64 `
        -p:Platform=x64 `
        --self-contained true `
        -p:WindowsAppSDKSelfContained=true `
        -p:PublishSingleFile=false `
        -o $appDir *> $publishLog

    $publishCode = $LASTEXITCODE
    if (-not $script:Quiet) {
        Get-Content $publishLog -Tail 25
    }

    if ($publishCode -ne 0) {
        Write-Fail "dotnet publish failed with code $publishCode."
        Write-Fail "Full log: $publishLog"
        exit $publishCode
    }

    if (-not (Test-Path $appExe)) {
        Write-Fail "Publish finished but $appExe is missing."
        exit 1
    }
    Write-Ok "Published: $appExe"
}

Set-Content -Path (Join-Path $appDir "signora-root.txt") -Value $Root -Encoding UTF8

# ------------------------------------------------------------------- shortcut
if (-not $NoShortcut) {
    Write-Step "Desktop shortcut"
    $desktop = [Environment]::GetFolderPath("Desktop")
    if ($desktop -and (Test-Path $desktop)) {
        try {
            $shortcutPath = Join-Path $desktop "Signora.lnk"
            $shell = New-Object -ComObject WScript.Shell
            $shortcut = $shell.CreateShortcut($shortcutPath)
            $shortcut.TargetPath = $appExe
            $shortcut.WorkingDirectory = $appDir
            $shortcut.IconLocation = "$appExe,0"
            $shortcut.Description = "Signora - Offline Sign Language Recognition"
            $shortcut.Save()
            Write-Ok "Shortcut: $shortcutPath"
        } catch {
            Write-Warn "Could not create the desktop shortcut: $_"
        }
    }
}

# --------------------------------------------------------------------- launch
if (-not $NoLaunch) {
    Write-Step "Launching Signora"
    Start-Process -FilePath $appExe -WorkingDirectory $appDir
    Write-Ok "Signora.Windows.exe started."
}

if ($script:PixelMode) {
    Show-PixelVictory -AppExe $appExe -PythonExe $venvPy -RootPath $Root -LogPath $publishLog
} else {
    Write-Host ""
    Write-Host "Signora is ready." -ForegroundColor Green
    Write-Host "  App:      $appExe"
    Write-Host "  Python:   $venvPy"
    Write-Host "  Root:     $Root"
    Write-Host "  Settings: $env:LOCALAPPDATA\Signora\settings.json"
    Write-Host ""
    Write-Host "If the preview is black, open Settings and change the camera index." -ForegroundColor DarkGray
    Write-Host "If the native build fails, the full compiler log is at $publishLog" -ForegroundColor DarkGray
}
