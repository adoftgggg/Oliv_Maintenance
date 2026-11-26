# pourcentage affiché seulement quand il est mesuré et non nul (« 42 %  ·  ») : pas de « 0 % » figé en début d'étape
function Format-Pct([int]$Pct) { if ($Pct -gt 0) { "$Pct %  ·  " } else { '' } }
# Journal de session (rapport d'intervention, 89-rapport.ps1) : actions réalisées depuis l'ouverture ; Level : ok | warn | error | info
$Session = @{ Start = [DateTime]::Now; Events = [Collections.ArrayList]::new() }
function Add-SessionEvent([string]$Cat, [string]$Title, [string]$Result, [string]$Level = 'ok', [string]$Detail = '') {
    $e = @{ Time = [DateTime]::Now; Cat = $Cat; Title = $Title; Result = $Result; Level = $Level; Detail = $Detail }
    [void]$Session.Events.Add($e); Save-HistoryEvent $e
}
# Historique du poste : chaque action de l'application (réglage, tâche, mise à jour, installation...) ajoutée à
# _etat\historique.jsonl (une ligne JSON), conservé d'une session et d'une version à l'autre ; Journal > Historique du poste
function Save-HistoryEvent($E) {
    try {
        $f = Join-Path (Get-LogPath 'Etat') 'historique.jsonl'
        $o = @{ Date = ([DateTime]$E.Time).ToString('o'); Cat = "$($E.Cat)"; Title = "$($E.Title)"; Result = "$($E.Result)"; Level = "$($E.Level)"; User = "$env:USERNAME" }
        [IO.File]::AppendAllText($f, (ConvertTo-Json -Compress -InputObject $o) + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
    } catch { Write-Ignored 'Historique du poste' $_ }
}
# Historique unique : actions de l'application (historique.jsonl) + mises à jour et installations de logiciels
# (logiciels-historique.jsonl, écrit par la tâche de fond), filtrables par catégorie et par texte
function Get-HistoryRow {
    $out = [Collections.Generic.List[object]]::new()
    foreach ($n in 'historique.jsonl', 'logiciels-historique.jsonl') {
        $f = Join-Path (Get-LogPath 'Etat') $n
        if (-not (Test-Path -LiteralPath $f)) { continue }
        try {
            foreach ($l in [IO.File]::ReadAllLines($f, [Text.Encoding]::UTF8)) {
                if (-not $l) { continue }
                try { $r = $l | ConvertFrom-Json } catch { continue }
                try { $d = [DateTime]$r.Date } catch { continue }
                if ($n -eq 'historique.jsonl') { $out.Add([pscustomobject]@{ D = $d; Cat = "$($r.Cat)"; Title = "$($r.Title)"; Result = "$($r.Result)" }) }
                else {
                    $res = $(if ($r.Ok) { $(if ($r.From -and $r.To) { "$($r.From) > $($r.To)" } elseif ($r.To) { "installé ($($r.To))" } else { 'réussi' }) } else { 'échec (code {0})' -f $r.Code })
                    $out.Add([pscustomobject]@{ D = $d; Cat = 'Logiciels'; Title = "$($r.Name)"; Result = $res })
                }
            }
        } catch { Write-Ignored 'Lecture de l''historique' $_ }
    }
    # une mise à jour de logiciel figure parfois aussi dans l'historique des actions : doublons (même minute, même titre) retirés
    $seen = @{}
    @($out | Sort-Object D -Descending | Where-Object { $k = '{0:yyyyMMddHHmm}|{1}' -f $_.D, $_.Title; if ($seen[$k]) { $false } else { $seen[$k] = 1; $true } })
}
function Format-HistoryLine($Rows) {
    $lines = [Collections.Generic.List[string]]::new(); $day = ''
    foreach ($r in @($Rows | Select-Object -First 1000)) {
        $k = $r.D.ToString('dddd dd MMMM yyyy')
        if ($k -ne $day) { if ($day) { $lines.Add('') }; $lines.Add($k.Substring(0, 1).ToUpper() + $k.Substring(1)); $day = $k }
        $lines.Add(('  {0:HH:mm}   {1}  ·  {2}  ·  {3}' -f $r.D, $r.Cat, $r.Title, $r.Result))
    }
    if (-not $lines.Count) { $lines.Add('Aucune action ne correspond au filtre.') }
    @($lines)
}
function Show-History {
    $rows = @(Get-HistoryRow)
    if (-not $rows.Count) { Show-Info "Historique du poste`n`nAucune action enregistrée pour l'instant."; return }
    $st = @{ Rows = $rows; Cat = ''; Q = ''; Box = $null; Count = $null }
    $bar = [Windows.Controls.DockPanel]::new(); $bar.LastChildFill = $true
    $cb = [Windows.Controls.ComboBox]::new(); $cb.Width = 200; $cb.Height = 30; $cb.Margin = New-Thickness 0 0 10 0; $cb.VerticalContentAlignment = 'Center'
    [void]$cb.Items.Add('Toutes les catégories'); foreach ($c in @($rows | ForEach-Object { $_.Cat } | Where-Object { $_ } | Sort-Object -Unique)) { [void]$cb.Items.Add($c) }
    $cb.SelectedIndex = 0; [Windows.Controls.DockPanel]::SetDock($cb, 'Left'); [void]$bar.Children.Add($cb)
    $cnt = New-Text ''; $cnt.VerticalAlignment = 'Center'; $cnt.Margin = New-Thickness 10 0 0 0; $cnt.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'MutedBrush')
    [Windows.Controls.DockPanel]::SetDock($cnt, 'Right'); [void]$bar.Children.Add($cnt); $st.Count = $cnt
    $q = [Windows.Controls.TextBox]::new(); $q.Height = 30; $q.VerticalContentAlignment = 'Center'; $q.ToolTip = 'Rechercher (titre, résultat, catégorie)'; [void]$bar.Children.Add($q)
    $refresh = {
        $f = @($st.Rows | Where-Object { (-not $st.Cat -or $_.Cat -eq $st.Cat) -and (-not $st.Q -or ('{0} {1} {2}' -f $_.Cat, $_.Title, $_.Result).IndexOf($st.Q, [StringComparison]::OrdinalIgnoreCase) -ge 0) })
        $st.Count.Text = '{0} / {1}' -f $f.Count, $st.Rows.Count
        if ($st.Box) { $st.Box.Text = (Format-HistoryLine $f) -join "`r`n"; $st.Box.ScrollToHome() }
    }.GetNewClosure()
    $cb.Tag = $refresh; $q.Tag = $refresh
    $cb.Add_SelectionChanged({ param($s) $st.Cat = $(if ($s.SelectedIndex -gt 0) { "$($s.SelectedItem)" } else { '' }); & $s.Tag }.GetNewClosure())
    $q.Add_TextChanged({ param($s) $st.Q = $s.Text.Trim(); & $s.Tag }.GetNewClosure())
    $ready = {
        param($dlg)
        $ex = $dlg.FindName('Extra'); [Windows.Controls.DockPanel]::SetDock($ex, 'Top'); $ex.Margin = New-Thickness 0 12 0 0
        $st.Box = @($dlg.FindName('List').Children)[0]; $dlg.Tag = $q; & $refresh
    }.GetNewClosure()
    [void](Show-Dialog ('Historique du poste  ·  {0} {1}' -f $rows.Count, (Get-Plural $rows.Count 'action' 'actions')) 'Info' $null @(Format-HistoryLine $rows) 'Actions de l''application, réglages, tâches, mises à jour et installations de logiciels (1 000 dernières lignes affichées par filtre).' 900 $bar $ready)
}
# détail technique sans intérêt pour l'utilisateur (incident non bloquant, relecture, préparation) : fichier journal du jour
# seulement, jamais affiché dans le Journal de l'application ni dans le bandeau
function Write-FileLog([string]$Message, [string]$Level = 'INFO') {
    try { [IO.File]::AppendAllText($TweakLog, ('{0:yyyy-MM-dd} {1:HH:mm:ss} [{2,-5}] {3}{4}' -f (Get-Date), (Get-Date), $Level, $Message, [Environment]::NewLine), [Text.Encoding]::UTF8) } catch { $null = $_ }
}
function Write-UiLog([string]$Message, [string]$Level = 'INFO') {
    $line = '{0} [{1,-5}] {2}' -f (Get-Date -Format 'HH:mm:ss'), $Level, $Message
    $Sync.Queue.Enqueue($line)
    try { [IO.File]::AppendAllText($TweakLog, ('{0:yyyy-MM-dd} {1}{2}' -f (Get-Date), $line, [Environment]::NewLine), [Text.Encoding]::UTF8) }
    catch {
        if (-not $script:TweakLogErr) {
            $script:TweakLogErr = $true
            $Sync.Queue.Enqueue(('{0} [WARN ] Écriture du journal impossible ({1}) : {2}' -f (Get-Date -Format 'HH:mm:ss'), $TweakLog, $_.Exception.Message))
        }
    }
}

