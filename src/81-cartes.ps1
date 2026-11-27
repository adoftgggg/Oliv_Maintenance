# ---------- Cartes masquées : clic droit sur une carte > « Masquer cette carte », liste complète dans Paramètres
# Clé Page|Titre enregistrée dans HKCU\Software\Oliv_Maintenance\Affichage\CartesMasquees (hors réglages vidés à la
# 1re installation : le choix survit même à une réinitialisation). Carte masquée : repliée (hauteur maximale 0, sans marge) en plus de
# Collapsed, pour qu'un affichage décidé ailleurs (carte qui se montre quand elle a du contenu) ne la fasse pas revenir.
$CardPages = [ordered]@{ Info = 'Accueil'; Maint = 'Maintenance'; Perf = 'Système'; Secu = 'Sécurité'; Perso = 'Personnalisation'; Tools = 'Outils' }
$CardRegKey = 'HKCU\Software\Oliv_Maintenance\Affichage'
$HiddenCards = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
try { foreach ($x in @((Get-RegValue $CardRegKey 'CartesMasquees'))) { if ($x) { [void]$HiddenCards.Add("$x") } } } catch { Write-Ignored 'Cartes masquées' $_ }
$CardState = @{}
function Save-HiddenCard {
    try { $k = Open-RegKey $CardRegKey $true $true; try { $k.SetValue('CartesMasquees', [string[]]@($HiddenCards), [Microsoft.Win32.RegistryValueKind]::MultiString) } finally { $k.Close() } }
    catch { Write-FileLog "Cartes masquées : $($_.Exception.Message)" 'WARN' }
}
# cartes d'une page : bordures « card:Titre » (New-Card) ou de style Panel (titre = premier texte), sans descendre dedans
function Get-PageCard($Root, [string]$Page, $List) {
    if ($null -eq $Root -or $Root -isnot [Windows.DependencyObject]) { return }
    if ($Root -is [Windows.Controls.Border]) {
        $tag = "$($Root.Tag)"; $t = $null
        if ($tag -like 'card:*') { $t = $tag.Substring(5) }
        elseif ($Root.Style -and $Root.Style -eq $Window.TryFindResource('Panel')) { $acc = [Collections.ArrayList]::new(); Get-UiText $Root $acc; if ($acc.Count) { $t = "$($acc[0])" } }
        if ($t) { [void]$List.Add(@{ Page = $Page; Title = $t; Key = "$Page|$t"; El = $Root }); return }
    }
    foreach ($c in [Windows.LogicalTreeHelper]::GetChildren($Root)) { if ($c -is [Windows.DependencyObject]) { Get-PageCard $c $Page $List } }
}
function Get-AllPageCard([string]$Page) { $l = [Collections.ArrayList]::new(); Get-PageCard $Ui["Page$Page"] $Page $l; $l.ToArray() }
function Set-CardShown($C, [bool]$Show) {
    $el = $C.El; $id = [Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($el)
    if (-not $Show) {
        if (-not $CardState.ContainsKey($id)) { $CardState[$id] = @{ Margin = $el.Margin; Vis = $el.Visibility } }
        $el.MaxHeight = 0; $el.Margin = New-Thickness 0 0 0 0; $el.Visibility = 'Collapsed'
    } elseif ($CardState.ContainsKey($id)) {
        $s = $CardState[$id]; $CardState.Remove($id)
        $el.MaxHeight = [double]::PositiveInfinity; $el.Margin = $s.Margin
        # visibilité rendue par le code de la carte pendant qu'elle était masquée (carte vide puis remplie) : gardée ; sinon
        # visibilité d'avant le masquage (avant : toujours celle d'avant, une carte remplie entre-temps restait invisible)
        if ("$($el.Visibility)" -eq 'Collapsed') { $el.Visibility = $s.Vis }
    }
}
# appliqué à chaque affichage d'une page (cartes construites à la demande) ; menu du clic droit ajouté une fois par carte
function Update-CardVisibility([string]$Page) {
    if (-not $CardPages.Contains($Page)) { return }
    foreach ($c in (Get-AllPageCard $Page)) {
        Set-CardShown $c (-not $HiddenCards.Contains($c.Key))
        if (-not $c.El.ContextMenu) {
            $cm = [Windows.Controls.ContextMenu]::new()
            $mi = [Windows.Controls.MenuItem]::new(); $mi.Header = 'Masquer cette carte'; $mi.Tag = $c; $mi.Icon = $null
            $mi.Add_Click({ param($s, $e) Hide-Card $s.Tag })
            [void]$cm.Items.Add($mi)
            $m2 = [Windows.Controls.MenuItem]::new(); $m2.Header = 'Cartes masquées...'; $m2.Add_Click({ Show-CardPicker })
            [void]$cm.Items.Add($m2)
            $m3 = [Windows.Controls.MenuItem]::new(); $m3.Header = 'Ordre des cartes par défaut (cet onglet)'; $m3.Tag = $Page; $m3.Add_Click({ param($s, $e) Reset-CardOrder "$($s.Tag)" })
            [void]$cm.Items.Add($m3)
            # « Ordre par défaut » proposé seulement si l'ordre de l'onglet a été changé (disposition enregistrée)
            $cm.Tag = @{ Reset = $m3; Page = $Page }
            $cm.Add_Opened({ param($s, $e) $v = @((Get-RegValue $CardRegKey "CartesOrdre_$($s.Tag.Page)") | Where-Object { $_ }); $s.Tag.Reset.Visibility = $(if ($v.Count) { 'Visible' } else { 'Collapsed' }) })
            $c.El.ContextMenu = $cm
            Enable-CardMove $c
        }
    }
    Restore-CardOrder $Page
}

# ---------- Cartes déplaçables dans leur onglet : glisser une carte par son en-tête (titre) et la lâcher sur une autre carte du
# même onglet = les 2 cartes échangent leur place (y compris d'une colonne à l'autre). Disposition enregistrée par onglet dans
# HKCU\Software\Oliv_Maintenance\Affichage\CartesOrdre_<onglet> (« clé|n° de colonne|position »), réappliquée à chaque affichage ;
# clic droit > Ordre des cartes par défaut (cet onglet), ou bouton de Paramètres > Cartes affichées, pour revenir tout de suite à l'ordre de l'application.
$CardMove = @{ Applied = @{}; PageOf = @{}; Orig = @{}; ColDone = [Collections.Generic.HashSet[object]]::new(); BgSet = [Collections.Generic.HashSet[object]]::new() }
# colonnes (panneaux) d'un onglet dans l'ordre de l'arbre : identifiant stable d'une colonne = son rang
function Register-CardColumnDrop($Col) {
    if ($CardMove.ColDone.Contains($Col)) { return }; [void]$CardMove.ColDone.Add($Col)
    $Col.Add_DragOver({ param($s, $e)
        $d = $CardMove.Drag; $e.Handled = $true; if (-not $d -or $d.Cols -notcontains $s) { $e.Effects = 'None'; return }
        $e.Effects = 'Move'
        # sous la dernière carte de la colonne : bloc en fin de colonne
        if ($e.OriginalSource -eq $s -and $d.Block.Parent -ne $s) { if ($d.Block.Parent -is [Windows.Controls.Panel]) { $d.Block.Parent.Children.Remove($d.Block) }; [void]$s.Children.Add($d.Block) }
    })
    $Col.Add_Drop({ param($s, $e) $e.Handled = $true; Complete-CardDrag })
}
# bandeaux fixes (pleine largeur, hors colonnes) : ni déplaçables, ni zones de dépôt, ni dans l'ordre des flèches
$CardFixed = @('Info|Processeur', 'Perf|Point de restauration')
function Test-CardFixed($C) { $CardFixed -contains $C.Key }
function Get-CardColumn([string]$Page) {
    $cols = [Collections.ArrayList]::new()
    $fixed = @(Get-AllPageCard $Page | Where-Object { Test-CardFixed $_ } | ForEach-Object { $_.El.Parent })
    foreach ($c in (Get-AllPageCard $Page)) { $p = $c.El.Parent; if ($p -is [Windows.Controls.Panel] -and -not $cols.Contains($p) -and $fixed -notcontains $p) { [void]$cols.Add($p) } }
    # sortie déroulée : chaque appel @(Get-CardColumn) reçoit les colonnes elles-mêmes (avec « , » il recevait un tableau dans un tableau)
    $cols.ToArray()
}
# Déplacement visible : la carte saisie suit le pointeur (copie semi-transparente), sa place est remplacée par un bloc en
# pointillés de même hauteur qui se déplace entre les cartes (au-dessus ou au-dessous de la carte survolée, selon la moitié
# survolée) et pousse les autres ; au lâcher, la carte prend la place du bloc. Échap ou lâcher hors de l'onglet : rien ne bouge.
function Enable-CardMove($C) {
    $el = $C.El
    if ((Test-CardFixed $C) -or "$($el.Tag)" -notlike 'card:*' -or $el.Parent -isnot [Windows.Controls.Panel]) { return }
    $hdr = $null; try { $hdr = $el.Child.Children[0] } catch { $hdr = $null }
    if (-not $hdr) { return }
    $CardMove.PageOf[[Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($el)] = $C.Page
    $el.AllowDrop = $true
    $hdr.Cursor = [Windows.Input.Cursors]::SizeAll; $hdr.ToolTip = 'Glisser le titre pour déplacer la carte dans l''onglet'
    $hdr.Tag = $C
    $hdr.Add_PreviewMouseLeftButtonDown({ param($s, $e) $CardMove.Start = $e.GetPosition($null); $CardMove.Src = $s.Tag })
    $hdr.Add_PreviewMouseMove({ param($s, $e)
        if ($e.LeftButton -ne 'Pressed' -or -not $CardMove.Src -or $CardMove.Src -ne $s.Tag) { return }
        $o = $e.OriginalSource; while ($o -and $o -ne $s) { if ($o -is [Windows.Controls.Primitives.ButtonBase]) { return }; $o = [Windows.Media.VisualTreeHelper]::GetParent($o) }
        $d = $e.GetPosition($null) - $CardMove.Start
        if ([math]::Abs($d.X) -lt 8 -and [math]::Abs($d.Y) -lt 8) { return }
        $src = $CardMove.Src; $CardMove.Src = $null
        Start-CardDrag $src $s
    })
    $el.Add_DragOver({ param($s, $e) Update-CardDrop $s $e })
    $el.Add_Drop({ param($s, $e) $e.Handled = $true; Complete-CardDrag })
}
# image de la carte prise avant le déplacement (une fois masquée, une copie dynamique VisualBrush ne montre plus rien :
# seul « Déposer ici » restait visible) ; résolution de l'écran respectée
function Get-CardSnapshot($El) {
    $w = [math]::Max([double]1, $El.ActualWidth); $h = [math]::Max([double]1, $El.ActualHeight)
    $dpi = try { [Windows.Media.VisualTreeHelper]::GetDpi($El) } catch { $null }
    $sx = $(if ($dpi) { $dpi.DpiScaleX } else { 1.0 }); $sy = $(if ($dpi) { $dpi.DpiScaleY } else { 1.0 })
    $rt = [Windows.Media.Imaging.RenderTargetBitmap]::new([int][math]::Ceiling($w * $sx), [int][math]::Ceiling($h * $sy), 96 * $sx, 96 * $sy, [Windows.Media.PixelFormats]::Pbgra32)
    $dv = [Windows.Media.DrawingVisual]::new(); $dc = $dv.RenderOpen()
    try { $dc.DrawRectangle([Windows.Media.VisualBrush]::new($El), $null, [Windows.Rect]::new(0, 0, $w, $h)) } finally { $dc.Close() }
    $rt.Render($dv); $rt.Freeze(); $rt
}
function New-CardGhostBlock([double]$H, $Img) {
    $b = [Windows.Controls.Border]::new(); $b.Height = [math]::Max([double]60, $H); $b.Margin = New-Thickness 0 0 0 14; $b.CornerRadius = [Windows.CornerRadius]::new(10)
    $b.BorderThickness = New-Thickness 2 2 2 2; $b.AllowDrop = $true
    $b.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, 'AccentBrush')
    $dash = [Windows.Shapes.Rectangle]::new(); $dash.StrokeDashArray = [Windows.Media.DoubleCollection]::new([double[]](6, 4)); $dash.StrokeThickness = 2; $dash.RadiusX = 10; $dash.RadiusY = 10
    $dash.SetResourceReference([Windows.Shapes.Shape]::StrokeProperty, 'AccentBrush')
    $b.BorderThickness = New-Thickness 0 0 0 0; $g = [Windows.Controls.Grid]::new(); [void]$g.Children.Add($dash)
    # aperçu estompé de la carte à l'emplacement où elle sera déposée
    if ($Img) { $im = [Windows.Controls.Image]::new(); $im.Source = $Img; $im.Stretch = 'Fill'; $im.Opacity = 0.35; $im.IsHitTestVisible = $false; $g.Children.Insert(0, $im) }
    $b.Child = $g; $b.Background = [Windows.Media.Brushes]::Transparent
    $b.Add_DragOver({ param($s, $e) $e.Effects = 'Move'; $e.Handled = $true })
    $b.Add_Drop({ param($s, $e) $e.Handled = $true; Complete-CardDrag })
    $b
}
function Start-CardDrag($Src, $Handle) {
    if (-not $Sync.FormsLoaded) { Add-Type -AssemblyName System.Windows.Forms, System.Drawing; $Sync.FormsLoaded = $true }
    $el = $Src.El; $p = $el.Parent; if ($p -isnot [Windows.Controls.Panel]) { return }
    # bloc de dépôt à la place de la carte, carte retirée du flux pendant le déplacement ; tout est remis en état dans finally,
    # même si la préparation échoue (sinon la carte restait masquée derrière le bloc)
    $blk = $null; $pop = $null; $cols = @(); $fb = $null
    try {
        $img = $null; try { $img = Get-CardSnapshot $el } catch { Write-Ignored 'Aperçu de la carte' $_ }
        $blk = New-CardGhostBlock $el.ActualHeight $img
        $p.Children.Insert($p.Children.IndexOf($el), $blk); $el.Visibility = 'Collapsed'
        # copie semi-transparente qui suit le pointeur
        $pop = [Windows.Controls.Primitives.Popup]::new(); $pop.AllowsTransparency = $true; $pop.Placement = 'Absolute'; $pop.IsHitTestVisible = $false
        $r = [Windows.Shapes.Rectangle]::new(); $r.Width = $el.ActualWidth; $r.Height = $el.ActualHeight; $r.Fill = $(if ($img) { [Windows.Media.ImageBrush]::new($img) } else { [Windows.Media.VisualBrush]::new($el.Child) }); $r.Opacity = 0.85; $r.IsHitTestVisible = $false
        $fr = [Windows.Controls.Border]::new(); $fr.CornerRadius = [Windows.CornerRadius]::new(10); $fr.Child = $r; $fr.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, 'PanelBrush'); $fr.Opacity = 0.9
        $sh = [Windows.Media.Effects.DropShadowEffect]::new(); $sh.BlurRadius = 18; $sh.ShadowDepth = 4; $sh.Opacity = 0.35; $fr.Effect = $sh
        $pop.Child = $fr
        # colonnes de l'onglet : zones vides aussi réceptrices (fond transparent pour le test de survol)
        $cols = @(Get-CardColumn $Src.Page | Where-Object { $_ -is [Windows.Controls.Panel] })
        foreach ($c in $cols) { Register-CardColumnDrop $c; $c.AllowDrop = $true; if ($null -eq $c.Background) { $c.Background = [Windows.Media.Brushes]::Transparent; [void]$CardMove.BgSet.Add($c) } }
        $CardMove.Drag = @{ Src = $Src; Block = $blk; Pop = $pop; Cols = $cols; Done = $false; Off = $(try { $Handle.TranslatePoint([Windows.Point]::new(0, 0), $el) } catch { [Windows.Point]::new(0, 0) }) }
        $pop.IsOpen = $true; Move-CardGhost
        $fb = [Windows.GiveFeedbackEventHandler]{ param($s, $e) Move-CardGhost }
        $Handle.AddHandler([Windows.DragDrop]::GiveFeedbackEvent, $fb)
        [void][Windows.DragDrop]::DoDragDrop($Handle, [Windows.DataObject]::new('OlivMCard', $Src), [Windows.DragDropEffects]::Move)
    } finally {
        if ($fb) { $Handle.RemoveHandler([Windows.DragDrop]::GiveFeedbackEvent, $fb) }
        $d = $CardMove.Drag; $CardMove.Drag = $null
        if ($pop) { $pop.IsOpen = $false }
        foreach ($c in $cols) { $c.AllowDrop = $false; if ($CardMove.BgSet.Remove($c)) { $c.Background = $null } }
        $bp = $(if ($blk) { $blk.Parent } else { $null })
        # carte retirée d'abord, puis rang du bloc relu (sinon décalage d'une place quand la carte était au-dessus du bloc)
        if ($d -and $d.Done -and $bp -is [Windows.Controls.Panel]) { $el.Parent.Children.Remove($el); $bp.Children.Insert($bp.Children.IndexOf($blk), $el) }
        if ($bp -is [Windows.Controls.Panel]) { $bp.Children.Remove($blk) }
        $el.Visibility = 'Visible'
        if ($d -and $d.Done) { Save-CardOrder $Src.Page; Write-UiLog ('{0} : carte « {1} » déplacée.' -f $CardPages[$Src.Page], $Src.Title) 'APP' }
    }
}
# copie sous le pointeur (position de l'écran convertie en unités WPF de la fenêtre)
function Move-CardGhost {
    $d = $CardMove.Drag; if (-not $d) { return }
    $pt = [System.Windows.Forms.Cursor]::Position
    $m = [Windows.PresentationSource]::FromVisual($Window).CompositionTarget.TransformFromDevice
    $w = $m.Transform([Windows.Point]::new($pt.X, $pt.Y))
    $d.Pop.HorizontalOffset = $w.X - $d.Off.X - 20; $d.Pop.VerticalOffset = $w.Y - 18
}
# survol : bloc de dépôt placé avant ou après la carte survolée (moitié haute / basse), ou en fin de colonne vide
function Update-CardDrop($S, $E) {
    $d = $CardMove.Drag; $E.Handled = $true
    if (-not $d -or $CardMove.PageOf[[Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($S)] -ne $d.Src.Page) { $E.Effects = 'None'; return }
    $E.Effects = 'Move'
    $p = $S.Parent; if ($p -isnot [Windows.Controls.Panel]) { return }
    $after = $E.GetPosition($S).Y -gt $S.ActualHeight / 2
    $blk = $d.Block; $bp = $blk.Parent
    $want = $p.Children.IndexOf($S) + $(if ($after) { 1 } else { 0 })
    if ($bp -eq $p) { $cur = $p.Children.IndexOf($blk); if ($cur -lt $want) { $want-- }; if ($cur -eq $want) { return } }
    if ($bp -is [Windows.Controls.Panel]) { $bp.Children.Remove($blk) }
    if ($want -lt 0) { $want = 0 }; if ($want -gt $p.Children.Count) { $want = $p.Children.Count }
    $p.Children.Insert($want, $blk)
}
function Complete-CardDrag { if ($CardMove.Drag) { $CardMove.Drag.Done = $true } }
function Save-CardOrder([string]$Page) {
    $cols = @(Get-CardColumn $Page); $l = [Collections.Generic.List[string]]::new()
    foreach ($c in (Get-AllPageCard $Page)) { $p = $c.El.Parent; $ci = [array]::IndexOf($cols, $p); if ($ci -ge 0) { $l.Add(('{0}|{1}|{2}' -f $c.Key, $ci, $p.Children.IndexOf($c.El))) } }
    try { $k = Open-RegKey $CardRegKey $true $true; try { $k.SetValue("CartesOrdre_$Page", [string[]]$l, [Microsoft.Win32.RegistryValueKind]::MultiString) } finally { $k.Close() } } catch { Write-FileLog "Disposition des cartes : $($_.Exception.Message)" 'WARN' }
}
# disposition enregistrée réappliquée une fois par construction de l'onglet (cartes construites à la demande)
# disposition d'origine (celle construite par l'application) relevée avant toute remise en ordre : bouton « Ordre par défaut »
# appliqué tout de suite, sans relancer l'application
function Save-CardOrigin([string]$Page) {
    $cols = @(Get-CardColumn $Page)
    foreach ($c in (Get-AllPageCard $Page)) {
        $h = [Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($c.El); if ($CardMove.Orig.ContainsKey($h)) { continue }
        $p = $c.El.Parent; $ci = [array]::IndexOf($cols, $p)
        if ($ci -ge 0) { $CardMove.Orig[$h] = @{ C = $c; Page = $Page; Col = $ci; Pos = $p.Children.IndexOf($c.El) } }
    }
}
function Restore-CardOrder([string]$Page) {
    Save-CardOrigin $Page
    $saved = @((Get-RegValue $CardRegKey "CartesOrdre_$Page") | Where-Object { $_ }); if (-not $saved.Count) { return }
    $cards = @(Get-AllPageCard $Page); if (-not $cards.Count) { return }
    $sig = ($cards | ForEach-Object { [Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($_.El) }) -join ','
    if ($CardMove.Applied[$Page] -eq $sig) { return }
    $cols = @(Get-CardColumn $Page); $byKey = @{}; foreach ($c in $cards) { $byKey[$c.Key] = $c }
    $want = @(foreach ($x in $saved) { $f = "$x" -split '\|'; if ($f.Count -ge 4) { @{ Key = "$($f[0])|$($f[1])"; Col = [int]$f[2]; Pos = [int]$f[3] } } }) | Sort-Object { $_.Col }, { $_.Pos }
    foreach ($w in $want) {
        $c = $byKey[$w.Key]; if (-not $c -or $w.Col -ge $cols.Count) { continue }
        $dst = $cols[$w.Col]; $p = $c.El.Parent; if ($p -isnot [Windows.Controls.Panel]) { continue }
        $p.Children.Remove($c.El); $dst.Children.Insert([math]::Min($w.Pos, $dst.Children.Count), $c.El)
    }
    $CardMove.Applied[$Page] = $sig
}
function Reset-CardOrder([string]$Page, [switch]$Quiet) {
    try { $k = Open-RegKey $CardRegKey $true; if ($k) { try { $k.DeleteValue("CartesOrdre_$Page", $false) } finally { $k.Close() } } } catch { Write-Ignored 'Disposition des cartes' $_ }
    $cols = @(Get-CardColumn $Page)
    foreach ($o in @($CardMove.Orig.Values | Where-Object { $_.Page -eq $Page } | Sort-Object { $_.Col }, { $_.Pos })) {
        if ($o.Col -ge $cols.Count) { continue }
        $el = $o.C.El; $p = $el.Parent; if ($p -isnot [Windows.Controls.Panel]) { continue }
        $dst = $cols[$o.Col]; $p.Children.Remove($el); $dst.Children.Insert([math]::Min($o.Pos, $dst.Children.Count), $el)
    }
    $CardMove.Applied.Remove($Page)
    if (-not $Quiet) { Write-UiLog ('{0} : ordre des cartes par défaut rétabli.' -f $CardPages[$Page]) 'APP' }
}
function Hide-Card($C) {
    [void]$HiddenCards.Add($C.Key); Save-HiddenCard; Set-CardShown $C $false
    Write-UiLog ('Carte « {0} » masquée (réaffichage : Paramètres > Onglets et cartes affichés).' -f $C.Title) 'APP'
    Show-CardToast $C
}
# bandeau d'annulation (10 s) en bas de la fenêtre après un masquage
function Show-CardToast($C) {
    $ToolsUI.UndoCard = $C
    if (-not $ToolsUI.UndoPop) {
        $pp = [Windows.Controls.Primitives.Popup]::new(); $pp.AllowsTransparency = $true; $pp.PlacementTarget = $Window.Content; $pp.Placement = 'Center'; $pp.StaysOpen = $true
        $bd = [Windows.Controls.Border]::new(); $bd.CornerRadius = [Windows.CornerRadius]::new(8); $bd.Padding = New-Thickness 16 8 8 8; $bd.Margin = New-Thickness 12 12 12 12; $bd.BorderThickness = New-Thickness 1 1 1 1
        $bd.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, 'PanelBrush'); $bd.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, 'LineBrush')
        $fx = [Windows.Media.Effects.DropShadowEffect]::new(); $fx.BlurRadius = 16; $fx.ShadowDepth = 2; $fx.Opacity = 0.3; $fx.Direction = 270; $bd.Effect = $fx
        $sp = [Windows.Controls.StackPanel]::new(); $sp.Orientation = 'Horizontal'
        $ToolsUI.UndoText = New-Text ''; $ToolsUI.UndoText.VerticalAlignment = 'Center'; $ToolsUI.UndoText.Margin = New-Thickness 0 0 14 0
        $ub = New-Button 'Annuler'; $ub.Height = 30; $ub.MinWidth = 80; $ub.Margin = New-Thickness 0 0 6 0; $ub.Add_Click({ Undo-CardHide })
        $gb = New-Button 'Choisir les cartes'; $gb.Height = 30; $gb.MinWidth = 80; $gb.Margin = New-Thickness 0 0 0 0; $gb.Add_Click({ $ToolsUI.UndoPop.IsOpen = $false; Show-CardPicker })
        [void]$sp.Children.Add($ToolsUI.UndoText); [void]$sp.Children.Add($ub); [void]$sp.Children.Add($gb); $bd.Child = $sp; $pp.Child = $bd
        $ToolsUI.UndoPop = $pp
        $ToolsUI.UndoTimer = [Windows.Threading.DispatcherTimer]::new(); $ToolsUI.UndoTimer.Interval = [TimeSpan]::FromSeconds(10)
        $ToolsUI.UndoTimer.Add_Tick({ $ToolsUI.UndoTimer.Stop(); $ToolsUI.UndoPop.IsOpen = $false })
    }
    $ToolsUI.UndoText.Text = "Carte « {0} » masquée.`nRéaffichable à tout moment : Paramètres > Onglets et cartes affichés, ou clic droit sur une carte > Cartes masquées." -f $C.Title
    $ToolsUI.UndoPop.VerticalOffset = [math]::Max([double]0, $Window.ActualHeight / 2 - 70)
    $ToolsUI.UndoPop.IsOpen = $false; $ToolsUI.UndoPop.IsOpen = $true
    $ToolsUI.UndoTimer.Stop(); $ToolsUI.UndoTimer.Start()
}
function Undo-CardHide {
    $c = $ToolsUI.UndoCard; if (-not $c) { return }
    [void]$HiddenCards.Remove($c.Key); Save-HiddenCard; Set-CardShown $c $true
    if ($ToolsUI.UndoPop) { $ToolsUI.UndoPop.IsOpen = $false }; $ToolsUI.UndoCard = $null
    Write-UiLog ('Carte « {0} » réaffichée.' -f $c.Title) 'APP'
}

# Paramètres > Onglets et cartes : résumé (onglets et cartes masqués) et bouton d'ouverture de la fenêtre de personnalisation
function Update-CardSetting {
    $b = $SetUI.CardsBody; if (-not $b) { return }
    $b.Children.Clear()
    $bar = [Windows.Controls.WrapPanel]::new(); $bar.Margin = New-Thickness 46 4 10 14
    $pk = New-Button 'Personnaliser les onglets et les cartes...' 'PrimaryBtn'; $pk.Height = 30; $pk.Margin = New-Thickness 0 0 8 0; $pk.Add_Click({ Show-CardPicker })
    $all = New-Button 'Tout réafficher'; $all.Height = 30; $all.Margin = New-Thickness 0 0 8 0; $all.Add_Click({ Show-AllCard })
    $SetUI.CardsCount = New-Text '' 'Muted'; $SetUI.CardsCount.VerticalAlignment = 'Center'; $SetUI.CardsCount.Margin = New-Thickness 6 0 0 0
    [void]$bar.Children.Add($pk); [void]$bar.Children.Add($all); [void]$bar.Children.Add($SetUI.CardsCount)
    [void]$b.Children.Add($bar)
    Update-CardCount
}
# tout réafficher : onglets et cartes
function Show-AllCard {
    foreach ($p in $CardPages.Keys) { foreach ($c in (Get-AllPageCard $p)) { Set-CardShown $c $true } }
    $HiddenCards.Clear(); Save-HiddenCard
    $HiddenTabs.Clear(); Save-HiddenTab; Update-TabVisibility
    Update-CardCount; Write-UiLog 'Tous les onglets et toutes les cartes réaffichés.' 'APP'
}
# fenêtre de personnalisation : une colonne par onglet (case de l'onglet en tête, puis ses cartes dans l'ordre affiché).
# Case = affiché / masqué ; carte glissée par sa ligne : la liste se réorganise en direct pendant le déplacement, l'onglet
# suit au lâcher. Bandeaux fixes (cadenas) grisés, ni masquables ni déplaçables.
function Show-CardPicker {
    if ($ToolsUI.UndoPop) { $ToolsUI.UndoPop.IsOpen = $false }
    if (-not $Lazy.Done) { New-DeferredPage }
    if (-not $ToolsUI.Built) { New-ToolsPage }
    foreach ($p in $CardPages.Keys) { try { Restore-CardOrder $p } catch { Write-Ignored 'Disposition des cartes' $_ } }
    $wrap = [Windows.Controls.WrapPanel]::new(); $CardMove.PickWrap = $wrap
    Update-CardPickerList
    $sv = [Windows.Controls.ScrollViewer]::new(); $sv.VerticalScrollBarVisibility = 'Auto'; $sv.MaxHeight = 540; $sv.Content = $wrap
    # « Ordre par défaut » seulement si l'ordre d'au moins un onglet a été changé
    $chg = @($CardPages.Keys | Where-Object { @((Get-RegValue $CardRegKey "CartesOrdre_$_") | Where-Object { $_ }).Count }).Count
    $btns = @($(if ($chg) { @{ T = 'Ordre par défaut'; V = 'order' } }) + @(@{ T = 'Tout réafficher'; V = 'all' }, @{ T = 'Fermer'; V = 'ok'; C = $true }) | Where-Object { $_ })
    $v = Show-Dialog "Onglets et cartes`n`nCase d'un onglet : onglet affiché dans la barre ou masqué. Case d'une carte : carte affichée ou masquée dans son onglet. Glisser une carte par sa ligne pour la déplacer : la liste se réorganise en direct, l'onglet suit au lâcher. Tout est appliqué tout de suite." 'Info' $btns $null $null 1040 $sv
    if ($sv.Parent) { $sv.Parent.Content = $null }
    if ($v -eq 'all') { Show-AllCard; Show-CardPicker }
    elseif ($v -eq 'order') { foreach ($p in $CardPages.Keys) { Reset-CardOrder $p -Quiet }; Write-UiLog 'Ordre des cartes par défaut rétabli dans tous les onglets.' 'APP'; Show-CardPicker }
}
# carte placée juste avant / après une autre carte du même onglet (même colonne ou autre colonne)
function Move-CardTo($C, $Target, [bool]$After) {
    $el = $C.El; $tp = $Target.El.Parent
    if ($el -eq $Target.El -or $tp -isnot [Windows.Controls.Panel] -or $el.Parent -isnot [Windows.Controls.Panel]) { return }
    $el.Parent.Children.Remove($el)
    $i = $tp.Children.IndexOf($Target.El) + $(if ($After) { 1 } else { 0 })
    if ($i -lt 0) { $i = 0 }; if ($i -gt $tp.Children.Count) { $i = $tp.Children.Count }
    $tp.Children.Insert($i, $el)
}
# déplacement en direct dans la liste : ligne glissée insérée avant / après la ligne survolée (jamais au-dessus des bandeaux fixes)
function Move-PickRow($Row, $Target, [bool]$After) {
    $l = $Row.Parent; if ($Target.Parent -ne $l -or $Row -eq $Target) { return }
    $want = $l.Children.IndexOf($Target) + $(if ($After) { 1 } else { 0 })
    $cur = $l.Children.IndexOf($Row); if ($cur -lt $want) { $want-- }
    if ($cur -eq $want) { return }
    $l.Children.Remove($Row); $l.Children.Insert($want, $Row)
}
# lâcher : place de la carte dans l'onglet déduite de ses voisines dans la liste, ordre enregistré
function Complete-PickDrag($Row) {
    $l = $Row.Parent; if ($l -isnot [Windows.Controls.Panel]) { return }
    $rows = @($l.Children | Where-Object { $_.Tag -is [hashtable] -and $_.Tag.Movable })
    $k = [array]::IndexOf($rows, $Row); $c = $Row.Tag.C
    if ($k -lt $rows.Count - 1) { Move-CardTo $c $rows[$k + 1].Tag.C $false } elseif ($k -gt 0) { Move-CardTo $c $rows[$k - 1].Tag.C $true } else { return }
    Save-CardOrder $c.Page
    Write-UiLog ('{0} : carte « {1} » déplacée.' -f $CardPages[$c.Page], $c.Title) 'APP'
}
function Update-CardPickerList {
    $wrap = $CardMove.PickWrap; if (-not $wrap) { return }
    $wrap.Children.Clear()
    # colonnes : Accueil puis les onglets de la barre, dans l'ordre de la barre
    $pages = [ordered]@{ Info = 'Accueil' }; foreach ($k in $TabLabels.Keys) { $pages[$k] = $(if ($CardPages.Contains($k)) { $CardPages[$k] } else { $TabLabels[$k] }) }
    foreach ($p in $pages.Keys) {
        $col = [Windows.Controls.StackPanel]::new(); $col.Width = 240; $col.Margin = New-Thickness 0 0 12 14
        # en-tête : case de l'onglet (Accueil toujours affiché)
        $hd = [Windows.Controls.StackPanel]::new()
        $tc = New-HoverCheck $hd '' $null $null
        $tt = New-Text $pages[$p]; $tt.FontWeight = [Windows.FontWeights]::SemiBold; $tt.FontSize = 14; $tc.Content = $tt
        $tc.IsChecked = $p -eq 'Info' -or -not $HiddenTabs.Contains($p)
        if ($p -eq 'Info') { $tc.IsEnabled = $false; $tc.ToolTip = 'Accueil toujours affiché' } else { $tc.ToolTip = 'Onglet affiché dans la barre' }
        $sep = [Windows.Controls.Border]::new(); $sep.Height = 1; $sep.Margin = New-Thickness 6 2 6 4; $sep.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, 'LineBrush'); [void]$hd.Children.Add($sep)
        [void]$col.Children.Add($hd)
        $list = [Windows.Controls.StackPanel]::new(); $list.Background = [Windows.Media.Brushes]::Transparent; $list.AllowDrop = $true
        $list.Opacity = $(if ($tc.IsChecked) { 1 } else { 0.45 })
        $tc.Tag = @{ Page = $p; List = $list }
        $tc.Add_Checked({ param($s, $e) $k = $s.Tag.Page; [void]$HiddenTabs.Remove($k); Save-HiddenTab; Update-TabVisibility; $s.Tag.List.Opacity = 1; Update-CardCount; Write-UiLog "Onglet « $($TabLabels[$k]) » affiché." 'APP' })
        $tc.Add_Unchecked({ param($s, $e) $k = $s.Tag.Page; [void]$HiddenTabs.Add($k); Save-HiddenTab; Update-TabVisibility; $s.Tag.List.Opacity = 0.45; Update-CardCount; Write-UiLog "Onglet « $($TabLabels[$k]) » masqué." 'APP' })
        $all = @($(if ($CardPages.Contains($p)) { Get-AllPageCard $p }))
        if (-not $all.Count) { $t = New-Text 'Pas de cartes dans cet onglet' 'Muted'; $t.Margin = New-Thickness 12 2 0 0; [void]$list.Children.Add($t) }
        $cards = @(@($all | Where-Object { Test-CardFixed $_ }) + @($all | Where-Object { -not (Test-CardFixed $_) }))
        foreach ($c in $cards) {
            $fixed = Test-CardFixed $c
            $movable = -not $fixed -and "$($c.El.Tag)" -like 'card:*' -and $c.El.Parent -is [Windows.Controls.Panel]
            $row = [Windows.Controls.Border]::new(); $row.CornerRadius = [Windows.CornerRadius]::new(6); $row.BorderThickness = New-Thickness 1 1 1 1
            $row.BorderBrush = [Windows.Media.Brushes]::Transparent; $row.Background = [Windows.Media.Brushes]::Transparent; $row.Margin = New-Thickness 0 1 0 1
            $row.Tag = @{ C = $c; Movable = $movable }; $row.AllowDrop = $true
            $g = [Windows.Controls.Grid]::new()
            foreach ($w in 'Auto', '*') { $cd = [Windows.Controls.ColumnDefinition]::new(); $cd.Width = $(if ($w -eq '*') { [Windows.GridLength]::new(1, 'Star') } else { [Windows.GridLength]::Auto }); [void]$g.ColumnDefinitions.Add($cd) }
            $gr = New-Text ([string][char]$(if ($movable) { 0xE76F } else { 0xE72E })); $gr.FontFamily = [Windows.Media.FontFamily]::new('Segoe MDL2 Assets'); $gr.FontSize = 12
            $gr.VerticalAlignment = 'Center'; $gr.Margin = New-Thickness 6 0 2 0; $gr.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'MutedBrush')
            [void]$g.Children.Add($gr)
            $hc = [Windows.Controls.Grid]::new(); [Windows.Controls.Grid]::SetColumn($hc, 1); [void]$g.Children.Add($hc)
            $ct = New-Text $c.Title; $ct.TextWrapping = 'Wrap'
            $cb = New-HoverCheck $hc '' $null $null; $cb.Content = $ct
            $cb.Tag = $c; $cb.IsChecked = -not $HiddenCards.Contains($c.Key)
            if ($fixed) {
                # bandeau fixe (cadenas) : grisé, ni masquable ni déplaçable
                if ($HiddenCards.Remove($c.Key)) { Save-HiddenCard; Set-CardShown $c $true }
                $cb.IsChecked = $true; $cb.IsEnabled = $false; $row.Opacity = 0.5; $row.ToolTip = 'Bandeau fixe en haut de l''onglet : toujours affiché, non déplaçable'
            } else {
                $cb.Add_Checked({ param($s, $e) [void]$HiddenCards.Remove($s.Tag.Key); Save-HiddenCard; Set-CardShown $s.Tag $true; Update-CardCount })
                $cb.Add_Unchecked({ param($s, $e) [void]$HiddenCards.Add($s.Tag.Key); Save-HiddenCard; Set-CardShown $s.Tag $false; Update-CardCount })
            }
            $row.Child = $g
            if ($movable) {
                $row.Cursor = [Windows.Input.Cursors]::SizeAll; $row.ToolTip = 'Glisser pour déplacer la carte'
                $row.Add_PreviewMouseLeftButtonDown({ param($s, $e) $CardMove.PickSrc = $s; $CardMove.PickPt = $e.GetPosition($s) })
                $row.Add_PreviewMouseLeftButtonUp({ $CardMove.PickSrc = $null })
                $row.Add_PreviewMouseMove({ param($s, $e)
                    if ($CardMove.PickSrc -ne $s -or $e.LeftButton -ne 'Pressed') { return }
                    $d = $e.GetPosition($s) - $CardMove.PickPt; if ([math]::Abs($d.X) -lt 6 -and [math]::Abs($d.Y) -lt 6) { return }
                    $CardMove.PickSrc = $null; $CardMove.PickDrag = $s
                    # ligne en cours de déplacement : surlignée (bord et fond d'accent), elle se déplace dans la liste sous le pointeur
                    $s.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, 'AccentBrush'); $s.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, 'HoverBrush')
                    $r = [Windows.DragDropEffects]::None
                    try { $r = [Windows.DragDrop]::DoDragDrop($s, [Windows.DataObject]::new('OlivMPick', 'x'), [Windows.DragDropEffects]::Move) }
                    finally {
                        $CardMove.PickDrag = $null; $s.BorderBrush = [Windows.Media.Brushes]::Transparent; $s.Background = [Windows.Media.Brushes]::Transparent
                        # lâché dans la liste : place appliquée à l'onglet ; annulé (Échap, hors de la liste) : liste remise dans l'ordre réel
                        if ($r -eq [Windows.DragDropEffects]::Move) { try { Complete-PickDrag $s } catch { Write-UiLog "Déplacement de la carte : $($_.Exception.Message)" 'ERROR' } }
                        [void]$CardMove.PickWrap.Dispatcher.BeginInvoke([Action]{ Update-CardPickerList }, [Windows.Threading.DispatcherPriority]::Background)
                    }
                })
            }
            $row.Add_DragOver({ param($s, $e)
                $e.Handled = $true; $src = $CardMove.PickDrag
                if (-not $src -or $src.Parent -ne $s.Parent) { $e.Effects = 'None'; return }
                $e.Effects = 'Move'
                if ($s -eq $src -or -not $s.Tag.Movable) { return }
                Move-PickRow $src $s ($e.GetPosition($s).Y -gt $s.ActualHeight / 2)
            })
            $row.Add_Drop({ param($s, $e) $e.Handled = $true; $e.Effects = 'Move' })
            [void]$list.Children.Add($row)
        }
        # espace libre sous la liste : la carte va en fin d'onglet
        $list.Add_DragOver({ param($s, $e)
            $e.Handled = $true; $src = $CardMove.PickDrag
            if (-not $src -or $src.Parent -ne $s) { $e.Effects = 'None'; return }
            $e.Effects = 'Move'
            $last = @($s.Children | Where-Object { $_.Tag -is [hashtable] -and $_.Tag.Movable })[-1]
            if ($last -and $last -ne $src -and $e.GetPosition($last).Y -gt $last.ActualHeight) { Move-PickRow $src $last $true }
        })
        $list.Add_Drop({ param($s, $e) $e.Handled = $true; $e.Effects = 'Move' })
        $list.MinHeight = 40
        [void]$col.Children.Add($list)
        [void]$wrap.Children.Add($col)
    }
}
function Update-CardCount {
    if (-not $SetUI.CardsCount) { return }
    $n = $HiddenCards.Count; $o = $HiddenTabs.Count
    $SetUI.CardsCount.Text = $(if (-not $n -and -not $o) { 'Tous les onglets et toutes les cartes sont affichés.' } else { (@($(if ($o) { '{0} {1}' -f $o, $(if ($o -gt 1) { 'onglets masqués' } else { 'onglet masqué' }) }), $(if ($n) { '{0} {1}' -f $n, $(if ($n -gt 1) { 'cartes masquées' } else { 'carte masquée' }) })) | Where-Object { $_ }) -join ', ' })
}

