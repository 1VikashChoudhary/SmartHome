# ==============================================================================
# SmartHome Controller - Firmware Compilation & Packaging Script
# Compiles firmware for both ESP8266 and ESP32, then packages .bin files into binaries/
# ==============================================================================

param(
    [ValidateSet("all", "esp32", "esp8266")]
    [string]$Target = "all"
)

$ErrorActionPreference = "Stop"

# 1. Resolve Arduino CLI path
$ArduinoCli = "C:\Users\vikas\AppData\Local\Programs\Arduino IDE\resources\app\lib\backend\resources\arduino-cli.exe"
if (-not (Test-Path $ArduinoCli)) {
    $cliInPath = Get-Command arduino-cli -ErrorAction SilentlyContinue
    if ($cliInPath) {
        $ArduinoCli = $cliInPath.Source
    } else {
        Write-Error "arduino-cli.exe not found! Please check Arduino IDE installation."
        exit 1
    }
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$BuildDir  = "C:\shbuild"
$BinDir    = Join-Path $ScriptDir "binaries"

# Ensure output folders exist
New-Item -ItemType Directory -Force -Path (Join-Path $BinDir "esp8266") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $BinDir "esp32") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $BuildDir "esp8266") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $BuildDir "esp32") | Out-Null

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  SmartHome Firmware Builder (ESP8266 + ESP32)" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "Compiler: $ArduinoCli" -ForegroundColor Gray
Write-Host "Sketch:   $ScriptDir" -ForegroundColor Gray
Write-Host ""

# ==============================================================================
# ESP8266 Build
# ==============================================================================
if ($Target -eq "all" -or $Target -eq "esp8266") {
    Write-Host "[1/2] Compiling for ESP8266 (NodeMCU v2 / D1 Mini 4MB)..." -ForegroundColor Yellow
    $sw8266 = [System.Diagnostics.Stopwatch]::StartNew()
    
    & $ArduinoCli compile `
        -b esp8266:esp8266:nodemcuv2 `
        --build-path "$BuildDir\esp8266" `
        "$ScriptDir"
    
    if ($LASTEXITCODE -eq 0) {
        $srcBin = "$BuildDir\esp8266\SmartHome.ino.bin"
        Copy-Item $srcBin "$BinDir\esp8266\SmartHome_ESP8266.bin" -Force
        Copy-Item $srcBin "$BinDir\esp8266\SmartHome.ino.bin" -Force
        $sw8266.Stop()
        $size = (Get-Item "$BinDir\esp8266\SmartHome_ESP8266.bin").Length / 1KB
        Write-Host "  -> ESP8266 Build SUCCESS! ($([math]::Round($size, 1)) KB in $($sw8266.Elapsed.Seconds)s)" -ForegroundColor Green
        Write-Host "     Output: binaries/esp8266/SmartHome_ESP8266.bin" -ForegroundColor Gray
    } else {
        Write-Host "  -> ESP8266 Build FAILED!" -ForegroundColor Red
        exit 1
    }
    Write-Host ""
}

# ==============================================================================
# ESP32 Build
# ==============================================================================
if ($Target -eq "all" -or $Target -eq "esp32") {
    Write-Host "[2/2] Compiling for ESP32 (Dev Module, min_spiffs OTA)..." -ForegroundColor Yellow
    $sw32 = [System.Diagnostics.Stopwatch]::StartNew()
    
    & $ArduinoCli compile `
        -b espressif:esp32:esp32:PartitionScheme=min_spiffs `
        --build-path "$BuildDir\esp32" `
        "$ScriptDir"
    
    if ($LASTEXITCODE -eq 0) {
        Copy-Item "$BuildDir\esp32\SmartHome.ino.bin" "$BinDir\esp32\SmartHome_ESP32.bin" -Force
        Copy-Item "$BuildDir\esp32\SmartHome.ino.bootloader.bin" "$BinDir\esp32\bootloader.bin" -Force
        Copy-Item "$BuildDir\esp32\SmartHome.ino.partitions.bin" "$BinDir\esp32\partitions.bin" -Force
        Copy-Item "$BuildDir\esp32\SmartHome.ino.merged.bin" "$BinDir\esp32\SmartHome_ESP32_merged_0x0.bin" -Force
        
        $sw32.Stop()
        $appSize = (Get-Item "$BinDir\esp32\SmartHome_ESP32.bin").Length / 1MB
        Write-Host "  -> ESP32 Build SUCCESS! ($([math]::Round($appSize, 2)) MB in $($sw32.Elapsed.Seconds)s)" -ForegroundColor Green
        Write-Host "     App OTA:    binaries/esp32/SmartHome_ESP32.bin" -ForegroundColor Gray
        Write-Host "     USB Merged: binaries/esp32/SmartHome_ESP32_merged_0x0.bin" -ForegroundColor Gray
    } else {
        Write-Host "  -> ESP32 Build FAILED!" -ForegroundColor Red
        exit 1
    }
    Write-Host ""
}

Write-Host "==========================================================" -ForegroundColor Green
Write-Host "  All binaries successfully built and copied to binaries/" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
