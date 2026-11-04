param([int]$Count = 1)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Runtime.WindowsRuntime
[Windows.Media.SpeechSynthesis.SpeechSynthesizer,Windows.Media.SpeechSynthesis,ContentType=WindowsRuntime] | Out-Null
[Windows.Media.SpeechSynthesis.SpeechSynthesisStream,Windows.Media.SpeechSynthesis,ContentType=WindowsRuntime] | Out-Null
$root = Split-Path $PSScriptRoot -Parent
$dir = Join-Path $root 'assets_720p/audio_article_batch'
$out = Join-Path $root 'assets_720p/audio_article_cues'
[System.IO.Directory]::CreateDirectory($out) | Out-Null
$manifest = Get-Content -Raw -Encoding UTF8 (Join-Path $dir 'manifest.json') | ConvertFrom-Json
$synth = New-Object Windows.Media.SpeechSynthesis.SpeechSynthesizer
$synth.Voice = @([Windows.Media.SpeechSynthesis.SpeechSynthesizer]::AllVoices | Where-Object { $_.Language -eq 'zh-CN' -and $_.DisplayName -match 'Huihui' })[0]
$synth.Options.IncludeWordBoundaryMetadata = $true
$synth.Options.IncludeSentenceBoundaryMetadata = $true
$method = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
    $_.Name -eq 'AsTask' -and $_.IsGenericMethod -and $_.GetParameters().Count -eq 1 -and
    $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
} | Select-Object -First 1
try {
    foreach ($item in @($manifest | Select-Object -First $Count)) {
        $task = $method.MakeGenericMethod([Windows.Media.SpeechSynthesis.SpeechSynthesisStream]).Invoke($null, @($synth.SynthesizeTextToStreamAsync($item.speech)))
        $stream = $task.GetAwaiter().GetResult()
        $tracks = @()
        foreach ($track in $stream.TimedMetadataTracks) {
            $cues = @()
            foreach ($cue in $track.Cues) {
                $cues += @{ time_ticks=$cue.StartTime.Ticks; duration_ticks=$cue.Duration.Ticks; text=$cue.Text; properties=$cue.Properties }
            }
            $tracks += @{ id=$track.Id; kind=[string]$track.TimedMetadataKind; cues=$cues }
        }
        $tracks | ConvertTo-Json -Depth 12 | Set-Content -Encoding UTF8 (Join-Path $out ($item.sfn + '.json'))
        $reader = [System.IO.WindowsRuntimeStreamExtensions]::AsStreamForRead($stream)
        $output = [System.IO.File]::Create((Join-Path $out $item.wav))
        try { $reader.CopyTo($output) } finally { $output.Dispose(); $reader.Dispose() }
        Write-Output ($item.sfn + ': ' + $tracks.Count + ' tracks')
    }
} finally { $synth.Dispose() }
