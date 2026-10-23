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
# Keep redistribution notices with the installed binaries. NuGet package roots and
# runtime versions come from this publish, not from whichever SDK is newest locally.
$licenses = Join-Path $payload 'licenses'
Copy-Item -LiteralPath (Join-Path $windowsRoot 'licenses') -Destination $licenses -Recurse
$noticeSources = Get-Content -LiteralPath (Join-Path $licenses 'sources.json') -Raw | ConvertFrom-Json
foreach ($notice in $noticeSources) {
    if ((Get-FileHash -LiteralPath (Join-Path $licenses $notice.file) -Algorithm SHA256).Hash -ne $notice.sha256) {
        throw "Bundled upstream notice checksum mismatch: $($notice.file)"
    }
}
$assets = Get-Content -LiteralPath (Join-Path (Split-Path $project -Parent) 'obj/project.assets.json') -Raw | ConvertFrom-Json -AsHashtable
$packageRoots = @($assets.packageFolders.Keys)
$packagedNotices = [Collections.Generic.List[object]]::new()
function Copy-PackageNotices([string]$Id, [string]$PackageVersion, [bool]$RequireThirdParty = $false) {
    $package = $null
    foreach ($root in $packageRoots) {
        $candidate = Join-Path $root "$($Id.ToLowerInvariant())/$PackageVersion"
        if (Test-Path -LiteralPath $candidate -PathType Container) { $package = $candidate; break }
    }
    if (-not $package) { throw "Restored package not found for notices: $Id/$PackageVersion" }
    $files = @(Get-ChildItem -LiteralPath $package -File | Where-Object { $_.Name -match '^(LICENSE|LICENCE|COPYING|.*NOTICES?)(\..*)?$' })
    if (-not ($files | Where-Object { $_.Name -match '^(LICENSE|LICENCE|COPYING)(\..*)?$' })) {
        throw "Package license is missing: $Id/$PackageVersion"
    }
    if ($RequireThirdParty -and -not ($files | Where-Object { $_.Name -match 'NOTICE' })) {
        throw "Package third-party notices are missing: $Id/$PackageVersion"
    }
    $target = Join-Path $licenses "$Id/$PackageVersion"
    New-Item -ItemType Directory -Path $target -Force | Out-Null
    foreach ($file in $files) { Copy-Item -LiteralPath $file.FullName -Destination $target }
    $packagedNotices.Add([ordered]@{ package = $Id; version = $PackageVersion; source = "https://www.nuget.org/packages/$Id/$PackageVersion" })
}
# NAudio 3 declares MIT only in its nuspec and ships no license file; the pinned
# upstream original is windows/licenses/naudio/LICENSE. Record every NAudio package.
$naudio = @($assets.libraries.Keys | Where-Object { $_ -like 'NAudio*/*' })
if (-not ($naudio -contains 'NAudio/3.3.0') -or @($naudio | Where-Object { $_ -notlike '*/3.3.0' }).Count -gt 0) {
    throw 'Refresh windows/licenses/naudio for the new NAudio version.'
}
foreach ($key in $naudio) {
    $id, $packageVersion = $key.Split('/')
    $packagedNotices.Add([ordered]@{ package = $id; version = $packageVersion; source = "https://www.nuget.org/packages/$id/$packageVersion"; license = 'naudio/LICENSE' })
}
# NAudio.Core 3 depends on System.Numerics.Tensors, which ships its own notices.
foreach ($key in @($assets.libraries.Keys | Where-Object { $_ -like 'System.Numerics.Tensors/*' })) {
    Copy-PackageNotices 'System.Numerics.Tensors' ($key.Split('/')[1]) $true
}
# .NET 10 prunes these NAudio dependencies because the shared framework contains them;
# their notices come with the runtime packages below. A package version would need its own.
foreach ($id in @('Microsoft.Win32.Registry', 'System.Security.AccessControl', 'System.Security.Principal.Windows')) {
    if (@($assets.libraries.Keys | Where-Object { $_ -like "$id/*" }).Count -gt 0) {
        throw "$id is restored as a package again; include its license and notices."
    }
}
# These upstream snapshots supplement the licenses absent from the sherpa NuGet
# packages. A dependency upgrade must refresh the matching source notices too.
if (-not $assets.libraries.ContainsKey('org.k2fsa.sherpa.onnx/1.13.8')) {
    throw 'Refresh windows/licenses for the new sherpa-onnx/ONNX Runtime version.'
}
$runtime = Get-Content -LiteralPath (Join-Path $payload 'Inlaut.runtimeconfig.json') -Raw | ConvertFrom-Json
$frameworks = @($runtime.runtimeOptions.includedFrameworks)
foreach ($name in @('Microsoft.NETCore.App', 'Microsoft.WindowsDesktop.App')) {
    $framework = @($frameworks | Where-Object name -eq $name)
    if ($framework.Count -ne 1) { throw "Published runtime version missing: $name" }
    if ($name -eq 'Microsoft.WindowsDesktop.App' -and $framework[0].version -ne '10.0.13') {
        throw 'Refresh the pinned WPF/WinForms notices in windows/licenses for the new WindowsDesktop runtime.'
    }
    Copy-PackageNotices "$name.Runtime.win-x64" $framework[0].version ($name -eq 'Microsoft.NETCore.App')
}
$packagedNotices | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $licenses 'nuget-packages.json') -Encoding utf8
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
