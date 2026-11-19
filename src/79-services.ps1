# ---------- Onglet Services : services Windows (Win32_Service), séparés en Microsoft / autres éditeurs
# Éditeur = CompanyName du fichier qui porte le service : l'exécutable, ou pour svchost.exe la DLL du service
# (Parameters\ServiceDll). Lecture et actions dans une tâche de fond (un arrêt peut attendre jusqu'à 30 s ou plus).
# Actions à l'unité : Démarrer / Arrêter (Stop-Service -Force : services dépendants arrêtés aussi), Désactiver
# (démarrage Désactivé + arrêt) / Réactiver (type de démarrage d'avant, mémorisé dans _etat\services-desactives.json).
$SvcUI = @{ Data = $null; Reading = $false; Busy = $null; Scope = 'All'; RunOnly = $false; Rows = @{}; Built = $false }
$SvcStateFile = Join-Path (Get-LogPath 'Etat') 'services-desactives.json'
# services indispensables à Windows ou à l'application : ni arrêt ni désactivation proposés
$SvcCritical = @('RpcSs', 'RpcEptMapper', 'DcomLaunch', 'LSM', 'SamSs', 'EventLog', 'EventSystem', 'PlugPlay', 'Power', 'BrokerInfrastructure',
    'CoreMessagingRegistrar', 'SystemEventsBroker', 'Schedule', 'ProfSvc', 'gpsvc', 'Winmgmt', 'UserManager', 'StateRepository', 'TimeBrokerSvc',
    'Dhcp', 'Dnscache', 'nsi', 'BFE', 'mpssvc', 'WinDefend', 'WdNisSvc', 'SecurityHealthService', 'Sense', 'TrustedInstaller', 'CryptSvc', 'KeyIso', 'AppXSvc', 'ClipSVC')
$SvcStartText = @{ Auto = 'Automatique'; Delayed = 'Automatique (différé)'; Manual = 'Manuel'; Disabled = 'Désactivé'; Boot = 'Démarrage'; System = 'Système' }

$SvcReadScript = @'
$items = [Collections.Generic.List[object]]::new()
try {
    $co = @{}
    $base = 'HKLM:\SYSTEM\CurrentControlSet\Services'
    foreach ($s in @(Get-CimInstance Win32_Service -ErrorAction Stop)) {
        $n = "$($s.Name)"; $p = "$($s.PathName)".Trim(); $exe = ''
        if ($p -match '^"([^"]+)"') { $exe = $Matches[1] } elseif ($p -match '^(.+?\.(exe|sys))(\s|$)') { $exe = $Matches[1] } else { $exe = ($p -split '\s')[0] }
        $exe = [Environment]::ExpandEnvironmentVariables($exe) -replace '^\\\?\?\\', '' -replace '^\\SystemRoot', $env:windir
        $img = $exe; $type = 0; $delayed = $false
        try {
            $k = Get-ItemProperty -LiteralPath (Join-Path $base $n) -ErrorAction Stop
            $type = [int]$k.Type; $delayed = [int]$k.DelayedAutostart -eq 1
            if ($exe -match '\\svchost\.exe$') {
                $dll = "$((Get-ItemProperty -LiteralPath (Join-Path $base "$n\Parameters") -ErrorAction SilentlyContinue).ServiceDll)"
                if (-not $dll) { $dll = "$($k.ServiceDll)" }
                if ($dll) { $img = [Environment]::ExpandEnvironmentVariables($dll) }
            }
        } catch { $null = $_ }
        if (-not $co.ContainsKey($img)) {
            $c = ''; try { if ($img -and (Test-Path -LiteralPath $img)) { $c = "$([Diagnostics.FileVersionInfo]::GetVersionInfo($img).CompanyName)".Trim() } } catch { $null = $_ }
            $co[$img] = $c
        }
        $start = "$($s.StartMode)"; if ($start -eq 'Auto' -and $delayed) { $start = 'Delayed' }
        $items.Add([pscustomobject]@{
            Name = $n; Disp = $(if ($s.DisplayName) { "$($s.DisplayName)" } else { $n }); Desc = "$($s.Description)"; State = "$($s.State)"; Start = $start
            Co = $co[$img]; Ms = $co[$img] -match '^Microsoft'; File = $img; Stop = [bool]$s.AcceptStop
            # service par utilisateur (modèle 0x40 ou instance 0x80) : type de démarrage géré par Windows
            User = [bool]($type -band 0xC0)
        })
    }
    $Sync.SvcRead = @{ Items = $items.ToArray(); Stamp = [DateTime]::Now }
} catch { $Sync.SvcRead = @{ Error = $_.Exception.Message } }
'@

