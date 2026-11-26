# Taille et position des fenêtres mémorisées (option des Paramètres, activée par défaut) : _etat\fenetres.json
$WinFile = Join-Path (Get-LogPath 'Etat') 'fenetres.json'
$WinPos = @{ Enabled = $true; W = @{} }
try {
    if (Test-Path -LiteralPath $WinFile) {
        $j = Get-Content -LiteralPath $WinFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -ne $j.Enabled) { $WinPos.Enabled = [bool]$j.Enabled }
        if ($j.W) { foreach ($pp in $j.W.PSObject.Properties) { $WinPos.W[$pp.Name] = $pp.Value } }
    }
} catch { Write-Ignored 'Lecture des positions de fenêtres' $_ }
function Save-WindowPositionStore { try { ConvertTo-Json -InputObject @{ Enabled = $WinPos.Enabled; W = $WinPos.W } -Depth 4 | Set-Content -LiteralPath $WinFile -Encoding UTF8 } catch { Write-Ignored 'Enregistrement des positions de fenêtres' $_ } }
# Placement par l'API Windows (GetWindowPlacement / SetWindowPlacement) : coordonnées de l'écran réel, plusieurs écrans et
# mises à l'échelle différentes gérés par Windows, qui ramène aussi sur un écran visible une fenêtre placée sur un écran débranché
function Save-WindowPlacement([string]$Name, $Win) {
    if (-not $WinPos.Enabled -or -not $Win) { return }
    try {
        $h = [Windows.Interop.WindowInteropHelper]::new($Win).Handle
        $r = [_OlivM.WinPlace]::Get($h)
        if (-not $r -or ($r[2] - $r[0]) -lt 200 -or ($r[3] - $r[1]) -lt 150) { return }
        $WinPos.W[$Name] = @{ V = 2; L = $r[0]; T = $r[1]; R = $r[2]; B = $r[3]; Max = ("$($Win.WindowState)" -eq 'Maximized') }
        Save-WindowPositionStore
    } catch { Write-FileLog "Position de la fenêtre $Name non enregistrée : $($_.Exception.Message)" 'WARN' }
}
# appliqué quand la fenêtre a son handle et avant son affichage (SourceInitialized), puis agrandissement si elle l'était
function Restore-WindowPlacement([string]$Name, $Win) {
    if (-not $WinPos.Enabled) { return $false }
    $p = $WinPos.W[$Name]; if (-not $p -or [int]$p.V -ne 2) { return $false }
    $Win.WindowStartupLocation = 'Manual'
    $Win.Uid = $Name
    $Win.Add_SourceInitialized({
        param($s, $e)
        $p = $WinPos.W["$($s.Uid)"]
        try {
            $h = [Windows.Interop.WindowInteropHelper]::new($s).Handle
            if ([_OlivM.WinPlace]::Set($h, [int]$p.L, [int]$p.T, [int]$p.R, [int]$p.B) -and $p.Max) {
                # fenêtre ouverte réduite : agrandie seulement quand elle sera rouverte
                if ("$($s.WindowState)" -eq 'Minimized') { if ($s -eq $Window) { $Tray.LastState = 'Maximized' } } else { $s.WindowState = 'Maximized' }
            }
        } catch { Write-FileLog "Position de la fenêtre $($s.Uid) non restaurée : $($_.Exception.Message)" 'WARN' }
    })
    $true
}
# Fenêtre secondaire (analyseur d'espace disque, logiciels) : sans propriétaire, pour que la fenêtre principale repasse
# au premier plan quand on clique dessus ; centrée sur la fenêtre principale, fermée avec elle (voir Closing)
# Zoom de l'interface (Ctrl + molette, Ctrl + / Ctrl -, Ctrl 0) : agrandissement de tout le contenu des fenêtres de l'application,
# de 80 à 150 % par pas de 10 %, mémorisé (_etat\zoom.txt) et réglable dans Paramètres > Apparence
$ZoomFile = Join-Path (Get-LogPath 'Etat') 'zoom.txt'
$UiZoom = 1.0
try {
    if (Test-Path -LiteralPath $ZoomFile) {
        $UiZoom = [double]::Parse([IO.File]::ReadAllText($ZoomFile).Trim(), [Globalization.CultureInfo]::InvariantCulture)
    }
} catch {
    Write-Ignored 'Lecture du zoom enregistré' $_
}
if ($UiZoom -lt 0.8 -or $UiZoom -gt 1.5) { $UiZoom = 1.0 }
# fenêtres Analyse de l'espace disque et Logiciels : zoom propre à chaque fenêtre ($WinZoom, clé = Uid de la fenêtre),
# mémorisé (_etat\zoom-<fenêtre>.txt), commandes en bas de la fenêtre ; les boîtes de dialogue suivent le zoom général
$WinZoom = @{}
# Zoom des fenêtres secondaires : texte de la liste seul (tailles de police multipliées), le reste de la fenêtre inchangé.
# Taille d'origine de chaque élément mémorisée sans le retenir en mémoire (ConditionalWeakTable) ; seuls les éléments dont
# la taille est fixée (locale, style, modèle) sont modifiés, les autres suivent leur parent par héritage.
$TextBase = [Runtime.CompilerServices.ConditionalWeakTable[object, object]]::new()
function Set-TextZoom($Root, [double]$Z) {
    if (-not $Root) { return }
    $stack = [Collections.Generic.Stack[object]]::new(); $stack.Push($Root)
    while ($stack.Count) {
        $d = $stack.Pop()
        $dp = $(if ($d -is [Windows.Controls.TextBlock]) { [Windows.Controls.TextBlock]::FontSizeProperty } elseif ($d -is [Windows.Controls.Control]) { [Windows.Controls.Control]::FontSizeProperty } else { $null })
        if ($dp) {
            $b = $null
            if ($TextBase.TryGetValue($d, [ref]$b)) { $d.SetValue($dp, [double]$b * $Z) }
            else {
                $src = "$([Windows.DependencyPropertyHelper]::GetValueSource($d, $dp).BaseValueSource)"
                if ($d -eq $Root -or $src -notin 'Inherited', 'Default') {
                    $v = [double]$d.GetValue($dp)
                    $TextBase.Add($d, $v)
                    $d.SetValue($dp, $v * $Z)
                }
            }
        }
        if ($d -is [Windows.Media.Visual]) {
            $n = [Windows.Media.VisualTreeHelper]::GetChildrenCount($d)
            for ($i = 0; $i -lt $n; $i++) { $stack.Push([Windows.Media.VisualTreeHelper]::GetChild($d, $i)) }
        }
    }
}
# zone concernée par le zoom : la liste seule (lignes et message de liste vide), ni en-têtes, ni boutons, ni tuiles
$WinZoomRoots = @{ Logiciels = { @($SoftUI.List, $SoftUI.Hint) }; EspaceDisque = { @($TreeUI.List, $TreeUI.ListHint) }; Moniteur = { @($MonUI.List, $MonUI.Hint) } }
# lignes ajoutées après coup : même zoom texte que la liste de leur fenêtre
function Update-WinTextZoom($W, $Root) { if ($W -and $W.Uid -and $WinZoom.ContainsKey($W.Uid)) { Set-TextZoom $Root $WinZoom[$W.Uid] } }
function Get-ZoomValue([double]$Z) { [math]::Round([double][math]::Max([double]0.8, [math]::Min([double]1.5, $Z)), [int]1) }
function Set-WindowZoom($W) {
    if (-not $W -or -not $W.Content) { return }
    $own = $W -ne $Window -and $W.Uid -and $WinZoom.ContainsKey($W.Uid)
    $z = $(if ($own) { $WinZoom[$W.Uid] } else { $UiZoom })
    if ($own) { $W.Content.LayoutTransform = $null; foreach ($r in @(& $WinZoomRoots[$W.Uid])) { Set-TextZoom $r $z } }
    else { $W.Content.LayoutTransform = $(if ([math]::Abs($z - 1) -lt 0.01) { $null } else { [Windows.Media.ScaleTransform]::new($z, $z) }) }
    $zt = $W.FindName('ZoomTxt'); if ($zt) { $zt.Text = '{0} %' -f [int][math]::Round(100 * $z) }
    # fenêtre principale : zone de titre (déplacement de la fenêtre) à la hauteur réelle de l'en-tête
    if ($W -eq $Window) {
        try { [Windows.Shell.WindowChrome]::GetWindowChrome($W).CaptionHeight = 56 * $UiZoom } catch {}
        # WindowChrome remet son découpage de la fenêtre agrandie en appliquant la nouvelle hauteur : retiré ensuite (voir WinPlace.MaxHook)
        [void]$W.Dispatcher.BeginInvoke([Action]{
            try { [_OlivM.WinPlace]::NoRegion([Windows.Interop.WindowInteropHelper]::new($Window).Handle) } catch { Write-Ignored 'Fenêtre agrandie (découpage)' $_ }
        }, [Windows.Threading.DispatcherPriority]::Background)
    }
}
function Set-ChildZoom($W, [double]$Z) {
    $Z = Get-ZoomValue $Z; $WinZoom[$W.Uid] = $Z
    Set-WindowZoom $W
    try {
        [IO.File]::WriteAllText((Join-Path (Get-LogPath 'Etat') "zoom-$($W.Uid).txt"), $Z.ToString([Globalization.CultureInfo]::InvariantCulture))
    } catch {
        Write-Ignored 'Enregistrement du zoom' $_
    }
    Show-ZoomToast $Z $W
}
function Initialize-ChildZoom($W) {
    $z = 1.0; $f = Join-Path (Get-LogPath 'Etat') "zoom-$($W.Uid).txt"
    try {
        if (Test-Path -LiteralPath $f) {
            $z = Get-ZoomValue ([double]::Parse([IO.File]::ReadAllText($f).Trim(), [Globalization.CultureInfo]::InvariantCulture))
        }
    } catch {
        Write-Ignored 'Lecture du zoom enregistré' $_
    }
    $WinZoom[$W.Uid] = $z
    $W.FindName('ZoomOut').Add_Click({ param($s, $e) $W = [Windows.Window]::GetWindow($s); Set-ChildZoom $W ($WinZoom[$W.Uid] - 0.1) })
    $W.FindName('ZoomIn').Add_Click({ param($s, $e) $W = [Windows.Window]::GetWindow($s); Set-ChildZoom $W ($WinZoom[$W.Uid] + 0.1) })
    $W.FindName('ZoomTxt').Add_MouseLeftButtonUp({ param($s, $e) Set-ChildZoom ([Windows.Window]::GetWindow($s)) 1 })
    Set-WindowZoom $W
}
function Set-UiZoom([double]$Z, [bool]$Show = $true) {
    $Z = Get-ZoomValue $Z
    $script:UiZoom = $Z
    foreach ($w in @($Window, $TreeUI.Win, $SoftUI.Win)) { Set-WindowZoom $w }
    try { [IO.File]::WriteAllText($ZoomFile, $Z.ToString([Globalization.CultureInfo]::InvariantCulture)) } catch { Write-Ignored 'Enregistrement du zoom' $_ }
    if ($SetUI.Zoom) {
        foreach ($b in $SetUI.Zoom) {
            $b.Tag = $(if ([math]::Abs([double]::Parse("$($b.DataContext)", [Globalization.CultureInfo]::InvariantCulture) - $Z) -lt 0.01) { 'on' } else { '' })
        }
    }
    if ($Show) { Show-ZoomToast }
}
# indicateur « Zoom 110 % » au centre de la fenêtre active, 1,2 s : apparition et disparition en fondu (150 ms), fond en
# verre dépoli : instantané de la zone de la fenêtre située derrière (RenderTargetBitmap, refait à chaque zoom), flouté,
# voilé de la couleur des
# panneaux du thème, contour fin et ombre. Pastille déjà affichée : texte mis à jour sans nouveau fondu.
function Show-ZoomToast([double]$Z = $UiZoom, $Target = $null) {
    if (-not $script:ZoomPop) {
        $zp = @{}
        $root = [Windows.Controls.Grid]::new(); $root.Margin = New-Thickness 16 16 16 16; $root.Opacity = 0
        # ombre : forme pleine sous le verre (masquée par lui), seul son halo dépasse
        $sh = [Windows.Controls.Border]::new()
        $sh.CornerRadius = [Windows.CornerRadius]::new(10)
        $sh.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, 'PanelBrush')
        $fx = [Windows.Media.Effects.DropShadowEffect]::new()
        $fx.BlurRadius = 18
        $fx.ShadowDepth = 3
        $fx.Opacity = 0.3
        $fx.Direction = 270
        $sh.Effect = $fx
        # verre : fond flouté découpé aux coins arrondis (le flou déborde de 24 px, rogné par la découpe)
        $glass = [Windows.Controls.Grid]::new(); $glass.ClipToBounds = $true
        # pas de VisualBrush sur la fenêtre : la fenêtre devenait parente logique de son propre contenu via la pastille
        # (cycle dans l'arborescence, erreur fatale à l'ouverture de la pastille en 0.108.8)
        $vb = [Windows.Media.ImageBrush]::new(); $vb.Stretch = 'Fill'
        $bg = [Windows.Shapes.Rectangle]::new(); $bg.Fill = $vb; $bg.Margin = New-Thickness -24 -24 -24 -24
        $bl = [Windows.Media.Effects.BlurEffect]::new(); $bl.Radius = 22; $bl.KernelType = 'Gaussian'; $bl.RenderingBias = 'Performance'; $bg.Effect = $bl
        $tint = [Windows.Shapes.Rectangle]::new(); $tint.SetResourceReference([Windows.Shapes.Shape]::FillProperty, 'PanelBrush'); $tint.Opacity = 0.62
        [void]$glass.Children.Add($bg); [void]$glass.Children.Add($tint)
        $edge = [Windows.Controls.Border]::new()
        $edge.CornerRadius = [Windows.CornerRadius]::new(10)
        $edge.BorderThickness = New-Thickness 1
        $edge.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, 'LineBrush')
        $t = New-Text ''
        $t.FontSize = 14
        $t.FontWeight = [Windows.FontWeights]::SemiBold
        $t.Margin = New-Thickness 18 9 18 9
        $t.HorizontalAlignment = 'Center'
        $t.VerticalAlignment = 'Center'
        $t.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'FgBrush')
        foreach ($c in $sh, $glass, $edge, $t) { [void]$root.Children.Add($c) }
        # découpe arrondie et cadrage du fond : zone de la fenêtre exactement derrière la pastille (centrée), marge du flou comprise
        $root.Add_SizeChanged({ & $script:ZoomPop.Fit })
        $zp.Fit = {
            $zp = $script:ZoomPop; $w = $zp.Root.ActualWidth; $h = $zp.Root.ActualHeight; if (-not $w) { return }
            $zp.Glass.Clip = [Windows.Media.RectangleGeometry]::new([Windows.Rect]::new(0, 0, $w, $h), 10, 10)
            $tg = $zp.Pop.PlacementTarget; if (-not $tg) { return }
            # zone de la fenêtre derrière la pastille (marge du flou comprise), en pixels réels, bornée à la fenêtre
            try {
                $m = [Windows.PresentationSource]::FromVisual($tg).CompositionTarget.TransformToDevice
                $tw = [int][math]::Ceiling($tg.ActualWidth * $m.M11); $th = [int][math]::Ceiling($tg.ActualHeight * $m.M22)
                if ($tw -lt 2 -or $th -lt 2) { return }
                $x = [int][math]::Max([double]0, (($tg.ActualWidth - $w) / 2 - 24) * $m.M11)
                $y = [int][math]::Max([double]0, (($tg.ActualHeight - $h) / 2 - 24) * $m.M22)
                $cw = [int][math]::Min([double]($tw - $x), ($w + 48) * $m.M11); $ch = [int][math]::Min([double]($th - $y), ($h + 48) * $m.M22)
                if ($cw -lt 1 -or $ch -lt 1) { return }
                $rtb = [Windows.Media.Imaging.RenderTargetBitmap]::new($tw, $th, 96 * $m.M11, 96 * $m.M22, [Windows.Media.PixelFormats]::Pbgra32)
                $rtb.Render($tg)
                $cb = [Windows.Media.Imaging.CroppedBitmap]::new($rtb, [Windows.Int32Rect]::new($x, $y, $cw, $ch)); $cb.Freeze()
                $zp.Brush.ImageSource = $cb
            } catch { Write-Ignored 'Pastille de zoom (fond)' $_ }
        }
        $pp = [Windows.Controls.Primitives.Popup]::new(); $pp.AllowsTransparency = $true; $pp.Child = $root; $pp.Placement = 'Center'; $pp.StaysOpen = $true
        $root.Resources.MergedDictionaries.Add($Window.Resources)
        $zp.Pop = $pp; $zp.Root = $root; $zp.Text = $t; $zp.Glass = $glass; $zp.Brush = $vb; $zp.Timer = [Windows.Threading.DispatcherTimer]::new()
        $zp.Timer.Interval = [TimeSpan]::FromMilliseconds(1200)
        $zp.Timer.Add_Tick({ param($s, $e)
            $s.Stop(); $zp = $script:ZoomPop
            $an = [Windows.Media.Animation.DoubleAnimation]::new(0, [Windows.Duration]::new([TimeSpan]::FromMilliseconds(180)))
            $an.Add_Completed({
                $zp = $script:ZoomPop
                if ($zp.Root.Opacity -lt 0.01 -and -not $zp.Timer.IsEnabled) { $zp.Pop.IsOpen = $false; $zp.Brush.ImageSource = $null }
            })
            $zp.Root.BeginAnimation([Windows.UIElement]::OpacityProperty, $an) })
        $script:ZoomPop = $zp
    }
    $zp = $script:ZoomPop
    $owner = $(if ($Target) { $Target } else { @($Window, $TreeUI.Win, $SoftUI.Win, $MonUI.Win) | Where-Object { $_ -and $_.IsActive } | Select-Object -First 1 })
    if (-not $owner) { $owner = $Window }
    $zp.Text.Text = 'Zoom {0} %' -f [int][math]::Round($Z * 100)
    $zp.Timer.Stop()
    if (-not $zp.Pop.IsOpen -or $zp.Pop.PlacementTarget -ne $owner) {
        $zp.Pop.IsOpen = $false; $zp.Pop.PlacementTarget = $owner
        $zp.Root.BeginAnimation([Windows.UIElement]::OpacityProperty, $null); $zp.Root.Opacity = 0
        # pastille = simple indication : un échec d'affichage ne doit jamais remonter (erreur fatale en 0.108.8)
        try { $zp.Pop.IsOpen = $true } catch { Write-Ignored 'Pastille de zoom' $_; return }
    }
    # instantané refait une fois la nouvelle taille de texte appliquée (après la mise en page)
    # plusieurs crans de molette rapprochés : un seul instantané (le dernier)
    if (-not $zp.FitQueued) {
        $zp.FitQueued = $true
        [void]$zp.Root.Dispatcher.BeginInvoke([Action]{
            $script:ZoomPop.FitQueued = $false
            & $script:ZoomPop.Fit
        }, [Windows.Threading.DispatcherPriority]::Loaded)
    }
    # fondu d'entrée depuis l'opacité courante (pastille en train de disparaître : elle revient sans clignoter)
    $an = [Windows.Media.Animation.DoubleAnimation]::new(1, [Windows.Duration]::new([TimeSpan]::FromMilliseconds(150)))
    $zp.Root.BeginAnimation([Windows.UIElement]::OpacityProperty, $an)
    $zp.Timer.Start()
}
# zone du journal : Ctrl + molette / Ctrl + touches zooment le texte du journal seul (74-journal.ps1), pas la fenêtre
$ZoomWheel = {
    param($s, $e)
    if (-not ([Windows.Input.Keyboard]::Modifiers -band [Windows.Input.ModifierKeys]::Control)) { return }
    if ($Ui -and $Ui.LogBox -and $Ui.LogBox.IsMouseOver) {
        Set-LogZoom ($LogView.Zoom + $(if ($e.Delta -gt 0) { 0.1 } else { -0.1 }))
        $e.Handled = $true
        return
    }
    if ($s -ne $Window -and $s.Uid -and $WinZoom.ContainsKey($s.Uid)) {
        Set-ChildZoom $s ($WinZoom[$s.Uid] + $(if ($e.Delta -gt 0) { 0.1 } else { -0.1 }))
        $e.Handled = $true
        return
    }
    Set-UiZoom ($UiZoom + $(if ($e.Delta -gt 0) { 0.1 } else { -0.1 })); $e.Handled = $true
}
$ZoomKeys = {
    param($s, $e)
    if (-not ([Windows.Input.Keyboard]::Modifiers -band [Windows.Input.ModifierKeys]::Control)) { return }
    # clavier : zone du journal sous la souris ou ayant le focus
    if ($Ui -and $Ui.LogBox -and ($Ui.LogBox.IsKeyboardFocusWithin -or $Ui.LogBox.IsMouseOver)) {
        switch ("$($e.Key)") {
            { $_ -in 'Add', 'OemPlus' } { Set-LogZoom ($LogView.Zoom + 0.1); $e.Handled = $true }
            { $_ -in 'Subtract', 'OemMinus', 'D6' } { Set-LogZoom ($LogView.Zoom - 0.1); $e.Handled = $true }
            { $_ -in 'D0', 'NumPad0' } { Set-LogZoom 1; $e.Handled = $true }
        }
        return
    }
    # fenêtre à zoom propre (Logiciels, Analyse de l'espace disque)
    if ($s -ne $Window -and $s.Uid -and $WinZoom.ContainsKey($s.Uid)) {
        switch ("$($e.Key)") {
            { $_ -in 'Add', 'OemPlus' } { Set-ChildZoom $s ($WinZoom[$s.Uid] + 0.1); $e.Handled = $true }
            { $_ -in 'Subtract', 'OemMinus', 'D6' } { Set-ChildZoom $s ($WinZoom[$s.Uid] - 0.1); $e.Handled = $true }
            { $_ -in 'D0', 'NumPad0' } { Set-ChildZoom $s 1; $e.Handled = $true }
        }
        return
    }
    switch ("$($e.Key)") {
        { $_ -in 'Add', 'OemPlus' } { Set-UiZoom ($UiZoom + 0.1); $e.Handled = $true }
        { $_ -in 'Subtract', 'OemMinus', 'D6' } { Set-UiZoom ($UiZoom - 0.1); $e.Handled = $true }
        { $_ -in 'D0', 'NumPad0' } { Set-UiZoom 1.0; $e.Handled = $true }
    }
}
