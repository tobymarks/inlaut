[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$OutputDirectory,
    [string]$CompilerPath,
    [string]$DotnetPath = 'dotnet',
    [string]$ModelDirectory,
    [switch]$SkipInstaller
)
$ErrorActionPreference = 'Stop'
if (-not $SkipInstaller -and -not $CompilerPath) { throw 'CompilerPath is required unless SkipInstaller is set.' }
$windowsRoot = Split-Path $PSScriptRoot -Parent
$repoRoot = Split-Path $windowsRoot -Parent
$project = Join-Path $windowsRoot 'src/Inlaut.App/Inlaut.App.csproj'
$version = ([xml](Get-Content -LiteralPath $project -Raw)).Project.PropertyGroup.Version
$destination = [IO.Path]::GetFullPath($OutputDirectory)
$payload = Join-Path $destination 'app'
# Refuse stale payloads: mixing old and new models/native DLLs is unsafe.
if (Test-Path -LiteralPath $payload) { throw "Use a fresh output directory: $payload already exists." }
New-Item -ItemType Directory -Path $payload -Force | Out-Null
& $DotnetPath publish $project -c Release -r win-x64 --self-contained true -p:PublishReadyToRun=false "-p:Version=$version" -p:Product=inlaut "-p:InformationalVersion=$version" -p:IncludeSourceRevisionInInformationalVersion=false -o $payload
if ($LASTEXITCODE -ne 0) { throw 'Application publish failed.' }
$helper = Join-Path $destination 'update-host'
& $DotnetPath publish (Join-Path $windowsRoot 'src/Inlaut.UpdateHost/Inlaut.UpdateHost.csproj') -c Release -r win-x64 --self-contained true "-p:Version=$version" -p:Product=inlaut "-p:InformationalVersion=$version" -p:IncludeSourceRevisionInInformationalVersion=false -o $helper
if ($LASTEXITCODE -ne 0) { throw 'Update helper publish failed.' }
Copy-Item -LiteralPath (Join-Path $helper 'Inlaut.UpdateHost.exe') -Destination $payload
$catalog = Get-Content -LiteralPath (Join-Path $windowsRoot 'models.json') -Raw | ConvertFrom-Json
foreach ($model in $catalog) {
    $modelTarget = Join-Path $payload "models/$($model.directory)"
    New-Item -ItemType Directory -Path $modelTarget -Force | Out-Null
    $source = $null
    if ($ModelDirectory -and $model.language -eq 'de') { $source = $ModelDirectory }
    elseif ($model.archiveUrl) {
        $archive = Join-Path $destination "$($model.language).tar.bz2"
        Invoke-WebRequest -Uri $model.archiveUrl -OutFile $archive
        if ((Get-FileHash $archive -Algorithm SHA256).Hash -ne $model.archiveSha256) { throw 'Model archive checksum mismatch' }
        & tar -xf $archive -C $destination
        if ($LASTEXITCODE -ne 0) { throw 'Model archive extraction failed' }
        $source = Join-Path $destination $model.archiveDirectory
    }
    foreach ($file in $model.files) {
        $target = Join-Path $modelTarget $file.name
        if ($source) { Copy-Item -LiteralPath (Join-Path $source $file.name) -Destination $target }
        else { Invoke-WebRequest -Uri "$($model.baseUrl)$($file.name)" -OutFile $target }
        if ((Get-Item $target).Length -ne $file.size -or (Get-FileHash $target -Algorithm SHA256).Hash -ne $file.sha256) {
            throw "Model checksum mismatch: $($model.language)/$($file.name)"
        }
    }
}
foreach ($name in @('README.md', 'HANDOFF.md', 'MODEL_EVALUATION.md', 'UX_REVIEW.md', 'CRASH_REPORTS.md', 'UPDATES.md')) {
    Copy-Item -LiteralPath (Join-Path $windowsRoot $name) -Destination $payload
}
Copy-Item -LiteralPath (Join-Path $repoRoot 'LICENSE') -Destination $payload
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'BETA.md') -Destination $payload
if ($SkipInstaller) { Write-Output $payload; return }
& $CompilerPath "/DPayloadDir=$payload" "/DArtifactDir=$destination" "/DAppVersion=$version" (Join-Path $PSScriptRoot 'inlaut.iss')
if ($LASTEXITCODE -ne 0) { throw 'Installer compilation failed.' }
$installer = Join-Path $destination "inlaut-$version-windows-x64-setup.exe"
"$((Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash.ToLowerInvariant())  $([IO.Path]::GetFileName($installer))" |
    Set-Content -LiteralPath (Join-Path $destination 'SHA256SUMS.txt') -Encoding utf8
Write-Output $installer
