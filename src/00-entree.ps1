<# :
@echo off
set "_OLIVM_SELF=%~f0"
set "_OLIVM_HIDDEN=1"
start "" /min "%windir%\System32\conhost.exe" "%windir%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -Command "$global:_OlivMScriptPath=$env:_OLIVM_SELF; Invoke-Expression ([IO.File]::ReadAllText($env:_OLIVM_SELF, [Text.Encoding]::UTF8))"
exit /b
#>

$AppVersion = '0.99.31'
$BuildDate  = '2026-11-16 10:45'

$SelfPath = if ($PSCommandPath) { $PSCommandPath } elseif ($global:_OlivMScriptPath) { $global:_OlivMScriptPath } else { $null }

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$need64  = [Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess
$isCore  = $PSVersionTable.PSEdition -eq 'Core'
$notSta  = [Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA'

if (-not $isAdmin -or $need64 -or $isCore -or $notSta) {
    $psExe = if ($need64) { "$env:windir\sysnative\WindowsPowerShell\v1.0\powershell.exe" } else { "$env:windir\System32\WindowsPowerShell\v1.0\powershell.exe" }
    if (-not $SelfPath) { Write-Warning 'Lancer Oliv_Maintenance par double-clic sur Oliv_Maintenance.cmd.'; return }
    $argLine = "-NoProfile -STA -ExecutionPolicy Bypass -Command `"`$env:_OLIVM_HIDDEN='1'; `$global:_OlivMScriptPath='$($SelfPath -replace "'", "''")'; Invoke-Expression ([IO.File]::ReadAllText('$($SelfPath -replace "'", "''")', [Text.Encoding]::UTF8))`""
    try {
        $con = "$env:windir\System32\conhost.exe"
        if (Test-Path -LiteralPath $con) { $exe = $con; $al = "`"$psExe`" $argLine" } else { $exe = $psExe; $al = $argLine }
        if ($isAdmin) { Start-Process -FilePath $exe -ArgumentList $al -WindowStyle Hidden }
        else          { Start-Process -FilePath $exe -ArgumentList $al -Verb RunAs -WindowStyle Hidden }
        Write-Host 'Relance en Windows PowerShell 5.1 administrateur...' -ForegroundColor Cyan
    } catch {
        Write-Warning "Elevation refusee ou impossible : $($_.Exception.Message)"
    }
    return
}
if ('é'.Length -ne 1) {
    if ($SelfPath) { $global:_OlivMScriptPath = $SelfPath; Invoke-Expression ([IO.File]::ReadAllText($SelfPath, [Text.Encoding]::UTF8)) }
    return
}

trap {
    $err = $_
    $msg = "ERREUR FATALE {0:yyyy-MM-dd HH:mm:ss}`r`nLigne {1} : {2}`r`n{3}`r`n" -f (Get-Date), $err.InvocationInfo.ScriptLineNumber, "$($err.InvocationInfo.Line)".Trim(), $err.Exception.ToString()
    try {
        $crashDir = Join-Path $env:ProgramData 'Oliv_Maintenance\Maintenance\Erreurs'
        New-Item -ItemType Directory -Path $crashDir -Force | Out-Null
        Set-Content -Path (Join-Path $crashDir 'crash.log') -Value ("Oliv_Maintenance $AppVersion`r`n" + $msg) -Encoding UTF8
        Add-Content -Path (Join-Path $crashDir 'crash-historique.log') -Value ("Oliv_Maintenance $AppVersion`r`n" + $msg) -Encoding UTF8
    } catch {}
    if ($env:_OLIVM_HIDDEN) {
        try { [void](New-Object -ComObject WScript.Shell).Popup(($msg.Substring(0, [math]::Min(1500, $msg.Length)) + "`r`n`r`nDétail : $env:ProgramData\Oliv_Maintenance\Maintenance\Erreurs\crash.log"), 0, 'Oliv_Maintenance - erreur fatale', 16) } catch {}
    } else {
        Write-Host $msg -ForegroundColor Red
        Write-Host "Détail enregistré dans $env:ProgramData\Oliv_Maintenance\Maintenance\Erreurs\crash.log" -ForegroundColor Yellow
        Read-Host 'Appuyer sur Entrée pour fermer'
    }
    # arrêt complet : sans cela, les tâches de fond (collecteur de l'Accueil en boucle, recherches) gardaient le processus en vie
    try { if (Get-Command Exit-App -ErrorAction SilentlyContinue) { Exit-App 1 } } catch {}
    [Environment]::Exit(1)
}