# copie dans le presse-papiers (menus contextuels) : presse-papiers occupé par une autre application = avertissement
# Copie dans le presse-papiers : renvoie $true / $false ; $Done = message de confirmation affiché (bandeau bref) quand la copie
# vient d'un menu, sans bouton pour porter le retour visuel. Échec toujours signalé (bandeau rouge + journal).
function Set-ClipText([string]$Text, [string]$Done) {
    $ok = $false
    for ($k = 0; $k -lt 5 -and -not $ok; $k++) { try { [Windows.Clipboard]::SetText($Text); $ok = $true } catch { if ($k -eq 4) { Write-UiLog "Copie dans le presse-papiers impossible : $($_.Exception.Message)" 'WARN' } else { Start-Sleep -Milliseconds 60 } } }
    if ($Done -or -not $ok) { Show-Toast $(if ($ok) { "$Done dans le presse-papiers" } else { 'Copie impossible : presse-papiers occupé par un autre programme' }) $ok }
    $ok
}
# libellé de confirmation accordé depuis l'intitulé d'un menu « Copier ... » (genre et nombre du nom copié)
function Get-CopyDone([string]$Head) {
    # « les » essayé avant « le » (sinon « Copier les lignes » donnait « S lignes copiés »)
    $h = $Head -replace '^Copier\s+', '' -replace '^(les|le|la)\s+|^l''\s*', '' -replace '^\d+\s+', ''
    $fem = $h -match '^(erreur|version|ligne|clé|cle|adresse|valeur|commande|taille)'
    $plu = $Head -match '^Copier\s+les\s'
    $mot = $h.Substring(0, 1).ToUpper() + $h.Substring(1)
    '{0} {1}' -f $mot, $('copi' + 'é' + $(if ($fem) { 'e' } else { '' }) + $(if ($plu) { 's' } else { '' }))
}
# bandeau bref (2,5 s) en bas de la fenêtre : confirmation d'une action sans bouton dédié (copie depuis un menu...)
$ToastUI = @{}
function Show-Toast([string]$Text, [bool]$Ok = $true) {
    if (-not $ToastUI.Pop) {
        $pp = [Windows.Controls.Primitives.Popup]::new(); $pp.AllowsTransparency = $true; $pp.Placement = 'Center'; $pp.StaysOpen = $true; $pp.IsHitTestVisible = $false
        $bd = [Windows.Controls.Border]::new(); $bd.CornerRadius = [Windows.CornerRadius]::new(8); $bd.Padding = New-Thickness 14 8 16 8; $bd.Margin = New-Thickness 12 12 12 12; $bd.BorderThickness = New-Thickness 1 1 1 1
        $bd.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, 'PanelBrush'); $bd.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, 'LineBrush')
        $fx = [Windows.Media.Effects.DropShadowEffect]::new(); $fx.BlurRadius = 16; $fx.ShadowDepth = 2; $fx.Opacity = 0.3; $fx.Direction = 270; $bd.Effect = $fx
        $sp = [Windows.Controls.StackPanel]::new(); $sp.Orientation = 'Horizontal'
        $ToastUI.Glyph = New-Text ''; $ToastUI.Glyph.FontFamily = [Windows.Media.FontFamily]::new('Segoe MDL2 Assets'); $ToastUI.Glyph.VerticalAlignment = 'Center'; $ToastUI.Glyph.Margin = New-Thickness 0 0 10 0
        $ToastUI.Text = New-Text ''; $ToastUI.Text.VerticalAlignment = 'Center'; $ToastUI.Text.FontWeight = [Windows.FontWeights]::SemiBold
        [void]$sp.Children.Add($ToastUI.Glyph); [void]$sp.Children.Add($ToastUI.Text); $bd.Child = $sp; $pp.Child = $bd
        $ToastUI.Pop = $pp
        $ToastUI.Timer = [Windows.Threading.DispatcherTimer]::new(); $ToastUI.Timer.Interval = [TimeSpan]::FromMilliseconds(2500)
        $ToastUI.Timer.Add_Tick({ $ToastUI.Timer.Stop(); $ToastUI.Pop.IsOpen = $false })
    }
    $ToastUI.Glyph.Text = [string][char]$(if ($Ok) { 0xE73E } else { 0xE783 })
    foreach ($x in $ToastUI.Glyph, $ToastUI.Text) { $x.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, $(if ($Ok) { 'OkFgBrush' } else { 'ErrFgBrush' })) }
    $ToastUI.Text.Text = $Text
    # fenêtre active de l'application (Logiciels, Espace disque, Variables...) : bandeau affiché dans celle-ci, pas derrière
    $w = $(if ($TreeUI.Win -and $TreeUI.Win.IsActive) { $TreeUI.Win } elseif ($SoftUI.Win -and $SoftUI.Win.IsActive) { $SoftUI.Win } elseif ($EnvUI.Win -and $EnvUI.Win.IsActive) { $EnvUI.Win } else { $Window })
    $ToastUI.Pop.PlacementTarget = $w.Content
    $ToastUI.Pop.VerticalOffset = [math]::Max([double]0, $w.ActualHeight / 2 - 60)
    $ToastUI.Pop.IsOpen = $false; $ToastUI.Pop.IsOpen = $true
    $ToastUI.Timer.Stop(); $ToastUI.Timer.Start()
}
# Bouton de copie (icône ou texte) : copie, puis le bouton affiche « Copié » / « Copiée » (accord avec ce qui est copié) et une
# coche en vert pendant 3 s, ou l'échec en rouge
function Invoke-CopyButton($Btn, [string]$Text, [string]$Word = 'Copié', [string]$Log) {
    $ok = Set-ClipText $Text
    if ($ok -and $Log) { Write-UiLog $Log 'APP' }
    Show-CopyFeedback $Btn $ok $Word
    $ok
}
# Ligne de clé secrète commune (licence Windows, récupération BitLocker...) : valeur masquée en points (points à la place des caractères, mêmes tirets
# que la clé), icône œil (afficher / masquer) et icône copier (« Copiée »), alignées à droite de la ligne
function Get-MaskedText([string]$S) { ($S -replace '[A-Za-z0-9]', [string][char]0x2022) }
function Add-SecretKeyRow($Body, [string]$Label, [string]$Key, [string]$Tip, [string]$ShowLog, [string]$CopyLog) {
    $v = Add-KV $Body $Label (Get-MaskedText $Key); $g = $v.Parent
    $v.VerticalAlignment = 'Center'; $g.Children[0].VerticalAlignment = 'Center'; $v.FontFamily = [Windows.Media.FontFamily]::new('Consolas')
    if ($Tip) { $v.ToolTip = $Tip }
    $col = Add-AutoColumn $g
    $sp = [Windows.Controls.StackPanel]::new(); $sp.Orientation = 'Horizontal'; $sp.VerticalAlignment = 'Center'; $sp.Margin = New-Thickness 8 0 0 0
    $eye = New-ToolIconButton 0xE7B3 'Afficher' @{ Box = $v; Key = $Key; Shown = $false; Log = $ShowLog } {
        param($s, $e) $t = $s.Tag; $t.Shown = -not $t.Shown
        $t.Box.Text = $(if ($t.Shown) { $t.Key } else { Get-MaskedText $t.Key }); Set-EyeState $s $t.Shown
        if ($t.Shown -and $t.Log) { Write-UiLog $t.Log 'APP' }
    }
    $cp = New-ToolIconButton 0xE8C8 'Copier' @{ Key = $Key; Log = $CopyLog } { param($s, $e) [void](Invoke-CopyButton $s $s.Tag.Key 'Copiée' $s.Tag.Log) }
    [void]$sp.Children.Add($eye); [void]$sp.Children.Add($cp)
    [Windows.Controls.Grid]::SetColumn($sp, $col); [void]$g.Children.Add($sp)
    $v
}
# Bouton œil : afficher / masquer un secret, icône et infobulle qui suivent l'état
function Set-EyeState($Btn, [bool]$Shown) {
    $Btn.Content = [string][char]$(if ($Shown) { 0xED1A } else { 0xE7B3 })
    $Btn.ToolTip = $(if ($Shown) { 'Masquer' } else { 'Afficher' })
    if ($Shown) { $Btn.SetResourceReference([Windows.Controls.Control]::ForegroundProperty, 'AccentBrush') } else { $Btn.ClearValue([Windows.Controls.Control]::ForegroundProperty) }
}