$SvcActScript = @'
$a = $Sync.SvcActReq; $r = @{ Name = $a.Name; Op = $a.Op; Ok = $false; Msg = '' }
try {
    $sc = Join-Path $env:windir 'System32\sc.exe'
    switch ($a.Op) {
        'start' { Start-Service -Name $a.Name -ErrorAction Stop }
        'stop' { Stop-Service -Name $a.Name -Force -ErrorAction Stop }
        'disable' {
            $o = & $sc config $a.Name start= disabled 2>&1
            if ($LASTEXITCODE -ne 0) { throw $(if ($LASTEXITCODE -eq 5) { 'accès refusé (service protégé par Windows)' } else { "sc.exe code $LASTEXITCODE : $((@($o) -join ' ').Trim())" }) }
            if ((Get-Service -Name $a.Name -ErrorAction Stop).Status -ne 'Stopped') { Stop-Service -Name $a.Name -Force -ErrorAction Stop }
        }
        'enable' {
            $o = & $sc config $a.Name start= $a.Start 2>&1
            if ($LASTEXITCODE -ne 0) { throw $(if ($LASTEXITCODE -eq 5) { 'accès refusé (service protégé par Windows)' } else { "sc.exe code $LASTEXITCODE : $((@($o) -join ' ').Trim())" }) }
        }
    }
    $r.Ok = $true
} catch { $r.Msg = $_.Exception.Message }
try {
    $s = Get-CimInstance Win32_Service -Filter ("Name='{0}'" -f ($a.Name -replace "'", "''")) -ErrorAction Stop
    $d = [int](Get-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Services\$($a.Name)" -ErrorAction SilentlyContinue).DelayedAutostart -eq 1
    $r.State = "$($s.State)"; $r.Start = $(if ("$($s.StartMode)" -eq 'Auto' -and $d) { 'Delayed' } else { "$($s.StartMode)" }); $r.Stop = [bool]$s.AcceptStop
} catch { $null = $_ }
$Sync.SvcActRes = $r
'@

function Start-SvcRead {
    if ($SvcUI.Reading -or $SvcUI.Busy) { return }
    $SvcUI.Reading = $true; $Sync.SvcRead = $null
    $Ui.SvcProg.IsIndeterminate = $true; $Ui.SvcProg.Visibility = 'Visible'; $Ui.SvcRefresh.IsEnabled = $false
    $Ui.SvcStatus.Text = 'Lecture des services...'
    if (-not $SvcUI.Data) { $Ui.SvcEmpty.Text = 'Lecture des services...'; $Ui.SvcEmpty.Visibility = 'Visible' }
    Start-BgJob 'SvcRead' $SvcReadScript
}
$BgJobDone['SvcRead'] = {
    $SvcUI.Reading = $false; $Ui.SvcProg.Visibility = 'Collapsed'; $Ui.SvcRefresh.IsEnabled = $true
    $r = $Sync.SvcRead
    if (-not $r -or $r.Error) {
        $m = 'Lecture des services impossible : ' + $(if ($r) { $r.Error } else { 'tâche interrompue' })
        $Ui.SvcStatus.Text = $m; if (-not $SvcUI.Data) { $Ui.SvcEmpty.Text = $m }
        Write-UiLog $m 'ERROR'; return
    }
    $SvcUI.Data = @($r.Items | Sort-Object Disp); $SvcUI.Stamp = $r.Stamp
    Update-SvcList
}

# ligne : nom affiché + nom court, état (pastille), démarrage, éditeur, 2 boutons (Démarrer/Arrêter, Désactiver/Réactiver)
function New-SvcCol([double]$W) { $c = [Windows.Controls.ColumnDefinition]::new(); $c.Width = $(if ($W -gt 0) { [Windows.GridLength]::new($W) } else { [Windows.GridLength]::new(1, 'Star') }); $c }
function New-SvcRow($S) {
    $b = [Windows.Controls.Border]::new(); $b.Style = $Window.FindResource('SvcRow'); $b.Padding = New-Thickness 10 5 6 5; $b.DataContext = $S
    $g = [Windows.Controls.Grid]::new(); foreach ($w in 0, 120, 160, 190, 206) { [void]$g.ColumnDefinitions.Add((New-SvcCol $w)) }
    $np = [Windows.Controls.StackPanel]::new(); $np.Margin = New-Thickness 0 0 10 0; $np.VerticalAlignment = 'Center'
    $t1 = New-Text $S.Disp; $t1.FontWeight = [Windows.FontWeights]::SemiBold; $t1.TextTrimming = 'CharacterEllipsis'
    $t2 = New-Text $S.Name 'Muted'; $t2.FontSize = 11; $t2.TextTrimming = 'CharacterEllipsis'
    [void]$np.Children.Add($t1); [void]$np.Children.Add($t2); [void]$g.Children.Add($np)
    $sp = [Windows.Controls.StackPanel]::new(); $sp.Orientation = 'Horizontal'; $sp.VerticalAlignment = 'Center'
    $dot = [Windows.Shapes.Ellipse]::new(); $dot.Width = 8; $dot.Height = 8; $dot.Margin = New-Thickness 0 0 8 0; $dot.VerticalAlignment = 'Center'
    $st = New-Text ''; $st.VerticalAlignment = 'Center'
    [void]$sp.Children.Add($dot); [void]$sp.Children.Add($st); [Windows.Controls.Grid]::SetColumn($sp, 1); [void]$g.Children.Add($sp)
    $sm = New-Text ''; $sm.VerticalAlignment = 'Center'; [Windows.Controls.Grid]::SetColumn($sm, 2); [void]$g.Children.Add($sm)
    $co = New-Text $(if ($S.Co) { $S.Co } else { 'inconnu' }) 'Muted'; $co.VerticalAlignment = 'Center'; $co.TextTrimming = 'CharacterEllipsis'; $co.Margin = New-Thickness 0 0 10 0
    [Windows.Controls.Grid]::SetColumn($co, 3); [void]$g.Children.Add($co)
    $bp = [Windows.Controls.StackPanel]::new(); $bp.Orientation = 'Horizontal'; $bp.HorizontalAlignment = 'Right'; $bp.VerticalAlignment = 'Center'
    $b1 = New-Button 'Démarrer'; $b2 = New-Button 'Désactiver'
    foreach ($x in $b1, $b2) { $x.Width = 98; $x.MinWidth = 0; $x.Height = 28; $x.Padding = New-Thickness 6 0 6 0; $x.Margin = New-Thickness 4 0 0 0; $x.Tag = $S.Name; [void]$bp.Children.Add($x) }
    $b1.Add_Click({ param($s, $e) Invoke-SvcAction "$($s.Tag)" $(if ($s.DataContext -eq 'stop') { 'stop' } else { 'start' }) })
    $b2.Add_Click({ param($s, $e) Invoke-SvcAction "$($s.Tag)" "$($s.DataContext)" })
    [Windows.Controls.Grid]::SetColumn($bp, 4); [void]$g.Children.Add($bp)
    $b.Child = $g
    $b.ToolTip = (@($S.Desc, ('Fichier : ' + $(if ($S.File) { $S.File } else { 'inconnu' }))) | Where-Object { $_ }) -join "`n`n"
    $SvcUI.Rows[$S.Name] = @{ Row = $b; Dot = $dot; State = $st; Start = $sm; B1 = $b1; B2 = $b2 }
    Set-SvcRowLook $S.Name
    $b
}
function Set-SvcRowLook([string]$Name) {
    $r = $SvcUI.Rows[$Name]; if (-not $r) { return }
    $S = $r.Row.DataContext
    $run = $S.State -eq 'Running'; $dis = $S.Start -eq 'Disabled'; $crit = $S.Name -in $SvcCritical
    $r.State.Text = $(switch ($S.State) { 'Running' { 'En cours' } 'Stopped' { 'Arrêté' } 'Paused' { 'En pause' } 'Start Pending' { 'Démarrage...' } 'Stop Pending' { 'Arrêt...' } default { $S.State } })
    $r.Dot.SetResourceReference([Windows.Shapes.Shape]::FillProperty, $(if ($run) { 'OkFgBrush' } elseif ($dis) { 'ErrFgBrush' } else { 'MutedBrush' }))
    $r.Start.Text = $(if ($SvcStartText[$S.Start]) { $SvcStartText[$S.Start] } else { $S.Start })
    $r.Start.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, $(if ($dis) { 'ErrFgBrush' } else { 'FgBrush' }))
    $busy = [bool]$SvcUI.Busy
    # bouton 1 : Arrêter si démarré, sinon Démarrer (grisé si désactivé)
    $r.B1.DataContext = $(if ($run) { 'stop' } else { 'start' }); $r.B1.Content = $(if ($run) { 'Arrêter' } else { 'Démarrer' })
    $r.B1.IsEnabled = -not $busy -and $(if ($run) { $S.Stop -and -not $crit } else { -not $dis })
    $r.B1.ToolTip = $(if ($run -and $crit) { 'Service indispensable à Windows : arrêt non proposé' } elseif ($run -and -not $S.Stop) { 'Ce service refuse l''arrêt' } elseif (-not $run -and $dis) { 'Service désactivé : le réactiver d''abord' } else { $null })
    # bouton 2 : Désactiver / Réactiver
    $r.B2.DataContext = $(if ($dis) { 'enable' } else { 'disable' }); $r.B2.Content = $(if ($dis) { 'Réactiver' } else { 'Désactiver' })
    $r.B2.IsEnabled = -not $busy -and -not $crit -and -not $S.User -and $S.Start -notin 'Boot', 'System'
    $r.B2.ToolTip = $(if ($crit) { 'Service indispensable à Windows : désactivation non proposée' } elseif ($S.User) { 'Service par utilisateur : type de démarrage géré par Windows' } elseif ($dis) { 'Remet le type de démarrage d''avant la désactivation (Manuel si inconnu)' } else { 'Arrête le service et l''empêche de démarrer' })
}
function Test-SvcVisible($S, [string]$Q) {
    if ($SvcUI.Scope -eq 'Other' -and $S.Ms) { return $false }
    if ($SvcUI.Scope -eq 'Ms' -and -not $S.Ms) { return $false }
    if ($SvcUI.RunOnly -and $S.State -ne 'Running') { return $false }
    -not $Q -or $S.Disp -like "*$Q*" -or $S.Name -like "*$Q*" -or $S.Co -like "*$Q*"
}
function Update-SvcList {
    $d = $SvcUI.Data; if (-not $d) { return }
    # lignes reconstruites à chaque lecture (données neuves), puis filtrées par visibilité
    $Ui.SvcList.Children.Clear(); $SvcUI.Rows = @{}
    foreach ($s in $d) { [void]$Ui.SvcList.Children.Add((New-SvcRow $s)) }
    Update-SvcFilter
}
function Update-SvcFilter {
    $d = @($SvcUI.Data | Where-Object { $_ -and $_.Name }); $q = "$($Ui.SvcFind.Text)".Trim() -replace '[\[\]\*\?]', ''
    $n = 0
    foreach ($s in $d) {
        $r = $SvcUI.Rows[$s.Name]; if (-not $r) { continue }
        $v = Test-SvcVisible $s $q; $r.Row.Visibility = $(if ($v) { 'Visible' } else { 'Collapsed' }); if ($v) { $n++ }
    }
    $ms = @($d | Where-Object { $_.Ms }).Count
    $Ui.SvcFOther.Content = 'Autres éditeurs ({0})' -f ($d.Count - $ms); $Ui.SvcFMs.Content = 'Microsoft ({0})' -f $ms; $Ui.SvcFAll.Content = 'Tous ({0})' -f $d.Count
    foreach ($p in @(@($Ui.SvcFOther, 'Other'), @($Ui.SvcFMs, 'Ms'), @($Ui.SvcFAll, 'All'))) { $p[0].Tag = $(if ($p[1] -eq $SvcUI.Scope) { 'on' } else { '' }) }
    $Ui.SvcFRun.Tag = $(if ($SvcUI.RunOnly) { 'on' } else { '' })
    $Ui.SvcEmpty.Text = $(if ($n) { '' } elseif ($q) { 'Aucun service pour cette recherche.' } else { 'Aucun service dans cette vue.' })
    $Ui.SvcEmpty.Visibility = $(if ($n) { 'Collapsed' } else { 'Visible' })
    if (-not $SvcUI.Busy -and -not $SvcUI.Reading) {
        $run = @($d | Where-Object { $_.State -eq 'Running' }).Count
        $Ui.SvcStatus.Text = '{0} services affichés sur {1}  ·  {2} en cours  ·  lu {3}' -f $n, $d.Count, $run, (Format-Age $SvcUI.Stamp)
    }
}

