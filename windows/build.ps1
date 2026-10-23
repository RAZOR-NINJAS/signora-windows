# ==============================================================================
# Signora — native Windows frontend build
#
# Publishes the WinUI 3 app self-contained so the target laptop does not need a
# preinstalled .NET runtime. The Python engine is provisioned by ..\install.ps1.
# ==============================================================================

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$project = Join-Path $PSScriptRoot "Signora.Windows\Signora.Windows.csproj"
$output = Join-Path $PSScriptRoot "dist\Signora"

Write-Host ""
Write-Host "  Signora native Windows build" -ForegroundColor Cyan
Write-Host "  Project: $project" -ForegroundColor DarkGray
Write-Host "  Output:  $output" -ForegroundColor DarkGray
Write-Host ""

if (-not (Test-Path $project)) {
    Write-Host "  [ERROR] WinUI project not found at $project" -ForegroundColor Red
    exit 1
}

$dotnetExe = $null
$dotnetCmd = Get-Command dotnet -ErrorAction SilentlyContinue
if ($dotnetCmd) {
    $sdks = & $dotnetCmd.Source --list-sdks 2>$null
    if ($sdks -match '(?m)^8\.') {
        $dotnetExe = $dotnetCmd.Source
    }
}

if (-not $dotnetExe) {
    $localDotnet = Join-Path $root ".dotnet"
    $localExe = Join-Path $localDotnet "dotnet.exe"
    if (-not (Test-Path $localExe)) {
        Write-Host "  [+] Provisioning .NET 8 SDK (user-local)..." -ForegroundColor Yellow
        $installer = Join-Path $env:TEMP "dotnet-install.ps1"
        Invoke-WebRequest -Uri "https://dot.net/v1/dotnet-install.ps1" -OutFile $installer -UseBasicParsing
        & $installer -Channel 8.0 -InstallDir $localDotnet
    }
    $dotnetExe = $localExe
    $env:PATH = "$localDotnet;$env:PATH"
}

if (-not $dotnetExe -or -not (Test-Path $dotnetExe)) {
    Write-Host "  [ERROR] .NET SDK could not be provisioned." -ForegroundColor Red
    exit 1
}

$env:DOTNET_CLI_TELEMETRY_OPTOUT = "1"
$env:DOTNET_NOLOGO = "1"

Write-Host "  [+] Restoring and publishing..." -ForegroundColor Cyan
& $dotnetExe publish $project `
    -c Release `
    -r win-x64 `
    -p:Platform=x64 `
    --self-contained true `
    -p:WindowsAppSDKSelfContained=true `
    -p:PublishSingleFile=false `
    -o $output

if ($LASTEXITCODE -ne 0) {
    Write-Host "  [ERROR] dotnet publish failed with code $LASTEXITCODE" -ForegroundColor Red
    exit $LASTEXITCODE
}

Set-Content -Path (Join-Path $output "signora-root.txt") -Value $root -Encoding UTF8

Write-Host ""
Write-Host "  [OK] Published to $output" -ForegroundColor Green
Write-Host "  Run: $output\Signora.Windows.exe" -ForegroundColor Green
Write-Host ""
