$InfoUI = @{}

$KCores = 'c' + [char]0x0153 + 'urs'
$SmbJunk = '^(?i)(to be filled.*|default string|system (product name|version|family|manufacturer|serial number)|not (specified|applicable|available)|none|n/?a|oem|o\.e\.m\.?|unknown|invalid|empty|x+|0+|[\s.\-_0]*)$'
# Icône « Copier » en haut à droite d'une carte, affichée au survol : copie le contenu de la carte seule
$CardCopyClick = {
    param($s, $e)
    $sb = [System.Text.StringBuilder]::new()
    Add-InfoLine $s.Tag $sb
    $name = "$($s.Tag.Tag)" -replace '^card:', ''
    $ok = $true
    try {
        [Windows.Clipboard]::SetText($sb.ToString().Trim())
    } catch {
        $ok = $false
        Write-UiLog "Copie du bloc « $name » impossible : $($_.Exception.Message)" 'ERROR'
    }
    Show-CopyFeedback $s $ok 'Copié'
}
# Retour visuel d'une copie : « Copié » / « Copiée » (ou échec) en couleur collé à une coche, pendant 3 s, puis contenu,
# infobulle, largeur et couleur d'origine du bouton rétablis. $Word : libellé accordé (ancien 3e paramètre = phrase ignorée)
$CopyFb = @{}
function Show-CopyFeedback($Btn, [bool]$Ok, [string]$Word = 'Copié') {
    if ($Word -notmatch '^Copi') { $Word = 'Copié' }
    $h = [Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($Btn)
    if (-not $CopyFb.ContainsKey($h)) { $CopyFb[$h] = @{ Content = $Btn.Content; Tip = $Btn.ToolTip; Width = $Btn.Width; Timer = $null } }
    $st = $CopyFb[$h]
    $Btn.ToolTip = $null; $Btn.Width = [double]::NaN
    $sp = [Windows.Controls.StackPanel]::new(); $sp.Orientation = 'Horizontal'
    $tx = New-Text $(if ($Ok) { $Word } else { 'Échec de la copie' })
    $tx.FontFamily = [Windows.Media.FontFamily]::new('Segoe UI'); $tx.FontSize = 12; $tx.FontWeight = [Windows.FontWeights]::SemiBold
    $tx.VerticalAlignment = 'Center'; $tx.Margin = New-Thickness 6 0 6 0
    $gl = New-Text ([string][char]$(if ($Ok) { 0xE73E } else { 0xE783 }))
    $gl.FontFamily = [Windows.Media.FontFamily]::new('Segoe MDL2 Assets'); $gl.VerticalAlignment = 'Center'
    [void]$sp.Children.Add($gl); [void]$sp.Children.Add($tx)
    $Btn.Content = $sp
    $Btn.SetResourceReference([Windows.Controls.Control]::ForegroundProperty, $(if ($Ok) { 'OkFgBrush' } else { 'ErrFgBrush' }))
    if ($st.Timer) { $st.Timer.Stop() }
    $t = [Windows.Threading.DispatcherTimer]::new(); $t.Interval = [TimeSpan]::FromSeconds(3); $t.Tag = @{ Btn = $Btn; H = $h }
    $t.Add_Tick({
        param($s, $e)
        $s.Stop(); $b = $s.Tag.Btn; $o = $CopyFb[$s.Tag.H]; $CopyFb.Remove($s.Tag.H)
        if ($o) { $b.Content = $o.Content; $b.ToolTip = $o.Tip; $b.Width = $o.Width }
        $b.ClearValue([Windows.Controls.Control]::ForegroundProperty)
        if ($b.Uid -eq 'hover' -and -not $b.Tag.IsMouseOver) { $b.Visibility = 'Hidden' }
    })
    $st.Timer = $t; $t.Start()
}
function Add-InfoCard($C, $Column) {
    Add-CardCopy $C; $C.Body.Children[0].Margin = New-Thickness 16 14 16 8
    $sp = [Windows.Controls.Border]::new(); $sp.Height = 12; [void]$C.Body.Children.Add($sp)
    $C.Card.Margin = New-Thickness 0 0 0 14; [void]$Column.Children.Add($C.Card)
}
# Petit texte gris dans l'en-tête de carte, à gauche des icônes (ancienneté d'une donnée)
function Add-CardLabel($C) {
    $hdr = $C.Body.Children[0]
    $t = New-Text '' 'Muted'; $t.FontSize = 11; $t.VerticalAlignment = 'Top'; $t.Margin = New-Thickness 8 4 4 0
    [Windows.Controls.Grid]::SetColumn($t, (Add-AutoColumn $hdr)); [void]$hdr.Children.Add($t)
    $t
}
function Add-CardCopy($C) { [void](Add-CardIcon $C 0xE8C8 'Copier' $CardCopyClick -Hover) }
# ---------- Moniteur d'activité (Accueil) : processeur (GetSystemTimes), mémoire (GlobalMemoryStatusEx), réseau
# (octets des cartes physiques actives). Relevé chaque seconde, uniquement quand l'Accueil est affiché : aucune charge sinon.
$Act = @{ N = 60; Tiles = @{}; Prev = $null }
function Format-Rate([double]$B) {
    if ($B -lt 1KB) {
        '{0:N0} o/s' -f $B
    } elseif ($B -lt 1MB) {
        '{0:N1} Ko/s' -f ($B / 1KB)
    } elseif ($B -lt 1GB) {
        '{0:N1} Mo/s' -f ($B / 1MB)
    } else {
        '{0:N2} Go/s' -f ($B / 1GB)
    }
}
# bandeau compact (une ligne, même style que le bandeau Point de restauration) : 3 sections alignées sur les colonnes de cartes,
# chacune « icône  libellé  valeur  [courbe 60 s]  détail »
function New-ActTile([string]$Key, [string]$Label, [string]$IconPath, [string]$Glyph, [int]$Col, [bool]$Two) {
    if (-not $Act.Band) {
        $bd = [Windows.Controls.Border]::new()
        $bd.Style = $Window.FindResource('Panel')
        $bd.Padding = New-Thickness 0 6 0 6
        $bd.Margin = New-Thickness 0 0 0 10
        [Windows.Controls.Grid]::SetColumnSpan($bd, 5)
        $bg = [Windows.Controls.Grid]::new()
        foreach ($w in '*', 'Auto', '*', 'Auto', '*') {
            $cd = [Windows.Controls.ColumnDefinition]::new()
            $cd.Width = $(if ($w -eq '*') { [Windows.GridLength]::new(1, 'Star') } else { [Windows.GridLength]::Auto })
            [void]$bg.ColumnDefinitions.Add($cd)
        }
        foreach ($c in 1, 3) {
            $sep = [Windows.Controls.Border]::new()
            $sep.Width = 1
            $sep.Margin = New-Thickness 0 4 0 4
            $sep.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, 'LineBrush')
            [Windows.Controls.Grid]::SetColumn($sep, $c)
            [void]$bg.Children.Add($sep)
        }
        $bd.Child = $bg; [void]$Ui.ActGrid.Children.Add($bd); $Act.Band = $bg
    }
    $g = [Windows.Controls.Grid]::new(); $g.Margin = New-Thickness 16 0 16 0; $g.Height = 30; $g.Background = [Windows.Media.Brushes]::Transparent
    [Windows.Controls.Grid]::SetColumn($g, $Col)
    foreach ($w in 'Auto', 'Auto', 'Auto', '*', 'Auto') {
        $cd = [Windows.Controls.ColumnDefinition]::new()
        $cd.Width = $(if ($w -eq '*') { [Windows.GridLength]::new(1, 'Star') } else { [Windows.GridLength]::Auto })
        [void]$g.ColumnDefinitions.Add($cd)
    }
    # libellé ajouté en premier : titre de la section pour la recherche
    $lab = New-Text $Label
    $lab.FontSize = 13
    $lab.VerticalAlignment = 'Center'
    $lab.Margin = New-Thickness 0 0 10 0
    [Windows.Controls.Grid]::SetColumn($lab, 1)
    $val = New-Text '...'
    $val.FontSize = 15
    $val.FontWeight = [Windows.FontWeights]::SemiBold
    $val.VerticalAlignment = 'Center'
    $val.MinWidth = 44
    [Windows.Controls.Grid]::SetColumn($val, 2)
    if ($IconPath) {
        $ic = [Windows.Shapes.Path]::new()
        $ic.Data = [Windows.Media.Geometry]::Parse($IconPath)
        $ic.StrokeThickness = 1.2
        $ic.Width = 18
        $ic.Height = 18
        $ic.Stretch = 'Uniform'
        $ic.SetResourceReference([Windows.Shapes.Shape]::StrokeProperty, 'HeadBrush')
    } else {
        $ic = New-Text $Glyph; $ic.FontFamily = [Windows.Media.FontFamily]::new('Segoe MDL2 Assets'); $ic.FontSize = 16
        $ic.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'HeadBrush')
    }
    $ic.VerticalAlignment = 'Center'; $ic.Margin = New-Thickness 0 0 10 0
    $cv = [Windows.Controls.Canvas]::new()
    [Windows.Controls.Grid]::SetColumn($cv, 3)
    $cv.ClipToBounds = $true
    $cv.Height = 22
    $cv.MinWidth = 40
    $cv.Margin = New-Thickness 12 0 12 0
    $cv.VerticalAlignment = 'Center'
    $det = New-Text '' 'Muted'; $det.FontSize = 11; $det.VerticalAlignment = 'Center'; [Windows.Controls.Grid]::SetColumn($det, 4)
    $fill = [Windows.Shapes.Polygon]::new(); $fill.SetResourceReference([Windows.Shapes.Shape]::FillProperty, 'AccentBrush'); $fill.Opacity = 0.16
    $line = [Windows.Shapes.Polyline]::new()
    $line.SetResourceReference([Windows.Shapes.Shape]::StrokeProperty, 'AccentBrush')
    $line.StrokeThickness = 1.3
    $line.StrokeLineJoin = 'Round'
    [void]$cv.Children.Add($fill); [void]$cv.Children.Add($line)
    $line2 = $null
    if ($Two) {
        $line2 = [Windows.Shapes.Polyline]::new()
        $line2.SetResourceReference([Windows.Shapes.Shape]::StrokeProperty, 'WarnFgBrush')
        $line2.StrokeThickness = 1.1
        $line2.StrokeLineJoin = 'Round'
        [void]$cv.Children.Add($line2)
    }
    foreach ($x in $lab, $ic, $val, $cv, $det) { [void]$g.Children.Add($x) }
    [void]$Act.Band.Children.Add($g)
    $t = @{ Value = $val; Detail = $det; Canvas = $cv; Fill = $fill; Line = $line; Line2 = $line2; H1 = [Collections.Generic.List[double]]::new(); H2 = [Collections.Generic.List[double]]::new(); Max = 100.0; Border = $g }
    $cv.Tag = $t; $cv.Add_SizeChanged({ param($s, $e) Update-ActGraph $s.Tag })
    $Act.Tiles[$Key] = $t
}
function Update-ActGraph($T) {
    $w = $T.Canvas.ActualWidth; $h = $T.Canvas.ActualHeight; if ($w -le 0 -or $h -le 0) { return }
    $n = $Act.N; $step = $w / ($n - 1); $mx = [math]::Max($T.Max, 1)
    $mk = {
        param($Hist, [bool]$Close)
        $pc = [Windows.Media.PointCollection]::new()
        $c = $Hist.Count; $x0 = ($n - $c) * $step
        for ($i = 0; $i -lt $c; $i++) { [void]$pc.Add([Windows.Point]::new($x0 + $i * $step, $h - 1 - [math]::Min([double]1, $Hist[$i] / $mx) * ($h - 2))) }
        if ($Close -and $c) { [void]$pc.Add([Windows.Point]::new($w, $h)); [void]$pc.Add([Windows.Point]::new($x0, $h)) }
        , $pc
    }
    $T.Line.Points = & $mk $T.H1 $false; $T.Fill.Points = & $mk $T.H1 $true
    if ($T.Line2) { $T.Line2.Points = & $mk $T.H2 $false }
}
function Push-ActValue($T, [double]$V, [double]$V2) {
    $T.H1.Add($V); if ($T.H1.Count -gt $Act.N) { $T.H1.RemoveAt(0) }
    if ($T.Line2) { $T.H2.Add($V2); if ($T.H2.Count -gt $Act.N) { $T.H2.RemoveAt(0) } }
}
function Get-NetByteCount {
    $rx = [double]0; $tx = [double]0
    foreach ($n in [Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()) {
        # cartes physiques actives : VPN, Hyper-V, VMware... écartés (le même trafic passerait 2 fois)
        if ("$($n.OperationalStatus)" -ne 'Up' -or "$($n.NetworkInterfaceType)" -in 'Loopback', 'Tunnel') { continue }
        if ("$($n.Description) $($n.Name)" -match '(?i)hyper-v|vethernet|virtual|vmware|virtualbox|tap-|wintun|wireguard|tailscale|zerotier|loopback|bluetooth|teredo|isatap|6to4|wan miniport') {
            continue
        }
        try { $st = $n.GetIPStatistics() } catch { try { $st = $n.GetIPv4Statistics() } catch { continue } }
        $rx += [double]$st.BytesReceived; $tx += [double]$st.BytesSent
    }
    @($rx, $tx)
}
function Update-Activity {
    if (-not $Act.Tiles.Count) { return }
    $now = [DateTime]::UtcNow
    $tm = $null; try { $tm = [_OlivM.Perf]::Times() } catch { Write-Ignored 'Mesure du processeur' $_ }
    $net = Get-NetByteCount
    $p = $Act.Prev; $Act.Prev = @{ T = $now; Times = $tm; Net = $net }
    if (-not $p) { return }
    $dt = ($now - $p.T).TotalSeconds; if ($dt -le 0.2) { return }
    # processeur : 1 - inactif / (noyau + utilisateur) ; GetSystemTimes compte l'inactif dans le temps noyau
    if ($tm -and $p.Times) {
        $di = $tm[0] - $p.Times[0]; $dk = $tm[1] - $p.Times[1]; $du = $tm[2] - $p.Times[2]; $tot = $dk + $du
        $cpu = $(if ($tot -gt 0) { [math]::Max([double]0, [math]::Min([double]100, 100 * ($tot - $di) / $tot)) } else { 0 })
        $t = $Act.Tiles.Cpu; Push-ActValue $t $cpu 0
        $t.Value.Text = '{0:N0} %' -f $cpu
        $t.Detail.Text = 'max 1 min : {0:N0} %' -f (($t.H1 | Measure-Object -Maximum).Maximum)
        Update-ActGraph $t
    }
    $m = $null; try { $m = [_OlivM.Perf]::Mem() } catch { Write-Ignored 'Mesure de la mémoire' $_ }
    if ($m) {
        $total = [double]$m[0]; $used = $total - [double]$m[1]; $pct = $(if ($total) { 100 * $used / $total } else { 0 })
        $t = $Act.Tiles.Mem; Push-ActValue $t $pct 0
        $t.Value.Text = '{0:N0} %' -f $pct
        $t.Detail.Text = '{0:N1} Go / {1:N1} Go' -f ($used / 1GB), ($total / 1GB)
        Update-ActGraph $t
    }
    # réseau : compteurs remis à zéro (carte reconnectée) = débit ignoré pour ce relevé
    $down = [math]::Max([double]0, ($net[0] - $p.Net[0]) / $dt); $up = [math]::Max([double]0, ($net[1] - $p.Net[1]) / $dt)
    $t = $Act.Tiles.Net; Push-ActValue $t $down $up
    $t.Max = [math]::Max([double]64KB, [math]::Max((($t.H1 | Measure-Object -Maximum).Maximum), (($t.H2 | Measure-Object -Maximum).Maximum)) * 1.15)
    $t.Value.Text = Format-Rate ($down + $up)
    $t.Detail.Text = '{0} {1}   {2} {3}' -f [char]0x2191, (Format-Rate $up), [char]0x2193, (Format-Rate $down)
    $t.Value.ToolTip = "Réception : $(Format-Rate $down)`nEnvoi : $(Format-Rate $up)"
    Update-ActGraph $t
}
function Initialize-Activity {
    $Ui.ActGrid.Children.Clear(); $Act.Tiles = @{}; $Act.Prev = $null; $Act.Band = $null
    New-ActTile 'Cpu' 'Processeur' 'M6,6 H14 V14 H6 Z M8.5,8.5 H11.5 V11.5 H8.5 Z M8,3 V6 M10,3 V6 M12,3 V6 M8,14 V17 M10,14 V17 M12,14 V17 M3,8 H6 M3,10 H6 M3,12 H6 M14,8 H17 M14,10 H17 M14,12 H17' '' 0 $false
    New-ActTile 'Mem' 'Mémoire' 'M1,4 H19 V11 H1 Z M4,11 V14 M7,11 V14 M10,11 V14 M13,11 V14 M16,11 V14 M3.5,6.5 H6.5 V8.5 H3.5 Z M8.5,6.5 H11.5 V8.5 H8.5 Z M13.5,6.5 H16.5 V8.5 H13.5 Z' '' 2 $false
    New-ActTile 'Net' 'Réseau' '' ([string][char]0xE774) 4 $true
    # clic sur Processeur, Mémoire ou Réseau : moniteur de ressources sur l'onglet correspondant (appui et relâchement sur
    # la même zone)
    foreach ($k in 'Cpu', 'Mem', 'Net') {
        $b = $Act.Tiles[$k].Border; $b.Cursor = [Windows.Input.Cursors]::Hand; $b.Tag = $k
        $b.ToolTip = 'Détail : processus, utilisation et analyse (moniteur de ressources)'
        $b.Add_MouseLeftButtonDown({ param($s, $e) $Act.Press = $s })
        $b.Add_MouseLeftButtonUp({
            param($s, $e)
            if (-not [object]::ReferenceEquals($Act.Press, $s)) { return }
            $Act.Press = $null
            try { Show-ResourceMonitor "$($s.Tag)" } catch { Write-UiLog "Moniteur de ressources : $($_.Exception.Message)" 'ERROR' }
        })
    }
    # largeurs fixes : la courbe ne change pas de taille quand le texte varie
    $Act.Tiles.Cpu.Detail.MinWidth = 96; $Act.Tiles.Mem.Detail.MinWidth = 112; $Act.Tiles.Net.Detail.MinWidth = 150; $Act.Tiles.Net.Value.MinWidth = 84
    foreach ($t in $Act.Tiles.Values) { $t.Detail.TextAlignment = 'Right'; $t.Value.TextAlignment = 'Right' }
    $Act.Tiles.Net.Border.ToolTip = 'Courbe : réception (bleu), envoi (orange) ; cartes physiques uniquement'
    Update-Activity
    if (-not $Act.Timer) {
        $Act.Timer = [Windows.Threading.DispatcherTimer]::new(); $Act.Timer.Interval = [TimeSpan]::FromSeconds(1)
        $Act.Timer.Add_Tick({
            if (-not (Test-AnimBusy) -and $Ui.PageInfo.Visibility -eq 'Visible' -and $Window.WindowState -ne 'Minimized' -and $Window.IsVisible) {
                try { Update-Activity } catch { Write-Ignored 'Moniteur d''activité' $_ }
            }
        })
        $Act.Timer.Start()
    }
}
function Initialize-InfoPage {
    $Ui.InfoLeft.Children.Clear(); $Ui.InfoMid.Children.Clear(); $Ui.InfoRight.Children.Clear()
    try { Initialize-Activity } catch { Write-FileLog "Moniteur d'activité : $($_.Exception.Message)" 'WARN' }
    foreach ($col in $Ui.InfoLeft, $Ui.InfoMid, $Ui.InfoRight, $Ui.SettingsPanel) { [Windows.Controls.Grid]::SetIsSharedSizeScope($col, $true) }
    $f = @{}
    # Système : Windows, démarrage et session regroupés (une seule carte au lieu de Système + Session). Champs de données
    # masqués (Édition, Version, Dernier démarrage, Allumé depuis, Domaine) gardés pour le rapport d'intervention et
    # recomposés en lignes lisibles par Update-InfoMerged.
    $c = New-Card 'Système' '' ([string][char]0xE770)
    foreach ($k in 'Poste', 'Windows', 'Installé le', 'Démarré le', 'Redémarrage en attente', 'Compte') { $f[$k] = Add-KV $c.Body $k '' }
    foreach ($k in 'Édition', 'Version', 'Dernier démarrage', 'Allumé depuis', 'Domaine') { $f[$k] = Add-KV $c.Body $k ''; $f[$k].Parent.Parent.Visibility = 'Collapsed'; $f[$k].Tag = 'data' }
    $f['Poste'].Text = $env:COMPUTERNAME
    $f['Compte'].Text = $(if ("$env:USERNAME" -ieq ("$UserName" -replace '^.*\\', '')) { $UserName } else { '{0}  (élévation : {1}\{2})' -f $UserName, $env:USERDOMAIN, $env:USERNAME })
    $f['Compte'].ToolTip = "Réglages utilisateur appliqués à ce compte`nSID : $UserSid`nCompte d'élévation (UAC) : $env:USERDOMAIN\$env:USERNAME"
    $lj = Add-KV $c.Body 'Journaux' $LogDir 'AccentBrush'
    $lj.FontWeight = [Windows.FontWeights]::Normal; $lj.TextDecorations = [Windows.TextDecorations]::Underline
    $lj.Cursor = [Windows.Input.Cursors]::Hand; $lj.Focusable = $false; $lj.ToolTip = 'Ouvrir le dossier des journaux'
    $lj.Add_PreviewMouseLeftButtonUp({ Start-Process explorer.exe -ArgumentList ('"{0}"' -f $LogDir) })
    Add-InfoCard $c $Ui.InfoLeft

    # Matériel : fabricant et modèle sur une ligne (Fabricant gardé en donnée masquée pour le rapport)
    $c = New-Card 'Matériel' '' ([string][char]0xE7F4)
    foreach ($k in 'Modèle', 'N° de série', 'BIOS / UEFI', 'Processeur', 'Carte graphique', 'Mémoire', 'Batterie', 'Fabricant') {
        $f[$k] = Add-KV $c.Body $k ''
    }
    $f['Fabricant'].Parent.Parent.Visibility = 'Collapsed'; $f['Fabricant'].Tag = 'data'
    $f['Carte graphique'].Parent.Parent.Visibility = 'Collapsed'
    $f['Batterie'].Parent.Parent.Visibility = 'Collapsed'
    Add-InfoCard $c $Ui.InfoLeft

    $c = New-Card 'Sécurité et stabilité' '' ([string][char]0xE9D9)
    $InfoUI.DiagPanel = [Windows.Controls.StackPanel]::new(); [void]$c.Body.Children.Add($InfoUI.DiagPanel)
    [void](Add-KV $InfoUI.DiagPanel 'État' 'analyse en cours...')
    $InfoUI.DiagTitle = $c.Title
    $InfoUI.DiagAge = Add-CardLabel $c
    [void](Add-CardIcon $c 0xE72C 'Actualiser' { Start-DiagCollector; Write-FileLog 'Diagnostic rapide relancé.' 'APP' })
    Add-InfoCard $c $Ui.InfoMid

    $c = New-Card 'Réseau' '' ([string][char]0xE968)
    $InfoUI.NetPanel = [Windows.Controls.StackPanel]::new(); [void]$c.Body.Children.Add($InfoUI.NetPanel)
    # ports ouverts sur le réseau (75-installation-reseau.ps1), lus une fois l'interface affichée
    New-NetPortSection $c.Body
    Add-InfoCard $c $Ui.InfoMid

    $c = New-Card 'Imprimantes' '' ([string][char]0xE749)
    $InfoUI.PrnPanel = [Windows.Controls.StackPanel]::new(); [void]$c.Body.Children.Add($InfoUI.PrnPanel)
    [void](Add-CardIcon $c 0xE72C 'Actualiser' { $Sync.PrnRequest = $true })
    Add-InfoCard $c $Ui.InfoMid
    Update-Printer

    # bandeau « Toutes les mises à jour » (même gabarit que le bandeau Point de restauration) : un seul bouton
    # qui lance la recherche Windows Update et la recherche constructeur
    $ab = [Windows.Controls.Border]::new()
    $ab.Style = $Window.FindResource('Panel')
    $ab.Padding = New-Thickness 16 8 16 8
    $ab.Margin = New-Thickness 0 0 0 14
    $ad = [Windows.Controls.DockPanel]::new(); $ab.Child = $ad
    $InfoUI.AllSearchBtn = New-Button 'Tout rechercher' 'PrimaryBtn'
    $InfoUI.AllSearchBtn.Margin = New-Thickness 12 0 0 0
    $InfoUI.AllSearchBtn.VerticalAlignment = 'Center'
    $InfoUI.AllSearchBtn.ToolTip = 'Lance en même temps la recherche Windows Update et la recherche constructeur'
    $InfoUI.AllSearchBtn.Add_Click({ Start-AllUpdateSearch })
    [Windows.Controls.DockPanel]::SetDock($InfoUI.AllSearchBtn, 'Right'); [void]$ad.Children.Add($InfoUI.AllSearchBtn)
    $ai = New-Text ([string][char]0xE895); $ai.Style = $Window.FindResource('CardIcon'); [void]$ad.Children.Add($ai)
    $at = [Windows.Controls.StackPanel]::new(); $at.VerticalAlignment = 'Center'
    $t1 = New-Text 'Toutes les mises à jour'; $t1.FontSize = 14; $t1.FontWeight = [Windows.FontWeights]::SemiBold; [void]$at.Children.Add($t1)
    $t2 = New-Text 'Windows Update et constructeur en une seule recherche' 'Muted'; $t2.TextWrapping = 'Wrap'; [void]$at.Children.Add($t2)
    [void]$ad.Children.Add($at); [void]$Ui.InfoRight.Children.Add($ab)

    $c = New-Card 'Mises à jour Windows' '' ([string][char]0xE895)
    $InfoUI.WuAge = Add-CardLabel $c
    $InfoUI.WuPanel = [Windows.Controls.StackPanel]::new(); [void]$c.Body.Children.Add($InfoUI.WuPanel)
    $bar = [Windows.Controls.WrapPanel]::new(); $bar.Margin = New-Thickness 46 6 16 0
    $InfoUI.WuBtn = New-Button 'Installer tout' 'PrimaryBtn'; $InfoUI.WuBtn.IsEnabled = $false
    $InfoUI.WuBtn.Add_Click({
        $selU = @(Get-WuSelection); $n = $selU.Count; if (-not $n) { return }
        $tot = @($Sync.WuPending.Items).Count
        $msg = $(if ($n -eq 1) { 'Installer cette mise à jour ?' } else { "Installer ces $n mises à jour ?" })
        if ($n -lt $tot) {
            $msg += "`n`n{0} {1} disponible{2}." -f ($tot - $n), (Get-Plural ($tot - $n) 'autre mise à jour reste' 'autres mises à jour restent'), $(if ($tot - $n -gt 1) { 's' } else { '' })
        }
        if (-not (Confirm-List $msg @($selU | ForEach-Object { $_.Title }) 'Un redémarrage du poste peut être nécessaire à la fin.' 'Installer' 'ActionBtn')) {
            return
        }
        $Sync.WuSel = @($selU | Where-Object { $_.Id } | ForEach-Object { $_.Id })
        [void](Start-Worker @('WuInstall'))
    })
    $InfoUI.WuSearchBtn = New-Button 'Rechercher' 'PrimaryBtn'
    $InfoUI.WuSearchBtn.Add_Click({ Start-WuOnlineSearch })
    $InfoUI.WuCancelBtn = New-Button 'Annuler la recherche' 'WarnBtn'; $InfoUI.WuCancelBtn.Visibility = 'Collapsed'
    $InfoUI.WuCancelBtn.Add_Click({ Stop-WuSearch })
    $InfoUI.WuRebootBtn = New-Button 'Programmer un redémarrage' 'ActionBtn'; $InfoUI.WuRebootBtn.Visibility = 'Collapsed'
    $InfoUI.WuRebootBtn.Add_Click({ Request-Reboot; Show-WuPending })
    $InfoUI.WuUnRebootBtn = New-Button 'Annuler le redémarrage' 'WarnBtn'; $InfoUI.WuUnRebootBtn.Visibility = 'Collapsed'
    $InfoUI.WuUnRebootBtn.Add_Click({ Stop-ScheduledReboot; Show-WuPending })
    [void]$bar.Children.Add($InfoUI.WuRebootBtn); [void]$bar.Children.Add($InfoUI.WuUnRebootBtn)
    [void]$bar.Children.Add($InfoUI.WuBtn)
    [void]$bar.Children.Add($InfoUI.WuSearchBtn)
    [void]$bar.Children.Add($InfoUI.WuCancelBtn)
    # suspension jusqu'à une date (Suspendre / Reprendre selon l'état)
    $InfoUI.WuPauseBtn = New-Button 'Suspendre'; $InfoUI.WuPauseBtn.Add_Click({ Switch-WuPause })
    [void]$bar.Children.Add($InfoUI.WuPauseBtn); Update-WuPauseButton
    [void]$c.Body.Children.Add($bar)
    Add-InfoCard $c $Ui.InfoRight
    Show-WuPending

    $c = New-Card 'Mises à jour constructeur' '' ([string][char]0xE896)
    $InfoUI.OemAge = Add-CardLabel $c
    $InfoUI.OemPanel = [Windows.Controls.StackPanel]::new(); [void]$c.Body.Children.Add($InfoUI.OemPanel)
    $bar = [Windows.Controls.WrapPanel]::new(); $bar.Margin = New-Thickness 46 6 16 0
    $InfoUI.OemBtn = New-Button 'Rechercher' 'PrimaryBtn'
    $InfoUI.OemBtn.Add_Click({ Start-OemScan })
    $InfoUI.OemInstBtn = New-Button 'Installer tout' 'PrimaryBtn'; $InfoUI.OemInstBtn.IsEnabled = $false
    $InfoUI.OemInstBtn.Add_Click({
        $ids = @(Get-OemInstallId)
        if (-not $ids.Count) { return }
        $names = @($Sync.OemResult.Items | Where-Object { $ids -contains $_.Id } | ForEach-Object { '{0}{1}{2}' -f $_.Title, $(if ($_.Version) { "  ·  version $($_.Version)" } else { '' }), $(if ($_.Unattended) { '' } else { '  (interactive)' }) })
        $tot = @($Sync.OemResult.Items | Where-Object { $_ -and $_.Id }).Count; $n = $ids.Count
        $msg = $(if ($n -eq 1) { 'Installer cette mise à jour ?' } else { "Installer ces $n mises à jour ?" })
        if ($n -lt $tot) {
            $msg += "`n`n{0} {1} disponible{2}." -f ($tot - $n), (Get-Plural ($tot - $n) 'autre mise à jour reste' 'autres mises à jour restent'), $(if ($tot - $n -gt 1) { 's' } else { '' })
        }
        if (-not (Confirm-List $msg $names 'Un redémarrage du poste peut être nécessaire à la fin. BIOS et firmware : sur un portable, brancher le secteur avant l''installation.' 'Installer' 'ActionBtn')) {
            return
        }
        Start-OemInstall $ids
    })
    [void]$bar.Children.Add($InfoUI.OemInstBtn)
    $InfoUI.OemToolBtn = New-Button 'Installer l''outil' 'PrimaryBtn'; $InfoUI.OemToolBtn.Visibility = 'Collapsed'
    $InfoUI.OemToolBtn.Add_Click({ Start-OemToolInstall })
    [void]$bar.Children.Add($InfoUI.OemToolBtn)
    $InfoUI.OemCancelBtn = New-Button 'Annuler la recherche' 'WarnBtn'; $InfoUI.OemCancelBtn.Visibility = 'Collapsed'
    $InfoUI.OemCancelBtn.Add_Click({ Stop-OemScan })
    [void]$bar.Children.Add($InfoUI.OemCancelBtn)
    [void]$bar.Children.Add($InfoUI.OemBtn); [void]$c.Body.Children.Add($bar)
    Add-InfoCard $c $Ui.InfoRight
    try {
        if (Test-Path -LiteralPath $OemFile) { $Sync.OemResult = Get-Content -LiteralPath $OemFile -Raw -Encoding UTF8 | ConvertFrom-Json }
    } catch {
        Write-Ignored 'Lecture de la dernière recherche constructeur' $_
    }
    Show-OemResult

    $c = New-Card 'Stockage' '' ([string][char]0xEDA2)
    $InfoUI.VolPanel  = [Windows.Controls.StackPanel]::new(); [void]$c.Body.Children.Add($InfoUI.VolPanel)
    $InfoUI.DiskPanel = [Windows.Controls.StackPanel]::new(); [void]$c.Body.Children.Add($InfoUI.DiskPanel)
    [void](Add-CardIcon $c 0xE72C 'Actualiser la santé des disques' { $Sync.DiskRequest = $true })
    Add-InfoCard $c $Ui.InfoRight

    $InfoUI.F = $f; $InfoUI.Vols = @{}; $InfoUI.VolSig = ''; $InfoUI.DiskSig = ''; $InfoUI.NetSig = ''
    Set-InfoStatic
    Update-InfoFast -Force
}

function Set-InfoStatic {
    $f = $InfoUI.F
    $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $name = "$($cv.ProductName)"; if ([int]$cv.CurrentBuild -ge 22000) { $name = $name -replace '^Windows 10', 'Windows 11' }
    # architecture accolée à l'édition ; ARM64 distingué (Is64BitOperatingSystem ne fait pas la différence)
    $InfoUI.Arch = $(if ("$env:PROCESSOR_ARCHITECTURE$env:PROCESSOR_ARCHITEW6432" -match 'ARM64') { 'ARM 64 bits' } elseif ([Environment]::Is64BitOperatingSystem) { '64 bits' } else { '32 bits' })
    $f['Édition'].Text = $name + '  ' + [char]0x00B7 + '  ' + $InfoUI.Arch
    $f['Version'].Text = '{0}  (build {1}.{2})' -f $(if ($cv.DisplayVersion) { $cv.DisplayVersion } else { $cv.ReleaseId }), $cv.CurrentBuild, $cv.UBR
    if ($cv.InstallDate) { $f['Installé le'].Text = '{0:dd/MM/yyyy}' -f [DateTimeOffset]::FromUnixTimeSeconds([long]$cv.InstallDate).LocalDateTime }
    if ($BootTime -and $BootTime -gt [DateTime]::MinValue) { $f['Dernier démarrage'].Text = '{0:dd/MM/yyyy HH:mm}' -f $BootTime }
    $bios = Get-ItemProperty 'HKLM:\HARDWARE\DESCRIPTION\System\BIOS' -ErrorAction SilentlyContinue
    # PC assemblé (« System manufacturer », « System Product Name », « To be filled by O.E.M. »...) : fabricant et modèle de
    # la carte mère (mêmes données SMBIOS, clé BIOS du registre), signalés comme tels ; rien de lisible : indiqué
    $man = "$($bios.SystemManufacturer)".Trim(); $mod = "$($bios.SystemProductName)".Trim()
    $bbMan = "$($bios.BaseBoardManufacturer)".Trim(); $bbMod = "$($bios.BaseBoardProduct)".Trim()
    $f['Fabricant'].Text = $(
        if ($man -and $man -notmatch $SmbJunk) { $man }
        elseif ($bbMan -and $bbMan -notmatch $SmbJunk) { "$bbMan  (carte mère, PC assemblé)" }
        else { 'non renseigné par le fabricant' }
    )
    $InfoUI.ModelRaw = $(
        if ($mod -and $mod -notmatch $SmbJunk) { $mod + $(if ($bios.SystemVersion -and $bios.SystemVersion -ne $bios.SystemProductName -and "$($bios.SystemVersion)".Trim() -notmatch $SmbJunk) { "  ($($bios.SystemVersion))" } else { '' }) }
        elseif ($bbMod -and $bbMod -notmatch $SmbJunk) { "$bbMod  (carte mère)" }
        else { 'non renseigné par le fabricant' }
    )
    $bd = ''
    try { $bd = '  ({0:dd/MM/yyyy})' -f [DateTime]::ParseExact("$($bios.BIOSReleaseDate)", 'MM/dd/yyyy', [Globalization.CultureInfo]::InvariantCulture) } catch {}
    $f['BIOS / UEFI'].Text = "$($bios.BIOSVersion)$bd"
    $InfoUI.CpuName = "$((Get-ItemProperty 'HKLM:\HARDWARE\DESCRIPTION\System\CentralProcessor\0' -ErrorAction SilentlyContinue).ProcessorNameString)".Trim() -replace '\s{2,}', ' '
    $f['Processeur'].Text = $InfoUI.CpuName
    # installée (barrettes, lecture différée) puis utilisable par Windows (moins la mémoire réservée : vidéo intégrée, firmware)
    $InfoUI.RamUse = ''
    try {
        Add-Type -AssemblyName Microsoft.VisualBasic
        $InfoUI.RamUse = '{0:N1} Go utilisables' -f ([Microsoft.VisualBasic.Devices.ComputerInfo]::new().TotalPhysicalMemory / 1GB)
    } catch {
        Write-Ignored 'Lecture de la mémoire installée' $_
    }
    $f['Mémoire'].Text = '...' + $(if ($InfoUI.RamUse) { '  ' + [char]0x00B7 + '  ' + $InfoUI.RamUse } else { '' })
    $dom = "$((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' -ErrorAction SilentlyContinue).Domain)"
    if ($dom) { $f['Domaine'].Text = $dom }
    Update-Uptime; Update-InfoMerged
}

function Get-NetFast {
    foreach ($ni in [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()) {
        if ("$($ni.OperationalStatus)" -ne 'Up' -or "$($ni.NetworkInterfaceType)" -in 'Loopback', 'Tunnel') { continue }
        $p = $ni.GetIPProperties()
        $v4 = @($p.UnicastAddresses | Where-Object { "$($_.Address.AddressFamily)" -eq 'InterNetwork' -and -not "$($_.Address)".StartsWith('169.254.') })
        if (-not $v4) { continue }
        $pl = try { $v4[0].PrefixLength } catch { $null }
        if (-not $pl) {
            $pl = 0
            foreach ($byte in $v4[0].IPv4Mask.GetAddressBytes()) { $x = [int]$byte; while ($x) { $pl += $x -band 1; $x = $x -shr 1 } }
        }
        $gw  = @($p.GatewayAddresses | Where-Object { "$($_.Address.AddressFamily)" -eq 'InterNetwork' } | ForEach-Object { "$($_.Address)" })
        $dns = @($p.DnsAddresses | Where-Object { "$($_.AddressFamily)" -eq 'InterNetwork' } | ForEach-Object { "$_" })
        $wifi = "$($ni.NetworkInterfaceType)" -eq 'Wireless80211'
        $ssid = $null
        if ($wifi -and $Sync.Ssid) { $ssid = $Sync.Ssid[$ni.Id.Trim('{}').ToLower()] }
        @{ Alias = $ni.Name; Ip = '{0}/{1}' -f $v4[0].Address, $pl; Gw = $(if ($gw) { $gw[0] } else { '-' }); Dns = ($dns -join ' / '); Wifi = $wifi; Ssid = $ssid }
    }
}
# Accueil, rafraîchi chaque seconde quand il est affiché : seuls les éléments qui ont changé sont réécrits (signatures),
# cartes réseau relues toutes les 5 s (et à chaque affichage de la page ou F5 : -Force)
function Update-InfoFast([switch]$Force) {
    $f = $InfoUI.F
    if ($Force) { $InfoUI.RebootSig = $null; $InfoUI.VolFastSig = $null }
    # lecture protégée : une erreur ne doit pas laisser la ligne vide (elle restait sans valeur)
    $rs = try { Get-RebootState -Force:$Force } catch { if (-not $InfoUI.RebootErr) { $InfoUI.RebootErr = $true; Write-FileLog "Redémarrage en attente : lecture impossible - $($_.Exception.Message)" 'WARN' }; @{ Why = @(); WuAt = $null } }
    $pending = [bool]@($rs.Why).Count
    # programmé : par l'outil (shutdown /r /t) ou par Windows Update (Paramètres > Planifier le redémarrage)
    $at = $(if ($Sync.RebootAt -and $Sync.RebootAt -gt [DateTime]::Now) { $Sync.RebootAt } elseif ($rs.WuAt) { $rs.WuAt } else { $null })
    $plan = [bool]$at
    $rsig = '{0}|{1:yyyyMMddHHmm}|{2:yyyyMMdd}' -f (@($rs.Why) -join ';'), $at, [DateTime]::Today
    if ($rsig -ne $InfoUI.RebootSig) {
        $InfoUI.RebootSig = $rsig
        $when = $(if ($plan -and $at.Date -eq [DateTime]::Today) { 'à {0:HH:mm}' -f $at } elseif ($plan) { 'le {0:dd/MM} à {0:HH:mm}' -f $at } else { '' })
        $who = $(if ($plan -and -not ($Sync.RebootAt -and $Sync.RebootAt -gt [DateTime]::Now)) { ' par Windows Update' } else { '' })
        $row = $f['Redémarrage en attente']
        $row.Text = $(
            if ($pending -and $plan) { "Oui, programmé {0}{1}`n- {2}" -f $when, $who, (@($rs.Why) -join "`n- ") }
            elseif ($pending) { "Oui :`n- " + (@($rs.Why) -join "`n- ") }
            elseif ($plan) { 'Non, mais redémarrage programmé {0}{1}' -f $when, $who }
            else { 'Non' }
        )
        $row.SetResourceReference([Windows.Controls.Control]::ForegroundProperty, $(if ($pending) { 'WarnFgBrush' } else { 'OkFgBrush' }))
        $row.FontWeight = $(if ($pending) { [Windows.FontWeights]::SemiBold } else { [Windows.FontWeights]::Normal })
    }

    $vsig = $(if ($null -ne $Sync.Vols) { (@($Sync.Vols) | ForEach-Object { '{0}|{1}|{2}|{3}' -f $_.Name, $_.Label, $_.Free, $_.Total }) -join ',' } else { $null })
    if ($null -ne $Sync.Vols -and $vsig -ne $InfoUI.VolFastSig) {
        $InfoUI.VolFastSig = $vsig
        $vols = @($Sync.Vols)
        Update-StorageLayout
        $fmt = { param($b) if ($b -ge 1GB) { '{0:N1} Go' -f ($b / 1GB) } else { Format-SizeUi $b } }
        foreach ($v in $vols) {
            $m = $InfoUI.Vols[$v.Name]
            $ltr = $v.Name.TrimEnd('\')
            if (-not $m) { continue }
            $m.Label.Text = '{0}  {1}  ({2}){3}' -f $ltr, $v.Label, $v.Fs, $(if ($v.Rem) { '  ·  amovible' } else { '' })
            $used = if ($v.Total) { 100 * ($v.Total - $v.Free) / $v.Total } else { 0 }
            $fr = & $fmt $v.Free
            Set-Meter $m $used $(if ($v.Free -le 0) { 'Plein : {0}' -f (& $fmt $v.Total) } else { '{0} {1} sur {2}' -f $fr, (Get-PluralOf $fr 'libre' 'libres'), (& $fmt $v.Total) })
        }
    }

    $InfoUI.NetTick = 1 + [int]$InfoUI.NetTick
    if (-not $Force -and $InfoUI.NetSig -and $InfoUI.NetTick % 5) { return }
    $nets = @(Get-NetFast)
    $raw = ($nets | ForEach-Object { "$($_.Alias)|$($_.Ip)|$($_.Gw)" }) -join ','
    if ($raw -ne $InfoUI.NetRaw) { $InfoUI.NetRaw = $raw; if (@($nets | Where-Object { $_.Wifi }).Count) { Start-SsidJob } }
    $sig = ($nets | ForEach-Object { "$($_.Alias)|$($_.Ip)|$($_.Gw)|$($_.Dns)|$($_.Ssid)" }) -join ','
    $sig += "|$($null -ne $Sync.Ssid)"
    if ($sig -ne $InfoUI.NetSig) {
        $InfoUI.NetPanel.Children.Clear()
        if ($nets.Count -eq 0) { [void](Add-KV $InfoUI.NetPanel 'État' 'Aucune carte connectée' 'WarnFgBrush') }
        $first = $true
        foreach ($n in $nets) {
            if (-not $first) {
                $sep = [Windows.Controls.Border]::new(); $sep.Height = 1; $sep.Margin = New-Thickness 42 6 10 6
                $sep.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, 'LineBrush')
                [void]$InfoUI.NetPanel.Children.Add($sep)
            }
            $first = $false
            $hb = Add-KV $InfoUI.NetPanel $n.Alias $n.Ip
            try { $hb.Parent.Children[0].FontWeight = [Windows.FontWeights]::SemiBold } catch {}
            if ($n.Wifi) {
                $w = if ($null -eq $Sync.Ssid) { 'recherche...' } elseif ($n.Ssid) { $n.Ssid } else { 'nom indisponible' }
                [void](Add-KV $InfoUI.NetPanel '   Réseau Wi-Fi' $w)
            }
            [void](Add-KV $InfoUI.NetPanel '   Passerelle' $n.Gw)
            [void](Add-KV $InfoUI.NetPanel '   DNS' $n.Dns)
        }
        $InfoUI.NetSig = $sig
    }
}

# Imprimante par défaut de l'utilisateur ciblé. Même compte que celui qui exécute l'application : méthode documentée
# Win32_Printer.SetDefaultPrinter. Autre compte (application lancée avec un compte administrateur) : valeur Device de sa
# ruche (HKU\<SID>\Software\Microsoft\Windows NT\CurrentVersion\Windows, « Nom,winspool,port » repris de la clé
# Devices), puis WM_SETTINGCHANGE « windows » diffusé aux applications ouvertes. Dans les deux cas « Laisser Windows gérer
# mon imprimante par défaut » désactivé pour ce compte (LegacyDefaultPrinterMode = 1), sinon Windows la remplace par la
# dernière imprimante utilisée.
# texte entre apostrophes d'une requête WQL : barre oblique inverse et apostrophe échappées
function ConvertTo-WqlString([string]$S) { $S.Replace('\', '\\').Replace("'", "\'") }
function Set-DefaultPrinter($P) {
    $names = @("$($P.Name)", "$($P.Source)") | Where-Object { $_ }
    if (-not (Confirm-Action ("Définir « {0} » comme imprimante par défaut de {1} ?`n`n« Laisser Windows gérer mon imprimante par défaut » est désactivé pour ce compte : l'imprimante choisie reste celle par défaut." -f $P.Name, $UserName))) { return }
    try {
        $self = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value -eq $UserSid
        Set-RegValue 'HKCU\Software\Microsoft\Windows NT\CurrentVersion\Windows' 'LegacyDefaultPrinterMode' 1
        if ($self) {
            # requête filtrée sur le nom (avant : toutes les imprimantes interrogées, plusieurs secondes de fenêtre figée avec des
            # imprimantes réseau hors ligne)
            $wq = (@($names | ForEach-Object { "Name='{0}'" -f (ConvertTo-WqlString $_) }) -join ' OR ')
            $wp = @(Get-CimInstance Win32_Printer -Filter $wq -ErrorAction Stop) | Select-Object -First 1
            if (-not $wp) { throw 'imprimante introuvable (Win32_Printer)' }
            $rc = (Invoke-CimMethod -InputObject $wp -MethodName SetDefaultPrinter -ErrorAction Stop).ReturnValue
            if ($rc -ne 0) { throw "SetDefaultPrinter : code $rc" }
        } else {
            $dev = $null; $hit = $null
            foreach ($n in $names) { $dev = Get-RegValue 'HKCU\Software\Microsoft\Windows NT\CurrentVersion\Devices' $n; if ($dev) { $hit = $n; break } }
            if (-not $dev) { throw "imprimante absente du profil de $UserName (clé Devices)" }
            Set-RegValue 'HKCU\Software\Microsoft\Windows NT\CurrentVersion\Windows' 'Device' ('{0},{1}' -f $hit, $dev) 'String'
            try { [void][_OlivM.Shell]::NotifySettingChange('windows') } catch { Write-Ignored 'Imprimante par défaut (notification aux applications)' $_ }
        }
        Write-UiLog ('Imprimante par défaut de {0} : {1}{2}.' -f $UserName, $P.Name, $(if ($self) { '' } else { ' (profil de l''utilisateur ciblé)' })) 'OK'
        Add-SessionEvent 'Imprimantes' 'Imprimante par défaut' $P.Name 'ok'
    } catch {
        Write-UiLog ('Imprimante par défaut : {0} non définie - {1}' -f $P.Name, $_.Exception.Message) 'WARN'
        Show-Info ("Impossible de définir « $($P.Name) » comme imprimante par défaut.`n`n$($_.Exception.Message)") 'Warn'
    }
    Update-Printer
}
# bouton « Par défaut » au bout de la ligne d'une imprimante, visible au survol de la ligne
function Add-PrinterDefaultButton($Value, $P) {
    $g = $Value.Parent; $hb = $g.Parent
    $cd = [Windows.Controls.ColumnDefinition]::new(); $cd.Width = [Windows.GridLength]::Auto; [void]$g.ColumnDefinitions.Add($cd)
    $b = New-Button 'Définir par défaut'; $b.Height = 24; $b.FontSize = 11; $b.Padding = New-Thickness 10 0 10 0; $b.Margin = New-Thickness 10 -2 0 -2
    $b.VerticalAlignment = 'Center'; $b.Visibility = 'Hidden'; $b.Tag = $P
    $b.ToolTip = "Imprimante par défaut de $UserName"
    [Windows.Controls.Grid]::SetColumn($b, 2); [void]$g.Children.Add($b)
    $b.Add_Click({ param($s, $e) Set-DefaultPrinter $s.Tag })
    # Tag de la ligne réservé (« kv » : copie, recherche) : bouton rangé dans ses ressources
    $hb.Resources['PrnBtn'] = $b
    $hb.Add_MouseEnter({ param($s, $e) $s.Resources['PrnBtn'].Visibility = 'Visible' })
    $hb.Add_MouseLeave({ param($s, $e) $s.Resources['PrnBtn'].Visibility = 'Hidden' })
}
function Update-Printer {
    if (-not $InfoUI.PrnPanel) { return }
    $list = [Collections.Generic.List[object]]::new()
    $k = Open-RegKey 'HKCU\Printers\Connections'
    if ($k) {
        try {
            foreach ($n in $k.GetSubKeyNames()) {
                $p = $n -split ','
                if ($p.Count -ge 4) { $list.Add(@{ Name = $p[3]; Source = ('\\{0}\{1}' -f $p[2], $p[3]) }) }
            }
        } finally {
            $k.Close()
        }
    }
    $loaded = $Sync.InfoSlow -and $Sync.InfoSlow.PrnStamp
    if ($loaded) { foreach ($x in @($Sync.InfoSlow.Printers)) { $list.Add($x) } }
    $def = "$(Get-RegValue 'HKCU\Software\Microsoft\Windows NT\CurrentVersion\Windows' 'Device')".Split(',')[0]
    $InfoUI.PrnPanel.Children.Clear()
    if ($list.Count -eq 0) {
        Add-StateLine $InfoUI.PrnPanel $(if ($loaded) { 'Aucune imprimante' } else { 'Lecture des imprimantes...' }) 'MutedBrush'
        return
    }
    # imprimante par défaut en premier, puis ordre alphabétique
    $more = [Windows.Controls.StackPanel]::new(); $idx = 0
    foreach ($x in ($list | Sort-Object @{ Expression = { -not (($def -eq $_.Name) -or ($def -eq $_.Source)) } }, @{ Expression = { $_.Name } })) {
        $isDef = ($def -eq $x.Name) -or ($def -eq $x.Source)
        $v = Add-KV $(if ($idx -lt $ListMax) { $InfoUI.PrnPanel } else { $more }) $x.Name ($x.Source + $(if ($isDef) { '  ·  par défaut' } else { '' }))
        if (-not $isDef) { Add-PrinterDefaultButton $v $x }
        $idx++
    }
    Add-FoldMore $InfoUI.PrnPanel $more $list.Count 'Printers'
}

# Disque physique : état, type et taille en colonnes alignées (le texte complet reste dans la ligne pour la copie)
# Stockage regroupé par disque physique (ordre des numéros de disque) : en-tête du disque (modèle, état, type, taille)
# puis ses volumes ; survol = groupe surligné, textes sélectionnables. Volumes sans disque connu à la fin.
function Update-StorageLayout {
    $vols = @($Sync.Vols); $s = $Sync.InfoSlow
    $disks = @(); $vd = @{}
    if ($s -and $null -ne $s.Disks) {
        $disks = @($s.Disks | Sort-Object { $(if ("$($_.Id)" -match '^\d+$') { [int]$_.Id } else { 999 }) })
        if ($s.VolDisk) { $vd = $s.VolDisk }
    }
    $sig = (@($vols | ForEach-Object { "$($_.Name)|$($_.Total)" }) + @($disks | ForEach-Object { "$($_.Id)|$($_.Name)|$($_.Health)" }) + @($vd.Keys | Sort-Object | ForEach-Object { "$_=$(@($vd[$_]) -join '+')" })) -join ','
    if ($sig -eq $InfoUI.VolSig) { return }
    $InfoUI.VolSig = $sig
    $InfoUI.VolPanel.Children.Clear(); $InfoUI.Vols = @{}; $InfoUI.DiskPanel.Children.Clear(); $InfoUI.StorGroups = @(); $InfoUI.StorSel = $null
    $sep = '  ' + [char]0x00B7 + '  '
    $byId = @{}; foreach ($d in $disks) { $byId["$($d.Id)"] = $d }
    # une ligne discrète par volume : disque, modèle, type ; état coloré (sain en vert, avertissement en orange, défaillant en rouge)
    $diskLine = {
        param($Parent, $D, [bool]$WithSize)
        $h = $HealthFr["$($D.Health)"]; if (-not $h) { $h = @("$($D.Health)", 'WarnFgBrush') }
        $wp = [Windows.Controls.WrapPanel]::new(); $wp.Margin = New-Thickness 0 4 0 0
        $parts = @($(if ("$($D.Id)" -match '^\d+$') { "Disque $($D.Id)" } else { 'Disque' }), "$($D.Name)".Trim(), ("$($D.Media) $($D.Bus)").Trim())
        if ($WithSize) { $parts += ('{0:N0} Go' -f ($D.Size / 1GB)) }
        $t = New-SelText ((@($parts | Where-Object { $_ }) -join $sep) + $sep) 'MutedBrush'; $t.FontSize = 12
        # état coloré comme partout : sain = vert, avertissement = orange, défaillant = rouge
        $st = New-SelText $h[0] $h[1]; $st.FontSize = 12
        if ($h[1] -ne 'OkFgBrush') { $st.FontWeight = [Windows.FontWeights]::SemiBold }
        [void]$wp.Children.Add($t); [void]$wp.Children.Add($st); [void]$Parent.Children.Add($wp)
    }
    # survol comme les lignes clé / valeur (HoverPlain) : même retrait de texte (38 + 8 = 46) et même marge à droite
    $hoverWrap = {
        param($Sp)
        [void]$InfoUI.VolPanel.Children.Remove($Sp)
        $hb = [Windows.Controls.Border]::new(); $hb.Style = $Window.FindResource('HoverPlain'); $hb.Margin = New-Thickness 38 0 10 2
        $Sp.Margin = New-Thickness 8 4 8 6; $hb.Child = $Sp; [void]$InfoUI.VolPanel.Children.Add($hb)
    }
    $used = @{}
    $order = @($vols | Sort-Object {
        $ids = @($vd[$_.Name.TrimEnd('\')])
        if ($ids.Count -and "$($ids[0])" -match '^\d+$') { [int]$ids[0] } else { 999 }
    }, Name)
    foreach ($v in $order) {
        $m = New-Meter $InfoUI.VolPanel ''
        $InfoUI.Vols[$v.Name] = $m
        $ids = @($vd[$v.Name.TrimEnd('\')])
        if ($ids.Count -and $byId.ContainsKey("$($ids[0])")) {
            & $diskLine $m.Bar.Parent $byId["$($ids[0])"] $false
            foreach ($i in $ids) { $used["$i"] = 1 }
        }
        & $hoverWrap $m.Bar.Parent
    }
    # disques sans lecteur (non initialisé, sans partition reconnue) : une seule ligne en fin de carte
    foreach ($d in $disks) {
        if ($used.ContainsKey("$($d.Id)")) { continue }
        $sp = [Windows.Controls.StackPanel]::new(); $sp.Tag = 'meter'; $sp.Margin = New-Thickness 46 4 18 8
        $g = [Windows.Controls.Grid]::new(); $l = New-SelText 'Sans lecteur' 'MutedBrush'; $l.FontSize = 13
        $r = New-SelText '' 'MutedBrush'; [void]$g.Children.Add($l); [void]$g.Children.Add($r); [void]$sp.Children.Add($g)
        & $diskLine $sp $d $true
        [void]$InfoUI.VolPanel.Children.Add($sp); & $hoverWrap $sp
    }
}
function Show-InfoSlow($S) {
    $f = $InfoUI.F
    if ($S.PrnStamp -and $S.PrnStamp -ne $InfoUI.PrnShown) { $InfoUI.PrnShown = $S.PrnStamp; Update-Printer }
    if ($S.Caption) { $f['Édition'].Text = $S.Caption + $(if ($InfoUI.Arch) { '  ' + [char]0x00B7 + '  ' + $InfoUI.Arch } else { '' }) }
    if ($S.Serial)  {
        $f['N° de série'].Text = $S.Serial
        $f['N° de série'].ToolTip = $(if ($S.SerialSrc -and $S.SerialSrc -ne 'aucun') { "Source : $($S.SerialSrc) (SMBIOS)" } else { $null })
        # ligne « Constructeur » des mises à jour constructeur affichée avant la collecte : n° de série ajouté
        if (-not $InfoUI.OemSerialShown -and $InfoUI.OemPanel -and -not $Sync.OemRunning -and -not $Sync.OemInstalling) { Show-OemResult }
    }
    if ($S.Ram)     {
        $f['Mémoire'].Text = ('{0:N0} Go installés' -f ($S.Ram / 1GB)) + $(if ($InfoUI.RamUse) { '  ' + [char]0x00B7 + '  ' + $InfoUI.RamUse } else { '' })
    }
    if ($S.Cores)   {
        $th = [Environment]::ProcessorCount
        $f['Processeur'].Text = '{0}  ·  {1} {2} / {3} {4}' -f $InfoUI.CpuName, $S.Cores, $(if ([int]$S.Cores -gt 1) { $KCores } else { 'c' + [char]0x0153 + 'ur' }), $th, $(if ($th -gt 1) { 'threads' } else { 'thread' })
    }
    if ($S.Domain)  { $f['Domaine'].Text = $S.Domain }
    if ($null -ne $S.Gpu) {
        # cartes dédiées seules ; à défaut (portable, bureautique), la puce intégrée avec la mention « intégrée »
        $all = @($S.Gpu); $show = @($all | Where-Object { -not $_.Integrated }); $integ = $show.Count -eq 0
        if ($integ) { $show = $all }
        $gv = $f['Carte graphique']; $grow = $gv.Parent.Parent
        if ($show.Count) {
            $gv.Text = (@($show | ForEach-Object { $_.Name + $(if ($_.Vram -ge 256MB -and -not $_.Integrated) { '  ' + [char]0x00B7 + '  {0:N0} Go' -f ($_.Vram / 1GB) } else { '' }) + $(if ($_.Integrated) { '  (intégrée)' } else { '' }) }) -join "`n")
            $gv.ToolTip = (@($show | Where-Object { $_.Driver } | ForEach-Object { '{0} : pilote {1}{2}' -f $_.Name, $_.Driver, $(if ($_.DriverDate) { " du $($_.DriverDate)" } else { '' }) }) -join "`n")
            $gv.Parent.Children[0].Text = $(if ($show.Count -gt 1) { 'Cartes graphiques' } else { 'Carte graphique' })
            $grow.Visibility = 'Visible'
        } else { $grow.Visibility = 'Collapsed' }
    }
    if ($S.Battery) {
        $bt = $f['Batterie']; $row = $bt.Parent.Parent
        if ($S.Battery.None) { $row.Visibility = 'Collapsed' }
        elseif ($S.Battery.Unknown) {
            $row.Visibility = 'Visible'
            $bt.Text = 'capacité non communiquée par le poste'
            $bt.ToolTip = $S.Battery.Error
        }
        else {
            $row.Visibility = 'Visible'
            $pct = [math]::Round(100 * $S.Battery.Full / $S.Battery.Design)
            $bt.Text = '{0} % de la capacité d''origine ({1:N1} / {2:N1} Wh){3}' -f $pct, ($S.Battery.Full / 1000), ($S.Battery.Design / 1000), $(if ($S.Battery.Cycles) { '  ·  {0} {1}' -f $S.Battery.Cycles, (Get-Plural $S.Battery.Cycles 'cycle' 'cycles') } else { '' })
            $bt.SetResourceReference([Windows.Controls.Control]::ForegroundProperty, $(if ($pct -ge 80) { 'OkFgBrush' } elseif ($pct -ge 60) { 'WarnFgBrush' } else { 'ErrFgBrush' }))
            $bt.FontWeight = [Windows.FontWeights]::SemiBold; $bt.ToolTip = "Source : $($S.Battery.Source)"
        }
    }
    if ($null -ne $S.Disks) { Update-StorageLayout; try { Update-InfoFast -Force } catch { Write-Ignored 'Accueil' $_ } }
}

# lignes recomposées de l'Accueil à partir des champs de données masqués (signature : réécriture seulement si changement)
function Update-InfoMerged {
    $f = $InfoUI.F; if (-not $f -or -not $f['Windows']) { return }
    # forme courte : « W11 Pro · 64 bits · 26H2 (build 26300.9974) » (texte complet en infobulle)
    $ed = "$($f['Édition'].Text)" -replace '^Microsoft\s+', '' -replace '^Windows\s+(\d+)', 'W$1' -replace 'Professionnel(le)?\s+pour les stations de travail', 'Pro Workstation' -replace 'Professionnel(le)?|Professional', 'Pro' -replace 'Famille|Home', 'Famille' -replace 'Entreprise|Enterprise', 'Entreprise'
    $ver = "$($f['Version'].Text)" -replace '\s{2,}', ' '
    $w = ($ed -replace '\s{2,}', ' ') + ' ' + [char]0x00B7 + ' ' + $ver
    if ($f['Windows'].ToolTip -ne "$($f['Édition'].Text) $ver") { $f['Windows'].ToolTip = "$($f['Édition'].Text) $ver" }
    if ($f['Windows'].Text -ne $w) { $f['Windows'].Text = $w }
    $d = "$($f['Dernier démarrage'].Text)" + $(if ($f['Allumé depuis'].Text) { '  ' + [char]0x00B7 + '  allumé depuis ' + $f['Allumé depuis'].Text } else { '' })
    if ($f['Démarré le'].Text -ne $d) { $f['Démarré le'].Text = $d; $f['Démarré le'].Foreground = $f['Allumé depuis'].Foreground }
    $p = $env:COMPUTERNAME + $(if ("$($f['Domaine'].Text)".Trim()) { '  ' + [char]0x00B7 + '  domaine ' + $f['Domaine'].Text } else { '' })
    if ($f['Poste'].Text -ne $p) { $f['Poste'].Text = $p }
    $fab = "$($f['Fabricant'].Text)"; $mo = "$($InfoUI.ModelRaw)"
    if ($mo) { $m = $(if ($fab -and $fab -notmatch '^non renseign' -and $mo -notmatch ('^' + [regex]::Escape($fab))) { "$fab $mo" } else { $mo }); if ($f['Modèle'].Text -ne $m) { $f['Modèle'].Text = $m } }
}
function Update-Uptime {
    if (-not $InfoUI.F -or -not $BootTime -or $BootTime -eq [DateTime]::MinValue) { return }
    $up = [DateTime]::Now - $BootTime
    $fld = $InfoUI.F['Allumé depuis']
    $fld.Text = '{0} j {1:00} h {2:00} min {3:00} s' -f $up.Days, $up.Hours, $up.Minutes, $up.Seconds
    $fld.SetResourceReference([Windows.Controls.Control]::ForegroundProperty, $(if ($up.Days -ge 14) { 'WarnFgBrush' } else { 'FgBrush' }))
    try { Update-InfoMerged } catch { Write-Ignored 'Accueil (lignes regroupées)' $_ }
}

# Copie texte : clé sur 34 colonnes puis « : valeur » ; lignes suivantes d'une valeur multiligne alignées sous la valeur
function Get-ElText($El) {
    if ($null -eq $El) { return '' }
    if ($El -is [Windows.Controls.TextBlock] -or $El -is [Windows.Controls.TextBox]) { return "$($El.Text)" }
    if ($El -is [Windows.Controls.ContentControl]) { if ($El.Content -is [string]) { return [string]$El.Content }; return Get-ElText $El.Content }
    if ($El -is [Windows.Controls.Border]) { return Get-ElText $El.Child }
    if ($El -is [Windows.Controls.Panel]) {
        return ((@($El.Children | Where-Object { "$($_.Visibility)" -ne 'Collapsed' } | ForEach-Object { Get-ElText $_ }) | Where-Object { "$_".Trim() }) -join '  ')
    }
    ''
}
function Add-CopyLine($Sb, [string]$Key, [string]$Val) {
    $lines = @("$Val".Trim() -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $k = $Key.Trim(); $w = [math]::Max(34, $k.Length + 1)
    [void]$Sb.AppendLine(('{0}: {1}' -f $k.PadRight($w), $(if ($lines.Count) { $lines[0] } else { '' })))
    for ($i = 1; $i -lt $lines.Count; $i++) { [void]$Sb.AppendLine((' ' * ($w + 2)) + $lines[$i]) }
}
function Add-InfoLine($El, $Sb) {
    if ($null -eq $El -or "$($El.Visibility)" -eq 'Collapsed') { return }
    if ($El -is [Windows.Controls.Border]) {
        $tag = "$($El.Tag)"
        if ($tag -like 'card:*') {
            [void]$Sb.AppendLine('')
            [void]$Sb.AppendLine('[' + $tag.Substring(5) + ']')
            Add-InfoLine $El.Child $Sb
            return
        }
        if ($tag -eq 'kv') { $g = $El.Child; Add-CopyLine $Sb (Get-ElText $g.Children[0]) (Get-ElText $g.Children[1]); return }
        if ($El.Child) { Add-InfoLine $El.Child $Sb }
        return
    }
    if ($El -is [Windows.Controls.StackPanel]) {
        if ("$($El.Tag)" -eq 'meter') {
            $g = $El.Children[0]; $val = Get-ElText $g.Children[1]
            $sub = @($El.Children | Where-Object { $_ -is [Windows.Controls.WrapPanel] } | ForEach-Object { (Get-ElText $_) -replace '\s+', ' ' })
            if ($sub.Count) { $val = (@($val) + $sub | Where-Object { "$_".Trim() }) -join "`n" }
            Add-CopyLine $Sb (Get-ElText $g.Children[0]) $val; return
        }
        foreach ($c in $El.Children) { Add-InfoLine $c $Sb }
    }
}

