param([string]$Drive = 'E:\')
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$driveRoot = [System.IO.Path]::GetFullPath($Drive)
if ($driveRoot -ne 'E:\') { throw "Unexpected target drive: $driveRoot" }
if (-not (Test-Path -LiteralPath (Join-Path $driveRoot 'BG001.BMP'))) {
    throw 'Competition TF card signature BG001.BMP is missing'
}
$copied = 0; $matched = 0; $bytes = [int64]0
foreach ($batch in @('audio_life_batch', 'audio_article_batch')) {
    $dir = Join-Path (Join-Path $root 'assets_720p') $batch
    $items = Get-Content -Raw -Encoding UTF8 (Join-Path $dir 'manifest.json') | ConvertFrom-Json
    foreach ($item in $items) {
        $source = Join-Path $dir $item.sfn
        $target = Join-Path $driveRoot $item.sfn
        if (-not (Test-Path -LiteralPath $source)) { throw "Missing local PCM: $source" }
        $sourceHash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
        if ($sourceHash -ne $item.sha256) { throw "Local manifest mismatch: $source" }
        if (-not (Test-Path -LiteralPath $target)) {
            Copy-Item -LiteralPath $source -Destination $target
            $copied++
        } else { $matched++ }
        $targetHash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
        if ($targetHash -ne $sourceHash) { throw "TF verification failed: $target" }
        $bytes += (Get-Item -LiteralPath $target).Length
    }
}
Write-Output "TF voice files verified: $($copied+$matched); copied=$copied; already_matched=$matched; bytes=$bytes"
