# ---------- Cartes masquées : clic droit sur une carte > « Masquer cette carte », liste complète dans Paramètres
# Clé Page|Titre enregistrée dans HKCU\Software\Oliv_Maintenance\Affichage\CartesMasquees (hors réglages vidés à la
# 1re installation : le choix survit même à une réinitialisation). Carte masquée : repliée (hauteur maximale 0, sans marge) en plus de
# Collapsed, pour qu'un affichage décidé ailleurs (carte qui se montre quand elle a du contenu) ne la fasse pas revenir.
$CardPages = [ordered]@{ Info = 'Accueil'; Maint = 'Maintenance'; Perf = 'Système'; Secu = 'Sécurité'; Perso = 'Personnalisation'; Tools = 'Outils' }
$CardRegKey = 'HKCU\Software\Oliv_Maintenance\Affichage'
$HiddenCards = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
try { foreach ($x in @(Get-RegValue $CardRegKey 'CartesMasquees')) { if ($x) { [void]$HiddenCards.Add("$x") } } } catch { Write-Ignored 'Cartes masquées' $_ }
$CardState = @{}
function Save-HiddenCard {
    try { $k = Open-RegKey $CardRegKey $true $true; try { $k.SetValue('CartesMasquees', [string[]]@($HiddenCards), [Microsoft.Win32.RegistryValueKind]::MultiString) } finally { $k.Close() } }
    catch { Write-UiLog "Cartes masquées : $($_.Exception.Message)" 'WARN' }
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
        $el.MaxHeight = [double]::PositiveInfinity; $el.Margin = $s.Margin; $el.Visibility = $s.Vis
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
            $c.El.ContextMenu = $cm
        }
    }
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

# Paramètres > Onglets et cartes affichés : une case par carte, groupées par onglet (pages construites si besoin)
# Paramètres > Onglets et cartes affichés : nombre de cartes masquées, bouton d'ouverture de la fenêtre de choix
function Update-CardSetting {
    $b = $SetUI.CardsBody; if (-not $b) { return }
    $b.Children.Clear()
    $bar = [Windows.Controls.WrapPanel]::new(); $bar.Margin = New-Thickness 38 0 10 14
    $pk = New-Button 'Choisir les cartes affichées...' 'PrimaryBtn'; $pk.Height = 30; $pk.Margin = New-Thickness 0 0 8 0; $pk.Add_Click({ Show-CardPicker })
    $all = New-Button 'Tout réafficher'; $all.Height = 30; $all.Margin = New-Thickness 0 0 8 0; $all.Add_Click({ Show-AllCard })
    $SetUI.CardsCount = New-Text '' 'Muted'; $SetUI.CardsCount.VerticalAlignment = 'Center'; $SetUI.CardsCount.Margin = New-Thickness 6 0 0 0
    [void]$bar.Children.Add($pk); [void]$bar.Children.Add($all); [void]$bar.Children.Add($SetUI.CardsCount)
    [void]$b.Children.Add($bar)
    Update-CardCount
}
function Show-AllCard {
    foreach ($p in $CardPages.Keys) { foreach ($c in (Get-AllPageCard $p)) { Set-CardShown $c $true } }
    $HiddenCards.Clear(); Save-HiddenCard; Update-CardCount; Write-UiLog 'Toutes les cartes réaffichées.' 'APP'
}
# fenêtre de choix : une colonne par onglet, une case par carte (cochée = affichée), appliqué tout de suite
function Show-CardPicker {
    if ($ToolsUI.UndoPop) { $ToolsUI.UndoPop.IsOpen = $false }
    if (-not $Lazy.Done) { New-DeferredPage }
    if (-not $ToolsUI.Built) { New-ToolsPage }
    $wrap = [Windows.Controls.WrapPanel]::new()
    $boxes = [Collections.ArrayList]::new()
    foreach ($p in $CardPages.Keys) {
        $cards = @(Get-AllPageCard $p); if (-not $cards.Count) { continue }
        $col = [Windows.Controls.StackPanel]::new(); $col.Width = 270; $col.Margin = New-Thickness 0 0 14 14
        $h = New-Text $CardPages[$p]; $h.FontWeight = [Windows.FontWeights]::SemiBold; $h.FontSize = 14; $h.Margin = New-Thickness 8 0 0 4; [void]$col.Children.Add($h)
        foreach ($c in $cards) {
            # case cochée = carte affichée ; gestionnaires posés après l'état initial (clic sur la case ou sur la ligne)
            $ct = New-Text $c.Title; $ct.TextWrapping = 'Wrap'
            $cb = New-HoverCheck $col '' $null $null; $cb.Content = $ct
            $cb.Tag = $c; $cb.IsChecked = -not $HiddenCards.Contains($c.Key); [void]$boxes.Add($cb)
            $cb.Add_Checked({ param($s, $e) [void]$HiddenCards.Remove($s.Tag.Key); Save-HiddenCard; Set-CardShown $s.Tag $true; Update-CardCount })
            $cb.Add_Unchecked({ param($s, $e) [void]$HiddenCards.Add($s.Tag.Key); Save-HiddenCard; Set-CardShown $s.Tag $false; Update-CardCount })
        }
        [void]$wrap.Children.Add($col)
    }
    $sv = [Windows.Controls.ScrollViewer]::new(); $sv.VerticalScrollBarVisibility = 'Auto'; $sv.MaxHeight = 520; $sv.Content = $wrap
    $v = Show-Dialog "Cartes affichées`n`nDécocher une carte la masque dans son onglet, la cocher la réaffiche ; appliqué tout de suite. Raccourci : clic droit sur une carte > Masquer cette carte." 'Info' @(@{ T = 'Tout réafficher'; V = 'all' }, @{ T = 'Fermer'; V = 'ok'; C = $true }) $null $null 920 $sv
    if ($v -eq 'all') { Show-AllCard; Show-CardPicker }
}
function Update-CardCount { if ($SetUI.CardsCount) { $SetUI.CardsCount.Text = $(if ($HiddenCards.Count) { '{0} carte(s) masquée(s)' -f $HiddenCards.Count } else { 'Aucune carte masquée.' }) } }

