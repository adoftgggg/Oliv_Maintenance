# ---------- Minuteur de l'interface (250 ms) : relais entre les runspaces (état dans $Sync) et l'affichage.
# Chaque tick enchaîne des étapes indépendantes : une étape en erreur n'empêche plus les suivantes (auparavant une
# exception arrêtait le reste du tick sans trace). Erreur journalisée une seule fois par étape et par message.
$TickErrors = @{}
function Invoke-TickStep([string]$Name, [scriptblock]$Step) {
    try { & $Step }
    catch {
        $m = $_.Exception.Message
        if ($TickErrors[$Name] -ne $m) { $TickErrors[$Name] = $m; Write-UiLog ('Rafraîchissement ({0}) : {1}' -f $Name, $m) 'WARN' }
    }
}

# journal : lignes en attente des runspaces
function Receive-LogQueue {
    $sb = [System.Text.StringBuilder]::new(); $line = $null
    while ($Sync.Queue.TryDequeue([ref]$line)) { [void]$sb.AppendLine($line) }
    if ($sb.Length -gt 0) { Add-LogLine $sb.ToString() }
}

# résultats des collectes en arrière-plan : affichés une seule fois par horodatage
function Update-BgResult {
    $wp = $Sync.WuPending
    if ($wp -and $wp.Stamp -ne $Sync.WuShown -and $InfoUI.WuPanel) { $Sync.WuShown = $wp.Stamp; Invoke-TickStep 'Windows Update' { Show-WuPending } }
    $dg = $Sync.Diag
    if ($dg -and $dg.Stamp -ne $Sync.DiagShown) { $Sync.DiagShown = $dg.Stamp; Invoke-TickStep 'diagnostic' { Show-DiagResult $dg } }
    $slow = $Sync.InfoSlow
    if ($slow -and $slow.Stamp -ne $Sync.InfoShown) { $Sync.InfoShown = $slow.Stamp; Invoke-TickStep 'Accueil' { Show-InfoSlow $slow } }
    if ($Sync.InfoBaseDone -and -not $script:BatteryCardDone) { Invoke-TickStep 'carte Disques et batterie' { Update-BatteryCard } }
    if ($Sync.AppxScan -and $AppxList -and $Sync.AppxScan.Stamp -ne $script:AppxShown) {
        $script:AppxShown = $Sync.AppxScan.Stamp
        Invoke-TickStep 'applications préinstallées' { Show-AppxList }
    }
}

# Windows Update : avancement de la recherche, puis événement de session et notification à la fin
function Watch-WuSearch {
    if ($Sync.WuSearching) { Update-WuProgress; $InfoUI.WuWasOnline = [bool]$Sync.WuOnline; return }
    if (-not ($InfoUI.WuWasOnline -and $Sync.WuStartT)) { return }
    $InfoUI.WuWasOnline = $false
    $wp = $Sync.WuPending
    if ($Sync.WuCancel) { Add-SessionEvent 'Windows Update' 'Recherche des mises à jour' 'annulée' 'warn'; return }
    if (-not $wp) { return }
    $nW = @($wp.Items).Count; $nR = @($wp.Reboot | Where-Object { $_ }).Count
    $found = '{0} {1}' -f $nW, (Get-Plural $nW 'mise à jour disponible' 'mises à jour disponibles')
    Add-SessionEvent 'Windows Update' 'Recherche des mises à jour' $(if ($wp.Error) { 'impossible : ' + $wp.Error } elseif ($nW) { $found } else { 'aucune mise à jour disponible' }) `
        $(if ($wp.Error) { 'error' } elseif ($nW) { 'warn' } else { 'ok' }) $(if ($nR) { '{0} {1}, redémarrage requis' -f $nR, (Get-Plural $nR 'installée' 'installées') } else { '' })
    Send-AppNotification 'Recherche Windows Update terminée' $(if ($wp.Error) { 'Recherche impossible : ' + $wp.Error } elseif ($nW) { $found } else { 'Aucune mise à jour disponible' }) `
        $(if ($wp.Error) { 'Error' } else { 'Info' }) ([DateTime]::Now - $Sync.WuStartT)
}