$BrushCache = @{}
function New-Brush([string]$Hex) {
    $c = $BrushCache[$Hex]
    if ($c) { return $c }
    $b = [Windows.Media.SolidColorBrush]::new([Windows.Media.Color][Windows.Media.ColorConverter]::ConvertFromString($Hex))
    $b.Freeze()
    $BrushCache[$Hex] = $b.psobject.BaseObject
    $BrushCache[$Hex]
}
$Themes = @{
    Dark  = @{ BgBrush='#1E1F22'; PanelBrush='#2B2D31'; LineBrush='#4A4E56'; FgBrush='#F2F3F5'; MutedBrush='#B5BAC1'; AccentBrush='#2563EB'; HeadBrush='#7AB8FF'; BtnBrush='#383A40'; BtnHoverBrush='#44474E'; OnAccentBrush='#FFFFFF'; HoverBrush='#35373C'; ScrollBrush='#5A5E66'; CheckBorderBrush='#8E939C'; SelBrush='#3B82F6'
               OkFgBrush='#4ADE80'; WarnFgBrush='#FBBF24'; ErrFgBrush='#FCA5A5'; PendBgBrush='#3A2E14'; ToggleOffBrush='#7C818B'; DisabledFgBrush='#8B9099' }
    Light = @{ BgBrush='#F2F3F5'; PanelBrush='#FFFFFF'; LineBrush='#C2C8D0'; FgBrush='#1D1F23'; MutedBrush='#555C67'; AccentBrush='#2563EB'; HeadBrush='#1D4ED8'; BtnBrush='#E6EAF0'; BtnHoverBrush='#D6DEEA'; OnAccentBrush='#FFFFFF'; HoverBrush='#E8EEF6'; ScrollBrush='#B0B7C0'; CheckBorderBrush='#7A828D'; SelBrush='#2563EB'
               OkFgBrush='#166534'; WarnFgBrush='#92400E'; ErrFgBrush='#B91C1C'; PendBgBrush='#FFF1D6'; ToggleOffBrush='#7A828D'; DisabledFgBrush='#7C828C' }
}
function Set-Theme([string]$Name) {
    foreach ($k in $Themes[$Name].Keys) { $Window.Resources[$k] = New-Brush $Themes[$Name][$k] }
    $Sync.Theme = $Name
}
$ThemeFile  = Join-Path (Get-LogPath 'Etat') 'theme.txt'
$StartFile  = Join-Path (Get-LogPath 'Etat') 'onglet.txt'
$SnapDir    = Join-Path (Get-LogPath 'Etat') 'instantanes'
$SetUI      = @{}
$ThemeModes = [ordered]@{ Systeme = @{ Glyph = 0xE7F4; Label = 'Système' }; Clair = @{ Glyph = 0xE706; Label = 'Clair' }; Sombre = @{ Glyph = 0xE708; Label = 'Sombre' } }
function Get-SystemTheme {
    $v = Get-RegValue 'HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'AppsUseLightTheme'
    if ($v -eq 1) { 'Light' } else { 'Dark' }
}
function Set-ThemeMode([string]$Mode, [bool]$Save = $false) {
    if (-not $ThemeModes.Contains($Mode)) { $Mode = 'Systeme' }
    $Sync.ThemeMode = $Mode
    $want = switch ($Mode) { 'Clair' { 'Light' } 'Sombre' { 'Dark' } default { Get-SystemTheme } }
    if ($want -ne $Sync.Theme) { Set-Theme $want }
    if ($SetUI.Theme) { foreach ($b in $SetUI.Theme) { $b.Tag = $(if ("$($b.DataContext)" -eq $Mode) { 'on' } else { '' }) } }
    if ($Save) { try { [IO.File]::WriteAllText($ThemeFile, $Mode) } catch { Write-Ignored 'Enregistrement du thème' $_ } }
}
$m = 'Systeme'
try {
    if (Test-Path -LiteralPath $ThemeFile) { $m = [IO.File]::ReadAllText($ThemeFile).Trim() }
} catch { Write-Ignored 'Lecture du thème enregistré' $_ }
Set-ThemeMode $m

