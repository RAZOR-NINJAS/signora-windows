# ==============================================================================
# Signora — one-shot Windows setup, build, and launch
#
# Classic:
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\setup-windows.ps1
#
# Pixel edition (animated, game-style installer):
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\setup-windows.ps1 -Pixel
#   or double-click Pixel-Install.cmd
#
# Non-admin. Provisions a user-local Python 3.11 (via uv), CPU PyTorch,
# MediaPipe, OpenCV, Piper, the model assets, a user-local .NET 8 SDK, then
# publishes and launches the native WinUI 3 app.
# ==============================================================================

[CmdletBinding()]
param(
    [switch]$NoLaunch,
    [switch]$NoShortcut,
    [switch]$SkipModels,
    [switch]$Pixel,
    [switch]$Silent
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$script:PixelMode = [bool]$Pixel
$script:Quiet = [bool]$Silent
$script:Ansi = $false
$script:QuestIndex = 0
$script:QuestTotal = 0
$script:Palette = @{}

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

    $e = [char]27
    $script:Palette = @{
        Reset   = "$e[0m"
        Text    = "$e[38;2;226;240;255m"
        Dim     = "$e[38;2;104;122;140m"
        Green   = "$e[38;2;57;255;20m"
        Cyan    = "$e[38;2;0;229;255m"
        Magenta = "$e[38;2;255;43;214m"
        Yellow  = "$e[38;2;255;212;0m"
        Red     = "$e[38;2;255;59;48m"
        Purple  = "$e[38;2;122;92;255m"
    }
}

function Write-Px {
    param(
        [string]$Text = "",
        [string]$Tone = "Text",
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
        if ($NoNewline) {
            [Console]::Write($out)
        } else {
            [Console]::WriteLine($out)
        }
        return
    }

    $map = @{
        Text    = "White"
        Dim     = "DarkGray"
        Green   = "Green"
        Cyan    = "Cyan"
        Magenta = "Magenta"
        Yellow  = "Yellow"
        Red     = "Red"
        Purple  = "Magenta"
    }
    $color = $map[$Tone]
    if (-not $color) { $color = "White" }
    if ($NoNewline) {
        Write-Host $Text -ForegroundColor $color -NoNewline
    } else {
        Write-Host $Text -ForegroundColor $color
    }
}