# constructeur : fin de recherche, fin d'installation de l'outil, fin d'installation des mises à jour
function Watch-Oem {
    if ($Sync.OemRunning) { $InfoUI.OemWasScan = $true; $InfoUI.OemWasAuto = [bool]$Sync.OemAuto }
    elseif ($InfoUI.OemWasScan) {
        $InfoUI.OemWasScan = $false
        $r = $Sync.OemResult
        $tt = $(if ($InfoUI.OemWasAuto) { 'Recherche automatique des mises à jour constructeur' } else { 'Recherche des mises à jour constructeur' })
        if ($Sync.OemCancelled) { Add-SessionEvent 'Constructeur' $tt 'annulée' 'warn' }
        elseif ($r) {
            $nO = @($r.Items | Where-Object { $_ }).Count
            $found = '{0} {1}' -f $nO, (Get-Plural $nO 'mise à jour disponible' 'mises à jour disponibles')
            Add-SessionEvent 'Constructeur' $tt $(if ($r.Error) { "impossible : $($r.Error)" } elseif ($nO) { $found } else { 'aucune mise à jour disponible' }) $(if ($r.Error) { 'error' } elseif ($nO) { 'warn' } else { 'ok' }) "$($r.Tool)"
            # notification pour une recherche lancée à la main seulement
            if (-not $InfoUI.OemWasAuto) {
                Send-AppNotification 'Recherche constructeur terminée' $(if ($r.Error) { "$($r.Error)" } elseif ($nO) { $found } else { 'Aucune mise à jour disponible' }) $(if ($r.Error) { 'Error' } else { 'Info' }) ([DateTime]::Now - $Sync.OemStart)
            }
        }
    }
    if ($Sync.Tick % 4 -eq 3 -and ($Sync.OemRunning -or $InfoUI.OemRunShown -or ($Sync.OemResult -and "$($Sync.OemResult.Time)" -ne $InfoUI.OemShown))) {
        $InfoUI.OemShown = "$($Sync.OemResult.Time)"
        Show-OemResult
    }
    if ($Sync.OemToolFinished) {
        $Sync.OemToolFinished = $false
        Add-SessionEvent 'Constructeur' "Installation de $($Sync.OemToolName)" $(if ($Sync.OemToolOk) { 'installé' } else { 'échec' }) $(if ($Sync.OemToolOk) { 'ok' } else { 'error' })
        if ($Sync.OemToolOk) { Write-UiLog "$($Sync.OemToolName) installé : nouvelle recherche des mises à jour constructeur." 'OK'; Start-OemScan }
        else { Write-UiLog "Installation de $($Sync.OemToolName) en échec - journal : $($Sync.OemLog)" 'ERROR'; Show-OemResult }
    }
    if ($Sync.OemInstFinished) {
        $Sync.OemInstFinished = $false; $InfoUI.OemSel = @{}
        Write-UiLog "Installation des mises à jour constructeur terminée - journal : $($Sync.OemLog)"
        try { Add-OemRunToSession } catch { Write-UiLog "Rapport (constructeur) : $($_.Exception.Message)" 'WARN' }
        $its = @(); if ($Sync.OemRun) { $its = @($Sync.OemRun.Items.Values) }
        $nOk = @($its | Where-Object { $_.State -eq 'ok' }).Count; $nKo = @($its | Where-Object { $_.State -eq 'fail' }).Count
        Send-AppNotification 'Mises à jour constructeur installées' ('{0} {1}{2}' -f $nOk, (Get-Plural $nOk 'installée' 'installées'), $(if ($nKo) { ", $nKo en échec" } else { '' })) $(if ($nKo) { 'Error' } else { 'Info' }) ([DateTime]::Now - $Sync.OemStart)
        Start-OemScan
        if ($Sync.OemReboot) {
            Request-Reboot $(if ([int]$Sync.OemOkCount -lt 2) { 'Mise à jour constructeur installée : un redémarrage du poste est nécessaire pour la finaliser.' } else { 'Mises à jour constructeur installées : un redémarrage du poste est nécessaire pour les finaliser.' })
        }
    }
}

# rafraîchissements périodiques : 1 s pour l'essentiel, page visible seulement, rien si la fenêtre est réduite
function Update-Periodic {
    $t = $Sync.Tick; $min = $Window.WindowState -eq 'Minimized'
    if ($t % 4 -eq 2 -and ($BgJobs.Count -or $BgOrphans.Count)) { Invoke-TickStep 'tâches de fond' { Close-BgJob } }
    if ($t % 4 -eq 1 -and $GpRows.Count) { Invoke-TickStep 'stratégies de groupe' { Update-GpRow } }
    if ($t % 4 -eq 0 -and -not $min) { Invoke-TickStep 'points de restauration' { Update-RestoreLast } }
    if ($t % 4 -eq 0) { Invoke-TickStep 'logiciels' { Update-SoftCard } }
    # fenêtre Logiciels pendant une mise à jour : avancement et état de chaque logiciel 2 fois par seconde
    if ($SoftUI.Win -and $t % 2 -eq 0 -and (Test-SoftUpgrading)) { Invoke-TickStep 'mise à jour des logiciels' {
        Update-SoftStatus
        Update-SoftRunRow
    } }
    # onglet Applications pendant une installation : état de chaque application 2 fois par seconde
    if ($AppsUI.Built -and $t % 2 -eq 0 -and $Sync.Running -and $Sync.Selected -contains 'AppInstall') { Invoke-TickStep 'installation d''applications' { Update-AppsRunState } }
    if ($Sync.ThemeMode -eq 'Systeme' -and $t % 8 -eq 0) { Invoke-TickStep 'thème' {
        $th = Get-SystemTheme
        if ($th -ne $Sync.Theme) { Set-Theme $th }
    } }
    if ($t % 4 -ne 0 -or $min) { return }
    if ($Ui.PageInfo.Visibility -eq 'Visible') { Invoke-TickStep 'Accueil' { Update-Uptime; Update-DiagAge; Update-WuAge; Update-InfoFast } }
    if ($Ui.PageMaint.Visibility -eq 'Visible') {
        $sig = '{0}|{1}' -f $Sync.CleanSizes.Count, $Sync.CleanScanDone
        if ($sig -ne $Sync.CleanSig -or $t % 20 -eq 0) { $Sync.CleanSig = $sig; Invoke-TickStep 'nettoyage' { Update-CleanSize } }
    }
}