# ---------- Droits du dossier de l'application (C:\ProgramData\Oliv_Maintenance)
# Hérités de ProgramData, ils laissent tout utilisateur standard créer des fichiers dans les sous-dossiers et en devenir
# propriétaire : il pouvait modifier le script extrait par le lanceur Oliv_Maintenance.exe avant son exécution (ou, avant
# la 0.104, déposer une DLL dans _etat\cache). Le code natif est désormais embarqué dans le script (01-natif.ps1).
# Mise en conformité (une seule fois par poste, contrôle de quelques millisecondes ensuite) : propriétaire Administrateurs
# partout (takeown /A), héritage coupé à la racine, Administrateurs et SYSTEM en contrôle total, Utilisateurs en lecture,
# sous-dossiers remis en héritage seul (icacls /reset), ancien cache de DLL supprimé. Même règle dans le lanceur.
$SidAdmins = 'S-1-5-32-544'; $SidSystem = 'S-1-5-18'; $SidUsers = 'S-1-5-32-545'
# Rules : { Sid ; Allow ; Rights (masque FileSystemRights) }. Sûr = héritage coupé, propriétaire Administrateurs ou SYSTEM,
# aucun autre compte autorisé en écriture (données, ajout, attributs, suppression, droits, propriétaire, GENERIC_WRITE / ALL).
function Test-AclSafe([bool]$Protected, [string]$Owner, [object[]]$Rules) {
    if (-not $Protected -or $Owner -notin $SidAdmins, $SidSystem) { return $false }
    foreach ($r in $Rules) {
        if ($r.Allow -and ($r.Sid -notin $SidAdmins, $SidSystem) -and ([int64]$r.Rights -band 0x500D0156)) { return $false }
    }
    $true
}
function Get-DirAclState([string]$Path) {
    $acl = [IO.Directory]::GetAccessControl($Path)
    $rules = @(foreach ($r in $acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier])) {
        @{ Sid = $r.IdentityReference.Value; Allow = ($r.AccessControlType -eq 'Allow'); Rights = [int64][int]$r.FileSystemRights }
    })
    Test-AclSafe $acl.AreAccessRulesProtected "$($acl.GetOwner([Security.Principal.SecurityIdentifier]))" $rules
}
function Protect-AppDir([string]$Path) {
    [void][IO.Directory]::CreateDirectory($Path)
    if ($(try { Get-DirAclState $Path } catch { $false })) { return 'ok' }
    $sys32 = [Environment]::GetFolderPath('System')
    $null | & (Join-Path $sys32 'takeown.exe') /F $Path /A /R 2>&1 | Out-Null
    $sec = [Security.AccessControl.DirectorySecurity]::new()
    $sec.SetOwner([Security.Principal.SecurityIdentifier]::new($SidAdmins))
    $sec.SetAccessRuleProtection($true, $false)
    foreach ($p in @(@($SidAdmins, 'FullControl'), @($SidSystem, 'FullControl'), @($SidUsers, 'ReadAndExecute'))) {
        $sec.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($p[0]), [Security.AccessControl.FileSystemRights]$p[1], [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit', [Security.AccessControl.PropagationFlags]'None', [Security.AccessControl.AccessControlType]'Allow'))
    }
    [IO.Directory]::SetAccessControl($Path, $sec)
    if (@(Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue).Count) {
        $null | & (Join-Path $sys32 'icacls.exe') (Join-Path $Path '*') /reset /T /C /Q 2>&1 | Out-Null
    }
    $cache = Join-Path $Path 'Maintenance\_etat\cache'
    if (Test-Path -LiteralPath $cache) { Remove-Item -LiteralPath $cache -Recurse -Force -ErrorAction SilentlyContinue }
    if (Get-DirAclState $Path) { 'fixed' } else { 'unsafe' }
}
$AppDirState = try { Protect-AppDir (Join-Path $env:ProgramData 'Oliv_Maintenance') } catch { "unsafe : $($_.Exception.Message)" }
$AppDirSafe  = $AppDirState -in 'ok', 'fixed'