function Write-Typewriter {
    param(
        [string]$Text,
        [string]$Tone = "Text",
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
    foreach ($note in @(523, 659, 784, 1047)) {
        try {
            [Console]::Beep($note, 90)
        } catch {
            return
        }
        Start-Sleep -Milliseconds 15
    }
}

function Write-PixelBar {
    param(
        [int]$Done,
        [int]$Total,
        [int]$Width = 28
    )

    if (-not $script:PixelMode -or $script:Quiet -or $Total -le 0) { return }

    $ratio = [Math]::Min(1.0, [Math]::Max(0.0, $Done / [double]$Total))
    $filled = [int][Math]::Round($Width * $ratio)
    $empty = $Width - $filled
    $bar = ("#" * $filled) + ("-" * $empty)
    $pct = [int][Math]::Round($ratio * 100)

    Write-Px ("      [$bar]  {0,3}%" -f $pct) "Cyan"
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
    $tones = @("Cyan", "Cyan", "Green", "Yellow", "Magenta")

    Write-Px ""
    for ($row = 0; $row -lt 5; $row++) {
        $line = ($letters | ForEach-Object { $_[$row] }) -join " "
        Write-Px ("  " + $line) $tones[$row]
    }
    Write-Px ""
    Write-Px "  OFFLINE SIGN LANGUAGE ENGINE  ::  WINDOWS EDITION" "Dim"
    Write-Px "  =================================================" "Dim"
}

function Show-PixelBoot {
    if (-not $script:PixelMode) { return }

    if (-not $script:Quiet) {
        try { Clear-Host } catch { }
        Write-PixelLogo
        Write-Px ""

        $os = "UNKNOWN"
        try { $os = [Environment]::OSVersion.VersionString.ToUpper() } catch { }
        $ps = $PSVersionTable.PSVersion.ToString()

        Write-Typewriter "  > SIGNORA SETUP CORE v1.0" "Cyan"
        Write-Typewriter "  > HOST ...................... $os" "Dim"
        Write-Typewriter "  > SHELL ..................... POWERSHELL $ps" "Dim"
        Write-Typewriter "  > MODE ...................... NON-ADMIN / USER-LOCAL" "Dim"
        Write-Typewriter "  > TARGET .................... NATIVE WINUI 3 APP" "Dim"
        Write-Typewriter "  > ALL SYSTEMS NOMINAL. PRESS ON, PLAYER." "Green"
        Write-Px ""
        Invoke-PixelBeep -Frequency 440 -Milliseconds 50
        Invoke-PixelBeep -Frequency 660 -Milliseconds 50
        Start-Sleep -Milliseconds 250
    }
}

function Write-PixelQuest {
    param([string]$Text)

    if (-not $script:PixelMode -or $script:Quiet) { return }

    $label = "QUEST {0:D2}/{1:D2}" -f $script:QuestIndex, $script:QuestTotal

    Write-Px ""
    Write-Px ("  " + ("=" * 58)) "Purple"
    Write-Px ("   >> $label   $($Text.ToUpper())") "Cyan"
    Write-Px ("  " + ("=" * 58)) "Purple"
    Write-PixelBar -Done ($script:QuestIndex - 1) -Total $script:QuestTotal
    Invoke-PixelBeep -Frequency 740 -Milliseconds 35
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
    Write-Px ("  " + ("#" * 62)) "Green"
    Write-Px ("  #" + (" " * 60) + "#") "Green"
    Write-Px ("  #" + "   ***  M I S S I O N   C O M P L E T E  ***".PadRight(60) + "#") "Yellow"
    Write-Px ("  #" + "       SIGNORA IS ONLINE. ALL SYSTEMS GO.".PadRight(60) + "#") "Green"
    Write-Px ("  #" + (" " * 60) + "#") "Green"
    Write-Px ("  " + ("#" * 62)) "Green"
    Write-Px ""
    Write-Px "   APP       $AppExe" "Text"
    Write-Px "   PYTHON    $PythonExe" "Text"
    Write-Px "   ROOT      $RootPath" "Text"
    Write-Px "   LOG       $LogPath" "Dim"
    Write-Px ""
    Write-PixelBar -Done 1 -Total 1
    Write-Px "   HIGH SCORE   $($script:QuestTotal) / $($script:QuestTotal) QUESTS" "Magenta"
    Write-Px ""
    Write-Px "   If the preview is black, open Settings and change the camera index." "Dim"
    Write-Px "   If the native build fails, read the compiler log above." "Dim"
    Write-Px ""
    Invoke-PixelChime
}

# ------------------------------------------------------------------- utilities

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
        Write-Px "     [+] $Text" "Green"
        return
    }
    Write-Host "  [OK] $Text" -ForegroundColor Green
}

function Write-Warn([string]$Text) {
    if ($script:PixelMode) {
        Write-Px "     [!] $Text" "Yellow"
        Invoke-PixelBeep -Frequency 320 -Milliseconds 70
        return
    }
    Write-Host "  [!] $Text" -ForegroundColor Yellow
}

function Write-Fail([string]$Text) {
    if ($script:PixelMode) {
        Write-Px "     [X] $Text" "Red"
        Invoke-PixelBeep -Frequency 180 -Milliseconds 220
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
    Write-Host ""
    Write-Fail "$($_.Exception.Message)"
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
    Write-Warn "Visual C++ runtime not detected. Trying a quiet install (may prompt for UAC)."
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

if (-not (Test-Path $venvPy)) {
    & $uvExe python install 3.11
    Assert-Native "uv python install"

    & $uvExe venv --python 3.11 $venvDir
    Assert-Native "uv venv"
}

if (-not (Test-Path $venvPy)) {
    Write-Fail "Python environment was not created at $venvDir"
    exit 1
}
Write-Ok "Python: $venvPy"

Write-Host "  Installing PyTorch (CPU) and Signora dependencies..." -ForegroundColor DarkGray
& $uvExe pip install --python $venvPy torch torchvision --index-url https://download.pytorch.org/whl/cpu
Assert-Native "PyTorch install"

& $uvExe pip install --python $venvPy -e $Root
Assert-Native "Signora install"
Write-Ok "Python dependencies installed."

# ---------------------------------------------------------------------- models
if (-not $SkipModels) {
    Write-Step "Model assets"
    & $venvPy (Join-Path $Root "scripts\fetch_models.py") --target-dir (Join-Path $Root "models")
    Assert-Native "Model fetch"

    $spatialModel = Join-Path $Root "models\isl_spatial_mlp.pt"
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

$appExe = Join-Path $appDir "Signora.Windows.exe"
if (-not (Test-Path $appExe)) {
    Write-Fail "Publish finished but $appExe is missing."
    exit 1
}

Set-Content -Path (Join-Path $appDir "signora-root.txt") -Value $Root -Encoding UTF8
Write-Ok "Published: $appExe"

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