# démarrage du type mémorisé à la désactivation (sc.exe : auto, delayed-auto, demand)
function Get-SvcSavedStart([string]$Name) {
    try { if (Test-Path -LiteralPath $SvcStateFile) { $j = Get-Content -LiteralPath $SvcStateFile -Raw -Encoding UTF8 | ConvertFrom-Json; $v = "$($j.$Name)"; if ($v -in 'auto', 'delayed-auto', 'demand') { return $v } } } catch { Write-Ignored 'Services désactivés' $_ }
    'demand'
}
function Save-SvcSavedStart([string]$Name, [string]$Start) {
    $h = [ordered]@{}
    try { if (Test-Path -LiteralPath $SvcStateFile) { $j = Get-Content -LiteralPath $SvcStateFile -Raw -Encoding UTF8 | ConvertFrom-Json; foreach ($p in $j.PSObject.Properties) { $h[$p.Name] = "$($p.Value)" } } } catch { Write-Ignored 'Services désactivés' $_ }
    if ($Start) { $h[$Name] = $Start } else { $h.Remove($Name) }
    try { [void][IO.Directory]::CreateDirectory((Split-Path $SvcStateFile)); [IO.File]::WriteAllText($SvcStateFile, ($h | ConvertTo-Json), [Text.UTF8Encoding]::new($false)) } catch { Write-Ignored 'Services désactivés' $_ }
}
function Invoke-SvcAction([string]$Name, [string]$Op) {
    $r = $SvcUI.Rows[$Name]; if (-not $r -or $SvcUI.Busy -or $SvcUI.Reading) { return }
    $S = $r.Row.DataContext
    $who = '« {0} » ({1})' -f $S.Disp, $S.Name
    $warn = $(if ($S.Ms) { "`n`nService Microsoft : une fonction de Windows peut cesser de marcher (son nom et sa description, au survol de la ligne, indiquent laquelle)." } else { '' })
    $start = ''
    switch ($Op) {
        'stop' {
            $dep = @(); try { $dep = @((Get-Service -Name $Name -ErrorAction Stop).DependentServices | Where-Object { $_.Status -eq 'Running' } | ForEach-Object { $_.DisplayName }) } catch { Write-Ignored 'Services dépendants' $_ }
            $m = "Arrêter le service $who ?" + $(if ($dep.Count) { "`n`nServices dépendants arrêtés aussi : " + ($dep -join ', ') + '.' } else { '' }) + $warn + "`n`nIl redémarre au prochain démarrage de Windows si son démarrage est automatique."
            if (-not (Confirm-Action $m)) { return }
        }
        'disable' {
            if (-not (Confirm-Action ("Désactiver le service $who ?`n`nIl est arrêté et ne démarre plus, même au démarrage de Windows. Réactivable ici (type de démarrage actuel mémorisé : {0})." -f $SvcStartText[$S.Start] + $warn))) { return }
            Save-SvcSavedStart $Name $(switch ($S.Start) { 'Auto' { 'auto' } 'Delayed' { 'delayed-auto' } default { 'demand' } })
        }
        'enable' { $start = Get-SvcSavedStart $Name }
    }
    $SvcUI.Busy = @{ Name = $Name; Op = $Op; Disp = $S.Disp; T0 = [DateTime]::Now }
    $Sync.SvcActReq = @{ Name = $Name; Op = $Op; Start = $start }; $Sync.SvcActRes = $null
    foreach ($k in @($SvcUI.Rows.Keys)) { $SvcUI.Rows[$k].B1.IsEnabled = $false; $SvcUI.Rows[$k].B2.IsEnabled = $false }
    $Ui.SvcRefresh.IsEnabled = $false; $Ui.SvcProg.IsIndeterminate = $true; $Ui.SvcProg.Visibility = 'Visible'
    Update-SvcBusyText
    # temps écoulé affiché pendant l'action (arrêt de service parfois long)
    if (-not $SvcUI.Timer) { $SvcUI.Timer = [Windows.Threading.DispatcherTimer]::new(); $SvcUI.Timer.Interval = [TimeSpan]::FromSeconds(1); $SvcUI.Timer.Add_Tick({ Update-SvcBusyText }) }
    $SvcUI.Timer.Start()
    Start-BgJob 'SvcAct' $SvcActScript
}
function Update-SvcBusyText {
    $b = $SvcUI.Busy; if (-not $b) { if ($SvcUI.Timer) { $SvcUI.Timer.Stop() }; return }
    $v = $(switch ($b.Op) { 'start' { 'Démarrage' } 'stop' { 'Arrêt' } 'disable' { 'Désactivation' } default { 'Réactivation' } })
    $Ui.SvcStatus.Text = '{0} de « {1} »  ·  {2:mm\:ss}' -f $v, $b.Disp, ([DateTime]::Now - $b.T0)
}
$BgJobDone['SvcAct'] = {
    $b = $SvcUI.Busy; $SvcUI.Busy = $null; if ($SvcUI.Timer) { $SvcUI.Timer.Stop() }
    $Ui.SvcProg.Visibility = 'Collapsed'; $Ui.SvcRefresh.IsEnabled = $true
    $r = $Sync.SvcActRes
    if ($b -and $r) {
        $row = $SvcUI.Rows[$b.Name]
        if ($row -and $r.State) { $row.Row.DataContext.State = $r.State; $row.Row.DataContext.Start = $r.Start; $row.Row.DataContext.Stop = $r.Stop }
        $v = $(switch ($b.Op) { 'start' { 'démarré' } 'stop' { 'arrêté' } 'disable' { 'désactivé' } default { 'réactivé' } })
        if ($r.Ok) {
            if ($b.Op -eq 'enable') { Save-SvcSavedStart $b.Name '' }
            Write-UiLog ('Service « {0} » ({1}) {2}.' -f $b.Disp, $b.Name, $v) 'OK'
            Add-SessionEvent 'Réglages' ('Service ' + $b.Disp) $v 'ok'
        } else {
            Write-UiLog ('Service « {0} » ({1}) non {2} : {3}' -f $b.Disp, $b.Name, $v, $r.Msg) 'ERROR'
            Add-SessionEvent 'Réglages' ('Service ' + $b.Disp) "échec : $($r.Msg)" 'error'
            Show-Info ("Service « {0} » non {1}.`n`n{2}" -f $b.Disp, $v, $r.Msg) 'Error'
        }
    }
    foreach ($k in @($SvcUI.Rows.Keys)) { Set-SvcRowLook $k }
    Update-SvcFilter
}