# Onglets masqués (Paramètres > Onglets et cartes affichés) : HKCU\Software\Oliv_Maintenance\Affichage\OngletsMasques,
# conservés d'une version à l'autre. Accueil et Paramètres toujours accessibles ; onglet affiché masqué = retour à l'Accueil.
$TabLabels = [ordered]@{ Maint = 'Maintenance'; Perf = 'Performances'; Secu = 'Sécurité'; Perso = 'Personnalisation'; Apps = 'Applications'; Svc = 'Services et tâches'; Tools = 'Outils'; Log = 'Journal' }
$HiddenTabs = [Collections.Generic.HashSet[string]]::new()
try { foreach ($x in @(Get-RegValue $CardRegKey 'OngletsMasques')) { if ($x) { [void]$HiddenTabs.Add("$x") } } } catch { Write-Ignored 'Onglets masqués' $_ }
function Save-HiddenTab {
    try { $k = Open-RegKey $CardRegKey $true $true; try { $k.SetValue('OngletsMasques', [string[]]@($HiddenTabs), [Microsoft.Win32.RegistryValueKind]::MultiString) } finally { $k.Close() } }
    catch { Write-Ignored 'Enregistrement des onglets masqués' $_ }
}
function Update-TabVisibility {
    foreach ($pg in $TabLabels.Keys) { $n = $Ui["Nav$pg"]; if ($n) { $n.Visibility = $(if ($HiddenTabs.Contains($pg)) { 'Collapsed' } else { 'Visible' }) } }
    if ($HiddenTabs.Contains("$($Sync.LastPage)") -and (Get-Command Show-Page -ErrorAction SilentlyContinue)) { Show-Page 'Info' }
}
Update-TabVisibility
