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
        $b = New-Button 'Interrompre' 'WarnBtn'; $b.Height = 30; $b.Margin = New-Thickness 12 0 0 0; $b.VerticalAlignment = 'Center'; $b.Visibility = 'Collapsed'
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
# Bandeau d'erreur : dernière erreur (texte complet en infobulle), boutons « Voir le journal » et « Fermer » ; erreurs
# suivantes comptées (« et 2 autres »). Visible depuis tous les onglets, ne bloque rien.
# bandeau « logiciels à mettre à jour » : affiché tant qu'il en reste (hors exclusions), masquable jusqu'au prochain changement du nombre
$UpdBanner = @{ Row = $null; Text = $null; Hidden = -1; N = 0 }
function Update-SoftUpdBanner {
    if (-not $Ui.BgList) { return }
    $n = @(Get-SoftUpdate | Where-Object { -not $SoftExcl[(Get-SoftKey $_)] }).Count; $UpdBanner.N = $n
    if (-not $n -or $n -eq $UpdBanner.Hidden) {
        if ($UpdBanner.Row) { [void]$Ui.BgList.Children.Remove($UpdBanner.Row); $UpdBanner.Row = $null; if (-not $Ui.BgList.Children.Count) { $Ui.BgBar.Visibility = 'Collapsed' } }
        if (-not $n) { $UpdBanner.Hidden = -1 }
        return
    }
    if (-not $UpdBanner.Row) {
        $g = [Windows.Controls.Grid]::new(); $g.Margin = New-Thickness 0 2 0 2
        [void]$g.ColumnDefinitions.Add([Windows.Controls.ColumnDefinition]::new()); $c = [Windows.Controls.ColumnDefinition]::new(); $c.Width = [Windows.GridLength]::Auto; [void]$g.ColumnDefinitions.Add($c)
        $t = New-Text ''; $t.FontWeight = [Windows.FontWeights]::SemiBold; $t.TextTrimming = 'CharacterEllipsis'; $t.VerticalAlignment = 'Center'
        $t.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'AccentBrush'); [void]$g.Children.Add($t)
        $sp = [Windows.Controls.StackPanel]::new(); $sp.Orientation = 'Horizontal'; [Windows.Controls.Grid]::SetColumn($sp, 1)
        $b1 = New-Button 'Voir les mises à jour'; $b1.Height = 30; $b1.Margin = New-Thickness 12 0 0 0; $b1.Add_Click({ Show-Page 'Apps'; Set-AppsMode 'Upd' })
        $b2 = New-Button 'Plus tard'; $b2.Height = 30; $b2.Margin = New-Thickness 6 0 0 0
        $b2.Add_Click({ $UpdBanner.Hidden = $UpdBanner.N; Update-SoftUpdBanner })
        [void]$sp.Children.Add($b1); [void]$sp.Children.Add($b2); [void]$g.Children.Add($sp)
        $Ui.BgList.Children.Insert(0, $g); $UpdBanner.Row = $g; $UpdBanner.Text = $t
    }
    $names = @(Get-SoftUpdate | Where-Object { -not $SoftExcl[(Get-SoftKey $_)] } | ForEach-Object { $_.Name })
    $UpdBanner.Text.Text = '{0} {1} : {2}' -f $n, (Get-Plural $n 'logiciel à mettre à jour' 'logiciels à mettre à jour'), ($names -join ', ')
    $UpdBanner.Row.ToolTip = ($names -join "`n")
    $Ui.BgBar.Visibility = 'Visible'
}
$ErrBanner = @{ Row = $null; N = 0 }
function Show-ErrorBanner([string]$Msg) {
    if (-not $Ui.BgList) { return }
    if (-not $ErrBanner.Row) {
        $g = [Windows.Controls.Grid]::new(); $g.Margin = New-Thickness 0 2 0 2
        [void]$g.ColumnDefinitions.Add([Windows.Controls.ColumnDefinition]::new()); $c = [Windows.Controls.ColumnDefinition]::new(); $c.Width = [Windows.GridLength]::Auto; [void]$g.ColumnDefinitions.Add($c)
        $t = New-Text ''; $t.FontWeight = [Windows.FontWeights]::SemiBold; $t.TextTrimming = 'CharacterEllipsis'; $t.VerticalAlignment = 'Center'
        $t.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'ErrFgBrush'); [void]$g.Children.Add($t)
        $sp = [Windows.Controls.StackPanel]::new(); $sp.Orientation = 'Horizontal'; [Windows.Controls.Grid]::SetColumn($sp, 1)
        $b1 = New-Button 'Voir le journal'; $b1.Height = 30; $b1.Margin = New-Thickness 12 0 0 0; $b1.Add_Click({ Show-Page 'Log' })
        $b2 = New-Button 'Fermer'; $b2.Height = 30; $b2.Margin = New-Thickness 6 0 0 0
        $b2.Add_Click({ [void]$Ui.BgList.Children.Remove($ErrBanner.Row); $ErrBanner.Row = $null; $ErrBanner.N = 0; if (-not $Ui.BgList.Children.Count) { $Ui.BgBar.Visibility = 'Collapsed' } })
        [void]$sp.Children.Add($b1); [void]$sp.Children.Add($b2); [void]$g.Children.Add($sp)
        $Ui.BgList.Children.Insert(0, $g); $ErrBanner.Row = $g; $ErrBanner.Text = $t
    }
    $ErrBanner.N++
    $ErrBanner.Text.Text = 'Erreur : ' + $Msg + $(if ($ErrBanner.N -gt 1) { '  (et {0} autre{1})' -f ($ErrBanner.N - 1), $(if ($ErrBanner.N -gt 2) { 's' } else { '' }) } else { '' })
    $ErrBanner.Row.ToolTip = $Msg
    $Ui.BgBar.Visibility = 'Visible'
}
# Surveillance de l'interface : un fil de fond vérifie chaque seconde que la fenêtre répond (horodatage posé par le
# minuteur de l'interface) ; blocage de plus de 2 s consigné avec l'étape en cours (avertissement, ou erreur au-delà de
# 10 s), pour repérer et corriger chaque traitement trop long fait dans l'interface
$WatchdogScript = @'
while (-not $Sync.InfoStop) {
    Start-Sleep -Milliseconds 500
    $p = $Sync.UiPing; if (-not $p) { continue }
    $late = ([DateTime]::Now - $p).TotalSeconds
    if ($late -gt 2 -and -not $Sync.UiFreeze) { $Sync.UiFreeze = @{ Start = $p; Step = "$($Sync.UiStep)" } }
}
'@
function Watch-UiFreeze {
    $now = [DateTime]::Now; $f = $Sync.UiFreeze
    if ($f) {
        $Sync.UiFreeze = $null; $d = ($now - $f.Start).TotalSeconds
        # blocages de l'interface : plus signalés à l'écran (ni Journal ni bandeau), demande de l'utilisateur ; consignés dans
        # le fichier journal seulement, avec l'étape en cours, pour repérer les traitements trop longs (avant : mesure gardée
        # dans $Sync.UiFreezeLast, lue nulle part)
        try { Write-FileLog ('Interface bloquée {0:N1} s{1}' -f $d, $(if ($f.Step) { " ($($f.Step))" } else { '' })) 'WARN' } catch { $null = $_ }
    }
    $Sync.UiPing = $now
}
function Remove-BgActivity([string]$Key) {
    $a = $Activities[$Key]; if (-not $a) { return }
    [void]$Ui.BgList.Children.Remove($a.Row); $Activities.Remove($Key)
    if (-not $Activities.Count -and -not $ErrBanner.Row -and -not $UpdBanner.Row) { $Ui.BgBar.Visibility = 'Collapsed' }
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
    # lecture en échec 3 fois de suite : suivi arrêté (avant : une tâche relancée toutes les 4 s sans fin)
    if (-not $p -or $p.Err) {
        $BlWatch.Err = 1 + [int]$BlWatch.Err
        if ($BlWatch.Err -ge 3) { $BlWatch.Timer.Stop(); $BlWatch.Err = 0; Remove-BgActivity 'BitLocker'; Write-Ignored 'Suivi du chiffrement BitLocker' $(if ($p) { $p.Err } else { 'tâche interrompue' }) }
        return
    }
    $BlWatch.Err = 0
    $txt = $null; $pct = 0
    # états « en pause » : EncryptionPaused / DecryptionPaused (noms de Get-BitLockerVolume ; « Suspended », seuls testés
    # avant, n'existent pas : une pause arrêtait le suivi comme une fin)
    switch -Regex ($p.St) {
        '^EncryptionInProgress$' { $pct = $p.Pct; $txt = 'BitLocker ({0}) : chiffrement en cours  ·  {1:N1} %' -f $vol, $pct }
        '^DecryptionInProgress$' { $pct = 100 - $p.Pct; $txt = 'BitLocker ({0}) : déchiffrement en cours  ·  {1:N1} % effectué' -f $vol, $pct }
        '^Encryption(Paused|Suspended)$' { $pct = $p.Pct; $txt = 'BitLocker ({0}) : chiffrement en pause à {1:N1} % (reprise automatique par Windows)' -f $vol, $pct }
        '^Decryption(Paused|Suspended)$' { $pct = 100 - $p.Pct; $txt = 'BitLocker ({0}) : déchiffrement en pause à {1:N1} % effectué' -f $vol, $pct }
    }
    if ($txt) {
        $BlWatch.Was = $p.St
        Set-BgActivity 'BitLocker' $txt $pct 'Avancement réel du volume système, relu toutes les 4 secondes. Le PC reste utilisable ; un redémarrage ne fait que mettre en pause.' $null
        $ps = $(if ($p.St -match 'Paused|Suspended') { 'en pause' } else { 'en cours' })
        if ($InfoUI.BlValue) { $InfoUI.BlValue.Text = $(if ($p.St -like 'Encryption*') { 'chiffrement {0} ({1:N1} %)' -f $ps, $p.Pct } else { 'déchiffrement {0} ({1:N1} % restant chiffré)' -f $ps, $p.Pct }) }
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
