Add-Type -AssemblyName System.Runtime.WindowsRuntime
[Windows.Media.SpeechSynthesis.SpeechSynthesizer,Windows.Media.SpeechSynthesis,ContentType=WindowsRuntime] | Out-Null
[Windows.Media.SpeechSynthesis.SpeechSynthesisStream,Windows.Media.SpeechSynthesis,ContentType=WindowsRuntime] | Out-Null
$synth = New-Object Windows.Media.SpeechSynthesis.SpeechSynthesizer
$synth.Voice = [Windows.Media.SpeechSynthesis.SpeechSynthesizer]::AllVoices | Where-Object { $_.Language -eq 'zh-CN' -and $_.DisplayName -match 'Huihui' } | Select-Object -First 1
$phrase = [string]::Concat([char[]](0x4E00,0x4E5D,0x4E8C,0x516D,0x5E74,0xFF0C,0x4E8E,0x654F,0x751F,0x4E8E,0x5929,0x6D25,0x5B81,0x6CB3,0xFF0C,0x5C11,0x5E74,0x65F6,0x4EE3,0x7ACB,0x5FD7,0x79D1,0x5B66,0x62A5,0x56FD,0x3002))
$operation = $synth.SynthesizeTextToStreamAsync($phrase)
$method = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.IsGenericMethod -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' } | Select-Object -First 1
$task = $method.MakeGenericMethod([Windows.Media.SpeechSynthesis.SpeechSynthesisStream]).Invoke($null,@($operation))
$stream = $task.GetAwaiter().GetResult()
$reader = [System.IO.WindowsRuntimeStreamExtensions]::AsStreamForRead($stream)
$outPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'assets_720p\audio_pilot\yumin_1926_voice.wav'
New-Item -ItemType Directory -Force (Split-Path $outPath) | Out-Null
$output = [System.IO.File]::Create($outPath)
try { $reader.CopyTo($output) } finally { $output.Dispose(); $reader.Dispose(); $synth.Dispose() }
Write-Output $outPath
