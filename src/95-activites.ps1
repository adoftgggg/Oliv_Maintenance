# ---------- Opérations longues en arrière-plan : bandeau sous la barre d'infos, visible depuis tous les onglets
# Une ligne par opération (texte, barre d'avancement, bouton d'arrêt si l'opération le permet).
# - BitLocker : avancement réel relu toutes les 4 s (Get-BitLockerVolume, VolumeStatus / EncryptionPercentage) tant que le
#   volume système est en chiffrement, déchiffrement ou pause ; fin signalée (journal, notification), diagnostic actualisé.
# - Analyse antivirus : Microsoft Defender et Sophos ne publient pas l'avancement d'une analyse en cours (ni pourcentage
#   ni nombre de fichiers) : temps écoulé réel et barre continue, sans pourcentage inventé ; Defender interrompable
#   (MpCmdRun.exe -Scan -Cancel).
$Activities = [ordered]@{}
function Set-BgActivity([string]$Key, [string]$Text, [double]$Pct, [string]$Tip, [scriptblock]$Stop) {
    $a = $Activities[$Key]
    if (-not $a) {
        $g = [Windows.Controls.Grid]::new(); $g.Margin = New-Thickness 0 2 0 2
        [void]$g.ColumnDefinitions.Add([Windows.Controls.ColumnDefinition]::new()); $c = [Windows.Controls.ColumnDefinition]::new(); $c.Width = [Windows.GridLength]::Auto; [void]$g.ColumnDefinitions.Add($c)
        $sp = [Windows.Controls.StackPanel]::new(); $sp.VerticalAlignment = 'Center'
        $t = New-Text ''; $t.FontWeight = [Windows.FontWeights]::SemiBold; $t.TextTrimming = 'CharacterEllipsis'
        $bar = [Windows.Controls.ProgressBar]::new(); $bar.Height = 5; $bar.Margin = New-Thickness 0 5 0 0; $bar.Minimum = 0; $bar.Maximum = 100; $bar.BorderThickness = New-Thickness 0 0 0 0
        $bar.SetResourceReference([Windows.Controls.Control]::ForegroundProperty, 'AccentBrush'); $bar.SetResourceReference([Windows.Controls.Control]::BackgroundProperty, 'LineBrush')
        [void]$sp.Children.Add($t); [void]$sp.Children.Add($bar); [void]$g.Children.Add($sp)
        $b = New-Button 'Interrompre' 'WarnBtn'; $b.Height = 28; $b.Margin = New-Thickness 12 0 0 0; $b.VerticalAlignment = 'Center'; $b.Visibility = 'Collapsed'
        $b.Add_Click({ param($s, $e) if ($s.Tag) { & $s.Tag } })
        [Windows.Controls.Grid]::SetColumn($b, 1); [void]$g.Children.Add($b)
        [void]$Ui.BgList.Children.Add($g)
        $a = @{ Row = $g; Text = $t; Bar = $bar; Btn = $b }; $Activities[$Key] = $a
    }
    if ($a.Text.Text -ne $Text) { $a.Text.Text = $Text }
    $a.Row.ToolTip = $(if ($Tip) { $Tip } else { $null })
    $a.Bar.IsIndeterminate = $Pct -lt 0; if ($Pct -ge 0) { $a.Bar.Value = [math]::Min([double]100, $Pct) }
    $a.Btn.Tag = $Stop; $a.Btn.Visibility = $(if ($Stop) { 'Visible' } else { 'Collapsed' })
    $Ui.BgBar.Visibility = 'Visible'
}
function Remove-BgActivity([string]$Key) {
    $a = $Activities[$Key]; if (-not $a) { return }
    [void]$Ui.BgList.Children.Remove($a.Row); $Activities.Remove($Key)
    if (-not $Activities.Count) { $Ui.BgBar.Visibility = 'Collapsed' }
}

