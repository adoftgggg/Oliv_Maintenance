# Fenêtre principale sans cadre Windows (WindowChrome) : agrandie, Windows la place au-delà de la zone de travail de
# l'épaisseur du cadre de redimensionnement ; le contenu est rentré d'autant pour occuper exactement l'écran. Débord lu par
# Win32 (GetWindowRect / GetMonitorInfo) : l'ancien calcul (PointToScreen + Screen.WorkingArea) mélangeait deux référentiels
# DPI et laissait quelques pixels vides en haut. Calcul WPF + Forms gardé en secours.
function Get-MaxOverhang($W = $Window) {
    try {
        $h = [Windows.Interop.WindowInteropHelper]::new($W).Handle
        $o = [_OlivM.WinPlace]::Overhang($h)
        if ($o) {
            $m = [System.Windows.PresentationSource]::FromVisual($W).CompositionTarget.TransformToDevice
            return New-Thickness ($o[0] / $m.M11) ($o[1] / $m.M22) ($o[2] / $m.M11) ($o[3] / $m.M22)
        }
    } catch { Write-Ignored 'Fenêtre agrandie (débord)' $_ }
    try {
        if (-not $Sync.FormsLoaded) { Add-Type -AssemblyName System.Windows.Forms, System.Drawing; $Sync.FormsLoaded = $true }
        $m  = [System.Windows.PresentationSource]::FromVisual($W).CompositionTarget.TransformToDevice
        $p  = $W.PointToScreen([System.Windows.Point]::new(0, 0))
        $pw = $W.ActualWidth * $m.M11; $ph = $W.ActualHeight * $m.M22
        $wa = [System.Windows.Forms.Screen]::FromPoint([System.Drawing.Point]::new([int]($p.X + $pw / 2), [int]($p.Y + $ph / 2))).WorkingArea
        return New-Thickness ([math]::Max([double]0, $wa.Left - $p.X) / $m.M11) ([math]::Max([double]0, $wa.Top - $p.Y) / $m.M22) ([math]::Max([double]0, ($p.X + $pw) - $wa.Right) / $m.M11) ([math]::Max([double]0, ($p.Y + $ph) - $wa.Bottom) / $m.M22)
    } catch {
        $b = [System.Windows.SystemParameters]::WindowResizeBorderThickness
        return New-Thickness ($b.Left + 4) ($b.Top + 4) ($b.Right + 4) ($b.Bottom + 4)
    }
}
# agrandissement calé sur la zone de travail (voir WinPlace.MaxHook) ; délégué gardé en variable (pas libéré par le GC)
$script:MaxHook = [Delegate]::CreateDelegate([Windows.Interop.HwndSourceHook], [_OlivM.WinPlace].GetMethod('MaxHook'))
$Window.Add_SourceInitialized({
    try { [Windows.Interop.HwndSource]::FromHwnd([Windows.Interop.WindowInteropHelper]::new($Window).Handle).AddHook($script:MaxHook) } catch { Write-Ignored 'Agrandissement de la fenêtre' $_ }
    # coins arrondis comme les fenêtres de Windows 11 (sans effet sur Windows 10)
    try { [void][_OlivM.WinPlace]::RoundCorners([Windows.Interop.WindowInteropHelper]::new($Window).Handle) } catch { Write-Ignored 'Coins arrondis de la fenêtre' $_ }
    # épinglage à la barre des tâches : l'épingle ouvre la copie fixe ProgramData\Oliv_Maintenance\Oliv_Maintenance.exe (mise à
    # jour à chaque lancement), jamais l'exe téléchargé qui change de nom ou disparaît à la mise à jour
    try { if (Sync-StableExe) { [void][_OlivM.Shell]::SetRelaunch([Windows.Interop.WindowInteropHelper]::new($Window).Handle, 'Oliv.Maintenance', ('"{0}"' -f $StableExe), 'Oliv_Maintenance', "$StableExe,0") } } catch { Write-Ignored 'Épinglage à la barre des tâches' $_ }
})
function Update-MaxState {
    if ($Window.WindowState -eq 'Maximized') {
        $Ui.RootBorder.Margin = Get-MaxOverhang
        $Ui.RootBorder.BorderThickness = New-Thickness 0 0 0 0
        $Ui.MaxBtn.Content = [string][char]0xE923; $Ui.MaxBtn.ToolTip = 'Restaurer'
    } else {
        $Ui.RootBorder.Margin = New-Thickness 0 0 0 0
        $Ui.RootBorder.BorderThickness = New-Thickness 1 1 1 1
        $Ui.MaxBtn.Content = [string][char]0xE922; $Ui.MaxBtn.ToolTip = 'Agrandir'
    }
}
$Window.Add_StateChanged({
    Update-MaxState
    if ($Window.WindowState -ne 'Minimized') { $Tray.LastState = "$($Window.WindowState)" }
    # réduire = zone de notification (réglage de l'utilisateur) : fenêtre masquée après la réduction
    elseif ($Tray.Min) { [void]$Window.Dispatcher.BeginInvoke([Action]{ if ($Window.WindowState -eq 'Minimized' -and $Tray.Min) { Hide-MainWindow } }) }
    # fenêtre réduite (au plus 1 fois par minute) : mémoire libérée pendant que personne ne regarde l'application
    if ($Window.WindowState -eq 'Minimized' -and -not $Sync.Running -and (-not $script:LastTrim -or ([DateTime]::Now - $script:LastTrim).TotalSeconds -ge 60)) {
        $script:LastTrim = [DateTime]::Now
        [void]$Window.Dispatcher.BeginInvoke([Action]{
            try { Invoke-MemoryTrim } catch { Write-Ignored 'Libération de la mémoire' $_ }
        }, [Windows.Threading.DispatcherPriority]::ApplicationIdle)
    }
})