$C_OK = '#15803D'; $C_PEND = '#B45309'; $C_WARN = '#A16207'; $C_ERR = '#B91C1C'; $C_STAGE = '#D97706'; $C_WAIT = '#2563EB'; $C_SCHED = '#0E7490'
$Check = [string][char]0x2713

function New-Thickness([double]$Left, [double]$Top, [double]$Right, [double]$Bottom) { [Windows.Thickness]::new($Left, $Top, $Right, $Bottom) }

function New-Text([string]$Text, [string]$StyleKey) {
    $tb = [Windows.Controls.TextBlock]::new()
    $tb.Text = $Text; $tb.TextWrapping = 'Wrap'
    if ($StyleKey) { $tb.Style = $Window.FindResource($StyleKey) }
    $tb
}

function New-Card([string]$Title, [string]$Desc, [string]$Glyph) {
    $card = [Windows.Controls.Border]::new()
    $card.Tag    = "card:$Title"
    $card.Style  = $Window.FindResource('Panel')
    $card.Margin = New-Thickness 0 0 0 12
    $body = [Windows.Controls.StackPanel]::new()
    $hdr  = [Windows.Controls.Grid]::new()
    $hdr.Margin = New-Thickness 16 14 16 10
    $c0 = [Windows.Controls.ColumnDefinition]::new(); $c0.Width = [Windows.GridLength]::Auto
    $c1 = [Windows.Controls.ColumnDefinition]::new()
    [void]$hdr.ColumnDefinitions.Add($c0); [void]$hdr.ColumnDefinitions.Add($c1)
    $g = New-Text $Glyph
    $g.FontFamily = [Windows.Media.FontFamily]::new('Segoe MDL2 Assets'); $g.FontSize = 18
    $g.Margin = New-Thickness 0 2 12 0; $g.VerticalAlignment = 'Top'
    $g.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'HeadBrush')
    $tx = [Windows.Controls.StackPanel]::new()
    [Windows.Controls.Grid]::SetColumn($tx, 1)
    $t1 = New-Text $Title
    $t1.FontSize = 16; $t1.FontWeight = [Windows.FontWeights]::SemiBold; $t1.TextWrapping = 'Wrap'
    [void]$tx.Children.Add($t1)
    if ($Desc) { [void]$tx.Children.Add((New-Text $Desc 'Muted')) }
    [void]$hdr.Children.Add($g); [void]$hdr.Children.Add($tx)
    [void]$body.Children.Add($hdr)
    $card.Child = $body
    @{ Card = $card; Body = $body; Title = $t1 }
}
# Icône d'action en haut à droite d'une carte (Actualiser, Copier...) : même taille et même position partout.
# -Hover : visible uniquement au survol de la carte.
function Add-AutoColumn($Grid) { $cd = [Windows.Controls.ColumnDefinition]::new(); $cd.Width = [Windows.GridLength]::Auto; [void]$Grid.ColumnDefinitions.Add($cd); $Grid.ColumnDefinitions.Count - 1 }
function Add-CardIcon($C, [int]$Glyph, [string]$Tip, [scriptblock]$Click, [switch]$Hover) {
    $hdr = $C.Body.Children[0]
    $col = Add-AutoColumn $hdr
    $b = [Windows.Controls.Button]::new()
    $b.Style = $Window.FindResource('IconBtn'); $b.Content = [string][char]$Glyph; $b.Width = 32; $b.Height = 30
    $b.Margin = New-Thickness 2 -4 -6 0; $b.VerticalAlignment = 'Top'; $b.ToolTip = $Tip; $b.Tag = $C.Card
    if ($Click) { $b.Add_Click($Click) }
    [Windows.Controls.Grid]::SetColumn($b, $col)
    [void]$hdr.Children.Add($b)
    if ($Hover) {
        $b.Uid = 'hover'; $b.Visibility = 'Hidden'
        if (-not $C.Card.Uid) {
            $C.Card.Uid = 'hoverhost'
            $C.Card.Add_MouseEnter({ param($s, $e)
                foreach ($x in $s.Child.Children[0].Children) { if ($x.Uid -eq 'hover') { $x.Visibility = 'Visible' } }
            })
            $C.Card.Add_MouseLeave({ param($s, $e)
                # bouton qui affiche encore « Copié » : laissé visible, masqué à la fin de son retour (Show-CopyFeedback)
                foreach ($x in $s.Child.Children[0].Children) { if ($x.Uid -eq 'hover' -and -not $CopyFb.ContainsKey([Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($x))) { $x.Visibility = 'Hidden' } }
            })
        }
    }
    $b
}

$SettingRowUp = {
    param($s, $e)
    if (Test-InButton $e.OriginalSource) { return }
    $r = $s.Tag
    if ($r -and $r.Toggle -and $r.Toggle.IsEnabled) {
        $r.Toggle.IsChecked = -not [bool]$r.Toggle.IsChecked
        Set-Staged $r ([bool]$r.Toggle.IsChecked)
    }
}
$HoverToggleUp = {
    param($s, $e)
    if (Test-InButton $e.OriginalSource) { return }
    $i = $s.Tag
    if (-not $i.Check.IsEnabled) { return }
    $i.Check.IsChecked = -not [bool]$i.Check.IsChecked
    if ($i.After) { & $i.After }
}
function Test-InButton($Element) {
    try {
        while ($Element) {
            if ($Element -is [Windows.Controls.Primitives.ButtonBase]) { return $true }
            $Element = [Windows.Media.VisualTreeHelper]::GetParent($Element)
        }
    } catch {}
    $false
}
function New-HoverCheck($Parent, [string]$Label, [string]$Tip, [scriptblock]$After) {
    $b = [Windows.Controls.Border]::new()
    $b.Style = $Window.FindResource('HoverRow')
    $cb = [Windows.Controls.CheckBox]::new()
    # explication : « ? » à côté de l'intitulé (comme partout ailleurs), plus d'infobulle sur toute la ligne
    $cb.Style = $Window.FindResource('TaskCheck'); $cb.Margin = New-Thickness 8 4 8 4
    $cb.Content = $(if ($Tip) { $lt = New-Text $Label; $lt.TextWrapping = 'Wrap'; New-LabelWithHelp $lt $Tip } else { $Label })
    if ($After) { $cb.Add_Click($After) }
    $b.Child = $cb
    $b.Tag = @{ Check = $cb; After = $After }
    $b.Add_MouseLeftButtonUp($HoverToggleUp)
    [void]$Parent.Children.Add($b)
    $cb
}

# Intitulé de la colonne des pastilles (Immédiat, Redémarrage, Déconnexion...) sur la ligne de titre de la carte.
# Colonnes de l'en-tête alignées sur celles des lignes (groupes partagés SrBadge / SrHost, portée = la carte) ;
# icônes d'en-tête (Actualiser...) placées dans la colonne des interrupteurs pour ne pas décaler l'intitulé.
$SrHostWidth = 52
function Add-EffectHeader($C) {
    $hdr = $C.Body.Children[0]
    [Windows.Controls.Grid]::SetIsSharedSizeScope($C.Card, $true)
    $cb = [Windows.Controls.ColumnDefinition]::new(); $cb.Width = [Windows.GridLength]::Auto; $cb.SharedSizeGroup = 'SrBadge'
    $ch = [Windows.Controls.ColumnDefinition]::new(); $ch.Width = [Windows.GridLength]::new($SrHostWidth)
    $ce = [Windows.Controls.ColumnDefinition]::new(); $ce.Width = [Windows.GridLength]::Auto; $ce.SharedSizeGroup = 'SrExtra'
    foreach ($cd in $cb, $ch, $ce) { [void]$hdr.ColumnDefinitions.Add($cd) }
    $ib = $hdr.ColumnDefinitions.Count - 3; $ie = $ib + 2
    foreach ($x in @($hdr.Children)) {
        if ([Windows.Controls.Grid]::GetColumn($x) -ge 2) { [Windows.Controls.Grid]::SetColumn($x, $ie); $x.HorizontalAlignment = 'Right' }
    }
    $t = New-Text 'Prend effet' 'Muted'
    $t.FontSize = 12
    $t.HorizontalAlignment = 'Center'
    $t.VerticalAlignment = 'Center'
    $t.Margin = New-Thickness 0 0 14 0
    $t.ToolTip = 'Moment où le réglage s''applique réellement une fois « Appliquer » cliqué : immédiatement, après relance d''une application, déconnexion ou redémarrage'
    [Windows.Controls.Grid]::SetColumn($t, $ib); [void]$hdr.Children.Add($t)
}
# Aide contextuelle : point d'interrogation à côté d'un libellé, explication au survol ou au clic (clic suivant : refermée),
# à la place des info-bulles sur toute la ligne
function New-HelpMark([string]$Text) {
    $b = [Windows.Controls.Border]::new(); $b.Width = 18; $b.Height = 18; $b.CornerRadius = [Windows.CornerRadius]::new(9); $b.BorderThickness = New-Thickness 1 1 1 1
    $b.Margin = New-Thickness 8 0 0 0; $b.VerticalAlignment = 'Center'; $b.Cursor = [Windows.Input.Cursors]::Hand; $b.Background = [Windows.Media.Brushes]::Transparent
    $b.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, 'AccentBrush')
    $q = New-Text '?'; $q.FontSize = 11; $q.FontWeight = [Windows.FontWeights]::SemiBold; $q.HorizontalAlignment = 'Center'; $q.VerticalAlignment = 'Center'; $q.Margin = New-Thickness 0 -1 0 0
    $q.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'AccentBrush'); $b.Child = $q
    # contenu = texte brut : le style global des infobulles l'affiche dans un TextBlock enveloppé (un TextBlock passé en contenu
    # s'affichait « System.Windows.Controls.TextBlock »)
    $tt = [Windows.Controls.ToolTip]::new(); $tt.Content = $Text
    $b.ToolTip = $tt; [Windows.Controls.ToolTipService]::SetShowDuration($b, 60000); [Windows.Controls.ToolTipService]::SetInitialShowDelay($b, 150)
    $b.Add_MouseLeftButtonDown({ param($s, $e) $e.Handled = $true })
    $b.Add_MouseLeftButtonUp({ param($s, $e) $t = $s.ToolTip; $t.PlacementTarget = $s; $t.IsOpen = -not $t.IsOpen; $e.Handled = $true })
    $b
}
# libellé + point d'interrogation sur une ligne (texte enveloppé à gauche, aide alignée en haut)
function New-LabelWithHelp($TextEl, [string]$Help) {
    if (-not $Help) { return $TextEl }
    $d = [Windows.Controls.DockPanel]::new(); $m = New-HelpMark $Help; [Windows.Controls.DockPanel]::SetDock($m, 'Right'); $m.VerticalAlignment = 'Top'; $m.Margin = New-Thickness 8 1 0 0
    $d.HorizontalAlignment = 'Left'; [void]$d.Children.Add($m); [void]$d.Children.Add($TextEl); $d
}
function New-SettingRow([string]$Label, [string]$Desc, [string]$Tip, [string]$Effect) {
    $row = [Windows.Controls.Border]::new()
    $row.BorderThickness = New-Thickness 0 1 0 0
    $row.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, 'LineBrush')
    # hauteur de ligne commune à toute l'application (40 px) : réglages, applications au démarrage, lignes de Maintenance
    $row.Padding = New-Thickness 16 4 16 4; $row.MinHeight = 40
    $row.Style = $Window.FindResource('HoverLine')
    $row.Add_MouseLeftButtonUp($SettingRowUp)
    $g = [Windows.Controls.Grid]::new()
    $c0 = [Windows.Controls.ColumnDefinition]::new()
    # colonnes : libellé | choix (boutons, à gauche de la pastille) | pastille (largeur partagée dans la carte) |
    # interrupteur (largeur fixe : pastilles alignées d'une carte à l'autre) | action supplémentaire (corbeille des applications au démarrage)
    $cc = [Windows.Controls.ColumnDefinition]::new(); $cc.Width = [Windows.GridLength]::Auto
    $c1 = [Windows.Controls.ColumnDefinition]::new(); $c1.Width = [Windows.GridLength]::Auto; $c1.SharedSizeGroup = 'SrBadge'
    $c2 = [Windows.Controls.ColumnDefinition]::new(); $c2.Width = [Windows.GridLength]::new($SrHostWidth)
    $c3 = [Windows.Controls.ColumnDefinition]::new(); $c3.Width = [Windows.GridLength]::Auto; $c3.SharedSizeGroup = 'SrExtra'
    foreach ($cd in $c0, $cc, $c1, $c2, $c3) { [void]$g.ColumnDefinitions.Add($cd) }
    $sp = [Windows.Controls.StackPanel]::new()
    $sp.VerticalAlignment = 'Center'; $sp.Margin = New-Thickness 34 0 12 0
    $lb = New-Text $Label; $lb.TextWrapping = 'Wrap'
    [void]$sp.Children.Add((New-LabelWithHelp $lb $Tip))
    if ($Desc) { [void]$sp.Children.Add((New-Text $Desc 'Muted')) }
    $badge = [Windows.Controls.Border]::new()
    $badge.CornerRadius = [Windows.CornerRadius]::new(10)
    $badge.BorderThickness = New-Thickness 1 1 1 1
    $badge.Padding = New-Thickness 10 3 10 3
    $badge.Margin = New-Thickness 0 0 14 0
    $badge.MinWidth = 180
    $badge.VerticalAlignment = 'Center'
    $bt = New-Text ''
    $bt.FontSize = 11; $bt.HorizontalAlignment = 'Center'; $bt.TextWrapping = 'Wrap'; $bt.TextAlignment = 'Center'
    $badge.Child = $bt
    [Windows.Controls.Grid]::SetColumn($badge, 2)
    $ch = [Windows.Controls.StackPanel]::new(); $ch.Orientation = 'Horizontal'; $ch.VerticalAlignment = 'Center'; $ch.Margin = New-Thickness 0 0 10 0
    [Windows.Controls.Grid]::SetColumn($ch, 1)
    $host_ = [Windows.Controls.StackPanel]::new()
    $host_.Orientation = 'Horizontal'; $host_.VerticalAlignment = 'Center'; $host_.HorizontalAlignment = 'Left'
    [Windows.Controls.Grid]::SetColumn($host_, 3)
    $ex = [Windows.Controls.StackPanel]::new(); $ex.Orientation = 'Horizontal'; $ex.VerticalAlignment = 'Center'
    [Windows.Controls.Grid]::SetColumn($ex, 4)
    [void]$g.Children.Add($sp); [void]$g.Children.Add($ch); [void]$g.Children.Add($badge); [void]$g.Children.Add($host_); [void]$g.Children.Add($ex)
    $row.Child = $g
    $r = @{ Row = $row; Host = $host_; Choices = $ch; Extra = $ex; Badge = $badge; BadgeText = $bt; Effect = $Effect; Label = "$Label $Desc"; Pending = $null }
    $row.Tag = $r
    Set-Badge $r 'idle'
    $r
}