# tâches en cours : avancement réel (tâche et ensemble), sans estimation de temps restant
function Update-RunProgress {
    if (-not $Sync.Running) { return }
    $pct = [double]$Sync.TaskPct
    $nT = [math]::Max(1, [int]$Sync.TaskCount); $it = [math]::Max(1, [int]$Sync.TaskIdx)
    $known = $pct -ge 0
    $Ui.ProgressBar.IsIndeterminate = -not $known
    $Ui.ProgressBar.Value = $(if ($known) { 100 * (($it - 1) + $pct / 100) / $nT } else { 100 * ($it - 1) / $nT })
    $Ui.RunBar.IsIndeterminate = -not $known
    $Ui.RunBar.Value = $(if ($known) { $pct } else { 0 })
    $Ui.RunTitle.Text = $Sync.Status
    $Ui.RunPct.Text = $(if ($known) { '{0:N0} %' -f [math]::Floor($pct) } else { '' })
    if ($Sync.ChildKind -eq 'api' -and -not $known) { $Ui.RunBar.IsIndeterminate = $false; $Ui.RunPct.Text = '0 %' }
    $el = [DateTime]::Now - $Sync.TaskStart; $tot = [DateTime]::Now - $Sync.RunStart
    $Ui.RunInfo.Text = 'Tâche {0}/{1}  ·  écoulé {2:hh\:mm\:ss}  ·  total {3:hh\:mm\:ss}{4}' -f $it, $nT, $el, $tot, $(if ($Sync.ChildName) { "  ·  processus $($Sync.ChildName) (PID $($Sync.ChildPid))" } else { '' })
    $Ui.StatusText.Text = $Sync.Status + $(if ($known) { ' - {0:N0} %' -f [math]::Floor($pct) } else { '' })
    $state = "$($Sync.PS.InvocationStateInfo.State)"
    if ($state -eq 'Failed') {
        Add-LogLine ('{0:HH:mm:ss} [ERROR] Erreur du runspace : {1}' -f (Get-Date), $Sync.PS.InvocationStateInfo.Reason)
        $Sync.Status = 'Erreur'; $Sync.Done = $true
    }
    if ($Sync.Done -or $state -in 'Completed', 'Stopped') { Complete-Run }
}

$Timer = [Windows.Threading.DispatcherTimer]::new()
$Timer.Interval = [TimeSpan]::FromMilliseconds(250)
$Timer.Add_Tick({
    # effet visuel en cours : tick sauté (repris 250 ms plus tard), aucune image perdue
    if (Test-AnimBusy) { return }
    $Sync.Tick = 1 + [int]$Sync.Tick
    # fenêtre réduite sans tâche en cours : 1 passage par seconde au lieu de 4 (rien n'est affiché, fins de recherche et
    # notifications relevées au plus 1 s plus tard)
    # nouvelle ouverture de l'application (instance unique) : fenêtre existante ramenée au premier plan
    if ($AppShowEvent.WaitOne(0)) { Invoke-TickStep 'ouverture de la fenêtre' { Show-MainWindow } }
    if (($Window.WindowState -eq 'Minimized' -or -not $Window.IsVisible) -and -not $Sync.Running -and $Sync.Tick % 4) { return }
    Invoke-TickStep 'journal' { Receive-LogQueue }
    Invoke-TickStep 'informations du poste' { Watch-InfoRequest }
    Update-BgResult
    Invoke-TickStep 'Windows Update' { Watch-WuSearch }
    Invoke-TickStep 'constructeur' { Watch-Oem }
    Invoke-TickStep 'pied de page' { Update-Footer }
    Update-Periodic
    Invoke-TickStep 'tâches' { Update-RunProgress }
})
$Timer.Start()
