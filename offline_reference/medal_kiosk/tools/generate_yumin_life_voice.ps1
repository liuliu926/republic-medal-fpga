param([ValidateSet('1961','1967')][string]$Year)

Add-Type -AssemblyName System.Runtime.WindowsRuntime
[Windows.Media.SpeechSynthesis.SpeechSynthesizer,Windows.Media.SpeechSynthesis,ContentType=WindowsRuntime] | Out-Null
[Windows.Media.SpeechSynthesis.SpeechSynthesisStream,Windows.Media.SpeechSynthesis,ContentType=WindowsRuntime] | Out-Null
$synth = New-Object Windows.Media.SpeechSynthesis.SpeechSynthesizer
$synth.Voice = [Windows.Media.SpeechSynthesis.SpeechSynthesizer]::AllVoices | Where-Object { $_.Language -eq 'zh-CN' -and $_.DisplayName -match 'Huihui' } | Select-Object -First 1
if ($null -eq $synth.Voice) { throw 'Chinese Huihui voice unavailable' }
$dir = Join-Path (Split-Path $PSScriptRoot -Parent) 'assets_720p\audio_pilot'
$segments = Get-Content -Raw -Encoding UTF8 (Join-Path $dir "yumin_${Year}_segments.json") | ConvertFrom-Json
$method = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.IsGenericMethod -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' } | Select-Object -First 1
for ($i=0; $i -lt $segments.Count; $i++) {
    $operation = $synth.SynthesizeTextToStreamAsync($segments[$i].speech)
    $task = $method.MakeGenericMethod([Windows.Media.SpeechSynthesis.SpeechSynthesisStream]).Invoke($null,@($operation))
    $stream = $task.GetAwaiter().GetResult()
    $reader = [System.IO.WindowsRuntimeStreamExtensions]::AsStreamForRead($stream)
    $output = [System.IO.File]::Create((Join-Path $dir ("segment${Year}_${i}.wav")))
    try { $reader.CopyTo($output) } finally { $output.Dispose(); $reader.Dispose() }
}
$synth.Dispose()
Write-Output "Generated $($segments.Count) speech segments for $Year."
