param([int]$Start = 0, [int]$Count = 48, [string]$Batch = 'audio_life_batch')

Add-Type -AssemblyName System.Runtime.WindowsRuntime
[Windows.Media.SpeechSynthesis.SpeechSynthesizer,Windows.Media.SpeechSynthesis,ContentType=WindowsRuntime] | Out-Null
[Windows.Media.SpeechSynthesis.SpeechSynthesisStream,Windows.Media.SpeechSynthesis,ContentType=WindowsRuntime] | Out-Null
$root = Split-Path $PSScriptRoot -Parent
$dir = Join-Path (Join-Path $root 'assets_720p') $Batch
$manifest = Get-Content -Raw -Encoding UTF8 (Join-Path $dir 'manifest.json') | ConvertFrom-Json
$voices = @([Windows.Media.SpeechSynthesis.SpeechSynthesizer]::AllVoices | Where-Object { $_.Language -eq 'zh-CN' -and $_.DisplayName -match 'Huihui' })
if ($voices.Count -eq 0) { throw 'Chinese Huihui voice is unavailable' }
$synth = New-Object Windows.Media.SpeechSynthesis.SpeechSynthesizer
$synth.Voice = $voices[0]
$method = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
    $_.Name -eq 'AsTask' -and $_.IsGenericMethod -and $_.GetParameters().Count -eq 1 -and
    $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
} | Select-Object -First 1
try {
    $end = [Math]::Min($manifest.Count, $Start + $Count)
    for ($i = $Start; $i -lt $end; $i++) {
        $item = $manifest[$i]
        $wavPath = Join-Path $dir $item.wav
        if (Test-Path -LiteralPath $wavPath) { continue }
        $operation = $synth.SynthesizeTextToStreamAsync($item.speech)
        $task = $method.MakeGenericMethod([Windows.Media.SpeechSynthesis.SpeechSynthesisStream]).Invoke($null, @($operation))
        $stream = $task.GetAwaiter().GetResult()
        $reader = [System.IO.WindowsRuntimeStreamExtensions]::AsStreamForRead($stream)
        $output = [System.IO.File]::Create($wavPath)
        try { $reader.CopyTo($output) } finally { $output.Dispose(); $reader.Dispose() }
        Write-Output ("{0}/{1} {2} {3}" -f ($i + 1), $manifest.Count, $item.person, $item.year)
    }
} finally { $synth.Dispose() }
