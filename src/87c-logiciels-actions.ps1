# Logiciels : actions (désinstallation, réinstallation, mise à jour, entrées orphelines) et chargement de l'inventaire enregistré
# Logiciel ouvert pendant sa mise à jour : certains installeurs (Discord, Slack... installeur Squirrel dans le profil)
# échouent au lieu de le fermer (« accès refusé » en déplaçant leur dossier). Bloquent ce dossier : le logiciel lui-même,
# mais aussi tout processus qui a chargé une de ses DLL (superposition Discord injectée dans les jeux, extension de
# l'Explorateur...). Repérés avant la confirmation : exécutable portant le nom du logiciel, exécutable ou DLL chargée
# dans son dossier d'installation (clé de désinstallation : InstallLocation, sinon dossier du désinstalleur).
function Get-SoftInstallDir($App) {
    $dirs = [Collections.Generic.List[string]]::new()
    foreach ($root in 'HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall') {
        $k = Open-RegKey $root; if (-not $k) { continue }
        try {
            foreach ($n in $k.GetSubKeyNames()) {
                $sk = $k.OpenSubKey($n); if (-not $sk) { continue }
                try {
                    if ("$($sk.GetValue('DisplayName'))" -ne "$($App.Name)") { continue }
                    $d = "$($sk.GetValue('InstallLocation'))".Trim().Trim('"')
                    if (-not $d) { $us = "$($sk.GetValue('UninstallString'))"; if ($us -match '^\s*"([^"]+\.exe)"' -or $us -match '^\s*(\S+\.exe)') { $d = Split-Path $Matches[1] } }
                    $d = [Environment]::ExpandEnvironmentVariables($d).TrimEnd('\')
                    # dossiers trop généraux (racine, Program Files, Windows) écartés
                    if ($d.Length -gt 12 -and $d -notmatch '(?i)^[a-z]:\\(program files( \(x86\))?|windows|programdata)?$' -and (Test-Path -LiteralPath $d)) { $dirs.Add($d + '\') }
                } finally { $sk.Close() }
            }
        } finally { $k.Close() }
    }
    @($dirs | Select-Object -Unique)
}
# Programmes qui bloquent le logiciel : recherche complète (processus du même nom + fichiers du dossier ouverts, gestionnaire
# de redémarrage de Windows) faite par la tâche juste avant l'installeur (Find-SoftLocker), jamais par l'interface :
# l'énumération des processus et de leurs fichiers prend plusieurs secondes et figeait la fenêtre (« Ne répond pas »).
# Ici : nom court et dossiers d'installation (registre, quelques ms) transmis à la tâche, et programmes ouverts du même
# nom (liste des processus seule, sans ouvrir chaque processus) pour les nommer dans la confirmation.
function Get-SoftLockInfo($App) {
    @{ Base = ((Get-SoftShortName "$($App.Name)") -replace '[^\p{L}\p{N}]', ''); Dirs = @(Get-SoftInstallDir $App) }
}
function Get-SoftOpenName($Items) {
    $run = @{}
    foreach ($p in [Diagnostics.Process]::GetProcesses()) { try { $run[$p.ProcessName] = 1 } finally { $p.Dispose() } }
    $out = @{}
    foreach ($a in $Items) { $b = (Get-SoftLockInfo $a).Base; if ($b.Length -ge 3 -and $run.ContainsKey($b)) { $out["$($a.Id)"] = "$b.exe" } }
    $out
}
# logiciel installé dans le profil de l'utilisateur (identifiant « ARP\User\... » ou entrée de désinstallation de son
# registre) : winget lancé sous son compte, sans élévation (Invoke-SoftToolAsUser)
function Test-SoftUserScope($App) {
    if ($App.Pfn) { return $false }
    if ("$(Get-SoftLocalId $App)" -match '^ARP\\User\\') { return $true }
    $k = Open-RegKey 'HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall'; if (-not $k) { return $false }
    try {
        foreach ($n in $k.GetSubKeyNames()) {
            $sk = $k.OpenSubKey($n); if (-not $sk) { continue }
            try { if ("$($sk.GetValue('DisplayName'))" -eq "$($App.Name)") { return $true } } finally { $sk.Close() }
        }
    } finally { $k.Close() }
    $false
}
function Get-SoftLocalId($App) { $(if ($App.LocalId) { "$($App.LocalId)" } elseif (-not $App.Match) { "$($App.Id)" } else { '' }) }
# Désinstallation ou réinstallation (désinstallation puis installation de la dernière version) via winget, mêmes suivi,
# historique et rapport que les mises à jour ; logiciel ouvert fermé avant.
function Invoke-SoftRemove($Items, [string]$Mode) {
    $sel = @($Items | Where-Object { $_ -and (Get-SoftLocalId $_) })
    if (-not $sel.Count) { return }
    if ($Sync.Running) { Show-Info 'Une tâche est déjà en cours. Relancer une fois terminée.'; return }
    $re = $Mode -eq 'reinstall'; $one = $sel.Count -eq 1
    $head = $(if ($re) { $(if ($one) { 'Réinstaller {0} ?' -f (Get-SoftShortName $sel[0].Name) } else { "Réinstaller ces $($sel.Count) logiciels ?" }) } else { $(if ($one) { 'Désinstaller {0} ?' -f (Get-SoftShortName $sel[0].Name) } else { "Désinstaller ces $($sel.Count) logiciels ?" }) })
    $lines = @($sel | ForEach-Object { '{0}  ·  {1}  ·  {2}' -f $_.Name, $_.From, $_.SrcLabel })
    $foot = $(if ($re) { 'Chaque logiciel est désinstallé puis réinstallé dans sa dernière version ; si la désinstallation échoue, il n''est pas réinstallé.' } else { 'Désinstallation silencieuse quand l''éditeur la prévoit, sinon le désinstalleur du logiciel s''affiche.' })
    $open = Get-SoftOpenName $sel
    $foot += ' Les programmes qui bloquent le dossier du logiciel sont fermés juste avant (travail non enregistré perdu)' + $(if ($open.Count) { ', dont ' + (@($open.Values | Select-Object -Unique) -join ', ') + '.' } else { '.' })
    if (-not (Confirm-List $head $lines $foot $(if ($re) { 'Réinstaller' } else { 'Désinstaller' }) 'WarnBtn')) { return }
    $Sync.Params = @{ Soft = @($sel | ForEach-Object { @{ Mode = $Mode; Name = "$($_.Name)"; Id = "$($_.Id)"; LocalId = (Get-SoftLocalId $_); Src = "$($_.Src)"; Pfn = "$($_.Pfn)"; From = "$($_.From)"; To = ''; Match = [bool]$_.Match; Unknown = $false; User = (Test-SoftUserScope $_); Lock = (Get-SoftLockInfo $_) } }) }
    [void](Start-Worker @('SoftUpgrade'))
    Update-SoftStatus
}
# entrées orphelines : sauvegardées (.reg, dossier d'état) puis supprimées du registre ; lignes retirées de l'inventaire
function Remove-SoftOrphan($Items) {
    $sel = @($Items | Where-Object { $_.Orphan -and $_.RegKey })
    if (-not $sel.Count) { return }
    $lines = @($sel | ForEach-Object { '{0}  ·  {1}' -f $_.Name, $_.RegKey })
    if (-not (Confirm-List $(if ($sel.Count -eq 1) { 'Retirer l''entrée de {0} ?' -f (Get-SoftShortName $sel[0].Name) } else { "Retirer ces $($sel.Count) entrées ?" }) $lines 'Logiciel déjà absent du poste : seule son entrée de désinstallation est supprimée du registre, après sauvegarde (.reg) dans le dossier d''état de l''application.' 'Retirer' 'WarnBtn')) { return }
    $dir = Join-Path (Get-LogPath 'Etat') 'entrees-retirees'
    try { [void][IO.Directory]::CreateDirectory($dir) } catch { Write-Ignored 'Dossier de sauvegarde des entrées' $_ }
    $done = [Collections.Generic.List[string]]::new()
    foreach ($a in $sel) {
        $file = Join-Path $dir ('{0:yyyyMMdd-HHmmss}_{1}.reg' -f (Get-Date), (("$($a.Name)" -replace '[^\w\-]+', '_').Trim('_')))
        try {
            $out = & "$env:windir\System32\reg.exe" export $a.RegKey $file /y 2>&1
            if ($LASTEXITCODE -ne 0) { throw "sauvegarde impossible : $((@($out) -join ' ').Trim())" }
            $root = $(if ($a.RegKey -like 'HKCU\*') { [Microsoft.Win32.Registry]::CurrentUser } else { [Microsoft.Win32.Registry]::LocalMachine })
            $root.DeleteSubKeyTree($a.RegKey.Substring(5), $false)
            $done.Add("$($a.Id)")
            Write-UiLog ('Entrée orpheline retirée : {0} ({1}), sauvegarde {2}' -f $a.Name, $a.RegKey, $file) 'OK'
            Add-SessionEvent 'Logiciels' $a.Name 'entrée orpheline retirée' 'ok'
        } catch { Write-UiLog ('Entrée de {0} non retirée : {1}' -f $a.Name, $_.Exception.Message) 'WARN' }
    }
    if ($done.Count -and $Sync.WgResult) {
        $Sync.WgResult.Apps = @($Sync.WgResult.Apps | Where-Object { $done -notcontains "$($_.Id)" })
        try { $o = @{} + $Sync.WgResult; $o.Stamp = ([DateTime]$Sync.WgResult.Stamp).ToString('o'); ConvertTo-Json -InputObject $o -Depth 4 | Set-Content -LiteralPath $SoftFile -Encoding UTF8 } catch { Write-Ignored 'Enregistrement de l''inventaire des logiciels' $_ }
        $SoftUI.CacheStamp = $null; Update-SoftView
    }
}
function Invoke-SoftUpgrade($Items) {
    $sel = @($Items | Where-Object { $_ -and $_.To -and $_.Src })
    if (-not $sel.Count) { return }
    if ($Sync.Running) { Show-Info 'Une tâche est déjà en cours. Relancer la mise à jour une fois terminée.'; return }
    $one = $sel.Count -eq 1
    $head = $(if ($one) { 'Installer la mise à jour de {0} ?' -f (Get-SoftShortName $sel[0].Name) } else { "Installer ces $($sel.Count) mises à jour ?" })
    $lines = @($sel | ForEach-Object { '{0}  ·  {1} > {2}  ·  {3}' -f $_.Name, $_.From, $_.To, $_.SrcLabel })
    $foot = 'Installation silencieuse' + $(if ($one) { '' } else { ', un logiciel après l''autre' }) + '. Les logiciels ouverts peuvent être fermés par leur installeur.'
    if (@($sel | Where-Object { $_.Match }).Count) { $foot += ' Logiciel rattaché par son nom : la nouvelle version est installée par-dessus l''existante.' }
    $open = Get-SoftOpenName $sel
    if ($open.Count) { $foot += ' Programmes ouverts qui bloquent la mise à jour, fermés juste avant (travail non enregistré perdu) : ' + (@($open.Values | Select-Object -Unique) -join ', ') + '.' }
    if (-not (Confirm-List $head $lines $foot 'Installer' 'ActionBtn')) { return }
    $Sync.Params = @{ Soft = @($sel | ForEach-Object { @{ Name = "$($_.Name)"; Id = "$($_.Id)"; Src = "$($_.Src)"; Pfn = "$($_.Pfn)"; From = "$($_.From)"; To = "$($_.To)"; Match = [bool]$_.Match; Unknown = [bool]$_.Unknown; User = (Test-SoftUserScope $_); Lock = (Get-SoftLockInfo $_) } }) }
    [void](Start-Worker @('SoftUpgrade'))
    Update-SoftStatus
}
# carte Logiciels de Maintenance retirée (mises à jour dans l'onglet Applications) : texte de résumé gardé hors écran,
# il porte l'état affiché sur le bouton « Mettre à jour (N) » et le journal des inventaires (Update-SoftCard)
$SoftUI.CardText = [Windows.Controls.TextBlock]::new()
# barre de progression du pied de page cliquable pendant une tâche : fenêtre Logiciels pendant leur mise à jour,
# onglet Journal (avancement détaillé) pour les autres tâches
$Ui.FooterStatus.Add_MouseLeftButtonUp({
    if (-not $Sync.Running) { return }
    if (Test-SoftUpgrading) { try { Show-SoftWindow } catch { Write-UiLog "Fenêtre Logiciels : $($_.Exception.Message)" 'ERROR' } }
    else { Show-Page 'Log' }
})
# dernier inventaire enregistré (logiciels.json) chargé dès le démarrage : Mes applications, Mettre à jour et le catalogue
# Installer l'affichent tout de suite, la relecture se fait ensuite en arrière-plan. Le chargement était fait par la carte
# Logiciels de Maintenance (New-SoftCard), retirée : la liste était relue entièrement à chaque ouverture de l'application.
try {
    if (-not $Sync.WgResult -and (Test-Path -LiteralPath $SoftFile)) {
        $Sync.WgResult = Get-Content -LiteralPath $SoftFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $SoftUI.Shown = $Sync.WgResult.Stamp
    }
} catch { Write-Ignored 'Lecture du dernier inventaire des logiciels' $_ }
$SoftUI.Fresh = $true
