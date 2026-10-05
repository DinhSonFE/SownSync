param(
  [ValidateSet("Debug","Release")]
  [string]$Config = "Debug"
)
$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

# Flutter may finish rebuilding while an older SOWN Sync process still owns
# sown_core_api.dll. Stop every process launched from this workspace before
# replacing the native DLL.
Get-Process -Name "sown_sync" -ErrorAction SilentlyContinue | ForEach-Object {
  Write-Host "[SOWN] Stopping running sown_sync.exe (PID $($_.Id))..." -ForegroundColor Yellow
  Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Milliseconds 350
$coreBuild = Join-Path $root "build-native"
$flutter = Join-Path $root "flutter_app"
$fontDir = Join-Path $flutter "assets\fonts"
$fontFile = Join-Path $fontDir "DSEG7Modern-Regular.ttf"
if (!(Test-Path $fontFile)) {
  Write-Host "[SOWN] Fetching bundled DSEG7 Modern font..." -ForegroundColor Cyan
  New-Item -ItemType Directory -Force -Path $fontDir | Out-Null
  Invoke-WebRequest -Uri "https://raw.githubusercontent.com/NoahGadelrab/DSEG/main/DSEG7Modern-Regular.ttf" -OutFile $fontFile
}

Write-Host "[SOWN] Configuring native core..." -ForegroundColor Cyan
cmake -S $root -B $coreBuild -A x64
Write-Host "[SOWN] Building sown_core_api ($Config)..." -ForegroundColor Cyan
cmake --build $coreBuild --config $Config --target sown_core_api

$dll = Join-Path $coreBuild "$Config\sown_core_api.dll"
if (!(Test-Path $dll)) { throw "Native DLL not found: $dll" }

Push-Location $flutter
try {
  Write-Host "[SOWN] Building Flutter Windows ($Config)..." -ForegroundColor Cyan
  if ($Config -eq "Release") { flutter build windows --release } else { flutter build windows --debug }
  if ($LASTEXITCODE -ne 0) { throw "Flutter Windows build failed with exit code $LASTEXITCODE" }
} finally { Pop-Location }

$mode = if ($Config -eq "Release") { "Release" } else { "Debug" }
$appDir = Join-Path $flutter "build\windows\x64\runner\$mode"
if (!(Test-Path $appDir)) { throw "Flutter output directory not found: $appDir" }
$targetDll = Join-Path $appDir "sown_core_api.dll"
$copied = $false
for ($attempt = 1; $attempt -le 8 -and -not $copied; $attempt++) {
  try {
    Copy-Item $dll $targetDll -Force -ErrorAction Stop
    $copied = $true
  } catch {
    if ($attempt -eq 8) { throw }
    Write-Host "[SOWN] Native DLL still locked; retry $attempt/8..." -ForegroundColor Yellow
    Get-Process -Name "sown_sync" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500
  }
}
Write-Host "[SOWN] Native core integrated: $appDir\sown_core_api.dll" -ForegroundColor Green
Write-Host "[SOWN] Run: $appDir\sown_sync.exe" -ForegroundColor Green
