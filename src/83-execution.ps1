$RepairButtons = 'SmartBtn', 'BatteryBtn', 'OptimizeBtn', 'PersoRestore', 'WuResetBtn', 'NetResetBtn', 'SpoolResetBtn', 'TimeSyncBtn', 'StoreResetBtn', 'GpuResetBtn', 'NetCheckBtn', 'GpForceBtn'
function Set-Busy([bool]$Busy) {
    $Ui.StopBtn.IsEnabled = $Busy
    foreach ($b in $RepairButtons) { $Ui[$b].IsEnabled = -not $Busy }
    foreach ($c in $CleanUI.Values) { $c.Check.IsEnabled = -not $Busy }
    foreach ($g in $GroupUI.Values) { $g.Check.IsEnabled = -not $Busy }
    $Ui.CleanRescan.IsEnabled = -not $Busy
    foreach ($c in @($RepDism, $RepSfc, $RepChk)) { $c.IsEnabled = -not $Busy }
    Update-RepairButton
    if ($InfoUI.WuBtn) { $InfoUI.WuBtn.IsEnabled = (-not $Busy) -and $Sync.WuPending -and (@($Sync.WuPending.Items).Count -gt 0) }
    Update-AllSearchButton
    # mises à jour constructeur : ni recherche ni installation pendant une tâche (même règle que Windows Update)
    if ($InfoUI.OemBtn -and -not $Sync.OemRunning -and -not $Sync.OemInstalling) { $InfoUI.OemBtn.IsEnabled = -not $Busy }
    Update-OemInstallButton
    Update-ApplyButton
}

function Start-Worker([string[]]$Ids) {
    if ($Sync.Running) { return $false }
    $Sync.Selected = $Ids
    $Sync.Cancel   = $false
    if (-not $Sync.WuSearching) { $Sync.WuCancel = $false }
    $Sync.Aborted  = $false
    $Sync.ChildPid = $null; $Sync.ChildKind = $null
    $Sync.TaskPct  = -1; $Sync.TaskIdx = 0; $Sync.TaskCount = $Ids.Count; $Sync.TaskStart = [DateTime]::Now
    $Sync.RunStart = [DateTime]::Now
    $Sync.TaskResults = [Collections.ArrayList]::Synchronized([Collections.ArrayList]::new())
    $Sync.WuInstalled = [Collections.ArrayList]::Synchronized([Collections.ArrayList]::new())
    $Sync.SpaceGain = $null
    $Ui.RunPanel.Visibility = 'Visible'; $Ui.AbortBtn.IsEnabled = $true; $Ui.AbortBtn.Content = 'Interrompre'
    $Sync.Done     = $false
    $Sync.Status   = 'Démarrage...'
    $cat = switch -Regex ($Ids[0]) {
        '^(Dism|Sfc|Chk)' { 'Reparation' } '^(Clean|WindowsOld)$' { 'Nettoyage' } '^(Smart|Optimize|Battery)$' { 'Disques' }
        '^AppxRemove$' { 'Applications' } '^RestorePoint$' { 'Restauration' } '^WuInstall$' { 'AccueilWu' } '^(SoftUpgrade|AppInstall)$' { 'Logiciels' } default { 'Depannage' }
    }
    $suffix = $(switch ($cat) { 'Depannage' { $Ids[0].ToLower() } 'AccueilWu' { 'mises-a-jour-windows' } 'Restauration' { 'point-de-restauration' } 'Disques' { 'disques' } default { $cat.ToLower() } })
    $Sync.LogRoot  = $LogDir
    $Sync.UserProfile = $UserProfilePath; $Sync.UserSession = $UserSession
    $Sync.UserName = $(if ($HkuSidOk) { $UserName } else { [Security.Principal.WindowsIdentity]::GetCurrent().Name })
    $Sync.LogFile  = Join-Path (Get-LogPath $cat) ('{0}_{1:yyyyMMdd-HHmmss}_{2}.log' -f $env:COMPUTERNAME, (Get-Date), $suffix)
    $Sync.DisksDir = Get-LogPath 'Disques'
    $Sync.Running  = $true
    $Sync.FooterKeep = $true
    # journal de la session conservé d'une exécution à l'autre : ligne vide de séparation avant la nouvelle exécution
    if ($LogView.Lines.Count) { Add-LogLine "`n" }
    Set-Busy $true
    $j = New-PsJob ($CleanLib + "`n" + $WuLib + "`n" + $WorkerScript)
    $Sync.PS = $j.PS; $Sync.Handle = $j.Handle
    $true
}

