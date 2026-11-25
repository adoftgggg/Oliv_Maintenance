# Instance unique par session Windows. Instance en cours décrite dans ProgramData\Oliv_Maintenance\instance.txt
# (« version|PID »). Nouvelle ouverture :
# - même version : fenêtre déjà ouverte ramenée au premier plan (éventuellement depuis la zone de notification), arrêt ;
# - autre version : question « fermer la version X et ouvrir celle-ci ? » ; oui = fermeture demandée à l'ancienne
#   (événement Oliv_Maintenance_Quitter, avertissement habituel si une tâche tourne), puis démarrage ; version antérieure
#   à ce mécanisme (pas de fichier d'instance) : processus arrêté.
# Attente de 4 s au plus avant tout : relance après réinitialisation, ancienne instance encore en cours de fermeture.
$AppMutex = [Threading.Mutex]::new($false, 'Local\Oliv_Maintenance')
$AppShowEvent = [Threading.EventWaitHandle]::new($false, [Threading.EventResetMode]::AutoReset, 'Local\Oliv_Maintenance_Afficher')
$AppQuitEvent = [Threading.EventWaitHandle]::new($false, [Threading.EventResetMode]::AutoReset, 'Local\Oliv_Maintenance_Quitter')
$AppInstFile = Join-Path $env:ProgramData 'Oliv_Maintenance\instance.txt'
function Get-MutexOwned([int]$Ms) { try { $AppMutex.WaitOne($Ms) } catch { ($_.Exception -is [Threading.AbandonedMutexException]) -or ($_.Exception.InnerException -is [Threading.AbandonedMutexException]) } }
$owned = Get-MutexOwned 4000
if (-not $owned) {
    $other = @(); try { $other = @([IO.File]::ReadAllText($AppInstFile).Trim() -split '\|') } catch { $other = @() }
    $ov = "$($other[0])"
    if ($ov -eq $AppVersion) { [void]$AppShowEvent.Set(); [Environment]::Exit(0) }
    $sh = New-Object -ComObject WScript.Shell
    $q = 'Oliv_Maintenance {0} est déjà ouvert.{1}{1}Le fermer et ouvrir la version {2} ?{1}{1}Non : la fenêtre déjà ouverte est affichée.' -f $(if ($ov) { $ov } else { '(version antérieure)' }), [Environment]::NewLine, $AppVersion
    if ($sh.Popup($q, 0, 'Oliv_Maintenance', 4 + 32) -ne 6) { [void]$AppShowEvent.Set(); [Environment]::Exit(0) }
    [void]$AppQuitEvent.Set()
    $owned = Get-MutexOwned 30000
    if (-not $owned -and -not $ov) {
        # version antérieure sans fermeture à distance : arrêt de ses processus PowerShell, reconnus à la variable propre au
        # lanceur (avant : tout powershell dont la ligne de commande contenait « Oliv_Maintenance », scripts du dossier compris)
        try {
            Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction Stop | Where-Object { $_.ProcessId -ne $PID -and "$($_.CommandLine)" -match '_OlivMScriptPath|_OLIVM_SELF' } |
                ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
        } catch { $null = $_ }
        $owned = Get-MutexOwned 10000
    }
    if (-not $owned) { [void]$sh.Popup('L''autre fenêtre d''Oliv_Maintenance ne s''est pas fermée (tâche en cours ?). Réessayer une fois fermée.', 0, 'Oliv_Maintenance', 48); [Environment]::Exit(0) }
}
try { [IO.File]::WriteAllText($AppInstFile, "$AppVersion|$PID") } catch { $null = $_ }
$Build = [int](Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').CurrentBuild

function Get-InteractiveUserSid {
    try {
        $sess = (Get-Process -Id $PID).SessionId
        $ex = Get-Process -Name explorer -IncludeUserName -ErrorAction Stop | Where-Object { $_.SessionId -eq $sess -and $_.UserName } | Select-Object -First 1
        if ($ex) { return [Security.Principal.NTAccount]::new($ex.UserName).Translate([Security.Principal.SecurityIdentifier]).Value }
    } catch { Write-Ignored 'Utilisateur de la session (explorer.exe)' $_ }
    ([Security.Principal.WindowsIdentity]::GetCurrent()).User.Value
}
$UserSid     = Get-InteractiveUserSid
$UserSession = (Get-Process -Id $PID).SessionId
$UserName    = try { [Security.Principal.SecurityIdentifier]::new($UserSid).Translate([Security.Principal.NTAccount]).Value } catch { $UserSid }
$HkuSidOk    = $false
try { $k = [Microsoft.Win32.Registry]::Users.OpenSubKey($UserSid); if ($k) { $HkuSidOk = $true; $k.Close() } } catch {}
if (-not $HkuSidOk) { $UserName = "$env:USERDOMAIN\$env:USERNAME (repli HKCU)" }
$UserProfilePath = [Environment]::ExpandEnvironmentVariables("$((Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$UserSid" -ErrorAction SilentlyContinue).ProfileImagePath)")
if (-not $UserProfilePath) { $UserProfilePath = $env:USERPROFILE }
$BootTime = try { (Get-Process -Name wininit -ErrorAction Stop | Select-Object -First 1).StartTime } catch { [DateTime]::MinValue }

