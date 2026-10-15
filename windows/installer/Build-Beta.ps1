[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$OutputDirectory,
    [Parameter(Mandatory)][string]$CompilerPath,
    [string]$DotnetPath = 'dotnet',
    [string]$ModelDirectory
)
$ErrorActionPreference = 'Stop'
$windowsRoot = Split-Path $PSScriptRoot -Parent
$repoRoot = Split-Path $windowsRoot -Parent
$project = Join-Path $windowsRoot 'src/Inlaut.App/Inlaut.App.csproj'
$version = ([xml](Get-Content -LiteralPath $project -Raw)).Project.PropertyGroup.Version
$destination = [IO.Path]::GetFullPath($OutputDirectory)
$payload = Join-Path $destination 'app'
# Refuse stale payloads: mixing old and new models/native DLLs is unsafe.
if (Test-Path -LiteralPath $payload) { throw "Use a fresh output directory: $payload already exists." }
New-Item -ItemType Directory -Path $payload -Force | Out-Null
& $DotnetPath publish $project -c Release -r win-x64 --self-contained true -p:PublishReadyToRun=false -o $payload
if ($LASTEXITCODE -ne 0) { throw 'Application publish failed.' }
$helper = Join-Path $destination 'update-host'
& $DotnetPath publish (Join-Path $windowsRoot 'src/Inlaut.UpdateHost/Inlaut.UpdateHost.csproj') -c Release -r win-x64 --self-contained true -o $helper
if ($LASTEXITCODE -ne 0) { throw 'Update helper publish failed.' }
Copy-Item -LiteralPath (Join-Path $helper 'Inlaut.UpdateHost.exe') -Destination $payload
$modelTarget = Join-Path $payload 'models'
New-Item -ItemType Directory -Path $modelTarget | Out-Null
$hashes = [ordered]@{
    'decoder.int8.onnx' = '4633A4B0A3F21F7ACE4DF02E772F5B5E63D45F84A71EE1E2660998FC4BEB46AD'
    'encoder.int8.onnx' = '10FBB959C36C461AFB02EA87C109119EB001F30E91A130663BD6D5BBCBA74BA9'
    'joiner.int8.onnx' = '80F493F2885F6CCBD9CF9C20F4B6C616C2EB6DAE48DF6A5D4A0653354F7FE66B'
    'tokens.txt' = 'ABB1136142604D6D1766AD5060BD4F4B1048D7A096CD094B2D40EEC3E666BE9F'
}
$modelUrl = 'https://huggingface.co/csukuangfj/sherpa-onnx-nemo-transducer-stt_de_fastconformer_hybrid_large_pc-int8/resolve/main'
foreach ($name in $hashes.Keys) {
    $target = Join-Path $modelTarget $name
    if ($ModelDirectory) { Copy-Item -LiteralPath (Join-Path $ModelDirectory $name) -Destination $target }
    else { Invoke-WebRequest -Uri "$modelUrl/$name" -OutFile $target }
    if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $hashes[$name]) { throw "Model checksum mismatch: $name" }
}
foreach ($name in @('README.md', 'HANDOFF.md', 'MODEL_EVALUATION.md', 'UX_REVIEW.md', 'CRASH_REPORTS.md', 'UPDATES.md')) {
    Copy-Item -LiteralPath (Join-Path $windowsRoot $name) -Destination $payload
}
Copy-Item -LiteralPath (Join-Path $repoRoot 'LICENSE') -Destination $payload
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'BETA.md') -Destination $payload
& $CompilerPath "/DPayloadDir=$payload" "/DArtifactDir=$destination" "/DAppVersion=$version" (Join-Path $PSScriptRoot 'inlaut.iss')
if ($LASTEXITCODE -ne 0) { throw 'Installer compilation failed.' }
$installer = Join-Path $destination "inlaut-$version-windows-x64-setup.exe"
"$((Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash.ToLowerInvariant())  $([IO.Path]::GetFileName($installer))" |
    Set-Content -LiteralPath (Join-Path $destination 'SHA256SUMS.txt') -Encoding utf8
Write-Output $installer
