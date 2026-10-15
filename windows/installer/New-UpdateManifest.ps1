[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Installer,
    [Parameter(Mandatory)][string]$Application,
    [Parameter(Mandatory)][string]$UpdateHost,
    [Parameter(Mandatory)][string]$Version,
    [Parameter(Mandatory)][string]$ReleaseTag,
    [Parameter(Mandatory)][string]$OutputFile
)
$ErrorActionPreference = 'Stop'
if ($Version -notmatch '^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-(?:beta|rc)\.(0|[1-9]\d*))?$') { throw 'Invalid release version' }
if ($ReleaseTag -notmatch '^[A-Za-z0-9._-]+$') { throw 'Invalid release tag' }
$signatures = @($Application, $UpdateHost, $Installer) | ForEach-Object {
    $signature = Get-AuthenticodeSignature -LiteralPath $_
    if ($signature.Status -ne 'Valid') { throw "Not validly signed: $_" }
    $signature.SignerCertificate.GetCertHashString([Security.Cryptography.HashAlgorithmName]::SHA256)
}
if (($signatures | Select-Object -Unique).Count -ne 1) { throw 'Application, helper and installer must use the same certificate' }
$file = Get-Item -LiteralPath $Installer
if ($file.Name -cne "inlaut-$Version-windows-x64-setup.exe" -or $file.Length -le 0 -or $file.Length -gt 600MB) { throw 'Invalid installer name/size' }
$info = [Diagnostics.FileVersionInfo]::GetVersionInfo($file.FullName)
# Inno Setup pads PE string resources with ASCII spaces.
if ($info.ProductVersion.TrimEnd([char]' ') -cne $Version -or $info.ProductName.TrimEnd([char]' ') -cnotin @('inlaut','inlaut Beta')) { throw 'Installer version/product mismatch' }
$appInfo = [Diagnostics.FileVersionInfo]::GetVersionInfo((Get-Item -LiteralPath $Application).FullName)
if ($appInfo.ProductVersion.Split('+')[0] -cne $Version) { throw 'Application version mismatch' }
$manifest = [ordered]@{ schema=1; version=$Version; url="https://github.com/tobymarks/inlaut/releases/download/$ReleaseTag/$($file.Name)"; sha256=(Get-FileHash -LiteralPath $Installer -Algorithm SHA256).Hash.ToLowerInvariant(); size=$file.Length }
$target = [IO.Path]::GetFullPath($OutputFile)
[IO.File]::WriteAllText($target, ($manifest | ConvertTo-Json) + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
Write-Output $target
