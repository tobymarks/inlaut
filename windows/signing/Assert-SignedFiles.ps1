[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Directory,
    [Parameter(Mandatory)][string[]]$Names,
    [Parameter(Mandatory)][string]$Version,
    [Parameter(Mandatory)][string]$CertificateSha256
)
$ErrorActionPreference = 'Stop'
if ($CertificateSha256 -notmatch '^[A-Fa-f0-9]{64}$') { throw 'Configure the approved certificate SHA-256 fingerprint.' }
foreach ($name in $Names) {
    $path = Join-Path $Directory $name
    $signature = Get-AuthenticodeSignature -LiteralPath $path
    if ($signature.Status -ne 'Valid') { throw "Invalid Authenticode signature: $name" }
    if (-not $signature.TimeStamperCertificate) { throw "Missing timestamp: $name" }
    $fingerprint = $signature.SignerCertificate.GetCertHashString([Security.Cryptography.HashAlgorithmName]::SHA256)
    if ($fingerprint -ne $CertificateSha256) { throw "Unexpected signing certificate: $name" }
    $info = [Diagnostics.FileVersionInfo]::GetVersionInfo((Get-Item -LiteralPath $path).FullName)
    if ($info.ProductName -cne 'inlaut' -or $info.ProductVersion -cne $Version) { throw "Product/version mismatch: $name" }
}
