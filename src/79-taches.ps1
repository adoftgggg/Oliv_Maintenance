# ---------- Onglet Services et tâches, vue Tâches planifiées : même présentation que les services
# Lecture par l'interface COM du Planificateur (Schedule.Service, tâches masquées comprises), plus rapide que
# Get-ScheduledTaskInfo tâche par tâche. Microsoft = dossier \Microsoft ou auteur Microsoft. Actions à l'unité :
# Lancer / Arrêter (IRegisteredTask.Run / Stop), Désactiver / Activer (IRegisteredTask.Enabled).
$TskUI = @{ Data = $null; Reading = $false; Busy = $null; Scope = 'All'; RunOnly = $false; Rows = @{} }
$SvcUI.Mode = 'Svc'
function Set-SvcMode([string]$Mode) {
    $SvcUI.Mode = $Mode
    $Ui.SvcModeSvc.Tag = $(if ($Mode -eq 'Svc') { 'on' } else { '' }); $Ui.SvcModeTsk.Tag = $(if ($Mode -eq 'Tsk') { 'on' } else { '' })
    $Ui.SvcView.Visibility = $(if ($Mode -eq 'Svc') { 'Visible' } else { 'Collapsed' }); $Ui.TskView.Visibility = $(if ($Mode -eq 'Tsk') { 'Visible' } else { 'Collapsed' })
    if ($Mode -eq 'Tsk' -and -not $TskUI.Data -and -not $TskUI.Reading) { Start-TskRead }
    if ($Mode -eq 'Svc' -and -not $SvcUI.Data -and -not $SvcUI.Reading) { Start-SvcRead }
}
$Ui.SvcModeSvc.Add_Click({ Set-SvcMode 'Svc' })
$Ui.SvcModeTsk.Add_Click({ Set-SvcMode 'Tsk' })

