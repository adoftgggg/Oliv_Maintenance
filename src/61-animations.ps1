# =====================================================================================================================
# Animations
#   - propriétés de rendu uniquement (Opacity, RenderTransform) : aucune mise en page recalculée pendant l'effet ;
#   - pas de cache bitmap (BitmapCache) : son image, arrondie au pixel, décalait le contenu de 1 à 2 px à la fin de l'effet ;
#   - mise en page faite AVANT le départ de l'horloge : la 1re image ne mange pas le début de l'animation ;
#   - travail PowerShell des minuteurs suspendu pendant l'effet (Test-AnimBusy) : le fil d'interface reste libre ;
#   - réglable dans Paramètres > Apparence : toujours (défaut), suivre Windows, jamais.
# API : Start-Transition (brique de base), Add-WindowAnim (ouverture / fermeture de fenêtre), Show-PageTransition,
#       Set-Fold (dépliage / repliage), Invoke-Morph (contenu reconstruit).
# =====================================================================================================================
$Anim = @{ Until = [DateTime]::MinValue }
$Anim.EaseOut = [Windows.Media.Animation.CubicEase]::new(); $Anim.EaseOut.EasingMode = 'EaseOut'; $Anim.EaseOut.Freeze()
$Anim.EaseIn  = [Windows.Media.Animation.CubicEase]::new(); $Anim.EaseIn.EasingMode  = 'EaseIn';  $Anim.EaseIn.Freeze()