function Set-RunInfoLog([string]$Prefix, [string]$Path, $Target = $Ui.RunInfo) {
    $Target.Inlines.Clear()
    $Target.Inlines.Add([Windows.Documents.Run]::new($Prefix))
    $h = [Windows.Documents.Hyperlink]::new([Windows.Documents.Run]::new($Path))
    $h.SetResourceReference([Windows.Documents.TextElement]::ForegroundProperty, 'AccentBrush')
    $h.ToolTip = "Ouvrir $Path"; $h.Cursor = [Windows.Input.Cursors]::Hand; $h.Tag = $Path
    $h.Add_Click({
        param($s, $e)
        if (Test-Path -LiteralPath $s.Tag) { Start-Process explorer.exe -ArgumentList ('"{0}"' -f $s.Tag) }
        else { Write-UiLog "Journal introuvable : $($s.Tag)" 'WARN' }
    })
    $Target.Inlines.Add($h)
}
function Confirm-Action([string]$Message) {
    (Show-Dialog $Message 'Warn' @(@{ T = 'Non'; V = $false; C = $true }, @{ T = 'Oui'; V = $true; S = 'PrimaryBtn'; D = $true })) -eq $true
}

function Complete-Run {
    $Sync.Running = $false
    [void]$Window.Dispatcher.BeginInvoke([Action]{
        try { Invoke-MemoryTrim 'fin des tâches' } catch { Write-Ignored 'Libération de la mémoire' $_ }
    }, [Windows.Threading.DispatcherPriority]::ApplicationIdle)
    $Ui.ProgressBar.IsIndeterminate = $false; $Ui.RunBar.IsIndeterminate = $false
    $Ui.AbortBtn.IsEnabled = $false
    $Ui.RunTitle.Text = $(if ($Sync.Aborted) { 'Interrompu' } else { $Sync.Status })
    $Ui.RunPct.Text = ''
    if (-not $Sync.Aborted -and -not $Sync.Cancel) { $Ui.RunBar.Value = 100; $Ui.ProgressBar.Value = 100 }
    Set-RunInfoLog ('Durée totale {0:hh\:mm\:ss}  ·  journal : ' -f ([DateTime]::Now - $Sync.RunStart)) $Sync.LogFile
    try { [void]$Sync.PS.EndInvoke($Sync.Handle) } catch {}
    try { $Sync.PS.Runspace.Dispose(); $Sync.PS.Dispose() } catch {}
    Set-Busy $false
    Set-RunInfoLog "$($Sync.Status) - journal : " $Sync.LogFile $Ui.StatusText
    try { Add-RunToSession } catch { Write-UiLog "Rapport d'intervention : $($_.Exception.Message)" 'WARN' }
    $dur = [DateTime]::Now - $Sync.RunStart
    $nErr = @($Sync.TaskResults | Where-Object { $_.Err }).Count
    $title = $(if ($Sync.Aborted -or $Sync.Cancel) { 'Tâche interrompue' } elseif ($nErr) { 'Tâche terminée avec des erreurs' } else { 'Tâche terminée' })
    $kind = $(if ($nErr) { 'Error' } elseif ($Sync.Aborted) { 'Warning' } else { 'Info' })
    $names = @($Sync.Selected | ForEach-Object { $Sync.Labels[$_] }) -join ', '
    Send-AppNotification $title ('{0}  ·  durée {1:hh\:mm\:ss}' -f $names, $dur) $kind $dur
    if ($Sync.Selected -contains 'AppxRemove') { Update-AppxList }
    if ($Sync.Selected -contains 'AppInstall') { try { Complete-AppsInstall } catch { Write-Ignored 'Onglet Applications' $_ } }
    if ($Sync.Selected -contains 'SoftUpgrade') {
        try { Update-SoftRunRow } catch { Write-Ignored 'Fenêtre Logiciels' $_ }
        $SoftUI.Sel = @{}
        # pas de nouvelle recherche automatique : bilan affiché dans la fenêtre Logiciels, nouvelle recherche au choix
        # (bouton Rechercher, libellé « Nouvelle recherche » tant que le bilan est affiché)
        $its = @($Sync.SoftRun.Items.Values)
        $SoftUI.Done = @{ Ok = @($its | Where-Object { $_.State -in 'ok', 'pend' }).Count; Fail = @($its | Where-Object { $_.State -eq 'fail' }).Count; Skip = @($its | Where-Object { $_.State -in 'skip', 'wait' }).Count }
        # logiciels désinstallés (absents de l'inventaire après coup) : retirés tout de suite de la liste et de l'inventaire enregistré
        $gone = @($its | Where-Object { $_.Removed } | ForEach-Object { "$($_.Id)" })
        if ($gone.Count -and $Sync.WgResult -and $Sync.WgResult.Apps) {
            $Sync.WgResult.Apps = @($Sync.WgResult.Apps | Where-Object { "$($_.Id)" -notin $gone })
            foreach ($g in $gone) { [void]$Sync.SoftRun.Items.Remove($g); if (-not $Sync.SoftGone) { $Sync.SoftGone = @{} }; $Sync.SoftGone[$g] = [DateTime]::Now }
            try { $o = @{} + $Sync.WgResult; $o.Stamp = ([DateTime]$Sync.WgResult.Stamp).ToString('o'); ConvertTo-Json -InputObject $o -Depth 4 | Set-Content -LiteralPath $SoftFile -Encoding UTF8 } catch { Write-Ignored 'Inventaire des logiciels' $_ }
            $SoftUI.CacheStamp = $null
            Write-UiLog ('Retiré(s) de la liste : {0} logiciel(s) désinstallé(s).' -f $gone.Count) 'APP'
        }
        $SoftUI.Stale = $true; Update-SoftCard
        if ($SoftUI.Win) { Update-SoftView }
    }
    [void](Update-LogStatistic)
    if ($Sync.Selected -contains 'Smart' -or $Sync.Selected -contains 'Battery') {
        Update-ReportStatus
        $new = if ($Sync.Selected -contains 'Smart') { $Sync.SmartReport } else { $Sync.BatteryReport }
        if ($new -and (Test-Path -LiteralPath $new) -and -not $Sync.Aborted) { Start-Process explorer.exe -ArgumentList ('"{0}"' -f $new) }
    }
    if ($Sync.Selected -contains 'Clean') {
        foreach ($c in $CleanUI.Values) { $c.Check.IsChecked = $false }
        foreach ($g in @($GroupUI.Keys)) { Update-GroupState $g }
        # décochage par code : pas d'événement Click, résumé, compteur et bouton recalculés ici
        Update-CleanSummary
        Start-CleanScan
    }
    foreach ($id in @($Sync.Selected)) { if ($LastRunIds.Contains($id)) { Save-LastRun $id $Sync.Status } }
    Update-LastRun
    if ($Sync.Selected -contains 'WuReset' -and -not $Sync.Aborted) { Start-DiagCollector }
    if ($Sync.Selected -contains 'WuInstall') {
        $Sync.WuSel = $null
        $Sync.WuOnline = $false; $Sync.WuPending = $null; $Sync.WuShown = $null; Show-WuPending; [void](Start-WuSearch); Start-DiagCollector
        if ($Sync.WuReboot -and -not $Sync.Cancel) {
            Update-PendingBar
            Request-Reboot $(if ([int]$Sync.WuOkCount -lt 2) { 'Mise à jour installée : un redémarrage du poste est nécessaire pour la finaliser.' } else { 'Mises à jour installées : un redémarrage du poste est nécessaire pour les finaliser.' })
        }
    }
    if ($Sync.Selected -contains 'NetReset' -and -not $Sync.Cancel) {
        Update-PendingBar
        Request-Reboot 'Réinitialisation réseau effectuée : un redémarrage du poste est nécessaire pour la finaliser.' 'pour finaliser la réinitialisation réseau'
    }
    if ($Sync.RepairRun) {
        $run = $Sync.RepairRun; $Sync.RepairRun = $null
        try {
            ConvertTo-Json -InputObject ([pscustomobject]@{ Time = [DateTime]::Now.ToString('o'); Mode = $run.Mode; Tools = $run.Tools; Status = $Sync.Status }) | Set-Content -LiteralPath $RepairFile -Encoding UTF8
        } catch {
            Write-Ignored 'Enregistrement de la dernière réparation' $_
        }
        Update-RepairButton
    }
}

