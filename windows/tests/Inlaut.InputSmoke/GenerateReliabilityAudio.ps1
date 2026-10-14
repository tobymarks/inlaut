param([Parameter(Mandatory)][string]$Destination)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Speech
New-Item -ItemType Directory -Force -Path $destination | Out-Null
$voice = New-Object System.Speech.Synthesis.SpeechSynthesizer
$voice.SelectVoice('Microsoft Hedda Desktop')
$format = New-Object System.Speech.AudioFormat.SpeechAudioFormatInfo(16000, [System.Speech.AudioFormat.AudioBitsPerSample]::Sixteen, [System.Speech.AudioFormat.AudioChannel]::Mono)
$sentences = @(
 'Guten Morgen. Das ist ein kurzer Test mit einer klaren deutschen Stimme.',
 'Guten Morgen neue Zeile die Lieferung kommt morgen um zehn Uhr neuer Absatz vielen Dank und freundliche Gruesse',
 (('Heute pruefen wir die Spracherkennung auf diesem Windows Rechner. Alle Woerter sollen vollstaendig und ohne Wiederholung im Dokument erscheinen. ' * 8).Trim())
)
try {
 for ($i=0; $i -lt $sentences.Length; $i++) {
  $voice.SetOutputToWaveFile((Join-Path $destination "speech-$i.wav"), $format)
  $voice.Speak($sentences[$i])
  $voice.SetOutputToNull()
 }
 $sentences | ConvertTo-Json | Set-Content (Join-Path $destination 'references.json') -Encoding UTF8
} finally {$voice.Dispose()}

# These negative fixtures are silence and very low amplitude noise, not a
# representative noisy-room or clipped-speech benchmark.
$random = [Random]::new(17)
foreach ($fixture in @(@('silence', 160000), @('short', 800), @('noise', 160000))) {
 $name = $fixture[0]; $samples = [int]$fixture[1]
 $writer = [IO.BinaryWriter]::new([IO.File]::Create((Join-Path $Destination "$name.wav")))
 try {
  $writer.Write([Text.Encoding]::ASCII.GetBytes('RIFF')); $writer.Write([int](36 + 2 * $samples))
  $writer.Write([Text.Encoding]::ASCII.GetBytes('WAVEfmt ')); $writer.Write([int]16)
  $writer.Write([int16]1); $writer.Write([int16]1); $writer.Write([int]16000)
  $writer.Write([int]32000); $writer.Write([int16]2); $writer.Write([int16]16)
  $writer.Write([Text.Encoding]::ASCII.GetBytes('data')); $writer.Write([int](2 * $samples))
  for ($i = 0; $i -lt $samples; $i++) {
   $value = if ($name -eq 'noise') { $random.Next(-30, 31) } else { 0 }
   $writer.Write([int16]$value)
  }
 } finally { $writer.Dispose() }
}
