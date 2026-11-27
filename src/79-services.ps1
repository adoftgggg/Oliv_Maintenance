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
    'Dhcp', 'Dnscache', 'nsi', 'BFE', 'mpssvc', 'WinDefend', 'WdNisSvc', 'SecurityHealthService', 'Sense', 'TrustedInstaller', 'CryptSvc', 'KeyIso', 'AppXSvc', 'ClipSVC',
    # élévation (UAC : l'application elle-même ne pourrait plus se relancer en administrateur), réseau, son, coffre des identifiants, installeur
    'Appinfo', 'Wcmsvc', 'netprofm', 'NlaSvc', 'LanmanWorkstation', 'WlanSvc', 'Netman', 'Audiosrv', 'AudioEndpointBuilder', 'VaultSvc', 'msiserver', 'wscsvc')
# importance affichée à côté du nom : Critique (arrêt et désactivation bloqués), Désactivable si... (service de Windows
# inutile dans un cas précis), Windows (à laisser par défaut), Logiciel (installé par un logiciel : utile tant qu'il sert)
$SvcOptional = @{
    Fax = 'aucun fax n''est utilisé'; Spooler = 'aucune imprimante (ni impression PDF) n''est utilisée'; PrintNotify = 'aucune imprimante n''est utilisée'
    bthserv = 'aucun appareil Bluetooth n''est utilisé'; BTAGService = 'aucun casque Bluetooth n''est utilisé'; WSearch = 'la recherche de fichiers n''est pas utilisée (recherche alors plus lente)'
    SysMain = 'le disque système est un SSD rapide (préchargement des programmes)'; DiagTrack = 'télémétrie envoyée à Microsoft : désactivable'; dmwappushservice = 'télémétrie : désactivable'
    MapsBroker = 'l''application Cartes n''est pas utilisée'; RetailDemo = 'toujours (mode démo des magasins)'; WMPNetworkSvc = 'le partage de bibliothèque Windows Media n''est pas utilisé'
    XblAuthManager = 'aucun jeu Xbox / Game Pass'; XblGameSave = 'aucun jeu Xbox / Game Pass'; XboxNetApiSvc = 'aucun jeu Xbox / Game Pass'; XboxGipSvc = 'aucune manette ou accessoire Xbox'
    RemoteRegistry = 'toujours sur un PC personnel (accès au registre à distance)'; PhoneSvc = 'aucune téléphonie (Mobile connecté, appels)'; lfsvc = 'la localisation n''est pas utilisée'
    WbioSrvc = 'aucun lecteur d''empreinte ni reconnaissance faciale (Windows Hello biométrique)'; wisvc = 'pas d''inscription au programme Windows Insider'
    SCardSvr = 'aucune carte à puce'; ScDeviceEnum = 'aucune carte à puce'; stisvc = 'aucun scanner ni appareil photo branché'; TermService = 'le Bureau à distance entrant n''est pas utilisé'
    SessionEnv = 'le Bureau à distance entrant n''est pas utilisé'; UmRdpService = 'le Bureau à distance entrant n''est pas utilisé'; WerSvc = 'les rapports d''erreurs envoyés à Microsoft ne sont pas souhaités'
    PcaSvc = 'l''assistant de compatibilité des anciens programmes n''est pas souhaité'; icssvc = 'le point d''accès mobile (partage de connexion) n''est pas utilisé'
    SharedAccess = 'le partage de connexion Internet n''est pas utilisé'; WpcMonSvc = 'le contrôle parental n''est pas utilisé'; Wecsvc = 'toujours sur un PC personnel (collecte d''événements d''entreprise)'
    TrkWks = 'aucun partage de fichiers en réseau d''entreprise'; edgeupdate = 'jamais conseillé : Edge ne serait plus mis à jour'; edgeupdatem = 'jamais conseillé : Edge ne serait plus mis à jour'
    gupdate = 'jamais conseillé : Google Chrome ne serait plus mis à jour'; gupdatem = 'jamais conseillé : Google Chrome ne serait plus mis à jour'; Netlogon = 'le PC n''est pas joint à un domaine'
    WinRM = 'aucune administration à distance (PowerShell à distance)'; AJRouter = 'aucun appareil connecté AllJoyn'; FrameServerMonitor = 'aucune caméra'; MixedRealityOpenXRSvc = 'aucun casque de réalité mixte'
}
function Get-SvcLevel($S) {
    if ($S.Name -in $SvcCritical) { return @{ L = 'Critique'; B = 'ErrFgBrush'; T = 'Indispensable à Windows ou à sa sécurité : arrêt et désactivation bloqués.' } }
    $n = ("$($S.Name)" -split '_')[0]
    if ($SvcOptional.ContainsKey($n)) { $c = $SvcOptional[$n]; return @{ L = $(if ($c -like 'jamais*') { 'À garder' } else { 'Désactivable' }); B = $(if ($c -like 'jamais*') { 'WarnFgBrush' } else { 'OkFgBrush' }); T = $(if ($c -like 'jamais*' -or $c -like 'toujours*') { $c.Substring(0, 1).ToUpper() + $c.Substring(1) + '.' } else { "Désactivable si $c." }) } }
    if ($S.Ms) { return @{ L = 'Windows'; B = 'MutedBrush'; T = 'Service de Windows : à laisser tel quel sauf besoin précis.' } }
    @{ L = 'Logiciel'; B = 'AccentBrush'; T = 'Installé par ' + $(if ($S.Co) { $S.Co } else { 'un logiciel' }) + ' : utile tant que ce logiciel est utilisé ; s''il ne sert plus, le désinstaller plutôt que désactiver le service.' }
}
# pastille d'importance (petit cadre coloré, explication au survol)
function New-LevelBadge($Lv) {
    $b = [Windows.Controls.Border]::new(); $b.CornerRadius = [Windows.CornerRadius]::new(8); $b.BorderThickness = New-Thickness 1 1 1 1; $b.Padding = New-Thickness 6 0 6 1; $b.Margin = New-Thickness 8 1 0 0; $b.VerticalAlignment = 'Center'
    $b.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, $Lv.B)
    $t = New-Text $Lv.L; $t.FontSize = 10.5; $t.TextWrapping = 'NoWrap'; $t.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, $Lv.B)
    $b.Child = $t; $b
}
# cellule « importance » : pastille + « ? » (explication au survol ou au clic)
function New-LevelCell($Lv) {
    $sp = [Windows.Controls.StackPanel]::new(); $sp.Orientation = 'Horizontal'; $sp.VerticalAlignment = 'Center'
    $bd = New-LevelBadge $Lv; $bd.Margin = New-Thickness 0 1 0 0; [void]$sp.Children.Add($bd)
    $hm = New-HelpMark $Lv.T; $hm.Margin = New-Thickness 6 0 0 0; [void]$sp.Children.Add($hm); $sp
}
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

