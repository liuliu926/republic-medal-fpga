param([string]$Drive = 'E:\')
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$targetRoot = [System.IO.Path]::GetFullPath($Drive)
if ($targetRoot -ne 'E:\') { throw "Unexpected target: $targetRoot" }
if (-not (Test-Path -LiteralPath (Join-Path $targetRoot 'BG001.BMP'))) { throw 'Competition TF card signature missing.' }
$source = Join-Path $root 'assets_720p\bgm_20261031\BGM.PCM'
$target = Join-Path $targetRoot 'BGM.PCM'
$expected = '98697BDCDD63B22C15675D61E1588B322AD95FA1B44D1AE246BBEF8BC75C3317'
if ((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ne $expected) { throw 'Source checksum mismatch.' }
if (Test-Path -LiteralPath $target) {
    if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $expected) { throw 'Different BGM.PCM already exists; preserve it for review.' }
} else {
    Copy-Item -LiteralPath $source -Destination $target
}
if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $expected) { throw 'TF checksum mismatch.' }
Write-Output "TF BGM verified; bytes=$((Get-Item -LiteralPath $target).Length); SHA256=$expected"