# ---- BitLocker
$BlWatch = @{ Timer = $null; Was = $null }
$BlPollScript = @'
try { $v = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction Stop; $Sync.BlPoll = @{ St = "$($v.VolumeStatus)"; Pct = [double]$v.EncryptionPercentage } }
catch { $Sync.BlPoll = @{ Err = $_.Exception.Message } }
'@
function Start-BlWatch {
    if ($BlWatch.Timer -and $BlWatch.Timer.IsEnabled) { return }
    if (-not $BlWatch.Timer) {
        $BlWatch.Timer = [Windows.Threading.DispatcherTimer]::new(); $BlWatch.Timer.Interval = [TimeSpan]::FromSeconds(4)
        $BlWatch.Timer.Add_Tick({ if (-not $BgJobs.ContainsKey('BlPoll')) { Start-BgJob 'BlPoll' $BlPollScript } })
    }
    $BlWatch.Timer.Start(); if (-not $BgJobs.ContainsKey('BlPoll')) { Start-BgJob 'BlPoll' $BlPollScript }
}
$BgJobDone['BlPoll'] = {
    $p = $Sync.BlPoll; $vol = $env:SystemDrive
    if (-not $p -or $p.Err) { return }
    $txt = $null; $pct = 0
    switch ($p.St) {
        'EncryptionInProgress' { $pct = $p.Pct; $txt = 'BitLocker ({0}) : chiffrement en cours  ·  {1:N1} %' -f $vol, $pct }
        'DecryptionInProgress' { $pct = 100 - $p.Pct; $txt = 'BitLocker ({0}) : déchiffrement en cours  ·  {1:N1} % effectué' -f $vol, $pct }
        'EncryptionSuspended' { $pct = $p.Pct; $txt = 'BitLocker ({0}) : chiffrement en pause à {1:N1} % (reprise automatique par Windows)' -f $vol, $pct }
        'DecryptionSuspended' { $pct = 100 - $p.Pct; $txt = 'BitLocker ({0}) : déchiffrement en pause à {1:N1} % effectué' -f $vol, $pct }
    }
    if ($txt) {
        $BlWatch.Was = $p.St
        Set-BgActivity 'BitLocker' $txt $pct 'Avancement réel du volume système, relu toutes les 4 secondes. Le PC reste utilisable ; un redémarrage ne fait que mettre en pause.' $null
        if ($InfoUI.BlValue) { $InfoUI.BlValue.Text = $(if ($p.St -like 'Encryption*') { 'chiffrement en cours ({0:N1} %)' -f $p.Pct } else { 'déchiffrement en cours ({0:N1} % restant chiffré)' -f $p.Pct }) }
        return
    }
    # terminé (FullyEncrypted / FullyDecrypted) : fin du suivi
    $BlWatch.Timer.Stop(); Remove-BgActivity 'BitLocker'
    if ($BlWatch.Was) {
        $m = $(if ($p.St -eq 'FullyEncrypted') { "BitLocker ($vol) : chiffrement terminé." } else { "BitLocker ($vol) : déchiffrement terminé." })
        Write-UiLog $m 'OK'; Add-SessionEvent 'Sécurité' "BitLocker ($vol)" $(if ($p.St -eq 'FullyEncrypted') { 'chiffrement terminé' } else { 'déchiffrement terminé' }) 'ok'
        try { Send-AppNotification 'BitLocker' $m 'Info' } catch { Write-Ignored 'Notification BitLocker' $_ }
        $BlWatch.Was = $null; Start-DiagCollector
    }
}

# ---- analyse antivirus (temps écoulé, Defender interrompable)
$MpCmdRun = Join-Path $env:ProgramFiles 'Windows Defender\MpCmdRun.exe'
function Start-AvActivity {
    $Sync.AvCancel = $false
    if (-not $script:AvTimer) {
        $script:AvTimer = [Windows.Threading.DispatcherTimer]::new(); $script:AvTimer.Interval = [TimeSpan]::FromSeconds(1)
        $script:AvTimer.Add_Tick({ Update-AvActivity })
    }
    $script:AvTimer.Start(); Update-AvActivity
}
function Update-AvActivity {
    if (-not $BgJobs.ContainsKey('AvScan')) { $script:AvTimer.Stop(); Remove-BgActivity 'AvScan'; return }
    $el = [DateTime]::Now - $Sync.AvScanStart
    $txt = 'Analyse {0} {1} {2}  ·  {3:hh\:mm\:ss} écoulées' -f $Sync.AvScanLabel, $Sync.AvScanName, $(if ($Sync.AvCancel) { 'en cours d''arrêt' } else { 'en cours' }), $el
    $stop = $(if ($Sync.AvScanName -eq 'Microsoft Defender' -and -not $Sync.AvCancel -and (Test-Path -LiteralPath $MpCmdRun)) { { Stop-AvScan } } else { $null })
    Set-BgActivity 'AvScan' $txt -1 ("$($Sync.AvScanName) ne publie pas l'avancement d'une analyse en cours (ni pourcentage ni nombre de fichiers) : seul le temps écoulé réel est affiché. Résultat à la fin de l'analyse.") $stop
}
function Stop-AvScan {
    if (-not (Confirm-Action "Interrompre l'analyse $($Sync.AvScanLabel) Microsoft Defender ?")) { return }
    $Sync.AvCancel = $true; Update-AvActivity
    try { Start-Process -FilePath $MpCmdRun -ArgumentList '-Scan', '-Cancel' -WindowStyle Hidden -ErrorAction Stop; Write-UiLog 'Microsoft Defender : interruption de l''analyse demandée.' 'WARN' }
    catch { Write-UiLog "Microsoft Defender : interruption impossible - $($_.Exception.Message)" 'ERROR'; $Sync.AvCancel = $false }
}