# Onglets masqués (Paramètres > Onglets et cartes affichés) : HKCU\Software\Oliv_Maintenance\Affichage\OngletsMasques,
# conservés d'une version à l'autre. Accueil et Paramètres toujours accessibles ; onglet affiché masqué = retour à l'Accueil.
$TabLabels = [ordered]@{ Maint = 'Maintenance'; Perf = 'Performances'; Secu = 'Sécurité'; Perso = 'Personnalisation'; Apps = 'Applications'; Svc = 'Services et tâches'; Tools = 'Outils'; Log = 'Journal' }
$HiddenTabs = [Collections.Generic.HashSet[string]]::new()
try { foreach ($x in @((Get-RegValue $CardRegKey 'OngletsMasques'))) { if ($x) { [void]$HiddenTabs.Add("$x") } } } catch { Write-Ignored 'Onglets masqués' $_ }
function Save-HiddenTab {
    try { $k = Open-RegKey $CardRegKey $true $true; try { $k.SetValue('OngletsMasques', [string[]]@($HiddenTabs), [Microsoft.Win32.RegistryValueKind]::MultiString) } finally { $k.Close() } }
    catch { Write-Ignored 'Enregistrement des onglets masqués' $_ }
}
function Update-TabVisibility {
    foreach ($pg in $TabLabels.Keys) { $n = $Ui["Nav$pg"]; if ($n) { $n.Visibility = $(if ($HiddenTabs.Contains($pg)) { 'Collapsed' } else { 'Visible' }) } }
    # onglet de retour masqué depuis Paramètres : Paramètres reste affiché (fenêtre de personnalisation encore ouverte), le
    # retour se fera sur l'Accueil ; sinon page masquée affichée = retour à l'Accueil
    if ($HiddenTabs.Contains("$($Sync.LastPage)")) {
        if ($Sync.CurPage -eq 'Settings') { $Sync.LastPage = 'Info' }
        elseif (Get-Command Show-Page -ErrorAction SilentlyContinue) { Show-Page 'Info' }
    }
}
Update-TabVisibility