$TskReadScript = @'
$items = [Collections.Generic.List[object]]::new()
function Get-Ind([string]$S) { if ($S -match '^\$\((@.+)\)$') { $S = $Matches[1] }; if ($S -like '@*') { try { $v = [_OlivM.Shell]::Indirect($S); if ($v) { return $v } } catch { $null = $_ } }; $S }
try {
    $svc = New-Object -ComObject Schedule.Service; $svc.Connect()
    $stack = [Collections.Stack]::new(); $stack.Push($svc.GetFolder('\'))
    while ($stack.Count) {
        $f = $stack.Pop()
        try { foreach ($sub in @($f.GetFolders(0))) { $stack.Push($sub) } } catch { $null = $_ }
        $ts = @(); try { $ts = @($f.GetTasks(1)) } catch { continue }
        foreach ($t in $ts) {
            try {
                $d = $t.Definition; $au = Get-Ind "$($d.RegistrationInfo.Author)"
                $act = @(foreach ($a in $d.Actions) { if ($a.Type -eq 0) { ('{0} {1}' -f $a.Path, $a.Arguments).Trim() } elseif ($a.Type -eq 5) { 'Objet COM ' + $a.ClassId } else { 'Action de type ' + $a.Type } })
                $last = [DateTime]$t.LastRunTime; $next = [DateTime]$t.NextRunTime
                $items.Add([pscustomobject]@{
                    Key = "$($t.Path)"; Name = "$($t.Name)"; Folder = "$($f.Path)"; State = [int]$t.State; Enabled = [bool]$t.Enabled
                    Last = $(if ($last.Year -gt 1900) { $last } else { $null }); Next = $(if ($next.Year -gt 1900) { $next } else { $null }); Res = [int]$t.LastTaskResult
                    Author = $au; Desc = (Get-Ind "$($d.RegistrationInfo.Description)"); Act = ($act -join "`n")
                    Ms = "$($f.Path)" -like '\Microsoft*' -or $au -match '^Microsoft'
                })
            } catch { $null = $_ }
        }
    }
    $Sync.TskRead = @{ Items = $items.ToArray(); Stamp = [DateTime]::Now }
} catch { $Sync.TskRead = @{ Error = $_.Exception.Message } }
'@
$TskActScript = @'
$a = $Sync.TskActReq; $r = @{ Key = $a.Key; Op = $a.Op; Ok = $false; Msg = '' }
try {
    $svc = New-Object -ComObject Schedule.Service; $svc.Connect()
    $t = $svc.GetFolder($a.Folder).GetTask($a.Name)
    switch ($a.Op) {
        'run' { [void]$t.Run($null) }
        'stop' { $t.Stop(0) }
        'disable' { $t.Enabled = $false }
        'enable' { $t.Enabled = $true }
    }
    if ($a.Op -eq 'run') { Start-Sleep -Milliseconds 800 }
    $r.State = [int]$t.State; $r.Enabled = [bool]$t.Enabled; $r.Res = [int]$t.LastTaskResult
    $l = [DateTime]$t.LastRunTime; $n = [DateTime]$t.NextRunTime
    $r.Last = $(if ($l.Year -gt 1900) { $l } else { $null }); $r.Next = $(if ($n.Year -gt 1900) { $n } else { $null })
    $r.Ok = $true
} catch {
    $e = $_.Exception; while ($e.InnerException) { $e = $e.InnerException }
    $r.Msg = $(if ($e.HResult -eq -2147024891) { 'accès refusé (tâche protégée par Windows)' } else { $e.Message })
}
$Sync.TskActRes = $r
'@

function Start-TskRead {
    if ($TskUI.Reading -or $TskUI.Busy) { return }
    $TskUI.Reading = $true; $Sync.TskRead = $null
    $Ui.TskProg.IsIndeterminate = $true; $Ui.TskProg.Visibility = 'Visible'; $Ui.TskRefresh.IsEnabled = $false
    $Ui.TskStatus.Text = 'Lecture des tâches planifiées...'
    if (-not $TskUI.Data) { $Ui.TskEmpty.Text = 'Lecture des tâches planifiées...'; $Ui.TskEmpty.Visibility = 'Visible' }
    Start-BgJob 'TskRead' $TskReadScript
}
$BgJobDone['TskRead'] = {
    $TskUI.Reading = $false; $Ui.TskProg.Visibility = 'Collapsed'; $Ui.TskRefresh.IsEnabled = $true
    $r = $Sync.TskRead
    if (-not $r -or $r.Error) {
        $m = 'Lecture des tâches planifiées impossible : ' + $(if ($r) { $r.Error } else { 'tâche interrompue' })
        $Ui.TskStatus.Text = $m; if (-not $TskUI.Data) { $Ui.TskEmpty.Text = $m }
        Write-UiLog $m 'ERROR'; return
    }
    $TskUI.Data = @($r.Items | Sort-Object Ms, Name); $TskUI.Stamp = $r.Stamp
    $Ui.TskList.Children.Clear(); $TskUI.Rows = @{}
    foreach ($t in $TskUI.Data) { [void]$Ui.TskList.Children.Add((New-TskRow $t)) }
    Update-TskFilter
}
# date courte : aujourd'hui / hier / date
function Format-TskDate($D) {
    if (-not $D) { return 'jamais' }
    $d = [DateTime]$D; $days = ([DateTime]::Today - $d.Date).Days
    $(if ($days -eq 0) { "aujourd'hui {0:HH:mm}" -f $d } elseif ($days -eq 1) { 'hier {0:HH:mm}' -f $d } elseif ($days -eq -1) { 'demain {0:HH:mm}' -f $d } else { '{0:dd/MM/yyyy HH:mm}' -f $d })
}
# résultat de la dernière exécution (codes SCHED_S_* / SCHED_E_* courants)
function Get-TskResultText([int]$Res, $Last) {
    if (-not $Last) { return '' }
    switch ($Res) { 0 { 'réussie' } 267009 { 'en cours' } 267011 { 'pas encore lancée' } 267014 { 'arrêtée' } -2147020576 { 'opérateur ou administrateur a refusé' } default { 'code 0x{0:X8}' -f $Res } }
}
function New-TskRow($T) {
    $b = [Windows.Controls.Border]::new(); $b.Style = $Window.FindResource('SvcRow'); $b.Padding = New-Thickness 10 5 6 5; $b.DataContext = $T
    $g = [Windows.Controls.Grid]::new(); foreach ($w in 0, 120, 160, 190, 206) { [void]$g.ColumnDefinitions.Add((New-SvcCol $w)) }
    $np = [Windows.Controls.StackPanel]::new(); $np.Margin = New-Thickness 0 0 10 0; $np.VerticalAlignment = 'Center'
    $t1 = New-Text $T.Name; $t1.FontWeight = [Windows.FontWeights]::SemiBold; $t1.TextTrimming = 'CharacterEllipsis'
    $t2 = New-Text $T.Folder 'Muted'; $t2.FontSize = 11; $t2.TextTrimming = 'CharacterEllipsis'
    [void]$np.Children.Add($t1); [void]$np.Children.Add($t2); [void]$g.Children.Add($np)
    $sp = [Windows.Controls.StackPanel]::new(); $sp.Orientation = 'Horizontal'; $sp.VerticalAlignment = 'Center'
    $dot = [Windows.Shapes.Ellipse]::new(); $dot.Width = 8; $dot.Height = 8; $dot.Margin = New-Thickness 0 0 8 0; $dot.VerticalAlignment = 'Center'
    $st = New-Text ''; $st.VerticalAlignment = 'Center'
    [void]$sp.Children.Add($dot); [void]$sp.Children.Add($st); [Windows.Controls.Grid]::SetColumn($sp, 1); [void]$g.Children.Add($sp)
    $lp = [Windows.Controls.StackPanel]::new(); $lp.VerticalAlignment = 'Center'; $lp.Margin = New-Thickness 0 0 8 0
    $l1 = New-Text ''; $l2 = New-Text '' 'Muted'; $l2.FontSize = 11
    [void]$lp.Children.Add($l1); [void]$lp.Children.Add($l2); [Windows.Controls.Grid]::SetColumn($lp, 2); [void]$g.Children.Add($lp)
    $nx = New-Text ''; $nx.VerticalAlignment = 'Center'; [Windows.Controls.Grid]::SetColumn($nx, 3); [void]$g.Children.Add($nx)
    $bp = [Windows.Controls.StackPanel]::new(); $bp.Orientation = 'Horizontal'; $bp.HorizontalAlignment = 'Right'; $bp.VerticalAlignment = 'Center'
    $b1 = New-Button 'Lancer'; $b2 = New-Button 'Désactiver'
    foreach ($x in $b1, $b2) { $x.Width = 98; $x.MinWidth = 0; $x.Height = 28; $x.Padding = New-Thickness 6 0 6 0; $x.Margin = New-Thickness 4 0 0 0; $x.Tag = $T.Key; [void]$bp.Children.Add($x) }
    $b1.Add_Click({ param($s, $e) Invoke-TskAction "$($s.Tag)" "$($s.DataContext)" })
    $b2.Add_Click({ param($s, $e) Invoke-TskAction "$($s.Tag)" "$($s.DataContext)" })
    [Windows.Controls.Grid]::SetColumn($bp, 4); [void]$g.Children.Add($bp)
    $b.Child = $g
    $b.ToolTip = (@($T.Desc, $(if ($T.Author) { 'Auteur : ' + $T.Author }), $(if ($T.Act) { "Action :`n" + $T.Act })) | Where-Object { $_ }) -join "`n`n"
    $TskUI.Rows[$T.Key] = @{ Row = $b; Dot = $dot; State = $st; L1 = $l1; L2 = $l2; Next = $nx; B1 = $b1; B2 = $b2 }
    Set-TskRowLook $T.Key
    $b
}
function Set-TskRowLook([string]$Key) {
    $r = $TskUI.Rows[$Key]; if (-not $r) { return }
    $T = $r.Row.DataContext; $run = $T.State -eq 4; $busy = [bool]$TskUI.Busy
    $r.State.Text = $(if ($run) { 'En cours' } elseif (-not $T.Enabled) { 'Désactivée' } else { 'Prête' })
    $r.Dot.SetResourceReference([Windows.Shapes.Shape]::FillProperty, $(if ($run) { 'OkFgBrush' } elseif (-not $T.Enabled) { 'ErrFgBrush' } else { 'MutedBrush' }))
    $r.L1.Text = Format-TskDate $T.Last; $r.L2.Text = Get-TskResultText $T.Res $T.Last
    $r.L2.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, $(if ($T.Last -and $T.Res -notin 0, 267009, 267011, 267014) { 'ErrFgBrush' } else { 'MutedBrush' }))
    $r.L2.Visibility = $(if ($r.L2.Text) { 'Visible' } else { 'Collapsed' })
    $r.Next.Text = $(if (-not $T.Enabled) { '-' } elseif ($T.Next) { Format-TskDate $T.Next } else { 'sur événement' })
    $r.B1.DataContext = $(if ($run) { 'stop' } else { 'run' }); $r.B1.Content = $(if ($run) { 'Arrêter' } else { 'Lancer' })
    $r.B1.IsEnabled = -not $busy -and ($run -or $T.Enabled)
    $r.B1.ToolTip = $(if (-not $run -and -not $T.Enabled) { 'Tâche désactivée : l''activer d''abord' } else { $null })
    $r.B2.DataContext = $(if ($T.Enabled) { 'disable' } else { 'enable' }); $r.B2.Content = $(if ($T.Enabled) { 'Désactiver' } else { 'Activer' })
    $r.B2.IsEnabled = -not $busy
}
function Update-TskFilter {
    $d = @($TskUI.Data | Where-Object { $_ -and $_.Key }); $q = "$($Ui.TskFind.Text)".Trim() -replace '[\[\]\*\?]', ''
    $n = 0
    foreach ($t in $d) {
        $r = $TskUI.Rows[$t.Key]; if (-not $r) { continue }
        $v = -not (($TskUI.Scope -eq 'Other' -and $t.Ms) -or ($TskUI.Scope -eq 'Ms' -and -not $t.Ms) -or ($TskUI.RunOnly -and -not $t.Enabled)) -and
            (-not $q -or $t.Name -like "*$q*" -or $t.Folder -like "*$q*" -or $t.Author -like "*$q*" -or $t.Act -like "*$q*")
        $r.Row.Visibility = $(if ($v) { 'Visible' } else { 'Collapsed' }); if ($v) { $n++ }
    }
    $ms = @($d | Where-Object { $_.Ms }).Count
    $Ui.TskFOther.Content = 'Autres éditeurs ({0})' -f ($d.Count - $ms); $Ui.TskFMs.Content = 'Microsoft ({0})' -f $ms; $Ui.TskFAll.Content = 'Toutes ({0})' -f $d.Count
    foreach ($p in @(@($Ui.TskFOther, 'Other'), @($Ui.TskFMs, 'Ms'), @($Ui.TskFAll, 'All'))) { $p[0].Tag = $(if ($p[1] -eq $TskUI.Scope) { 'on' } else { '' }) }
    $Ui.TskFRun.Tag = $(if ($TskUI.RunOnly) { 'on' } else { '' })
    $Ui.TskEmpty.Text = $(if ($n) { '' } elseif ($q) { 'Aucune tâche pour cette recherche.' } else { 'Aucune tâche dans cette vue.' })
    $Ui.TskEmpty.Visibility = $(if ($n) { 'Collapsed' } else { 'Visible' })
    if (-not $TskUI.Busy -and -not $TskUI.Reading) {
        $off = @($d | Where-Object { -not $_.Enabled }).Count
        $Ui.TskStatus.Text = '{0} tâches affichées sur {1}  ·  {2} désactivées  ·  lu {3}  ·  détail (auteur, programme lancé) au survol' -f $n, $d.Count, $off, (Format-Age $TskUI.Stamp)
    }
}
function Invoke-TskAction([string]$Key, [string]$Op) {
    $r = $TskUI.Rows[$Key]; if (-not $r -or $TskUI.Busy -or $TskUI.Reading) { return }
    $T = $r.Row.DataContext
    $warn = $(if ($T.Ms) { "`n`nTâche Microsoft : une fonction de Windows (mise à jour, maintenance, diagnostic) peut ne plus s'exécuter." } else { '' })
    if ($Op -eq 'disable' -and -not (Confirm-Action ((("Désactiver la tâche « {0} » ({1}) ?`n`nElle ne se lance plus, ni à l'heure prévue ni sur événement. Réactivable ici." -f $T.Name, $T.Folder)) + $warn))) { return }
    if ($Op -eq 'stop' -and -not (Confirm-Action ('Arrêter la tâche « {0} » en cours ?' -f $T.Name))) { return }
    $TskUI.Busy = @{ Key = $Key; Op = $Op; Name = $T.Name; T0 = [DateTime]::Now }
    $Sync.TskActReq = @{ Key = $Key; Op = $Op; Folder = $T.Folder; Name = $T.Name }; $Sync.TskActRes = $null
    foreach ($k in @($TskUI.Rows.Keys)) { $TskUI.Rows[$k].B1.IsEnabled = $false; $TskUI.Rows[$k].B2.IsEnabled = $false }
    $Ui.TskRefresh.IsEnabled = $false; $Ui.TskProg.Visibility = 'Visible'
    $Ui.TskStatus.Text = '{0} de « {1} »...' -f $(switch ($Op) { 'run' { 'Lancement' } 'stop' { 'Arrêt' } 'disable' { 'Désactivation' } default { 'Activation' } }), $T.Name
    Start-BgJob 'TskAct' $TskActScript
}
$BgJobDone['TskAct'] = {
    $b = $TskUI.Busy; $TskUI.Busy = $null
    $Ui.TskProg.Visibility = 'Collapsed'; $Ui.TskRefresh.IsEnabled = $true
    $r = $Sync.TskActRes
    if ($b -and $r) {
        $row = $TskUI.Rows[$b.Key]
        $v = $(switch ($b.Op) { 'run' { 'lancée' } 'stop' { 'arrêtée' } 'disable' { 'désactivée' } default { 'activée' } })
        if ($r.Ok) {
            if ($row) { $o = $row.Row.DataContext; $o.State = $r.State; $o.Enabled = $r.Enabled; $o.Res = $r.Res; $o.Last = $r.Last; $o.Next = $r.Next }
            Write-UiLog ('Tâche planifiée « {0} » {1}.' -f $b.Name, $v) 'OK'; Add-SessionEvent 'Réglages' ('Tâche ' + $b.Name) $v 'ok'
        } else {
            Write-UiLog ('Tâche planifiée « {0} » non {1} : {2}' -f $b.Name, $v, $r.Msg) 'ERROR'
            Show-Info ("Tâche « {0} » non {1}.`n`n{2}" -f $b.Name, $v, $r.Msg) 'Error'
        }
    }
    foreach ($k in @($TskUI.Rows.Keys)) { Set-TskRowLook $k }
    Update-TskFilter
}
foreach ($p in @(@($Ui.TskFOther, 'Other'), @($Ui.TskFMs, 'Ms'), @($Ui.TskFAll, 'All'))) {
    $p[0].DataContext = $p[1]; $p[0].Add_Click({ param($s, $e) $TskUI.Scope = "$($s.DataContext)"; Update-TskFilter; $Ui.TskScroll.ScrollToTop() })
}
$Ui.TskFRun.Add_Click({ $TskUI.RunOnly = -not $TskUI.RunOnly; Update-TskFilter; $Ui.TskScroll.ScrollToTop() })
$Ui.TskRefresh.Add_Click({ Start-TskRead })
$TskUI.FindTimer = [Windows.Threading.DispatcherTimer]::new(); $TskUI.FindTimer.Interval = [TimeSpan]::FromMilliseconds(200)
$TskUI.FindTimer.Add_Tick({ $TskUI.FindTimer.Stop(); Update-TskFilter })
$Ui.TskFind.Add_TextChanged({ $Ui.TskFindHint.Visibility = $(if ($Ui.TskFind.Text) { 'Collapsed' } else { 'Visible' }); $TskUI.FindTimer.Stop(); $TskUI.FindTimer.Start() })
$Ui.TskFind.Add_GotKeyboardFocus({ $Ui.TskFindBox.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, 'AccentBrush') })
$Ui.TskFind.Add_LostKeyboardFocus({ $Ui.TskFindBox.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, 'LineBrush') })
$Ui.TskFindBox.Add_MouseLeftButtonDown({ [void]$Ui.TskFind.Focus() })
$Ui.TskScroll.Add_SizeChanged({ $sb = [math]::Max([double]0, $Ui.TskScroll.ActualWidth - $Ui.TskScroll.ViewportWidth); $Ui.TskHead.Margin = New-Thickness 14 8 (10 + $sb) 6 })
