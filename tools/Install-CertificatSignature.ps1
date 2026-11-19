<#
.SYNOPSIS
    Installe sur un poste client la confiance dans le certificat de signature de code « Oliv ».

.DESCRIPTION
    Ajoute Oliv_Maintenance_SignatureCode.cer (à côté de ce script, ou -CerPath) aux magasins de l'ordinateur « Autorités de
    certification racines de confiance » (Root) et « Éditeurs approuvés » (TrustedPublisher). Ensuite, l'UAC de
    Oliv_Maintenance.exe affiche l'éditeur vérifié « Oliv ». Sans effet si déjà installé.
    Windows PowerShell 5.1, Windows 10 / 11, administrateur ou SYSTEM, sans module à installer.
    Code de sortie : 0 installé ou déjà présent, 1 échec.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\Install-CertificatSignature.ps1
#>
[CmdletBinding()]
param([string]$CerPath = (Join-Path $PSScriptRoot 'Oliv_Maintenance_SignatureCode.cer'))
$ErrorActionPreference = 'Stop'
try {
    $c = [Security.Cryptography.X509Certificates.X509Certificate2]::new($CerPath)
    if ($c.Subject -notlike '*Oliv*') { throw "Certificat inattendu : $($c.Subject)" }
    foreach ($st in 'Root', 'TrustedPublisher') {
        if (Test-Path -LiteralPath "Cert:\LocalMachine\$st\$($c.Thumbprint)") { Write-Output "$st : déjà présent ($($c.Thumbprint))"; continue }
        [void](Import-Certificate -FilePath $CerPath -CertStoreLocation "Cert:\LocalMachine\$st")
        Write-Output "$st : installé ($($c.Thumbprint))"
    }
    exit 0
} catch { Write-Output "Échec : $($_.Exception.Message)"; exit 1 }
