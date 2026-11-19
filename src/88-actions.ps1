$Ui.SpaceBtn.Add_Click({
    try { Show-SpaceAnalyzer } catch {
        Write-UiLog "Analyseur d'espace disque : $($_.Exception.Message)" 'ERROR'
        Show-Info "Ouverture de l'analyseur d'espace disque impossible.`n`n$($_.Exception.Message)" 'Error'
    }
})

$Ui.PersoRestore.Add_Click({ [void](Start-Worker @('RestorePoint')) })
# redémarrage de l'Explorateur : arrêt puis attente de sa relance par Windows (AutoRestartShell), vérifiée toutes les
# 250 ms pendant 6 s au plus par un minuteur (l'interface reste utilisable, fin dès que l'Explorateur est revenu)
$ExplorerWait = @{ Timer = $null; Start = $null; Old = @() }
function Complete-ExplorerRestart([bool]$Ok) {
    $ExplorerWait.Timer.Stop(); $Ui.PendingExplorer.IsEnabled = $true
    if ($Ok) {
        foreach ($r in $TweakRows) {
            if ($r.Pending -eq 'E') {
                $r.Pending = $null
                $r.Orig = $r.Current
                Remove-PendingRecord $r.Key
                if ($null -eq $r.Staged) { Set-Badge $r 'ok' } else { $r.BadgeState = 'ok' }
            }
        }
        Write-UiLog 'Explorateur redémarré : réglages en attente appliqués.' 'OK'
    } else {
        Write-UiLog 'Explorateur non relancé automatiquement : Gestionnaire des tâches > Exécuter une nouvelle tâche > explorer.exe (sans cocher « droits administrateur »).' 'WARN'
    }
    Update-PendingBar
}
$Ui.PendingExplorer.Add_Click({
    $Ui.PendingExplorer.IsEnabled = $false
    # nouvel Explorateur = PID différent de ceux arrêtés (un processus en cours d'arrêt reste visible quelques instants)
    $old = @(Get-Process -Name explorer -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $UserSession })
    $ExplorerWait.Old = @($old | ForEach-Object { $_.Id }); $old | Stop-Process -Force
    if (-not $ExplorerWait.Timer) {
        $ExplorerWait.Timer = [Windows.Threading.DispatcherTimer]::new(); $ExplorerWait.Timer.Interval = [TimeSpan]::FromMilliseconds(250)
        $ExplorerWait.Timer.Add_Tick({
            if (@(Get-Process -Name explorer -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $UserSession -and $_.Id -notin $ExplorerWait.Old }).Count) { Complete-ExplorerRestart $true }
            elseif (([DateTime]::Now - $ExplorerWait.Start).TotalSeconds -ge 6) { Complete-ExplorerRestart $false }
        })
    }
    $ExplorerWait.Start = [DateTime]::Now; $ExplorerWait.Timer.Start()
})
$Ui.PendingLogoff.Add_Click({
    if (-not (Confirm-Action "Déconnecter la session de $UserName ?`n`nLes applications ouvertes sont fermées, les documents non enregistrés seront perdus.")) {
        return
    }
    Write-UiLog "Déconnexion de la session $UserSession ($UserName)." 'INFO'
    try {
        Start-Process -FilePath "$env:windir\System32\logoff.exe" -ArgumentList "$UserSession" -WindowStyle Hidden
    } catch {
        Write-UiLog "logoff : $($_.Exception.Message)" 'ERROR'
    }
})
$Ui.PendingReboot.Add_Click({
    if ($Sync.RebootAt -and $Sync.RebootAt -gt [DateTime]::Now) {
        $r = Show-Dialog ("Redémarrage programmé à {0:HH:mm}.`n`nLe conserver, le modifier ou l'annuler ?" -f $Sync.RebootAt) 'Question' @(@{ T = 'Conserver'; V = $null; C = $true; D = $true }, @{ T = 'Annuler le redémarrage'; V = 'cancel'; S = 'WarnBtn' }, @{ T = 'Modifier'; V = 'edit'; S = 'PrimaryBtn' })
        if ($r -eq 'cancel') {
            Stop-ScheduledReboot
        } elseif ($r -eq 'edit') {
            Request-Reboot 'Un redémarrage du poste est en attente.' 'pour finaliser les modifications en attente'
        }
        $Sync.WuShown = $null; return
    }
    Request-Reboot 'Un redémarrage du poste est en attente.' 'pour finaliser les modifications en attente'
})

$Ui.OpenLogDir.Add_Click({ Start-Process explorer.exe -ArgumentList "`"$LogDir`"" })
$AbortClick = {
    if (-not $Sync.Running) { return }
    $child = $Sync.ChildPid; $name = $Sync.ChildName
    if ($Sync.ChildKind -eq 'api') {
        if (-not (Confirm-Action ("Interrompre DISM ?`n`nUne réparation interrompue peut laisser le magasin de composants incomplet : relancer DISM Réparer ensuite." + (Get-RestNote)))) {
            return
        }
        $Sync.Aborted = $true; $Sync.Cancel = $true
        Write-UiLog 'Interruption de DISM demandée (arrêt propre du moteur DISM, quelques secondes).' 'WARN'
    }
    elseif ($child) {
        $warn = if ($name -eq 'DISM') { "`n`nUne réparation interrompue peut laisser le magasin de composants incomplet : relancer DISM Réparer ensuite." } else { '' }
        if (-not (Confirm-Action (('Interrompre {0} ?{1}' -f $name, $warn) + (Get-RestNote)))) { return }
        $Sync.Aborted = $true; $Sync.Cancel = $true
        & "$env:windir\System32\taskkill.exe" /PID $child /T /F 2>&1 | Out-Null
        Write-UiLog ('{0} interrompu (PID {1} et processus enfants).' -f $name, $child) 'WARN'
    } else {
        $rest = @($Sync.Selected).Count - [math]::Max(1, [int]$Sync.TaskIdx)
        # dernière tâche en cours, non interruptible proprement : rien à annuler
        if ($rest -le 0) {
            Show-Info 'Aucune tâche en attente : la tâche en cours ne peut pas être interrompue proprement, elle se termine normalement.'
            return
        }
        if (-not (Confirm-Action ($(if ($rest -eq 1) { 'Interrompre après la tâche en cours ? 1 tâche en attente ne sera pas lancée.' } else { "Interrompre après la tâche en cours ? $rest tâches en attente ne seront pas lancées." }) + "`n`nLa tâche en cours ne peut pas être interrompue proprement : elle se termine avant l'arrêt."))) {
            return
        }
        $Sync.Cancel = $true
        $Sync.Status = 'Arrêt après la tâche en cours...'
    }
    $Ui.AbortBtn.IsEnabled = $false; $Ui.StopBtn.IsEnabled = $false
}
$Ui.StopBtn.Add_Click($AbortClick)
$Ui.FooterClose.Add_Click({ $Sync.FooterKeep = $false; Update-Footer })
$Ui.AbortBtn.Add_Click($AbortClick)