# ---- listes gardées en local (services, tâches) : affichées tout de suite à l'ouverture, puis actualisées en arrière-plan ;
# lignes existantes mises à jour sur place (pas de reconstruction), reconstruction seulement si des éléments
# apparaissent ou disparaissent
function Read-ListCache([string]$Name) {
    $f = Join-Path (Get-LogPath 'Etat') "liste-$Name.json"
    try { if (Test-Path -LiteralPath $f) { $j = Get-Content -LiteralPath $f -Raw -Encoding UTF8 | ConvertFrom-Json; return @{ Items = @($j.Items | Where-Object { $_ }); Stamp = [DateTime]::Parse("$($j.Stamp)", [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind) } } } catch { Write-Ignored "Liste enregistrée ($Name)" $_ }
    $null
}
function Save-ListCache([string]$Name, $Items, $Stamp) {
    $f = Join-Path (Get-LogPath 'Etat') "liste-$Name.json"
    try { ConvertTo-Json -InputObject @{ Stamp = ([DateTime]$Stamp).ToString('o'); Items = @($Items) } -Depth 3 -Compress | Set-Content -LiteralPath $f -Encoding UTF8 } catch { Write-Ignored "Liste enregistrée ($Name)" $_ }
}
# (paramètre $ListUI et non $UI : PowerShell ne distingue pas la casse, $UI masquerait $Ui de la fenêtre principale
# pour les fonctions appelées pendant la fusion)
function Merge-ListData($ListUI, [string]$KeyProp, $New, [scriptblock]$Rebuild, [scriptblock]$Look) {
    $nk = @($New | ForEach-Object { "$($_.$KeyProp)" } | Sort-Object); $ok = @($ListUI.Data | Where-Object { $_ } | ForEach-Object { "$($_.$KeyProp)" } | Sort-Object)
    if (-not $ListUI.Rows -or -not $ListUI.Rows.Count -or ($nk -join '|') -ne ($ok -join '|')) { $ListUI.Data = @($New); & $Rebuild; return }
    foreach ($n in $New) {
        $k = "$($n.$KeyProp)"; $r = $ListUI.Rows[$k]; if (-not $r) { continue }
        $o = $r.Row.DataContext
        foreach ($p in $n.PSObject.Properties) { $o | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value -Force }
        & $Look $k
    }
}
function Start-SvcRead {
    if ($SvcUI.Reading -or $SvcUI.Busy) { return }
    if (-not $SvcUI.Data) { $c = Read-ListCache 'services'; if ($c -and $c.Items.Count) { $SvcUI.Data = $c.Items; $SvcUI.Stamp = $c.Stamp; Update-SvcList } }
    $SvcUI.Reading = $true; $Sync.SvcRead = $null
    $Ui.SvcProg.IsIndeterminate = $true; $Ui.SvcProg.Visibility = 'Visible'; $Ui.SvcRefresh.IsEnabled = $false
    $Ui.SvcStatus.Text = $(if ($SvcUI.Data) { 'Liste du {0:dd/MM HH:mm} affichée  ·  actualisation en cours...' -f $SvcUI.Stamp } else { 'Lecture des services...' })
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
    $SvcUI.Stamp = $r.Stamp; $SvcUI.Fresh = $true
    Merge-ListData $SvcUI 'Name' @($r.Items | Sort-Object Disp) { Update-SvcList } { param($k) Set-SvcRowLook $k }
    if ($SvcUI.SortKey -in 'State', 'Start') { Set-SvcOrder }
    Update-SvcFilter
    Save-ListCache 'services' $SvcUI.Data $SvcUI.Stamp
}

# ligne : nom affiché + nom court, état (pastille), démarrage, éditeur, 2 boutons (Démarrer/Arrêter, Désactiver/Réactiver)
# colonnes (largeurs) et en-têtes triables : clic = tri sur la colonne, nouveau clic = ordre inverse ; flèche sur la colonne
$SvcColW = @(0, 140, 110, 160, 170, 206)
$LevelRank = @{ 'Critique' = 0; 'Importante' = 0; 'À garder' = 1; 'Windows' = 2; 'Logiciel' = 3; 'Désactivable' = 4 }
function Set-ListHeader($Head, $Cols, $ListUI, [scriptblock]$Apply) {
    $Head.Children.Clear(); $Head.ColumnDefinitions.Clear(); $ListUI.HeadCells = @{}
    $i = 0
    foreach ($c in $Cols) {
        [void]$Head.ColumnDefinitions.Add((New-SvcCol $c.W))
        if ($c.T) {
            $sp = [Windows.Controls.StackPanel]::new(); $sp.Orientation = 'Horizontal'; $sp.Background = [Windows.Media.Brushes]::Transparent
            $t = New-Text $c.T 'Muted'; $t.FontSize = 11; $t.FontWeight = [Windows.FontWeights]::SemiBold; $t.TextWrapping = 'NoWrap'
            $ar = New-Text ''; $ar.FontFamily = [Windows.Media.FontFamily]::new('Segoe MDL2 Assets'); $ar.FontSize = 9; $ar.Margin = New-Thickness 6 2 0 0; $ar.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'AccentBrush')
            [void]$sp.Children.Add($t); [void]$sp.Children.Add($ar)
            if ($c.K) {
                $sp.Cursor = [Windows.Input.Cursors]::Hand; $sp.ToolTip = 'Trier sur cette colonne (nouveau clic : ordre inverse)'
                $sp.Tag = @{ K = $c.K; U = $ListUI; A = $Apply }
                $sp.Add_MouseLeftButtonUp({ param($s, $e) $x = $s.Tag; if ($x.U.SortKey -eq $x.K) { $x.U.SortDesc = -not $x.U.SortDesc } else { $x.U.SortKey = $x.K; $x.U.SortDesc = $false }; & $x.A })
                $ListUI.HeadCells[$c.K] = $ar
            }
            [Windows.Controls.Grid]::SetColumn($sp, $i); [void]$Head.Children.Add($sp)
        }
        $i++
    }
}
function Update-HeadArrow($ListUI) { foreach ($k in @($ListUI.HeadCells.Keys)) { $ListUI.HeadCells[$k].Text = $(if ($k -eq $ListUI.SortKey) { [string][char]$(if ($ListUI.SortDesc) { 0xE70D } else { 0xE70E }) } else { '' }) } }
# réordonne les lignes déjà construites (pas de reconstruction) selon la clé de tri
function Set-ListOrder($ListUI, $Panel, [string]$KeyProp, [scriptblock]$SortVal) {
    $d = @($ListUI.Data | Where-Object { $_ -and $ListUI.Rows["$($_.$KeyProp)"] })
    $sorted = @($d | Sort-Object -Property @{ Expression = { & $SortVal $_ }; Descending = [bool]$ListUI.SortDesc }, @{ Expression = { "$($_.$KeyProp)" } })
    $Panel.Children.Clear()
    foreach ($o in $sorted) { [void]$Panel.Children.Add($ListUI.Rows["$($o.$KeyProp)"].Row) }
    Update-HeadArrow $ListUI
}
function Set-SvcOrder {
    Set-ListOrder $SvcUI $Ui.SvcList 'Name' {
        param($o)
        switch ($SvcUI.SortKey) {
            'Level' { $LevelRank[$SvcUI.Rows[$o.Name].Level.L] }
            'State' { $(if ($o.State -eq 'Running') { 0 } else { 1 }) }
            'Start' { $v = @{ Boot = 0; System = 0; Auto = 1; Delayed = 2; Manual = 3; Disabled = 4 }["$($o.Start)"]; $(if ($null -eq $v) { 9 } else { $v }) }
            'Co' { "$($o.Co)" }
            default { "$($o.Disp)" }
        }
    }
}
function New-SvcCol([double]$W) { $c = [Windows.Controls.ColumnDefinition]::new(); $c.Width = $(if ($W -gt 0) { [Windows.GridLength]::new($W) } else { [Windows.GridLength]::new(1, 'Star') }); $c }
function New-SvcRow($S) {
    $b = [Windows.Controls.Border]::new(); $b.Style = $Window.FindResource('SvcRow'); $b.Padding = New-Thickness 10 5 6 5; $b.DataContext = $S
    $g = [Windows.Controls.Grid]::new(); foreach ($w in $SvcColW) { [void]$g.ColumnDefinitions.Add((New-SvcCol $w)) }
    $np = [Windows.Controls.StackPanel]::new(); $np.Margin = New-Thickness 0 0 10 0; $np.VerticalAlignment = 'Center'
    $t1 = New-Text $S.Disp; $t1.FontWeight = [Windows.FontWeights]::SemiBold; $t1.TextTrimming = 'CharacterEllipsis'; $t1.TextWrapping = 'NoWrap'
    $help = (@($S.Desc, ('Fichier : ' + $(if ($S.File) { $S.File } else { 'inconnu' }))) | Where-Object { $_ }) -join "`n`n"
    $t2 = New-Text $S.Name 'Muted'; $t2.FontSize = 11; $t2.TextTrimming = 'CharacterEllipsis'; $t2.TextWrapping = 'NoWrap'
    [void]$np.Children.Add((New-LabelWithHelp $t1 $help)); [void]$np.Children.Add($t2); [void]$g.Children.Add($np)
    $lv = Get-SvcLevel $S; $lb = New-LevelCell $lv; [Windows.Controls.Grid]::SetColumn($lb, 1); [void]$g.Children.Add($lb)
    $sp = [Windows.Controls.StackPanel]::new(); $sp.Orientation = 'Horizontal'; $sp.VerticalAlignment = 'Center'
    $dot = [Windows.Shapes.Ellipse]::new(); $dot.Width = 8; $dot.Height = 8; $dot.Margin = New-Thickness 0 0 8 0; $dot.VerticalAlignment = 'Center'
    $st = New-Text ''; $st.VerticalAlignment = 'Center'
    [void]$sp.Children.Add($dot); [void]$sp.Children.Add($st); [Windows.Controls.Grid]::SetColumn($sp, 2); [void]$g.Children.Add($sp)
    $sm = New-Text ''; $sm.VerticalAlignment = 'Center'; [Windows.Controls.Grid]::SetColumn($sm, 3); [void]$g.Children.Add($sm)
    $co = New-Text $(if ($S.Co) { $S.Co } else { 'inconnu' }) 'Muted'; $co.VerticalAlignment = 'Center'; $co.TextTrimming = 'CharacterEllipsis'; $co.Margin = New-Thickness 0 0 10 0
    [Windows.Controls.Grid]::SetColumn($co, 4); [void]$g.Children.Add($co)
    $bp = [Windows.Controls.StackPanel]::new(); $bp.Orientation = 'Horizontal'; $bp.HorizontalAlignment = 'Right'; $bp.VerticalAlignment = 'Center'
    $b1 = New-Button 'Démarrer'; $b2 = New-Button 'Désactiver'
    foreach ($x in $b1, $b2) { $x.Width = 98; $x.MinWidth = 0; $x.Height = 28; $x.Padding = New-Thickness 6 0 6 0; $x.Margin = New-Thickness 4 0 0 0; $x.Tag = $S.Name; [void]$bp.Children.Add($x) }
    $b1.Add_Click({ param($s, $e) Invoke-SvcAction "$($s.Tag)" $(if ($s.DataContext -eq 'stop') { 'stop' } else { 'start' }) })
    $b2.Add_Click({ param($s, $e) Invoke-SvcAction "$($s.Tag)" "$($s.DataContext)" })
    [Windows.Controls.Grid]::SetColumn($bp, 5); [void]$g.Children.Add($bp)
    $b.Child = $g
    $SvcUI.Rows[$S.Name] = @{ Row = $b; Dot = $dot; State = $st; Start = $sm; B1 = $b1; B2 = $b2; Level = $lv }
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
    -not $Q -or (Test-TextHas "$($S.Disp)" $Q) -or (Test-TextHas "$($S.Name)" $Q) -or (Test-TextHas "$($S.Co)" $Q)
}
function Update-SvcList {
    $d = $SvcUI.Data; if (-not $d) { return }
    # lignes reconstruites à chaque lecture (données neuves), puis filtrées par visibilité
    $Ui.SvcList.Children.Clear(); $SvcUI.Rows = @{}
    foreach ($s in $d) { [void]$Ui.SvcList.Children.Add((New-SvcRow $s)) }
    Set-SvcOrder
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
            # dépendants en cours : arrêtés aussi par Stop-Service -Force, nommés comme pour « Arrêter »
            $dep = @(); try { $dep = @((Get-Service -Name $Name -ErrorAction Stop).DependentServices | Where-Object { $_.Status -eq 'Running' } | ForEach-Object { $_.DisplayName }) } catch { Write-Ignored 'Services dépendants' $_ }
            if (-not (Confirm-Action (("Désactiver le service $who ?`n`nIl est arrêté et ne démarre plus, même au démarrage de Windows. Réactivable ici (type de démarrage actuel mémorisé : {0})." -f $SvcStartText[$S.Start]) + $(if ($dep.Count) { "`n`nServices dépendants arrêtés aussi : " + ($dep -join ', ') + '.' } else { '' }) + $warn))) { return }
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
    # tâche de fond terminée sans résultat (runspace en erreur) : échec affiché (avant : état « en cours » effacé sans message)
    if ($b -and -not $r) { $r = @{ Ok = $false; Msg = 'action interrompue sans résultat (tâche de fond en erreur)' } }
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

# en-tête des services : colonnes triables (tri par défaut : nom)
$SvcUI.SortKey = 'Name'; $SvcUI.SortDesc = $false
Set-ListHeader $Ui.SvcHead @(@{ T = 'SERVICE'; W = 0; K = 'Name' }, @{ T = 'IMPORTANCE'; W = 140; K = 'Level' }, @{ T = 'ÉTAT'; W = 110; K = 'State' }, @{ T = 'DÉMARRAGE'; W = 160; K = 'Start' }, @{ T = 'ÉDITEUR'; W = 170; K = 'Co' }, @{ T = ''; W = 206 }) $SvcUI { Set-SvcOrder }
Update-HeadArrow $SvcUI