$Resp = @{ Mode = ''; Cols = ''; Short = $false }
$NavInfo = [ordered]@{
    Info  = @('Accueil', 'Accueil', 0xE80F)
    Maint = @('Maintenance', 'Maint.', 0xE90F)
    Perf  = @('Système', 'Système', 0xE770)
    Secu  = @('Sécurité', 'Sécurité', 0xE72E)
    Perso = @('Personnalisation', 'Perso.', 0xE771)
    Apps  = @('Applications', 'Apps', 0xE71D)
    Svc   = @('Services et tâches', 'Services', 0xE912)
    Tools = @('Outils', 'Outils', 0xEC7A)
    Log   = @('Journal', 'Journal', 0xE81C)
}
$FontIcon = [Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
function Set-TwoCol($Grid, $L, $R, [int]$Base, [bool]$Narrow, [bool]$Star) {
    if (-not $Grid -or -not $L -or -not $R) { return }
    if ($Narrow) {
        $Grid.ColumnDefinitions[1].Width = [Windows.GridLength]::new(0)
        $Grid.ColumnDefinitions[2].Width = [Windows.GridLength]::new(0)
        if ($Star) {
            $Grid.RowDefinitions.Clear()
            foreach ($i in 1..2) {
                $rd = [Windows.Controls.RowDefinition]::new()
                $rd.Height = [Windows.GridLength]::new(1, [Windows.GridUnitType]::Star)
                [void]$Grid.RowDefinitions.Add($rd)
            }
        } else {
            while ($Grid.RowDefinitions.Count -lt $Base + 2) {
                $rd = [Windows.Controls.RowDefinition]::new()
                $rd.Height = [Windows.GridLength]::Auto
                [void]$Grid.RowDefinitions.Add($rd)
            }
        }
        [Windows.Controls.Grid]::SetColumnSpan($L, 3)
        [Windows.Controls.Grid]::SetColumn($R, 0); [Windows.Controls.Grid]::SetColumnSpan($R, 3); [Windows.Controls.Grid]::SetRow($R, $Base + 1)
        $R.Margin = New-Thickness 0 12 0 0
    } else {
        $Grid.ColumnDefinitions[1].Width = [Windows.GridLength]::new(12)
        $Grid.ColumnDefinitions[2].Width = [Windows.GridLength]::new(1, [Windows.GridUnitType]::Star)
        if ($Star) { $Grid.RowDefinitions.Clear() }
        [Windows.Controls.Grid]::SetColumnSpan($L, 1)
        [Windows.Controls.Grid]::SetColumn($R, 2); [Windows.Controls.Grid]::SetColumnSpan($R, 1); [Windows.Controls.Grid]::SetRow($R, $Base)
        $R.Margin = New-Thickness 0 0 0 0
    }
}
# Pastille sur l'onglet : nombre de modifications sélectionnées mais pas encore appliquées dans cette page
$TabBadges = @{}
function New-TabContent([int]$Glyph, [string]$Text, [string]$Page) {
    $sp = [Windows.Controls.StackPanel]::new(); $sp.Orientation = 'Horizontal'
    $g = [Windows.Controls.TextBlock]::new(); $g.Text = [string][char]$Glyph; $g.FontFamily = $FontIcon; $g.FontSize = 14; $g.VerticalAlignment = 'Center'
    [void]$sp.Children.Add($g)
    if ($Text) {
        $g.Margin = New-Thickness 0 0 8 0
        $t = [Windows.Controls.TextBlock]::new()
        $t.Text = $Text
        $t.VerticalAlignment = 'Center'
        [void]$sp.Children.Add($t)
    }
    if ($Page) {
        $bd = [Windows.Controls.Border]::new()
        $bd.CornerRadius = [Windows.CornerRadius]::new(9)
        $bd.MinWidth = 18
        $bd.Height = 18
        $bd.Padding = New-Thickness 5 0 5 0
        $bd.Margin = New-Thickness $(if ($Text) { 8 } else { 2 }) 0 0 0; $bd.VerticalAlignment = 'Center'; $bd.Visibility = 'Collapsed'
        $bd.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, 'AccentBrush')
        $bt = [Windows.Controls.TextBlock]::new()
        $bt.FontSize = 11
        $bt.FontWeight = [Windows.FontWeights]::SemiBold
        $bt.HorizontalAlignment = 'Center'
        $bt.VerticalAlignment = 'Center'
        $bt.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'OnAccentBrush')
        $bd.Child = $bt; [void]$sp.Children.Add($bd); $TabBadges[$Page] = $bd
    }
    $sp
}
# nombre de modifications en attente par page (réglages, applications au démarrage, nettoyage, applications à désinstaller)
function Get-PendingByPage {
    $st = @(Get-StagedRow)
    $perfTw = @($st | Where-Object { $_.Tweak -and $_.Tweak.Page -eq 'Perf' }).Count
    $perfSu = @($st | Where-Object { $_.Entry }).Count
    $persoTw = @($st | Where-Object { $_.Tweak -and $_.Tweak.Page -eq 'Perso' }).Count
    $secuTw = @($st | Where-Object { $_.Tweak -and $_.Tweak.Page -eq 'Secu' }).Count
    $apx = @(Get-AppxChecked).Count
    $cl = $(if ($CleanUI -and $CleanUI.Count) { @(Get-CleanSelection).Count } else { 0 })
    @{ Perf = @{ N = $perfTw + $perfSu; D = @($(if ($perfTw) { '{0} {1}' -f $perfTw, (Get-Plural $perfTw 'réglage' 'réglages') }), $(if ($perfSu) { '{0} {1} au démarrage' -f $perfSu, (Get-Plural $perfSu 'application' 'applications') })) }
       Perso = @{ N = $persoTw + $apx; D = @($(if ($persoTw) { '{0} {1}' -f $persoTw, (Get-Plural $persoTw 'réglage' 'réglages') }), $(if ($apx) { '{0} {1} à désinstaller' -f $apx, (Get-Plural $apx 'application' 'applications') })) }
       Secu = @{ N = $secuTw; D = @($(if ($secuTw) { '{0} {1}' -f $secuTw, (Get-Plural $secuTw 'réglage' 'réglages') })) }
       Maint = @{ N = $cl; D = @($(if ($cl) { '{0} {1} de nettoyage' -f $cl, (Get-Plural $cl 'élément' 'éléments') })) } }
}
function Update-TabBadge {
    $pp = Get-PendingByPage
    $names = @{ Perf = 'Système'; Secu = 'Sécurité'; Perso = 'Personnalisation'; Maint = 'Maintenance' }
    $tip = @()
    foreach ($k in 'Maint', 'Perf', 'Secu', 'Perso') {
        $n = [int]$pp[$k].N; $bd = $TabBadges[$k]
        $d = @($pp[$k].D | Where-Object { $_ }) -join ', '
        if ($n) { $tip += '{0} : {1}' -f $names[$k], $d }
        if ($bd) {
            $bd.Visibility = $(if ($n) { 'Visible' } else { 'Collapsed' })
            $bd.Child.Text = "$n"
            $bd.ToolTip = $(if ($n) { "En attente d'application : $d" } else { $null })
        }
    }
    # bouton du bas : détail de ce qui sera appliqué, page par page
    $Ui.RunBtn.ToolTip = $(if ($tip.Count) { "En attente d'application :`n" + ($tip -join "`n") } else { $null })
}
# Format des onglets : texte complet > compact > texte court > icône seule
function Set-TabFormat([string]$Mode) {
    foreach ($p in $NavInfo.Keys) {
        $b = $Ui["Nav$p"]; $n = $NavInfo[$p]
        $b.ToolTip = '{0}  (Ctrl+{1})' -f $n[0], (1 + [array]::IndexOf([string[]]$PageNames, [string]$p)); $b.Width = [double]::NaN; $b.MinWidth = 0
        switch ($Mode) {
            'full'    { $b.FontSize = 14; $b.Content = New-TabContent $n[2] $n[0] $p; $b.Padding = New-Thickness 14 0 14 0 }
            'compact' { $b.FontSize = 13; $b.Content = New-TabContent $n[2] $n[0] $p; $b.Padding = New-Thickness 10 0 10 0 }
            'short'   { $b.FontSize = 13; $b.Content = New-TabContent $n[2] $n[1] $p; $b.Padding = New-Thickness 8 0 8 0 }
            'icon'    { $b.FontSize = 14; $b.Content = New-TabContent $n[2] '' $p; $b.MinWidth = 46; $b.Padding = New-Thickness 6 0 6 0 }
        }
    }
}
# largeur réelle des onglets dans chaque format (mesurée une fois, + 24 px de marge pour les pastilles de modifications)
function Get-TabWidth {
    if ($Resp.TabW) { return $Resp.TabW }
    $w = @{}
    foreach ($m in 'full', 'compact', 'short', 'icon') {
        Set-TabFormat $m
        $Ui.TabStrip.Measure([Windows.Size]::new([double]::PositiveInfinity, [double]::PositiveInfinity))
        $w[$m] = $Ui.TabStrip.DesiredSize.Width + 24
    }
    if ($Resp.Mode) { Set-TabFormat $Resp.Mode }
    if ($w.full -gt 100) { $Resp.TabW = $w }
    $w
}
# Choix du format : le plus large qui laisse au moins 220 px à la barre de recherche ; s'il n'y en a aucun, icônes seules
# (et la recherche passe alors en icône). Ordre en élargissant : icônes + loupe > icônes + barre > texte court + barre >
# compact + barre > texte complet + barre ; jamais de retour à la loupe en élargissant. Hystérésis de 16 px vers le haut.
function Get-TabMode {
    $hw = $Ui.HeaderBar.ActualWidth
    if ($hw -le 0) {
        $w = $Window.ActualWidth
        return $(if ($w -ge 1200) { 'full' } elseif ($w -ge 1000) { 'compact' } elseif ($w -ge 820) { 'short' } else { 'icon' })
    }
    $tw = Get-TabWidth
    $stack = $Ui.ThemeBtn.Parent
    $right = $Ui.HeaderBar.ColumnDefinitions[2].ActualWidth + $stack.ActualWidth + $stack.Margin.Left + $stack.Margin.Right
    if ($Ui.SearchIconBtn.Visibility -eq 'Visible') { $right -= $Ui.SearchIconBtn.ActualWidth }
    $order = 'full', 'compact', 'short', 'icon'
    $cur = [array]::IndexOf([string[]]$order, [string]$Resp.Mode)
    for ($i = 0; $i -lt $order.Count; $i++) {
        $m = $order[$i]; $hy = $(if ($cur -ge 0 -and $i -lt $cur) { 16 } else { 0 })
        if ($tw[$m] + $right + 220 + $hy -le $hw) { return $m }
    }
    'icon'
}
function Update-Responsive {
    $w = $Window.ActualWidth
    if (-not $w) { return }
    $mode = Get-TabMode
    if ($mode -ne $Resp.Mode) {
        # changement de format des onglets (texte complet / court / icône) : nouveau contenu en fondu, sans saut brutal
        if ($Resp.Mode) { Start-Transition $Ui.TabStrip -From 0.2 -Ms 220 }
        $Resp.Mode = $mode
        $Resp.Short = $mode -in 'short', 'icon'
        Set-TabFormat $mode
        $Ui.RunBtn.MinWidth      = $(if ($Resp.Short) { 110 } else { 220 })
        # largeur du champ de recherche : place réellement libre dans l'en-tête (Update-SearchLayout, après mise en page)
        $Ui.OpenLogDir.Content   = $(if ($Resp.Short) { 'Journaux' } else { 'Dossier des journaux' })
        Update-ApplyButton
    }
    $ic = $w -ge 1150
    if ($ic -ne $Resp.InfoThree) { $Resp.InfoThree = $ic; Set-InfoLayout $ic }
    $cols = if ($w -ge 1100) { 'two' } else { 'one' }
    if ($cols -ne $Resp.Cols) {
        $Resp.Cols = $cols
        $one = $cols -eq 'one'
        Set-TwoCol $Ui.PageMaint $Ui.MaintLeft $Ui.MaintRight 0 $one $true
        Set-TwoCol $Ui.PerfLeft.Parent $Ui.PerfLeft $Ui.PerfRight 0 $one $false
        Set-TwoCol $Ui.PersoLeft.Parent $Ui.PersoLeft $Ui.PersoRight 0 $one $false
        Set-TwoCol $Ui.ToolsLeft.Parent $Ui.ToolsLeft $Ui.ToolsRight 0 $one $false
    }
    # Sécurité : 3 colonnes sur grand écran (tout visible sans défiler), 2 puis 1 en dessous
    # 3 colonnes sur grand écran (Sécurité | Confidentialité | Publicités), 2 puis 1 en dessous
    $sm = $(if ($w -ge 1450) { 3 } elseif ($w -ge 1100) { 2 } else { 1 })
    if ($sm -ne $Resp.SecuCols) { $Resp.SecuCols = $sm; Set-SecuLayout $sm }
}
function Set-InfoLayout([bool]$Three) {
    $g = $Ui.InfoGrid
    $g.ColumnDefinitions[1].Width = [Windows.GridLength]::new($(if ($Three) { 12 } else { 0 }))
    $g.ColumnDefinitions[3].Width = [Windows.GridLength]::new($(if ($Three) { 12 } else { 0 }))
    $g.ColumnDefinitions[2].Width = [Windows.GridLength]::new($(if ($Three) { 1 } else { 0 }), [Windows.GridUnitType]::Star)
    $g.ColumnDefinitions[4].Width = [Windows.GridLength]::new($(if ($Three) { 1 } else { 0 }), [Windows.GridUnitType]::Star)
    $i = 0
    foreach ($p in $Ui.InfoLeft, $Ui.InfoMid, $Ui.InfoRight) {
        [Windows.Controls.Grid]::SetColumn($p, $(if ($Three) { 2 * $i } else { 0 }))
        [Windows.Controls.Grid]::SetColumnSpan($p, $(if ($Three) { 1 } else { 5 }))
        [Windows.Controls.Grid]::SetRow($p, $(if ($Three) { 0 } else { $i }))
        $i++
    }
}
$Window.Add_SizeChanged({ Update-Responsive })
$Window.Add_SizeChanged({ if ($Window.WindowState -eq 'Maximized') { $Ui.RootBorder.Margin = Get-MaxOverhang } })
$Window.Add_LocationChanged({ if ($Window.WindowState -eq 'Maximized') { $Ui.RootBorder.Margin = Get-MaxOverhang } })