function Set-Badge($R, [string]$State) {
    $info = $EffectInfo[$R.Effect]
    if ($State -ne 'staged') { $R.BadgeState = $State }
    switch ($State) {
        # modification en attente : pastille ambre et ligne teintée (repérable d'un coup d'œil, distincte du bleu des interrupteurs)
        'staged'  { $txt = 'À appliquer'; $bg = $C_STAGE }
        'ok'      { $txt = "$Check Appliqué"; if ($R.Effect -eq 'P') { $txt += ' - rouvrir Paramètres' }; $bg = $C_OK }
        'pending' {
            if ($info.Bar) { $txt = $info.Pending; $bg = $C_PEND }
            elseif ($R.Entry) {
                $txt = "$Check " + $(if ($R.Current) { 'Activé' } else { 'Désactivé' }) + ' - effectif après déconnexion'
                $bg = $C_SCHED
            }
            else { $txt = "$Check " + $info.Pending; $bg = $C_SCHED }
        }
        'wait'    { $txt = 'Application en cours...'; $bg = $C_WAIT }
        'warn'    { $txt = 'Non appliqué - voir Journal'; $bg = $C_WARN }
        'error'   { $txt = 'Erreur - voir le Journal'; $bg = $C_ERR }
        default   { $txt = $info.Idle; $bg = $null }
    }
    # applications au démarrage : moment d'effet identique pour toutes (indiqué une fois dans l'en-tête de la carte),
    # pastille affichée seulement quand une modification est en attente ou vient d'être appliquée
    $R.Badge.Visibility = $(if ($R.Entry -and $State -eq 'idle') { 'Collapsed' } else { 'Visible' })
    $R.BadgeText.Text = $txt
    if ($State -eq 'staged') { $R.Row.Background = New-Brush '#2ED97706' } else { $R.Row.ClearValue([Windows.Controls.Border]::BackgroundProperty) }
    if ($bg) {
        $R.Badge.Background = New-Brush $bg; $R.Badge.BorderBrush = New-Brush $bg
        $R.BadgeText.Foreground = [Windows.Media.Brushes]::White
    } else {
        $R.Badge.Background = [Windows.Media.Brushes]::Transparent
        $R.Badge.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, 'LineBrush')
        $R.BadgeText.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'MutedBrush')
    }
}