# Mode (Paramètres > Apparence, _etat\animations.txt) : On = toujours, Sys = suivre Windows (« Effets d'animation » et
# « Animer les contrôles et éléments à l'intérieur des fenêtres » des options de performances : SPI_GETCLIENTAREAANIMATION), Off = jamais
$AnimFile = Join-Path (Get-LogPath 'Etat') 'animations.txt'
$Anim.Mode = 'On'
try {
    if (Test-Path -LiteralPath $AnimFile) { $m = [IO.File]::ReadAllText($AnimFile).Trim(); if ($m -in 'On', 'Sys', 'Off') { $Anim.Mode = $m } }
} catch {
    Write-Ignored 'Lecture du réglage des animations' $_
}
function Test-Anim {
    switch ($Anim.Mode) { 'Off' { return $false } 'Sys' {
        try { return [bool][Windows.SystemParameters]::ClientAreaAnimation } catch { return $true }
    } default { return $true } }
}
function Test-AnimBusy { [DateTime]::UtcNow -lt $Anim.Until }
# minuteurs suspendus jusqu'à la fin de l'effet le plus long en cours
function Lock-Anim([int]$Ms) { $u = [DateTime]::UtcNow.AddMilliseconds($Ms + 60); if ($u -gt $Anim.Until) { $Anim.Until = $u } }
function New-Anim([double]$From, [double]$To, [int]$Ms, [bool]$EaseIn = $false) {
    $a = [Windows.Media.Animation.DoubleAnimation]::new($From, $To, [Windows.Duration]::new([TimeSpan]::FromMilliseconds($Ms)))
    $a.EasingFunction = $(if ($EaseIn) { $Anim.EaseIn } else { $Anim.EaseOut })
    $a
}
# Brique de base : opacité From > To, translation (Dx, Dy) > 0 en entrée ou 0 > (Dx, Dy) en sortie, échelle Scale > 1 / 1 > Scale.
# En fin d'effet : transformation retirée ; -Collapse masque l'élément, -CloseWindow ferme la fenêtre indiquée.
function Start-Transition {
    param($El, [double]$From = 0, [double]$To = 1, [double]$Dx = 0, [double]$Dy = 0, [double]$Scale = 1, [int]$Ms = 240,
          [switch]$Out, [switch]$Collapse, $CloseWindow)
    if ($null -eq $El) { return }
    if (-not (Test-Anim)) {
        if ($Collapse) { $El.Visibility = 'Collapsed' }
        if ($CloseWindow) { $CloseWindow.Close() }
        return
    }
    if (-not $Out) { $El.UpdateLayout() }
    $tt = [Windows.Media.TranslateTransform]::new(); $st = $null
    if ($Scale -ne 1) {
        $st = [Windows.Media.ScaleTransform]::new(); $tg = [Windows.Media.TransformGroup]::new()
        $tg.Children.Add($st); $tg.Children.Add($tt); $El.RenderTransformOrigin = [Windows.Point]::new(0.5, 0.5); $El.RenderTransform = $tg
    } else { $El.RenderTransform = $tt }
    Lock-Anim $Ms
    $op = New-Anim $From $To $Ms ([bool]$Out)
    $El = $El; $col = [bool]$Collapse; $win = $CloseWindow
    $op.Add_Completed({
        $El.RenderTransform = [Windows.Media.Transform]::Identity
        $El.BeginAnimation([Windows.UIElement]::OpacityProperty, $null)
        if ($col) { $El.Visibility = 'Collapsed' }
        if ($win) { $win.Close() }
    }.GetNewClosure())
    if ($Out) {
        $x0 = 0
        $x1 = $Dx
        $y0 = 0
        $y1 = $Dy
        $s0 = 1
        $s1 = $Scale
    } else {
        $x0 = $Dx
        $x1 = 0
        $y0 = $Dy
        $y1 = 0
        $s0 = $Scale
        $s1 = 1
    }
    if ($Dx) { $tt.BeginAnimation([Windows.Media.TranslateTransform]::XProperty, (New-Anim $x0 $x1 $Ms ([bool]$Out))) }
    if ($Dy) { $tt.BeginAnimation([Windows.Media.TranslateTransform]::YProperty, (New-Anim $y0 $y1 $Ms ([bool]$Out))) }
    if ($st) {
        $st.BeginAnimation([Windows.Media.ScaleTransform]::ScaleXProperty, (New-Anim $s0 $s1 $Ms ([bool]$Out)))
        $st.BeginAnimation([Windows.Media.ScaleTransform]::ScaleYProperty, (New-Anim $s0 $s1 $Ms ([bool]$Out)))
    }
    $El.BeginAnimation([Windows.UIElement]::OpacityProperty, $op)
}
# Fenêtre : apparition (fondu, zoom 96 % > 100 %, glissement 12 px) ; disparition (fondu, recul à 97 %) puis fermeture réelle.
# -NoClose : fenêtre principale, ou fenêtre dont le résultat passe par DialogResult (annuler Closing le perturberait).
function Add-WindowAnim($W, [switch]$NoClose) {
    $W.Add_Loaded({ param($s, $e) if ($s.Content -is [Windows.UIElement]) { Start-Transition $s.Content -Dy 12 -Scale 0.96 -Ms 260 } })
    if ($NoClose) { return }
    $W.Add_Closing({
        param($s, $e)
        if ($s.Resources.Contains('_olivmClosing') -or -not (Test-Anim) -or $s.Content -isnot [Windows.UIElement]) { return }
        $e.Cancel = $true; $s.Resources['_olivmClosing'] = $true
        Start-Transition $s.Content -From 1 -To 0 -Scale 0.97 -Ms 150 -Out -CloseWindow $s
    })
}
# Changement de page : la nouvelle page glisse depuis le côté de l'onglet choisi
function Show-PageTransition($Page, [double]$Dx) { Start-Transition $Page -Dx $Dx -Ms 240 }
# Dépliage / repliage (comme l'Expander de WinUI) : le contenu apparaît en glissant, le reste de la page se décale d'un coup
function Set-Fold($El, [bool]$Open) {
    if ($Open) { $El.Visibility = 'Visible'; Start-Transition $El -Dy -8 -Ms 200 }
    else { Start-Transition $El -From 1 -To 0 -Dy -6 -Ms 120 -Out -Collapse }
}
# Contenu reconstruit (« + N autres » / « Réduire ») : nouveau contenu affiché en fondu
function Invoke-Morph($Panel, [scriptblock]$Action) {
    & $Action
    Start-Transition $Panel -From 0.25 -Dy -4 -Ms 180
}
# Travail différé après l'effet en cours (rafraîchissement de page) : la dernière demande remplace la précédente
function Invoke-AfterAnim([scriptblock]$Action) {
    $Anim.Pending = $Action
    if (-not $Anim.Timer) {
        $Anim.Timer = [Windows.Threading.DispatcherTimer]::new()
        $Anim.Timer.Add_Tick({
            if (Test-AnimBusy) { return }
            $Anim.Timer.Stop(); $a = $Anim.Pending; $Anim.Pending = $null
            if ($a) { try { & $a } catch { Write-Ignored 'Action après animation' $_ } }
        })
    }
    $Anim.Timer.Interval = [TimeSpan]::FromMilliseconds(60); $Anim.Timer.Stop(); $Anim.Timer.Start()
}