# Sécurité : 3 colonnes (Sécurité + Réseau | Confidentialité | Publicités), 2 colonnes (Publicités sous les 2 premières,
# pleine largeur) ou 1 colonne (empilées)
function Set-SecuLayout([int]$Cols) {
    $g = $Ui.SecuGrid
    $wd = $(switch ($Cols) { 3 { @(1, 12, 1, 12, 1) } 2 { @(1, 12, 1, 0, 0) } default { @(1, 0, 0, 0, 0) } })
    for ($i = 0; $i -lt 5; $i++) { $g.ColumnDefinitions[$i].Width = $(if ($i % 2) { [Windows.GridLength]::new($wd[$i]) } elseif ($wd[$i]) { [Windows.GridLength]::new(1, 'Star') } else { [Windows.GridLength]::new(0) }) }
    $pos = $(switch ($Cols) { 3 { @(@(0, 0, 1), @(0, 2, 1), @(0, 4, 1)) } 2 { @(@(0, 0, 1), @(0, 2, 1), @(1, 0, 3)) } default { @(@(0, 0, 1), @(1, 0, 1), @(2, 0, 1)) } })
    $i = 0
    foreach ($p in $Ui.SecuLeft, $Ui.SecuMid, $Ui.SecuRight) {
        [Windows.Controls.Grid]::SetRow($p, $pos[$i][0]); [Windows.Controls.Grid]::SetColumn($p, $pos[$i][1]); [Windows.Controls.Grid]::SetColumnSpan($p, $pos[$i][2])
        # 2 colonnes : Sécurité sur toute la hauteur à gauche
        $i++
    }
}