# Bouton « Afficher tout (N) » / « Afficher moins » sous une liste raccourcie : centré, chevron vers le bas ou le haut
function Set-ShowMoreContent($Btn, [int]$Total, [bool]$Expanded) {
    $sp = [Windows.Controls.StackPanel]::new(); $sp.Orientation = 'Horizontal'
    $t = New-Text $(if ($Expanded) { 'Afficher moins' } else { "Afficher tout ($Total)" }); $t.VerticalAlignment = 'Center'; $t.TextWrapping = 'NoWrap'
    $g = New-Text ([string][char]$(if ($Expanded) { 0xE70E } else { 0xE70D }))
    $g.FontFamily = [Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
    $g.FontSize = 10
    $g.VerticalAlignment = 'Center'
    $g.Margin = New-Thickness 10 1 0 0
    [void]$sp.Children.Add($t); [void]$sp.Children.Add($g); $Btn.Content = $sp
}
# Listes raccourcies (même règle partout : mises à jour Windows et constructeur, applications au démarrage, applications
# préinstallées, imprimantes) : $ListMax éléments affichés, les suivants dans un panneau replié sous le bouton
# « Afficher tout (N) » / « Afficher moins ». État déplié gardé par liste ($ListFold[clé]) quand la liste est reconstruite.
$ListMax = 4
$ListFold = @{}
function Add-FoldMore($Panel, $More, [int]$Total, [string]$Key) {
    if (-not $More.Children.Count) { return }
    $exp = [bool]$ListFold[$Key]
    $More.Visibility = $(if ($exp) { 'Visible' } else { 'Collapsed' })
    [void]$Panel.Children.Add($More)
    $b = New-ShowMoreButton $Total $exp
    $b.Tag = @{ Panel = $More; Total = $Total; Key = $Key }
    $b.Add_Click({
        param($s, $e)
        $t = $s.Tag; $ListFold[$t.Key] = -not [bool]$ListFold[$t.Key]
        Set-ShowMoreContent $s $t.Total ([bool]$ListFold[$t.Key])
        Set-Fold $t.Panel ([bool]$ListFold[$t.Key])
    })
    [void]$Panel.Children.Add($b)
}
function New-ShowMoreButton([int]$Total, [bool]$Expanded) {
    $b = [Windows.Controls.Button]::new(); $b.Style = $Window.FindResource('ActionBtn')
    $b.HorizontalAlignment = 'Center'; $b.Height = 30; $b.MinWidth = 160; $b.Padding = New-Thickness 18 0 18 0; $b.Margin = New-Thickness 0 10 0 4
    Set-ShowMoreContent $b $Total $Expanded
    $b
}
function New-Button([string]$Text, [string]$StyleKey = 'ActionBtn') {
    $b = [Windows.Controls.Button]::new()
    $b.Content = $Text; $b.Style = $Window.FindResource($StyleKey); $b.Margin = New-Thickness 0 0 6 0
    $b
}

function Add-KV($Body, [string]$Key, [string]$Value, [string]$Color) {
    $hb = [Windows.Controls.Border]::new()
    $hb.Style = $Window.FindResource('HoverPlain'); $hb.Margin = New-Thickness 38 0 10 0; $hb.Tag = 'kv'
    $g = [Windows.Controls.Grid]::new()
    $g.Margin = New-Thickness 8 4 8 4
    $hb.Child = $g
    $c0 = [Windows.Controls.ColumnDefinition]::new()
    $c0.Width = [Windows.GridLength]::Auto
    $c0.SharedSizeGroup = 'KvKey'
    $c0.MinWidth = 120
    $c0.MaxWidth = 230
    $c1 = [Windows.Controls.ColumnDefinition]::new()
    [void]$g.ColumnDefinitions.Add($c0); [void]$g.ColumnDefinitions.Add($c1)
    $k = [Windows.Controls.TextBox]::new()
    $k.Text = $Key; $k.IsReadOnly = $true; $k.TextWrapping = 'Wrap'; $k.FontSize = 13; $k.Margin = New-Thickness 0 0 12 0; $k.VerticalAlignment = 'Top'
    $k.BorderThickness = New-Thickness 0 0 0 0; $k.Background = [Windows.Media.Brushes]::Transparent; $k.Padding = New-Thickness 0 0 0 0
    $k.SetResourceReference([Windows.Controls.Control]::ForegroundProperty, 'MutedBrush')
    $k.SetResourceReference([Windows.Controls.Primitives.TextBoxBase]::CaretBrushProperty, 'FgBrush')
    $v = [Windows.Controls.TextBox]::new()
    $v.Text = $Value; $v.IsReadOnly = $true; $v.TextWrapping = 'Wrap'; $v.FontSize = 13; $v.VerticalAlignment = 'Top'
    $v.BorderThickness = New-Thickness 0 0 0 0; $v.Background = [Windows.Media.Brushes]::Transparent; $v.Padding = New-Thickness 0 0 0 0
    $v.SetResourceReference([Windows.Controls.Control]::ForegroundProperty, 'FgBrush')
    $v.SetResourceReference([Windows.Controls.Primitives.TextBoxBase]::CaretBrushProperty, 'FgBrush')
    if ($Color) { $v.SetResourceReference([Windows.Controls.Control]::ForegroundProperty, $Color); $v.FontWeight = [Windows.FontWeights]::SemiBold }
    [Windows.Controls.Grid]::SetColumn($v, 1)
    [void]$g.Children.Add($k); [void]$g.Children.Add($v)
    [void]$Body.Children.Add($hb)
    $v
}
function Add-Spacer($Body) { $s = [Windows.Controls.Border]::new(); $s.Height = 10; [void]$Body.Children.Add($s) }
function New-SelText([string]$Text, [string]$BrushKey) {
    $x = [Windows.Controls.TextBox]::new()
    $x.Text = $Text; $x.IsReadOnly = $true; $x.BorderThickness = New-Thickness 0 0 0 0
    $x.Background = [Windows.Media.Brushes]::Transparent; $x.Padding = New-Thickness 0 0 0 0
    $x.SetResourceReference([Windows.Controls.Control]::ForegroundProperty, $BrushKey)
    $x.SetResourceReference([Windows.Controls.Primitives.TextBoxBase]::CaretBrushProperty, 'FgBrush')
    $x
}
function New-Meter($Body, [string]$Label) {
    $sp = [Windows.Controls.StackPanel]::new()
    $sp.Tag = 'meter'
    $sp.Margin = New-Thickness 46 4 18 8
    $g = [Windows.Controls.Grid]::new()
    $c0 = [Windows.Controls.ColumnDefinition]::new()
    $c1 = [Windows.Controls.ColumnDefinition]::new(); $c1.Width = [Windows.GridLength]::Auto
    [void]$g.ColumnDefinitions.Add($c0); [void]$g.ColumnDefinitions.Add($c1)
    $l = New-SelText $Label 'FgBrush'; $l.FontWeight = [Windows.FontWeights]::SemiBold
    $r = New-SelText '' 'MutedBrush'; $r.FontSize = 13
    [Windows.Controls.Grid]::SetColumn($r, 1)
    [void]$g.Children.Add($l); [void]$g.Children.Add($r)
    $pb = [Windows.Controls.ProgressBar]::new()
    $pb.Height = 8; $pb.Minimum = 0; $pb.Maximum = 100; $pb.Margin = New-Thickness 0 5 0 0
    $pb.BorderThickness = New-Thickness 0 0 0 0
    $pb.SetResourceReference([Windows.Controls.Control]::BackgroundProperty, 'BgBrush')
    [void]$sp.Children.Add($g); [void]$sp.Children.Add($pb)
    [void]$Body.Children.Add($sp)
    @{ Label = $l; Text = $r; Bar = $pb }
}
function Set-Meter($M, [double]$Percent, [string]$Text) {
    $M.Bar.Value = $Percent; $M.Text.Text = $Text
    $M.Bar.SetResourceReference([Windows.Controls.Control]::ForegroundProperty, $(if ($Percent -ge 90) { 'ErrFgBrush' } elseif ($Percent -ge 80) { 'WarnFgBrush' } else { 'AccentBrush' }))
}
