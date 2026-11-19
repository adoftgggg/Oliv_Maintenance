<#
.SYNOPSIS
    Crée le certificat interne de signature de code « Oliv » (une seule fois, sur le poste de construction).

.DESCRIPTION
    1. Certificat auto-signé RSA 3072 / SHA-256, usage signature de code, valable 5 ans, dans le magasin personnel de
       l'utilisateur (Cert:\CurrentUser\My), clé privée exportable pour la sauvegarde.
    2. Export de la partie publique (Oliv_Maintenance_SignatureCode.cer) : à déployer sur les postes clients
       (tools\Install-CertificatSignature.ps1 en administrateur, ou GPO).
    3. Sauvegarde complète avec clé privée (Oliv_Maintenance_SignatureCode.pfx, mot de passe demandé) : à ranger dans le coffre de
       mots de passe, puis à supprimer du disque. Quiconque détient la clé privée peut signer du code accepté par tous les
       postes où le certificat est déployé.
    4. Confiance sur ce poste (racine et éditeurs approuvés de l'utilisateur) : build.ps1 peut contrôler la signature.
    Windows PowerShell 5.1, Windows 10 / 11, sans droits administrateur, sans module à installer.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\New-CertificatSignature.ps1
#>
[CmdletBinding()]
param([string]$OutDir = (Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference = 'Stop'

$exist = @(Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert | Where-Object { $_.Subject -like '*Oliv*' -and $_.NotAfter -gt (Get-Date) })
if ($exist.Count) {
    $exist | Format-Table Thumbprint, Subject, NotAfter -AutoSize
    throw 'Un certificat de signature de code Oliv valide existe déjà dans ce magasin : rien n''est créé.'
}
$cert = New-SelfSignedCertificate -Type CodeSigningCert -Subject 'CN=Oliv, O=Oliv, C=FR' -FriendlyName 'Oliv - signature de code' `
    -KeyAlgorithm RSA -KeyLength 3072 -HashAlgorithm SHA256 -KeyExportPolicy Exportable -NotAfter (Get-Date).AddYears(5) -CertStoreLocation Cert:\CurrentUser\My

$cer = Join-Path $OutDir 'Oliv_Maintenance_SignatureCode.cer'
$pfx = Join-Path $OutDir 'Oliv_Maintenance_SignatureCode.pfx'
[void](Export-Certificate -Cert $cert -FilePath $cer -Type CERT)
$pw = Read-Host 'Mot de passe de la sauvegarde .pfx (clé privée)' -AsSecureString
[void](Export-PfxCertificate -Cert $cert -FilePath $pfx -Password $pw)

# confiance sur le poste de construction (utilisateur courant) : contrôle Status Valid dans build.ps1
# (Windows demande de confirmer l'ajout de la racine : répondre Oui)
foreach ($st in 'Root', 'TrustedPublisher') { [void](Import-Certificate -FilePath $cer -CertStoreLocation "Cert:\CurrentUser\$st") }

Write-Host ''
Write-Host "Certificat créé : $($cert.Thumbprint)  (expire le $('{0:dd/MM/yyyy}' -f $cert.NotAfter))" -ForegroundColor Green
Write-Host "Partie publique à déployer : $cer"
Write-Host "Sauvegarde avec clé privée : $pfx  -> à ranger dans le coffre puis à supprimer du disque" -ForegroundColor Yellow
Write-Host 'Signature : .\build.ps1 (automatique) ou .\build.ps1 -SignOnly'
