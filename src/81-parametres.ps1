# Page Paramètres (roue crantée) : thème, onglet d'ouverture, instantanés des réglages, à propos
$StartPages = [ordered]@{ Info = 'Accueil'; Maint = 'Maintenance'; Perf = 'Système'; Secu = 'Sécurité'; Perso = 'Personnalisation'; Apps = 'Applications'; Svc = 'Services et tâches'; Tools = 'Outils'; Log = 'Journal' }
function Add-SettingsChoice($Body, [string]$Label, [string]$Desc, $Options, [string]$Current, [scriptblock]$OnPick) {
    # option aérée : retrait de 46 px sous le titre de la carte, 12 px entre options, filet de séparation sous chaque option
    $hb = [Windows.Controls.Border]::new(); $hb.Style = $Window.FindResource('HoverPlain'); $hb.Margin = New-Thickness 46 4 16 12
    $hb.BorderThickness = New-Thickness 0 0 0 1; $hb.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, 'LineBrush')
    $g = [Windows.Controls.Grid]::new(); $g.Margin = New-Thickness 10 8 10 14; $g.MinHeight = 28
    # libellé puis choix sur la ligne suivante : tient dans une demi-largeur (paramètres sur 2 colonnes)
    [void]$g.RowDefinitions.Add([Windows.Controls.RowDefinition]::new())
    $ra = [Windows.Controls.RowDefinition]::new()
    $ra.Height = [Windows.GridLength]::Auto
    [void]$g.RowDefinitions.Add($ra)
    $tx = [Windows.Controls.StackPanel]::new(); $tx.VerticalAlignment = 'Center'
    $t1 = New-Text $Label; $t1.FontWeight = [Windows.FontWeights]::SemiBold; $t1.FontSize = 14; [void]$tx.Children.Add($t1)
    if ($Desc) { $d = New-Text $Desc 'Muted'; $d.TextWrapping = 'Wrap'; $d.Margin = New-Thickness 0 3 0 0; [void]$tx.Children.Add($d) }
    $wp = [Windows.Controls.WrapPanel]::new(); $wp.Margin = New-Thickness 0 10 0 0
    [Windows.Controls.Grid]::SetRow($wp, 1)
    $list = [Collections.ArrayList]::new()
    foreach ($k in $Options.Keys) {
        $b = New-Button $Options[$k]
        $b.MinWidth = 88; $b.Height = 28; $b.Padding = New-Thickness 10 0 10 0; $b.Margin = New-Thickness 0 2 6 2
        $b.DataContext = $k; $b.Tag = $(if ($k -eq $Current) { 'on' } else { '' })
        $b.Add_Click($OnPick)
        [void]$wp.Children.Add($b); [void]$list.Add($b)
    }
    [void]$g.Children.Add($tx); [void]$g.Children.Add($wp); $hb.Child = $g
    [void]$Body.Children.Add($hb)
    , $list.ToArray()
}
function New-SettingsPage {
    $p = $Ui.SettingsPanel
    $top = [Windows.Controls.StackPanel]::new(); $top.Orientation = 'Horizontal'; $top.Margin = New-Thickness 0 0 0 12
    $bk = [Windows.Controls.Button]::new()
    $bk.Style = $Window.FindResource('IconBtn')
    $bk.Content = [string][char]0xE72B
    $bk.ToolTip = 'Retour'
    $bk.Width = 32
    $bk.Height = 30
    $bk.Add_Click({ Show-Page $Sync.LastPage })
    $tt = New-Text 'Paramètres'
    $tt.FontSize = 20
    $tt.FontWeight = [Windows.FontWeights]::SemiBold
    $tt.VerticalAlignment = 'Center'
    $tt.Margin = New-Thickness 8 0 0 0
    [void]$top.Children.Add($bk); [void]$top.Children.Add($tt); [void]$p.Children.Add($top)
    # grille 2 x 2 par thème : ligne 1 Apparence | Démarrage (réglages de l'application), ligne 2 Restauration | Réinitialisation ;
    # les 2 cartes d'une ligne ont la même hauteur et leurs boutons en bas ; « À propos » en pleine largeur dessous
    $cols = [Windows.Controls.Grid]::new()
    foreach ($w in '*', '12', '*') {
        $cd = [Windows.Controls.ColumnDefinition]::new()
        $cd.Width = $(if ($w -eq '*') { [Windows.GridLength]::new(1, 'Star') } else { [Windows.GridLength]::new(12) })
        [void]$cols.ColumnDefinitions.Add($cd)
    }
    foreach ($i in 0, 1) {
        $rd = [Windows.Controls.RowDefinition]::new()
        $rd.Height = [Windows.GridLength]::Auto
        [void]$cols.RowDefinitions.Add($rd)
    }
    [void]$p.Children.Add($cols)
    $setCell = { param($C, [int]$Row, [int]$Col)
        [Windows.Controls.Grid]::SetRow($C.Card, $Row)
        [Windows.Controls.Grid]::SetColumn($C.Card, $Col)
        [void]$cols.Children.Add($C.Card)
    }
    # barre de boutons ancrée en bas de la carte (alignée avec la carte voisine plus haute)
    $setFoot = {
        param($C, $Bar)
        [void]$C.Body.Children.Remove($Bar); $C.Card.Child = $null
        $dk = [Windows.Controls.DockPanel]::new(); [Windows.Controls.DockPanel]::SetDock($Bar, 'Bottom')
        [void]$dk.Children.Add($Bar); [void]$dk.Children.Add($C.Body); $C.Card.Child = $dk
    }

    $c = New-Card 'Apparence' '' ([string][char]0xE790)
    $opts = [ordered]@{}; foreach ($k in $ThemeModes.Keys) { $opts[$k] = $ThemeModes[$k].Label }
    $SetUI.Theme = Add-SettingsChoice $c.Body 'Thème' 'Système : suit le mode clair / sombre de Windows.' $opts $Sync.ThemeMode {
        param($s, $e) Set-ThemeMode "$($s.DataContext)" $true; Write-UiLog "Thème : $($ThemeModes["$($s.DataContext)"].Label)." 'APP' }
    $zo = [ordered]@{ '0.9' = '90 %'; '1.0' = '100 %'; '1.1' = '110 %'; '1.2' = '120 %'; '1.3' = '130 %' }
    $cur = $UiZoom.ToString('0.0', [Globalization.CultureInfo]::InvariantCulture)
    $SetUI.Zoom = Add-SettingsChoice $c.Body 'Taille de l''interface' 'Aussi au clavier et à la souris : Ctrl + molette, Ctrl + / Ctrl -, Ctrl 0 pour revenir à 100 %.' $zo $cur {
        param($s, $e) Set-UiZoom ([double]::Parse("$($s.DataContext)", [Globalization.CultureInfo]::InvariantCulture)) $false }
    $sysOn = $true; try { $sysOn = [bool][Windows.SystemParameters]::ClientAreaAnimation } catch {}
    $SetUI.Anim = Add-SettingsChoice $c.Body 'Animations' ("Ouverture des fenêtres, changement d'onglet, dépliage des listes. Windows : animations {0} sur ce poste." -f $(if ($sysOn) { 'activées' } else { 'désactivées' })) ([ordered]@{ On = 'Activées'; Sys = 'Comme Windows'; Off = 'Désactivées' }) $Anim.Mode {
        param($s, $e)
        $Anim.Mode = "$($s.DataContext)"
        try { [IO.File]::WriteAllText($AnimFile, $Anim.Mode) } catch { Write-UiLog "Animations : $($_.Exception.Message)" 'ERROR' }
        foreach ($b in $SetUI.Anim) { $b.Tag = $(if ($b.DataContext -eq $s.DataContext) { 'on' } else { '' }) }
        Write-UiLog "Animations : $(@{ On = 'activées'; Sys = 'comme Windows'; Off = 'désactivées' }[$Anim.Mode])." 'APP'
    }
    & $setCell $c 0 0

    $c = New-Card 'Démarrage' '' ([string][char]0xE7E8)
    $cur = 'Info'
    try {
        if (Test-Path -LiteralPath $StartFile) { $cur = [IO.File]::ReadAllText($StartFile).Trim() }
    } catch {
        Write-Ignored 'Lecture de l''onglet de démarrage' $_
    }
    $SetUI.Start = Add-SettingsChoice $c.Body 'Onglet affiché à l''ouverture' '' $StartPages $cur {
        param($s, $e)
        try { [IO.File]::WriteAllText($StartFile, "$($s.DataContext)") } catch {
            Write-UiLog "Onglet d'ouverture : $($_.Exception.Message)" 'ERROR'
            return
        }
        foreach ($b in $SetUI.Start) { $b.Tag = $(if ($b.DataContext -eq $s.DataContext) { 'on' } else { '' }) }
        Write-UiLog "Onglet d'ouverture : $($StartPages["$($s.DataContext)"])." 'APP'
    }
    $SetUI.WinPos = Add-SettingsChoice $c.Body 'Taille et position des fenêtres' 'Rouvre la fenêtre principale, Logiciels et Espace disque là où elles ont été fermées, à la même taille.' ([ordered]@{ On = 'Mémoriser'; Off = 'Par défaut' }) $(if ($WinPos.Enabled) { 'On' } else { 'Off' }) {
        param($s, $e)
        $WinPos.Enabled = "$($s.DataContext)" -eq 'On'
        # désactivation : positions oubliées, fenêtres de nouveau centrées à la prochaine ouverture
        if (-not $WinPos.Enabled) { $WinPos.W = @{} }
        Save-WindowPositionStore
        foreach ($b in $SetUI.WinPos) { $b.Tag = $(if ($b.DataContext -eq $s.DataContext) { 'on' } else { '' }) }
        Write-UiLog $(if ($WinPos.Enabled) { 'Taille et position des fenêtres : mémorisées.' } else { 'Taille et position des fenêtres : par défaut.' }) 'APP'
    }
    # réglages propres au compte de l'utilisateur (93-zone-notification)
    $SetUI.TrayMin = Add-SettingsChoice $c.Body 'Réduire' 'Zone de notification : la fenêtre disparaît de la barre des tâches, icône près de l''horloge.' ([ordered]@{ Bar = 'Barre des tâches'; Tray = 'Zone de notification' }) $(if ($Tray.Min) { 'Tray' } else { 'Bar' }) {
        param($s, $e)
        $Tray.Min = "$($s.DataContext)" -eq 'Tray'
        try { Save-TraySetting } catch { Write-UiLog "Réduction : $($_.Exception.Message)" 'ERROR'; return }
        foreach ($b in $SetUI.TrayMin) { $b.Tag = $(if ($b.DataContext -eq $s.DataContext) { 'on' } else { '' }) }
        Write-UiLog $(if ($Tray.Min) { 'Réduire : dans la zone de notification.' } else { 'Réduire : dans la barre des tâches.' }) 'APP'
    }
    $SetUI.TrayClose = Add-SettingsChoice $c.Body 'Bouton Fermer' 'Réduire : l''application reste ouverte dans la zone de notification ; clic droit sur l''icône > Quitter pour la fermer. Demandé au premier clic sur la croix tant qu''aucun choix n''est fait.' ([ordered]@{ Close = 'Fermer l''application'; Tray = 'Réduire' }) $(if ($Tray.Close) { 'Tray' } else { 'Close' }) {
        param($s, $e)
        $Tray.Close = "$($s.DataContext)" -eq 'Tray'; $Tray.CloseSet = $true
        try { Save-TraySetting } catch { Write-UiLog "Bouton Fermer : $($_.Exception.Message)" 'ERROR'; return }
        foreach ($b in $SetUI.TrayClose) { $b.Tag = $(if ($b.DataContext -eq $s.DataContext) { 'on' } else { '' }) }
        Write-UiLog $(if ($Tray.Close) { 'Bouton Fermer : réduit dans la zone de notification.' } else { 'Bouton Fermer : ferme l''application.' }) 'APP'
    }
    $SetUI.AutoStart = Add-SettingsChoice $c.Body 'Ouverture de session' ('Ouvre Oliv_Maintenance à l''ouverture de session de ' + ("$UserName" -split '\\')[-1] + ', sans demande d''autorisation (tâche planifiée aux droits administrateur).') ([ordered]@{ Off = 'Désactivée'; On = 'Activée' }) $(if (Get-AutoStartTask) { 'On' } else { 'Off' }) {
        param($s, $e)
        $on = "$($s.DataContext)" -eq 'On'
        try { Set-AutoStart $on } catch { Write-UiLog "Ouverture de session : $($_.Exception.Message)" 'ERROR'; Show-Info "Réglage impossible.`n`n$($_.Exception.Message)" 'Error'; return }
        foreach ($b in $SetUI.AutoStart) { $b.Tag = $(if ($b.DataContext -eq $s.DataContext) { 'on' } else { '' }) }
        Write-UiLog $(if ($on) { "Lancement à l'ouverture de session activé (tâche \Oliv_Maintenance\$AutoTaskName, exe $StableExe)." } else { 'Lancement à l''ouverture de session désactivé.' }) 'APP'
    }
    $lb = [Windows.Controls.WrapPanel]::new(); $lb.Margin = New-Thickness 46 0 10 14
    $b1 = New-Button 'Épingler à la barre des tâches...'; $b1.Height = 30; $b1.Margin = New-Thickness 0 0 8 4; $b1.Add_Click({ Request-TaskbarPin })
    $b2 = New-Button 'Raccourci dans le menu Démarrer'; $b2.Height = 30; $b2.Margin = New-Thickness 0 0 8 4
    $b2.Add_Click({ try { New-StartMenuShortcut; Write-UiLog "Raccourci du menu Démarrer créé : $StartLnk." 'OK'; Show-Info 'Raccourci Oliv_Maintenance ajouté au menu Démarrer (Toutes les applications).' 'Ok' } catch { Show-Info "Raccourci impossible.`n`n$($_.Exception.Message)" 'Error' } })
    [void]$lb.Children.Add($b1); [void]$lb.Children.Add($b2); [void]$c.Body.Children.Add($lb)
    & $setCell $c 0 2

    $c = New-Card 'Restauration des réglages' '' ([string][char]0xE777)
    $t = New-Text "Instantané de tous les réglages gérés par l'application, enregistré avant chaque modification (30 derniers conservés)." 'Muted'
    $t.Margin = New-Thickness 46 0 18 8
    [void]$c.Body.Children.Add($t)
    $SetUI.SnapList = [Windows.Controls.StackPanel]::new(); $SetUI.SnapList.Margin = New-Thickness 38 0 10 0
    $sv = [Windows.Controls.ScrollViewer]::new(); $sv.MaxHeight = 280; $sv.VerticalScrollBarVisibility = 'Auto'; $sv.Content = $SetUI.SnapList
    [void]$c.Body.Children.Add($sv)
    $SetUI.SnapDetail = [Windows.Controls.StackPanel]::new(); $SetUI.SnapDetail.Margin = New-Thickness 46 10 10 0
    [void]$c.Body.Children.Add($SetUI.SnapDetail)
    $bar = [Windows.Controls.StackPanel]::new(); $bar.Orientation = 'Horizontal'; $bar.HorizontalAlignment = 'Right'; $bar.Margin = New-Thickness 0 8 18 14
    $SetUI.SnapBtn = New-Button 'Restaurer' 'WarnBtn'
    $SetUI.SnapBtn.MinWidth = 96
    $SetUI.SnapBtn.IsEnabled = $false
    $SetUI.SnapBtn.Margin = New-Thickness 8 0 0 0
    $SetUI.SnapBtn.Add_Click({ if ($SetUI.SnapSel) { Restore-TweakSnapshot $SetUI.SnapSel } })
    $SetUI.SnapDel = New-Button 'Supprimer'; $SetUI.SnapDel.MinWidth = 96; $SetUI.SnapDel.IsEnabled = $false; $SetUI.SnapDel.Margin = New-Thickness 8 0 0 0
    $SetUI.SnapDel.Add_Click({ if ($SetUI.SnapSel) { Remove-TweakSnapshot $SetUI.SnapSel } })
    $fb = New-Button 'Restauration d''usine' 'WarnBtn'; $fb.MinWidth = 96; $fb.Margin = New-Thickness 0
    $fb.ToolTip = 'Remet tous les réglages gérés par l''application à leur valeur par défaut de Windows'
    $fb.Add_Click({ Restore-TweakDefault })
    [void]$bar.Children.Add($fb)
    [void]$bar.Children.Add($SetUI.SnapDel)
    [void]$bar.Children.Add($SetUI.SnapBtn); [void]$c.Body.Children.Add($bar)
    & $setFoot $c $bar; & $setCell $c 1 0

    # Réinitialisation de l'application : paramètres d'origine, historique supprimé, relance
    $c = New-Card 'Réinitialisation' '' ([string][char]0xE777)
    $t = New-Text 'Remet les paramètres de l''application à leur état d''origine (thème, onglet de démarrage, zone de notification) et supprime tous ses journaux, rapports, instantanés et résultats mémorisés. Les réglages Windows déjà appliqués ne sont pas annulés.' 'Muted'
    $t.Margin = New-Thickness 46 0 18 0
    [void]$c.Body.Children.Add($t)
    $bar = [Windows.Controls.StackPanel]::new(); $bar.Orientation = 'Horizontal'; $bar.HorizontalAlignment = 'Right'; $bar.Margin = New-Thickness 0 8 18 14
    $rb = New-Button 'Réinitialiser l''application' 'WarnBtn'; $rb.Margin = New-Thickness 0
    $rb.Add_Click({ Invoke-AppReset })
    [void]$bar.Children.Add($rb); [void]$c.Body.Children.Add($bar)
    & $setFoot $c $bar; & $setCell $c 1 2

    $c = New-Card 'Mises à jour de l''application' ("Version installée : $AppVersion  ·  publiée sur github.com/$UpdRepo") ([string][char]0xE895)
    $SetUI.UpdAuto = Add-SettingsChoice $c.Body 'Recherche au lancement' 'Bandeau en haut de la fenêtre quand une nouvelle version est publiée ; rien n''est installé sans ton accord.' ([ordered]@{ On = 'Activée'; Off = 'Désactivée' }) $(if (Get-UpdAuto) { 'On' } else { 'Off' }) {
        param($s, $e) Set-UpdAuto ("$($s.DataContext)" -eq 'On'); foreach ($x in $SetUI.UpdAuto) { $x.Tag = $(if ($x.DataContext -eq $s.DataContext) { 'on' } else { '' }) }
        Write-UiLog ('Recherche de mise à jour au lancement : {0}.' -f $(if ("$($s.DataContext)" -eq 'On') { 'activée' } else { 'désactivée' })) 'APP' }
    $ub = [Windows.Controls.WrapPanel]::new(); $ub.Margin = New-Thickness 38 0 10 14
    $bt = New-Button 'Rechercher maintenant'; $bt.Height = 30; $bt.Margin = New-Thickness 0 0 12 0; $bt.Add_Click({ Start-UpdCheck $true })
    $SetUI.UpdStatus = New-Text '' 'Muted'; $SetUI.UpdStatus.VerticalAlignment = 'Center'; $SetUI.UpdStatus.TextWrapping = 'Wrap'
    [void]$ub.Children.Add($bt); [void]$ub.Children.Add($SetUI.UpdStatus); [void]$c.Body.Children.Add($ub)
    $c.Card.Margin = New-Thickness 0 12 0 0
    [void]$p.Children.Add($c.Card)
    Update-UpdStatus $(if ($UpdUI.Info) { 'Version {0} disponible.' -f (Get-UpdVersion $UpdUI.Info.Tag) } elseif ($UpdUI.Checked) { "Oliv_Maintenance $AppVersion est à jour." } else { 'Pas encore vérifié pendant cette session.' })

    $c = New-Card 'Cartes affichées' 'Cartes inutiles masquées dans les onglets ; raccourci : clic droit sur une carte > Masquer cette carte' ([string][char]0xE8A9)
    $SetUI.CardsBody = [Windows.Controls.StackPanel]::new(); [void]$c.Body.Children.Add($SetUI.CardsBody); $SetUI.CardsCard = $c.Card; $c.Card.Margin = New-Thickness 0 12 0 12
    [void]$p.Children.Add($c.Card)

    $c = New-Card 'À propos' '' ([string][char]0xE946)
    # logo sur fond blanc fixe : texte noir du logo lisible quel que soit le thème
    $logo = Get-EmbeddedImage $LogoFullB64
    if ($logo) {
        $li = [Windows.Controls.Image]::new(); $li.Source = $logo; $li.Width = 200; $li.Stretch = 'Uniform'
        [Windows.Media.RenderOptions]::SetBitmapScalingMode($li, 'HighQuality')
        $lb = [Windows.Controls.Border]::new(); $lb.Background = [Windows.Media.Brushes]::White; $lb.CornerRadius = [Windows.CornerRadius]::new(6)
        $lb.Padding = New-Thickness 10 6 10 6; $lb.Margin = New-Thickness 10 0 10 10; $lb.HorizontalAlignment = 'Center'; $lb.Child = $li
        [void]$c.Body.Children.Add($lb)
    }
    # bloc centré à la largeur de la ligne la plus longue (« Application  Oliv_Maintenance ») : survol de même largeur pour les 3 lignes
    $ab = [Windows.Controls.StackPanel]::new()
    $ab.HorizontalAlignment = 'Center'
    [Windows.Controls.Grid]::SetIsSharedSizeScope($ab, $true)
    [void]$c.Body.Children.Add($ab)
    $bd = $BuildDate
    try { $bd = '{0:dd/MM/yyyy}' -f [DateTime]::ParseExact($BuildDate, 'yyyy-MM-dd HH:mm', [Globalization.CultureInfo]::InvariantCulture) } catch {}
    foreach ($kv in @(@('Application', 'Oliv_Maintenance'), @('Version', $AppVersion), @('Date de compilation', $bd))) {
        $v = Add-KV $ab $kv[0] $kv[1]; $v.Parent.Parent.Margin = New-Thickness 0 0 0 0
    }
    $sig = New-Text 'Développé avec passion par Oliv' 'Muted'
    $sig.Margin = New-Thickness 10 10 10 14
    $sig.FontStyle = [Windows.FontStyles]::Italic
    $sig.HorizontalAlignment = 'Center'
    $sig.TextAlignment = 'Center'
    [void]$c.Body.Children.Add($sig)
    [void]$p.Children.Add($c.Card)
    Set-SettingsLayout $p $cols
    $SetUI.Built = $true
}
# Disposition des Paramètres : toutes les cartes à droite, rubrique par rubrique ; sommaire à gauche, qui reste visible
# pendant le défilement, amène à la rubrique choisie et suit la rubrique affichée.
# rubrique Mises à jour en premier : visible dès l'ouverture des paramètres
$SettingsSections = [ordered]@{
    Update = @{ T = 'Mises à jour'; G = 0xE895; C = @('Mises à jour de l''application') }
    Look   = @{ T = 'Apparence'; G = 0xE790; C = @('Apparence', 'Cartes affichées') }
    Start  = @{ T = 'Démarrage et fermeture'; G = 0xE7E8; C = @('Démarrage') }
    Save   = @{ T = 'Sauvegarde et réinitialisation'; G = 0xE777; C = @('Restauration des réglages', 'Réinitialisation') }
    About  = @{ T = 'À propos'; G = 0xE946; C = @('À propos') }
}
function Set-SettingsLayout($P, $Cols) {
    $cards = @{}
    foreach ($el in @(@($Cols.Children) + @($P.Children))) {
        if ($el -is [Windows.Controls.Border] -and "$($el.Tag)" -like 'card:*') { $cards["$($el.Tag)".Substring(5)] = $el }
    }
    foreach ($el in $cards.Values) { [void]$el.Parent.Children.Remove($el); $el.Margin = New-Thickness 0 0 0 12; $el.HorizontalAlignment = 'Stretch' }
    [void]$P.Children.Remove($Cols)
    $g = [Windows.Controls.Grid]::new()
    $c0 = [Windows.Controls.ColumnDefinition]::new(); $c0.Width = [Windows.GridLength]::new(250); [void]$g.ColumnDefinitions.Add($c0)
    [void]$g.ColumnDefinitions.Add([Windows.Controls.ColumnDefinition]::new())
    $nav = [Windows.Controls.StackPanel]::new(); $nav.Margin = New-Thickness 0 0 16 0; $nav.VerticalAlignment = 'Top'
    $nav.RenderTransform = [Windows.Media.TranslateTransform]::new()
    $sh = [Windows.Controls.StackPanel]::new(); $sh.MaxWidth = 960; $sh.HorizontalAlignment = 'Stretch'; [Windows.Controls.Grid]::SetColumn($sh, 1)
    $SetUI.SecHost = $sh; $SetUI.SecCards = $cards; $SetUI.SecBtns = @{}; $SetUI.SecFirst = [ordered]@{}; $SetUI.SecNav = $nav; $SetUI.SecGrid = $g
    foreach ($k in $SettingsSections.Keys) {
        $sec = $SettingsSections[$k]
        $b = [Windows.Controls.Button]::new(); $b.Style = $Window.FindResource('ActionBtn'); $b.Height = 42; $b.Margin = New-Thickness 0 0 0 6
        $b.HorizontalContentAlignment = 'Left'; $b.Padding = New-Thickness 14 0 14 0; $b.DataContext = $k
        $sp = [Windows.Controls.StackPanel]::new(); $sp.Orientation = 'Horizontal'
        $ic = New-Text ([string][char]$sec.G); $ic.FontFamily = [Windows.Media.FontFamily]::new('Segoe MDL2 Assets'); $ic.FontSize = 15; $ic.Margin = New-Thickness 0 0 12 0; $ic.VerticalAlignment = 'Center'
        $tx = New-Text $sec.T; $tx.FontSize = 14; $tx.VerticalAlignment = 'Center'
        [void]$sp.Children.Add($ic); [void]$sp.Children.Add($tx); $b.Content = $sp
        $b.Add_Click({ param($s, $e) Show-SettingsSection "$($s.DataContext)" })
        [void]$nav.Children.Add($b); $SetUI.SecBtns[$k] = $b
        # cartes de la rubrique, dans l'ordre ; 1re carte = point d'arrivée du sommaire
        foreach ($t in $sec.C) { $c = $cards[$t]; if ($c) { [void]$sh.Children.Add($c); if (-not $SetUI.SecFirst.Contains($k)) { $SetUI.SecFirst[$k] = $c } } }
    }
    [void]$g.Children.Add($nav); [void]$g.Children.Add($sh)
    [void]$P.Children.Add($g)
    # sommaire fixe à l'écran (décalé de la hauteur défilée) et rubrique en cours surlignée
    if (-not $SetUI.SecScrollHooked -and $Ui.PageSettings -is [Windows.Controls.ScrollViewer]) {
        $SetUI.SecScrollHooked = $true
        $Ui.PageSettings.Add_ScrollChanged({ Update-SettingsNav })
    }
    Set-SettingsNavOn 'Update'
}
function Get-SettingsTop($El) { try { $El.TranslatePoint([Windows.Point]::new(0, 0), $Ui.SettingsPanel).Y } catch { 0 } }
function Set-SettingsNavOn([string]$Key) { foreach ($k in $SetUI.SecBtns.Keys) { $SetUI.SecBtns[$k].Tag = $(if ($k -eq $Key) { 'on' } else { '' }) } }
function Update-SettingsNav {
    if (-not $SetUI.SecNav) { return }
    $off = $Ui.PageSettings.VerticalOffset; $top = Get-SettingsTop $SetUI.SecGrid
    $SetUI.SecNav.RenderTransform.Y = [math]::Max([double]0, $off - $top)
    if ($SetUI.SecJump -and ([DateTime]::Now - $SetUI.SecJump).TotalMilliseconds -lt 400) { return }
    # rubrique en cours : dernière dont la 1re carte est passée sous le haut de la zone visible (fin de page : la dernière)
    $cur = $null
    foreach ($k in $SetUI.SecFirst.Keys) { if ((Get-SettingsTop $SetUI.SecFirst[$k]) -le $off + 60) { $cur = $k } }
    if ($off -ge $Ui.PageSettings.ScrollableHeight - 2 -and $Ui.PageSettings.ScrollableHeight -gt 0) { $cur = @($SetUI.SecFirst.Keys)[-1] }
    if (-not $cur) { $cur = @($SetUI.SecFirst.Keys)[0] }
    Set-SettingsNavOn $cur
}
function Show-SettingsSection([string]$Key) {
    if (-not $SetUI.SecFirst -or -not $SetUI.SecFirst.Contains($Key)) { return }
    $SetUI.Sec = $Key; Set-SettingsNavOn $Key; $SetUI.SecJump = [DateTime]::Now
    $y = (Get-SettingsTop $SetUI.SecFirst[$Key]) - 4
    if ($Ui.PageSettings -is [Windows.Controls.ScrollViewer]) { $Ui.PageSettings.ScrollToVerticalOffset([math]::Max([double]0, $y)) }
}
function Get-TweakSnapshot {
    if (-not (Test-Path -LiteralPath $SnapDir)) { return @() }
    @(Get-ChildItem -LiteralPath $SnapDir -Filter '*.json' -File -ErrorAction SilentlyContinue | Sort-Object Name -Descending | ForEach-Object {
        $sf = $_.Name
        try {
            $o = Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($o.Sid -eq $UserSid) { $o | Add-Member -NotePropertyName File -NotePropertyValue $_.FullName -PassThru }
        } catch {
            Write-Ignored "Instantané illisible ($sf)" $_
        }
    })
}
function Save-TweakSnapshot([string]$Reason, [string[]]$Changes) {
    $vals = [ordered]@{}
    foreach ($r in $TweakRows) { if ($r.Enabled -and $null -ne $r.Current) { $vals[$r.Tweak.Id] = $r.Current } }
    if ($vals.Count -eq 0) { return }
    try {
        if (-not (Test-Path -LiteralPath $SnapDir)) { [void](New-Item -ItemType Directory -Path $SnapDir -Force) }
        $now = [DateTime]::Now
        $o = [pscustomobject]@{ Time = $now.ToString('o'); Sid = $UserSid; User = $UserName; Reason = $Reason; Changes = @($Changes); Values = [pscustomobject]$vals }
        ConvertTo-Json -InputObject $o -Depth 3 | Set-Content -LiteralPath (Join-Path $SnapDir ('{0:yyyyMMdd-HHmmss-fff}.json' -f $now)) -Encoding UTF8
        @(Get-ChildItem -LiteralPath $SnapDir -Filter '*.json' -File | Sort-Object Name -Descending | Select-Object -Skip 30) | Remove-Item -Force -ErrorAction SilentlyContinue
        Write-UiLog "Instantané des réglages enregistré : $Reason." 'APP'
    } catch { Write-UiLog "Instantané des réglages : $($_.Exception.Message)" 'WARN' }
    if ($SetUI.Built) { Update-SnapshotList }
}
function Get-SnapshotTime($Snap) {
    try {
        [DateTime]::Parse("$($Snap.Time)", [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
    } catch {
        [DateTime]::MinValue
    }
}
function Get-SnapshotDiff($Snap) {
    if (-not $Lazy.Done) { $Window.Cursor = [Windows.Input.Cursors]::Wait; try { New-DeferredPage } finally { $Window.Cursor = $null } }
    $diff = @()
    foreach ($pr in $Snap.Values.PSObject.Properties) {
        $r = $TweakRows | Where-Object { $_.Tweak.Id -eq $pr.Name } | Select-Object -First 1
        if ($r -and $r.Enabled -and "$($r.Current)" -ne "$($pr.Value)") {
            $diff += @{ R = $r; V = $pr.Value; Line = '{0} : {1} > {2}' -f $r.Tweak.Label, (Format-TweakValue $r.Tweak $r.Current), (Format-TweakValue $r.Tweak $pr.Value) }
        }
    }
    , $diff
}
function Set-SnapRowState($Row, [bool]$Sel) {
    $Row.Tag = $(if ($Sel) { 'sel' } else { '' })
    $Row.BorderThickness = New-Thickness $(if ($Sel) { 3 } else { 0 }) 0 0 0
    $Row.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, 'AccentBrush')
    if ($Sel) {
        $Row.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, 'BtnBrush')
    } else {
        $Row.Background = [Windows.Media.Brushes]::Transparent
    }
}
function Show-SnapshotDetail($Snap) {
    $d = $SetUI.SnapDetail; $d.Children.Clear()
    $SetUI.SnapDel.IsEnabled = [bool]$Snap
    if (-not $Snap) { $SetUI.SnapBtn.IsEnabled = $false; return }
    $diff = Get-SnapshotDiff $Snap
    $when = '{0:dd/MM/yyyy HH:mm}' -f (Get-SnapshotTime $Snap)
    if (-not $diff.Count) {
        [void]$d.Children.Add((New-Text "Les réglages actuels correspondent déjà à l'état du $when : rien à restaurer." 'Muted'))
        $SetUI.SnapBtn.IsEnabled = $false; return
    }
    $h = New-Text ("Restaurer l'état du {0} modifiera {1} {2} :" -f $when, $diff.Count, (Get-Plural $diff.Count 'réglage' 'réglages'))
    $h.FontWeight = [Windows.FontWeights]::SemiBold
    $h.Margin = New-Thickness 0 0 0 4
    [void]$d.Children.Add($h)
    foreach ($x in $diff) {
        $t = New-Text ('-  ' + $x.Line) 'Muted'
        $t.TextWrapping = 'Wrap'
        $t.Margin = New-Thickness 8 1 0 1
        [void]$d.Children.Add($t)
    }
    $SetUI.SnapBtn.IsEnabled = -not $Sync.Running
}
function Update-SnapshotList {
    if (-not $SetUI.Built) { return }
    $SetUI.SnapList.Children.Clear(); $SetUI.SnapSel = $null; Show-SnapshotDetail $null
    $snaps = @(Get-TweakSnapshot)
    # Supprimer / Restaurer seulement s'il existe au moins un instantané
    $vis = $(if ($snaps.Count) { 'Visible' } else { 'Collapsed' }); $SetUI.SnapDel.Visibility = $vis; $SetUI.SnapBtn.Visibility = $vis
    if (-not $snaps.Count) {
        $t = New-Text 'Aucun instantané : le premier sera enregistré à la prochaine modification de réglages.' 'Muted'
        $t.Margin = New-Thickness 8 0 0 4
        $t.TextWrapping = 'Wrap'
        [void]$SetUI.SnapList.Children.Add($t); return
    }
    foreach ($o in $snaps) {
        $row = [Windows.Controls.Border]::new()
        $row.CornerRadius = [Windows.CornerRadius]::new(4)
        $row.Padding = New-Thickness 10 6 10 6
        $row.Margin = New-Thickness 0 0 0 2
        $row.Cursor = [Windows.Input.Cursors]::Hand; $row.DataContext = $o
        $sp = [Windows.Controls.StackPanel]::new()
        $t1 = New-Text ('{0:dd/MM/yyyy HH:mm:ss}  ·  {1}' -f (Get-SnapshotTime $o), $o.Reason); $t1.FontWeight = [Windows.FontWeights]::SemiBold
        [void]$sp.Children.Add($t1)
        $names = @($o.Changes | Where-Object { $_ } | ForEach-Object { ("$_" -split ' : ', 2)[0] })
        if ($names.Count) { $t2 = New-Text ($names -join ', ') 'Muted'; $t2.TextWrapping = 'Wrap'; [void]$sp.Children.Add($t2) }
        $row.Child = $sp
        Set-SnapRowState $row $false
        $row.Add_MouseEnter({ param($s, $e)
            if ($s.Tag -ne 'sel') { $s.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, 'HoverBrush') }
        })
        $row.Add_MouseLeave({ param($s, $e) if ($s.Tag -ne 'sel') { $s.Background = [Windows.Media.Brushes]::Transparent } })
        $row.Add_MouseLeftButtonUp({
            param($s, $e)
            foreach ($x in $SetUI.SnapList.Children) { if ($x -is [Windows.Controls.Border]) { Set-SnapRowState $x ($x -eq $s) } }
            $SetUI.SnapSel = $s.DataContext
            Show-SnapshotDetail $s.DataContext
        })
        [void]$SetUI.SnapList.Children.Add($row)
    }
}
function Remove-TweakSnapshot($Snap) {
    $when = '{0:dd/MM/yyyy HH:mm:ss}' -f (Get-SnapshotTime $Snap)
    if (-not (Confirm-Action "Supprimer l'instantané du $when ($($Snap.Reason)) ?`n`nSuppression définitive : cet état ne pourra plus être restauré.")) {
        return
    }
    try { Remove-Item -LiteralPath $Snap.File -Force -ErrorAction Stop; Write-UiLog "Instantané du $when supprimé." }
    catch { Write-UiLog "Suppression de l'instantané du $when : $($_.Exception.Message)" 'ERROR' }
    Update-SnapshotList
}
# Valeur Windows d'origine d'un réglage : Def explicite (réglages par commande), sinon valeur de registre absente (D)
function Get-TweakDefault($Tw) {
    if ($Tw.DefGet) { return (& $Tw.DefGet) }
    if ($null -ne $Tw.Def) { return $Tw.Def }
    $r = $Tw.Reg[0]
    if ($Tw.Kind -eq 'Choice') { return $r.D }
    if ($r.T -eq 'Key') { return $false }
    $onv = if ($null -eq $r.On) { $r.D } else { $r.On }
    return ("$($r.D)" -eq "$onv")
}
# Restauration d'usine : tous les réglages de l'outil remis à la valeur par défaut de Windows (instantané pris avant)
function Restore-TweakDefault {
    $vals = [ordered]@{}
    foreach ($tw in $Tweaks) { $vals[$tw.Id] = Get-TweakDefault $tw }
    $diff = Get-SnapshotDiff ([pscustomobject]@{ Values = [pscustomobject]$vals })
    if (-not $diff.Count) { Show-Info 'Tous les réglages sont déjà à leur valeur par défaut de Windows.' 'Ok'; return }
    $lines = @($diff | ForEach-Object { $_.Line })
    if (-not (Confirm-List ('Remettre les réglages à leur valeur par défaut de Windows ? {0} {1} :' -f $diff.Count, (Get-Plural $diff.Count 'réglage modifié' 'réglages modifiés')) $lines 'Un instantané de l''état actuel est enregistré avant, pour pouvoir revenir en arrière.' 'Restaurer')) {
        return
    }
    Save-TweakSnapshot 'Avant restauration d''usine' $lines
    Write-UiLog "Restauration d'usine des réglages ($($diff.Count) $(Get-Plural $diff.Count 'réglage' 'réglages'))."
    foreach ($d in $diff) { Invoke-TweakChange $d.R $d.V }
    Update-ApplyButton
}
function Restore-TweakSnapshot($Snap) {
    $diff = Get-SnapshotDiff $Snap
    $when = '{0:dd/MM/yyyy HH:mm}' -f (Get-SnapshotTime $Snap)
    if (-not $diff.Count) { Show-SnapshotDetail $Snap; return }
    $lines = @($diff | ForEach-Object { $_.Line })
    if (-not (Confirm-List ("Restaurer les réglages à l'état du {0} ? {1} {2} :" -f $when, $diff.Count, (Get-Plural $diff.Count 'réglage modifié' 'réglages modifiés')) $lines $null 'Restaurer')) {
        return
    }
    Save-TweakSnapshot "Avant restauration de l'état du $when" $lines
    Write-UiLog "Restauration des réglages à l'état du $when ($($diff.Count) $(Get-Plural $diff.Count 'réglage' 'réglages'))."
    foreach ($d in $diff) { Invoke-TweakChange $d.R $d.V }
    Update-ApplyButton
}

