$RepairFile = Join-Path (Get-LogPath 'Etat') 'reparation.json'
function Update-RepairButton {
    $n = @($RepDism, $RepSfc, $RepChk | Where-Object { $_.IsChecked }).Count
    $Ui.RepairScanBtn.IsEnabled = ($n -gt 0) -and -not $Sync.Running
    $Ui.RepairFixBtn.IsEnabled  = ($n -gt 0) -and -not $Sync.Running
    $t = $null; $sfx = ''
    if (Test-Path -LiteralPath $RepairFile) {
        try {
            $j = Get-Content -LiteralPath $RepairFile -Raw -Encoding UTF8 | ConvertFrom-Json
            $t = [DateTime]::Parse("$($j.Time)", [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
            $st = "$($j.Status)".ToLower()
            if ($st -and $st -notin 'terminé', 'interrompu', 'erreur') { $st = 'interrompu' }
            $sfx = '{0} : {1}{2}' -f "$($j.Mode)".ToLower(), $j.Tools, $(if ($st -and $st -ne 'terminé') { " - $st" } else { '' })
            $Ui.RepairLast.ToolTip = 'Dernière exécution : {0:dd/MM/yyyy HH:mm:ss} - {1} : {2} - {3}' -f $t, $j.Mode, $j.Tools, $j.Status
        } catch { Write-Ignored 'Lecture de la dernière réparation' $_ }
    }
    $Ui.RepairLast.Text = Format-LastStamp 'dernière exécution' $t $sfx
    $Ui.RepairStatus.Text = $(if ($n) { "$n $(Get-Plural $n 'outil sélectionné' 'outils sélectionnés')" } else { 'Sélectionner au moins un outil' })
}
$RepairAfter = { Update-RepairButton }
# ordre affiché = ordre d'exécution : DISM répare d'abord le magasin de composants, puis SFC s'en sert pour réparer
# les fichiers système (ordre recommandé par Microsoft, KB929833), CHKDSK programmé en dernier
$RepDism = New-HoverCheck $Ui.RepairList 'DISM (maintenance de l''image Windows)' 'Analyser : /ScanHealth. Réparer : /RestoreHealth (source Windows Update / WSUS). Exécuté en premier.' $RepairAfter
$RepSfc  = New-HoverCheck $Ui.RepairList 'SFC (vérificateur des fichiers système)' 'Analyser : /verifyonly. Réparer : /scannow, après DISM (réparation à partir de l''image Windows remise en état).' $RepairAfter
$RepChk  = New-HoverCheck $Ui.RepairList 'CHKDSK (vérification du disque système)' 'Analyser : état du volume sans analyse disque (bit dirty, événements NTFS 55 / 98, dernier résultat CHKDSK). Réparer : CHKDSK /F programmé au prochain démarrage.' $RepairAfter
Update-RepairButton

$LastRunFile = Join-Path (Get-LogPath 'Etat') 'dernieres-actions.json'
$LastRunIds  = [ordered]@{ Optimize = 'OptimizeStatus'; WuReset = 'WuResetStatus'; NetReset = 'NetResetStatus'; SpoolReset = 'SpoolResetStatus'; TimeSync = 'TimeSyncStatus'; StoreReset = 'StoreResetStatus'; GpuReset = 'GpuResetStatus'; NetCheck = 'NetCheckStatus'; GpForce = 'GpForceStatus' }
function Get-LastRun {
    $h = @{}
    if (Test-Path -LiteralPath $LastRunFile) {
        try {
            $j = Get-Content -LiteralPath $LastRunFile -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($p in $j.PSObject.Properties) { $h[$p.Name] = $p.Value }
        } catch {
            Write-Ignored 'Lecture des derniers passages' $_
        }
    }
    $h
}
function Save-LastRun([string]$Id, [string]$Status) {
    $h = Get-LastRun
    $h[$Id] = [pscustomobject]@{ Time = [DateTime]::Now.ToString('o'); Status = $Status }
    try {
        ConvertTo-Json -InputObject ([pscustomobject]$h) | Set-Content -LiteralPath $LastRunFile -Encoding UTF8
    } catch {
        Write-Ignored 'Enregistrement des derniers passages' $_
    }
}
$LastRunTips = @{
    Optimize   = 'Optimize-Volume -DriveLetter <système> (ReTrim sur SSD, Analyze + Defrag sur HDD).'
    WuReset    = "Stop bits, wuauserv, cryptsvc`nDel %ProgramData%\Microsoft\Network\Downloader\qmgr*.dat`nRen SoftwareDistribution\DataStore, SoftwareDistribution\Download, System32\catroot2 -> *.bak_<date>`nStart cryptsvc, bits, wuauserv"
    NetReset   = "ipconfig /flushdns`nnetsh winsock reset (redémarrage requis)"
    SpoolReset = "Stop Spooler`nDel <DefaultSpoolDirectory>\* (défaut System32\spool\PRINTERS)`nStart Spooler"
    TimeSync   = "Start W32Time`nDomaine : w32tm /resync /rediscover (contrôleur de domaine)`nHors domaine, sans source réseau : w32tm /config /manualpeerlist:time.windows.com,0x9 /syncfromflags:manual /update`nw32tm /resync /rediscover`nw32tm /stripchart /samples:1 (écart restant)"
    NetCheck   = "Get-NetIPConfiguration (carte, IP, passerelle, DNS)`nTest-Connection passerelle`nResolve-DnsName www.microsoft.com par serveur DNS`n_ldap._tcp.dc._msdcs.<domaine> (SRV) + LDAP 389`nTCP www.microsoft.com:443`nhttp://www.msftconnecttest.com/connecttest.txt`nnetsh winhttp show proxy"
    GpForce    = 'gpupdate /force /wait:600 (réponse « N » aux demandes de déconnexion / redémarrage)'
    StoreReset = "Stop WinStore.App (session ciblée)`nDel <profil ciblé>\AppData\Local\Packages\Microsoft.WindowsStore_8wekyb3d8bbwe\LocalCache\*"
    GpuReset   = "Get-PnpDevice -Class Display -PresentOnly (PCI\*)`npnputil /restart-device <InstanceId> (Windows 10 2004+)"
}
function Update-LastRun {
    $h = Get-LastRun
    foreach ($id in $LastRunIds.Keys) {
        $tb = $Ui[$LastRunIds[$id]]
        $tb.Text = "$($tb.Tag)"
        $row = $tb.Parent.Parent.Parent
        $row.ToolTip = $LastRunTips[$id]
        [Windows.Controls.ToolTipService]::SetShowDuration($row, 30000)
        $t = $null; $st = ''
        if ($h.ContainsKey($id)) {
            try {
                $t = [DateTime]::Parse("$($h[$id].Time)", [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
                $st = "$($h[$id].Status)".ToLower()
            } catch {}
        }
        $Ui["${id}Last"].Text = Format-LastStamp 'dernière exécution' $t $(if ($st -ne 'terminé') { $st } else { '' })
    }
}
Update-LastRun

function Update-ReportStatus {
    foreach ($r in @(@{ Dir = $LogCats.Disques; Filter = '*_SMART_*.txt'; Btn = $Ui.SmartOpenBtn; Last = $Ui.SmartLast },
                     @{ Dir = $LogCats.Disques; Filter = '*_batterie_*.html'; Btn = $Ui.BatteryOpenBtn; Last = $Ui.BatteryLast })) {
        $f = Get-ChildItem -LiteralPath (Join-Path $LogDir $r.Dir) -Filter $r.Filter -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        $r.Btn.IsEnabled = [bool]$f; $r.Btn.Visibility = $(if ($f) { 'Visible' } else { 'Collapsed' })
        $r.Btn.Tag = $(if ($f) { $f.FullName } else { $null })
        $r.Last.Text = Format-LastStamp 'dernier rapport' $(if ($f) { $f.LastWriteTime } else { $null })
    }
}
Update-ReportStatus

function Update-LogStatistic {
    $all = @(Get-LogFile 0); $old = @(Get-LogFile 30)
    $sa = [double]0; foreach ($f in $all) { $sa += $f.Length }
    $so = [double]0; foreach ($f in $old) { $so += $f.Length }
    $Ui.LogStats.Text = $(if (-not $all.Count) { 'Journaux et rapports : aucun fichier' }
        else { 'Journaux et rapports : {0} {1}, {2}  ·  {3}' -f $all.Count, (Get-Plural $all.Count 'fichier' 'fichiers'), (Format-SizeUi $sa), $(if ($old.Count) { 'dont {0} de plus de 30 jours ({1})' -f $old.Count, (Format-SizeUi $so) } else { 'aucun de plus de 30 jours' }) })
    $Ui.LogPurgeOld.IsEnabled = $old.Count -gt 0
    $Ui.LogPurgeAll.IsEnabled = $all.Count -gt 0
    $Ui.LogPurgeOld.ToolTip = $(if ($old.Count) { 'Supprimer les journaux et rapports de plus de 30 jours ({0})' -f (Format-SizeUi $so) } else { 'Aucun journal ni rapport de plus de 30 jours' })
    $Ui.LogPurgeAll.ToolTip = $(if ($all.Count) { 'Supprimer tous les journaux et rapports ({0})' -f (Format-SizeUi $sa) } else { 'Aucun journal ni rapport' })
    @{ All = $all.Count; Old = $old.Count; OldSize = $so }
}
function Remove-LogFile([int]$Days) {
    $files = @(Get-LogFile $Days)
    if ($files.Count -eq 0) { return }
    $size = [double]0; foreach ($f in $files) { $size += $f.Length }
    $one = $files.Count -lt 2
    $what = if ($Days -gt 0) { "de plus de $Days jours" } elseif ($one) { 'existant' } else { 'existants (tous types, rapports SMART et batterie compris)' }
    if (-not (Confirm-Action ("{0} {1} ({2}) ?`n`nSuppression définitive. Les fichiers internes de l'application sont conservés." -f $(if ($one) { 'Supprimer le seul journal ou rapport' } else { "Supprimer les $($files.Count) journaux et rapports" }), $what, (Format-SizeUi $size)))) {
        return
    }
    # taille comptée sur les fichiers réellement supprimés ; échecs (fichier ouvert, droits) signalés avec le premier motif
    $n = 0; $size = [double]0; $ko = 0; $why = ''
    foreach ($f in $files) {
        $len = $f.Length
        try { $f.Delete(); $n++; $size += $len } catch { $ko++; if (-not $why) { $why = $_.Exception.Message } }
    }
    Write-UiLog ('{0} {1} ({2}).' -f $n, (Get-Plural $n 'fichier supprimé' 'fichiers supprimés'), (Format-SizeUi $size)) 'OK'
    if ($ko) { Write-UiLog ('{0} {1} : {2}' -f $ko, (Get-Plural $ko 'fichier non supprimé' 'fichiers non supprimés'), $why) 'WARN' }
    Add-SessionEvent 'Journaux' $(if ($Days -gt 0) { "Journaux de plus de $Days jours" } else { 'Tous les journaux' }) ('{0} {1} ({2}){3}' -f $n, (Get-Plural $n 'fichier supprimé' 'fichiers supprimés'), (Format-SizeUi $size), $(if ($ko) { ", $ko en échec" } else { '' })) $(if ($ko) { 'warn' } else { 'ok' })
    [void](Update-LogStatistic); Update-ReportStatus
}
$LogStart = Update-LogStatistic
if ($LogStart.Old -gt 0) {
    Write-UiLog ('{0} {1} de plus de 30 jours ({2}) : suppression proposée en haut de l''onglet Journal.' -f $LogStart.Old, (Get-Plural $LogStart.Old 'journal' 'journaux'), (Format-SizeUi $LogStart.OldSize)) 'APP'
}
$Ui.LogPurgeOld.Add_Click({ Remove-LogFile 30 })
$Ui.LogPurgeAll.Add_Click({ Remove-LogFile 0 })