# filtres et recherche (recalcul 200 ms après la dernière frappe)
foreach ($p in @(@($Ui.SvcFOther, 'Other'), @($Ui.SvcFMs, 'Ms'), @($Ui.SvcFAll, 'All'))) {
    $p[0].DataContext = $p[1]; $p[0].Add_Click({ param($s, $e) $SvcUI.Scope = "$($s.DataContext)"; Update-SvcFilter; $Ui.SvcScroll.ScrollToTop() })
}
$Ui.SvcFRun.Add_Click({ $SvcUI.RunOnly = -not $SvcUI.RunOnly; Update-SvcFilter; $Ui.SvcScroll.ScrollToTop() })
$Ui.SvcRefresh.Add_Click({ Start-SvcRead })
$SvcUI.FindTimer = [Windows.Threading.DispatcherTimer]::new(); $SvcUI.FindTimer.Interval = [TimeSpan]::FromMilliseconds(200)
$SvcUI.FindTimer.Add_Tick({ $SvcUI.FindTimer.Stop(); Update-SvcFilter })
$Ui.SvcFind.Add_TextChanged({ $Ui.SvcFindHint.Visibility = $(if ($Ui.SvcFind.Text) { 'Collapsed' } else { 'Visible' }); $SvcUI.FindTimer.Stop(); $SvcUI.FindTimer.Start() })
$Ui.SvcFind.Add_GotKeyboardFocus({ $Ui.SvcFindBox.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, 'AccentBrush') })
$Ui.SvcFind.Add_LostKeyboardFocus({ $Ui.SvcFindBox.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, 'LineBrush') })
$Ui.SvcFindBox.Add_MouseLeftButtonDown({ [void]$Ui.SvcFind.Focus() })
# en-tête aligné sur les lignes : marge droite = largeur réelle de la barre de défilement
$Ui.SvcScroll.Add_SizeChanged({ $sb = [math]::Max([double]0, $Ui.SvcScroll.ActualWidth - $Ui.SvcScroll.ViewportWidth); $Ui.SvcHead.Margin = New-Thickness 14 8 (10 + $sb) 6 })
