# Page Paramètres (roue crantée) : thème, onglet d'ouverture, instantanés des réglages, à propos
$StartPages = [ordered]@{ Info = 'Accueil'; Maint = 'Maintenance'; Perf = 'Système'; Secu = 'Sécurité'; Perso = 'Personnalisation'; Apps = 'Applications'; Svc = 'Services et tâches'; Tools = 'Outils'; Log = 'Journal' }
function Add-SettingsChoice($Body, [string]$Label, [string]$Desc, $Options, [string]$Current, [scriptblock]$OnPick) {
    # option aérée : retrait de 46 px sous le titre de la carte, 12 px entre options, filet de séparation sous chaque option
    $hb = [Windows.Controls.Border]::new(); $hb.Style = $Window.FindResource('HoverPlain'); $hb.Margin = New-Thickness 46 4 16 12; $hb.Uid = 'setchoice'
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

    # Démarrage : comportement à l'ouverture (fenêtre ou réduite, ouverture de session, onglet affiché)
    $c = New-Card 'Démarrage' '' ([string][char]0xE7E8)
    $SetUI.StartMin = Add-SettingsChoice $c.Body 'Au lancement' 'Fenêtre affichée, ou application réduite dans la zone de notification (près de l''horloge) : clic sur l''icône pour l''afficher.' ([ordered]@{ Window = 'Fenêtre affichée'; Tray = 'Réduite' }) $(if ($Tray.StartMin) { 'Tray' } else { 'Window' }) {
        param($s, $e)
        $Tray.StartMin = "$($s.DataContext)" -eq 'Tray'
        try { Save-TraySetting } catch { Write-UiLog "Au lancement : $($_.Exception.Message)" 'ERROR'; return }
        foreach ($b in $SetUI.StartMin) { $b.Tag = $(if ($b.DataContext -eq $s.DataContext) { 'on' } else { '' }) }
        Write-UiLog $(if ($Tray.StartMin) { 'Au lancement : réduite dans la zone de notification.' } else { 'Au lancement : fenêtre affichée.' }) 'APP'
    }
    $SetUI.AutoStart = Add-SettingsChoice $c.Body 'Ouverture de session' ('Ouvre Oliv_Maintenance à l''ouverture de session de ' + ("$UserName" -split '\\')[-1] + ', sans demande d''autorisation (tâche planifiée aux droits administrateur).') ([ordered]@{ Off = 'Désactivée'; On = 'Activée' }) $(if (Get-AutoStartTask) { 'On' } else { 'Off' }) {
        param($s, $e)
        $on = "$($s.DataContext)" -eq 'On'
        try { Set-AutoStart $on } catch { Write-UiLog "Ouverture de session : $($_.Exception.Message)" 'ERROR'; Show-Info "Réglage impossible.`n`n$($_.Exception.Message)" 'Error'; return }
        foreach ($b in $SetUI.AutoStart) { $b.Tag = $(if ($b.DataContext -eq $s.DataContext) { 'on' } else { '' }) }
        Write-UiLog $(if ($on) { "Lancement à l'ouverture de session activé (tâche \Oliv_Maintenance\$AutoTaskName, exe $StableExe)." } else { 'Lancement à l''ouverture de session désactivé.' }) 'APP'
    }
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
    & $setCell $c 0 2

    # Raccourcis vers l'application (Bureau, menu Démarrer, barre des tâches)
    $c = New-Card 'Raccourcis' '' ([string][char]0xE71B)
    $t = New-Text 'Raccourcis vers la copie fixe de l''application (C:\ProgramData\Oliv_Maintenance), toujours valables après une mise à jour.' 'Muted'; $t.TextWrapping = 'Wrap'; $t.Margin = New-Thickness 46 0 18 0; [void]$c.Body.Children.Add($t)
    $lb = [Windows.Controls.WrapPanel]::new(); $lb.Margin = New-Thickness 46 4 10 14
    $b1 = New-Button 'Épingler à la barre des tâches...'; $b1.Height = 30; $b1.Margin = New-Thickness 0 0 8 4; $b1.Add_Click({ Request-TaskbarPin })
    $b3 = New-Button 'Raccourci sur le Bureau'; $b3.Height = 30; $b3.Margin = New-Thickness 0 0 8 4
    $b3.Add_Click({ try { $f = New-DesktopShortcut; Write-UiLog "Raccourci créé sur le Bureau : $f." 'OK'; Show-Toast 'Raccourci créé sur le Bureau' } catch { Write-UiLog "Raccourci sur le Bureau : $($_.Exception.Message)" 'ERROR'; Show-Info "Raccourci impossible.`n`n$($_.Exception.Message)" 'Error' } })
    $b2 = New-Button 'Raccourci dans le menu Démarrer'; $b2.Height = 30; $b2.Margin = New-Thickness 0 0 8 4
    $b2.Add_Click({ try { New-StartMenuShortcut; Write-UiLog "Raccourci du menu Démarrer créé : $StartLnk." 'OK'; Show-Info 'Raccourci Oliv_Maintenance ajouté au menu Démarrer (Toutes les applications).' 'Ok' } catch { Show-Info "Raccourci impossible.`n`n$($_.Exception.Message)" 'Error' } })
    [void]$lb.Children.Add($b3); [void]$lb.Children.Add($b2); [void]$lb.Children.Add($b1); [void]$c.Body.Children.Add($lb)
    [void]$p.Children.Add($c.Card)

    # Fenêtre et zone de notification : réduction, bouton Fermer, position mémorisée, alertes quand l'application est réduite
    $c = New-Card 'Fenêtre et zone de notification' '' ([string][char]0xE737)
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
    $SetUI.WinPos = Add-SettingsChoice $c.Body 'Taille et position des fenêtres' 'Rouvre la fenêtre principale, Logiciels et Espace disque là où elles ont été fermées, à la même taille.' ([ordered]@{ On = 'Mémoriser'; Off = 'Par défaut' }) $(if ($WinPos.Enabled) { 'On' } else { 'Off' }) {
        param($s, $e)
        $WinPos.Enabled = "$($s.DataContext)" -eq 'On'
        # désactivation : positions oubliées, fenêtres de nouveau centrées à la prochaine ouverture
        if (-not $WinPos.Enabled) { $WinPos.W = @{} }
        Save-WindowPositionStore
        foreach ($b in $SetUI.WinPos) { $b.Tag = $(if ($b.DataContext -eq $s.DataContext) { 'on' } else { '' }) }
        Write-UiLog $(if ($WinPos.Enabled) { 'Taille et position des fenêtres : mémorisées.' } else { 'Taille et position des fenêtres : par défaut.' }) 'APP'
    }
    $SetUI.AlertOn = Add-SettingsChoice $c.Body 'Alertes du poste en notification' 'Quand l''application est réduite ou dans la zone de notification : redémarrage en attente, mises à jour Windows et logiciels disponibles, disque presque plein (une seule fois par alerte).' ([ordered]@{ On = 'Activées'; Off = 'Désactivées' }) $(if (Get-AlertOn) { 'On' } else { 'Off' }) {
        param($s, $e) $on = "$($s.DataContext)" -eq 'On'
        try { $k = Open-RegKey $CardRegKey $true $true; try { $k.SetValue('AlertesPoste', [int]$on, [Microsoft.Win32.RegistryValueKind]::DWord) } finally { $k.Close() } } catch { Write-Ignored 'Alertes du poste' $_ }
        foreach ($x in $SetUI.AlertOn) { $x.Tag = $(if ($x.DataContext -eq $s.DataContext) { 'on' } else { '' }) }
        Write-UiLog ('Alertes du poste en notification : {0}.' -f $(if ($on) { 'activées' } else { 'désactivées' })) 'APP' }
    [void]$p.Children.Add($c.Card)

    # Configuration du poste : exportation / importation (préparer un autre PC à l'identique)
    $c = New-Card 'Configuration du poste' '' ([string][char]0xE8B7)
    $t = New-Text 'Exporter : réglages gérés par l''application, applications du catalogue installées, onglets et cartes masqués, dans un fichier. Importer sur un autre poste : réglages différents préparés (bandeau Appliquer, rien n''est changé sans validation), applications manquantes sélectionnées dans Applications > Installer.' 'Muted'
    $t.Margin = New-Thickness 46 0 18 8; [void]$c.Body.Children.Add($t)
    $bar = [Windows.Controls.StackPanel]::new(); $bar.Orientation = 'Horizontal'; $bar.Margin = New-Thickness 46 0 18 14
    $b = New-Button 'Exporter...' 'PrimaryBtn'; $b.Height = 30; $b.MinWidth = 96; $b.Margin = New-Thickness 0 0 8 0; $b.Add_Click({ try { Export-PcConfig } catch { Write-UiLog "Exportation de la configuration : $($_.Exception.Message)" 'ERROR' } }); [void]$bar.Children.Add($b)
    $b = New-Button 'Importer...'; $b.Height = 30; $b.MinWidth = 96; $b.Add_Click({ try { Import-PcConfig } catch { Write-UiLog "Importation de la configuration : $($_.Exception.Message)" 'ERROR' } }); [void]$bar.Children.Add($b)
    [void]$c.Body.Children.Add($bar)
    $c.Card.Margin = New-Thickness 0 0 0 12
    [void]$p.Children.Add($c.Card)

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

    $c = New-Card 'Mises à jour de l''application' '' ([string][char]0xE895)
    $SetUI.UpdAuto = Add-SettingsChoice $c.Body 'Recherche au lancement' 'Bandeau en haut de la fenêtre quand une nouvelle version est publiée ; rien n''est installé sans ton accord.' ([ordered]@{ On = 'Activée'; Off = 'Désactivée' }) $(if (Get-UpdAuto) { 'On' } else { 'Off' }) {
        param($s, $e) Set-UpdAuto ("$($s.DataContext)" -eq 'On'); foreach ($x in $SetUI.UpdAuto) { $x.Tag = $(if ($x.DataContext -eq $s.DataContext) { 'on' } else { '' }) }
        Write-UiLog ('Recherche de mise à jour au lancement : {0}.' -f $(if ("$($s.DataContext)" -eq 'On') { 'activée' } else { 'désactivée' })) 'APP' }
    $SetUI.SoftAuto = Add-SettingsChoice $c.Body 'Mises à jour des logiciels installés au lancement' 'Recherche en arrière-plan 30 secondes après l''ouverture de l''application (winget et Microsoft Store) ; résultat dans Applications > Mettre à jour, rien n''est installé sans ton accord.' ([ordered]@{ On = 'Activée'; Off = 'Désactivée' }) $(if (Get-SoftAuto) { 'On' } else { 'Off' }) {
        param($s, $e) Set-SoftAuto ("$($s.DataContext)" -eq 'On'); foreach ($x in $SetUI.SoftAuto) { $x.Tag = $(if ($x.DataContext -eq $s.DataContext) { 'on' } else { '' }) }
        Write-UiLog ('Recherche des mises à jour des logiciels au lancement : {0}.' -f $(if ("$($s.DataContext)" -eq 'On') { 'activée' } else { 'désactivée' })) 'APP' }
    $ub = [Windows.Controls.WrapPanel]::new(); $ub.Margin = New-Thickness 38 0 10 14
    # recherche manuelle et état : en-tête de Paramètres (pas de doublon dans cette carte)
    $c.Card.Margin = New-Thickness 0 12 0 0
    [void]$p.Children.Add($c.Card)
    Update-UpdStatus $(if ($UpdUI.Info) { 'Version {0} disponible.' -f (Get-UpdVersion $UpdUI.Info.Tag) } elseif ($UpdUI.Checked) { Get-UpdUpToDate } else { 'Pas encore vérifié pendant cette session.' })

    $c = New-Card 'Onglets et cartes affichés' 'Onglets de la barre et cartes de chaque onglet : affichés ou masqués, ordre des cartes (raccourci : clic droit sur une carte)' ([string][char]0xE8A9)
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
    Update-UpdStatus $(if ($UpdUI.Info) { 'Version {0} disponible.' -f (Get-UpdVersion $UpdUI.Info.Tag) } elseif ($UpdUI.Checked) { Get-UpdUpToDate } else { 'Pas encore vérifié pendant cette session.' })
    $SetUI.Built = $true
}
# Disposition des Paramètres : toutes les cartes à droite, rubrique par rubrique ; sommaire à gauche, qui reste visible
# pendant le défilement, amène à la rubrique choisie et suit la rubrique affichée.
# rubrique Mises à jour en premier : visible dès l'ouverture des paramètres
$SettingsSections = [ordered]@{
    Update = @{ T = 'Mises à jour'; G = 0xE895; C = @('Mises à jour de l''application') }
    Look   = @{ T = 'Apparence'; G = 0xE790; C = @('Apparence') }
    Tabs   = @{ T = 'Onglets et cartes'; G = 0xE8A9; C = @('Onglets et cartes affichés') }
    Start  = @{ T = 'Démarrage et raccourcis'; G = 0xE7E8; C = @('Démarrage', 'Raccourcis') }
    Win    = @{ T = 'Fenêtre et notifications'; G = 0xE737; C = @('Fenêtre et zone de notification') }
    Save   = @{ T = 'Sauvegarde et réinitialisation'; G = 0xE777; C = @('Configuration du poste', 'Restauration des réglages', 'Réinitialisation'); Merge = $true }
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
    # en-tête : logo, version, état de la mise à jour et action directe (remplace la carte « À propos »)
    [void]$sh.Children.Add((New-SettingsHero))
    $SetUI.SecHost = $sh; $SetUI.SecCards = $cards; $SetUI.SecBtns = @{}; $SetUI.SecFirst = [ordered]@{}; $SetUI.SecNav = $nav; $SetUI.SecGrid = $g; $SetUI.SecList = @{}
    # recherche d'un réglage : filtre les rubriques, cartes et choix pendant la saisie (accents et casse ignorés)
    # même champ que « Rechercher dans l'application » (en-tête) : arrondi, loupe bleue, contour bleu au focus, Échap pour effacer
    $sx = [xml]@'
<Border xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Height="36" Margin="0,0,0,12" CornerRadius="18" Background="{DynamicResource BgBrush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="1.5" Cursor="IBeam">
  <Grid>
    <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
    <TextBlock Text="&#xE721;" FontFamily="Segoe MDL2 Assets" FontSize="14" Foreground="{DynamicResource AccentBrush}" Margin="14,0,8,0" VerticalAlignment="Center"/>
    <TextBox x:Name="Find" Grid.Column="1" BorderThickness="0" Background="Transparent" Foreground="{DynamicResource FgBrush}" CaretBrush="{DynamicResource FgBrush}" VerticalAlignment="Center" VerticalContentAlignment="Center" Padding="0" FontSize="13">
      <TextBox.Template><ControlTemplate TargetType="TextBox"><ScrollViewer x:Name="PART_ContentHost" Focusable="False" HorizontalScrollBarVisibility="Hidden" VerticalScrollBarVisibility="Hidden" Background="Transparent"/></ControlTemplate></TextBox.Template>
    </TextBox>
    <TextBlock x:Name="Hint" Grid.Column="1" Text="Rechercher un réglage" Foreground="{DynamicResource MutedBrush}" VerticalAlignment="Center" IsHitTestVisible="False" TextTrimming="CharacterEllipsis"/>
    <Button x:Name="Clear" Grid.Column="2" Content="&#xE711;" Style="{DynamicResource IconBtn}" Width="26" Height="26" Margin="0,0,6,0" FontSize="10" ToolTip="Effacer la recherche" Visibility="Collapsed"/>
  </Grid>
</Border>
'@
    $sb = [Windows.Markup.XamlReader]::Load([System.Xml.XmlNodeReader]::new($sx))
    $SetUI.Find = $sb.FindName('Find'); $SetUI.FindHint = $sb.FindName('Hint'); $SetUI.FindClear = $sb.FindName('Clear'); $SetUI.FindBox = $sb
    $sb.Add_MouseLeftButtonDown({ [void]$SetUI.Find.Focus() })
    $SetUI.Find.Add_TextChanged({ Set-SettingsFilter $SetUI.Find.Text; $SetUI.FindClear.Visibility = $(if ($SetUI.Find.Text) { 'Visible' } else { 'Collapsed' }) })
    $SetUI.Find.Add_GotKeyboardFocus({ $SetUI.FindBox.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, 'AccentBrush') })
    $SetUI.Find.Add_LostKeyboardFocus({ $SetUI.FindBox.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, 'LineBrush') })
    $SetUI.Find.Add_PreviewKeyDown({ param($s, $e) if ($e.Key -eq 'Escape' -and $s.Text) { $s.Text = ''; $e.Handled = $true } })
    $SetUI.FindClear.Add_Click({ $SetUI.Find.Text = ''; [void]$SetUI.Find.Focus() })
    [void]$nav.Children.Add($sb)
    $SetUI.FindNone = New-Text 'Aucun réglage ne correspond à la recherche.' 'Muted'; $SetUI.FindNone.Margin = New-Thickness 4 18 0 0; $SetUI.FindNone.Visibility = 'Collapsed'
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
        # titre de rubrique (repère en défilant), puis ses cartes ; rubrique « Merge » : cartes fondues en une seule carte à
        # sous-parties séparées par un filet ; titre = point d'arrivée du sommaire
        $hd = New-Text $sec.T; $hd.FontSize = 20; $hd.FontWeight = [Windows.FontWeights]::SemiBold; $hd.Margin = New-Thickness 4 18 0 10
        $hd.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'HeadBrush')
        [void]$sh.Children.Add($hd); $SetUI.SecFirst[$k] = $hd
        $list = @($sec.C | ForEach-Object { $cards[$_] } | Where-Object { $_ })
        if ($sec.Merge -and $list.Count -gt 1) {
            $host0 = $list[0].Child
            foreach ($c in $list[1..($list.Count - 1)]) {
                $sep = [Windows.Controls.Border]::new(); $sep.Height = 1; $sep.Margin = New-Thickness 16 6 16 0; $sep.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, 'LineBrush')
                [void]$host0.Children.Add($sep)
                # carte à pied de boutons ($setFoot : DockPanel [barre, contenu], barre ancrée en bas) : contenu d'abord, barre
                # ensuite (avant : tri par ligne de grille, 0 pour les deux, boutons affichés au-dessus du texte qu'ils commandent)
                $kids = @($c.Child.Children | Sort-Object { "$([Windows.Controls.DockPanel]::GetDock($_))" -eq 'Bottom' }, { [Windows.Controls.Grid]::GetRow($_) }); $c.Child.Children.Clear()
                foreach ($x in $kids) { [Windows.Controls.Grid]::SetRow($x, 0); [void]$host0.Children.Add($x) }
            }
            $list = @($list[0])
        }
        foreach ($c in $list) { [void]$sh.Children.Add($c) }
        $SetUI.SecList[$k] = $list
    }
    [void]$sh.Children.Add($SetUI.FindNone)
    [void]$g.Children.Add($nav); [void]$g.Children.Add($sh)
    [void]$P.Children.Add($g)
    # sommaire fixe à l'écran (décalé de la hauteur défilée) et rubrique en cours surlignée
    if (-not $SetUI.SecScrollHooked -and $Ui.PageSettings -is [Windows.Controls.ScrollViewer]) {
        $SetUI.SecScrollHooked = $true
        $Ui.PageSettings.Add_ScrollChanged({ Update-SettingsNav })
    }
    Set-SettingsNavOn 'Update'
}
# texte d'un élément d'interface (libellés, boutons) sans accents ni casse, pour la recherche dans les Paramètres
function Get-PlainText([string]$S) { $d = $S.Normalize([Text.NormalizationForm]::FormD); (-join @($d.ToCharArray() | Where-Object { [Globalization.CharUnicodeInfo]::GetUnicodeCategory($_) -ne 'NonSpacingMark' })).ToLowerInvariant() }
function Get-UiText($El) {
    $sb = [Text.StringBuilder]::new()
    $walk = { param($x)
        if ($x -is [Windows.Controls.TextBlock]) { [void]$sb.Append($x.Text).Append(' ') }
        elseif ($x -is [Windows.Controls.ContentControl] -and $x.Content -is [string]) { [void]$sb.Append($x.Content).Append(' ') }
        if ($x -is [Windows.DependencyObject]) { foreach ($c in [Windows.LogicalTreeHelper]::GetChildren($x)) { & $walk $c } }
    }
    & $walk $El; Get-PlainText $sb.ToString()
}
function Get-UiByUid($El, [string]$Uid) {
    $r = [Collections.ArrayList]::new()
    $walk = { param($x) if ($x -is [Windows.UIElement] -and $x.Uid -eq $Uid) { [void]$r.Add($x); return }; if ($x -is [Windows.DependencyObject]) { foreach ($c in [Windows.LogicalTreeHelper]::GetChildren($x)) { & $walk $c } } }
    & $walk $El; $r.ToArray()
}
function Set-SettingsFilter([string]$Q) {
    $q = Get-PlainText "$Q".Trim()
    $SetUI.FindHint.Visibility = $(if ($Q) { 'Collapsed' } else { 'Visible' })
    $any = $false
    foreach ($k in $SetUI.SecList.Keys) {
        $secVis = $false
        foreach ($c in $SetUI.SecList[$k]) {
            $ch = @(Get-UiByUid $c 'setchoice')
            if (-not $q) { foreach ($x in $ch) { $x.Visibility = 'Visible' }; $c.Visibility = 'Visible'; $secVis = $true; continue }
            $hit = @($ch | Where-Object { (Get-UiText $_).Contains($q) })
            # choix correspondants seuls ; correspondance ailleurs dans la carte (titre, texte, boutons) : carte entière
            if ($hit.Count) { foreach ($x in $ch) { $x.Visibility = $(if ($hit -contains $x) { 'Visible' } else { 'Collapsed' }) }; $c.Visibility = 'Visible'; $secVis = $true }
            elseif ((Get-UiText $c).Contains($q)) { foreach ($x in $ch) { $x.Visibility = 'Visible' }; $c.Visibility = 'Visible'; $secVis = $true }
            else { $c.Visibility = 'Collapsed' }
        }
        $SetUI.SecFirst[$k].Visibility = $(if ($secVis) { 'Visible' } else { 'Collapsed' })
        $SetUI.SecBtns[$k].Visibility = $(if ($secVis) { 'Visible' } else { 'Collapsed' })
        if ($secVis) { $any = $true }
    }
    $SetUI.FindNone.Visibility = $(if ($any) { 'Collapsed' } else { 'Visible' })
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
    # 1re rubrique (Mises à jour) : haut des Paramètres, avec l'en-tête Oliv_Maintenance et son bouton de recherche de mise à jour
    $y = $(if ($Key -eq @($SettingsSections.Keys)[0]) { 0 } else { (Get-SettingsTop $SetUI.SecFirst[$Key]) - 4 })
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
# instantanés à supprimer : au-delà des $Keep plus récents de chaque compte (nom = date) ; compte inconnu (fichier
# illisible) : jamais supprimé
function Get-SnapshotPurge($Files, [int]$Keep) {
    foreach ($g in @($Files | Where-Object { $_.Sid } | Group-Object Sid)) { @($g.Group | Sort-Object Name -Descending | Select-Object -Skip $Keep) }
}
function Save-TweakSnapshot([string]$Reason, [string[]]$Changes) {
    $vals = [ordered]@{}
    foreach ($r in $TweakRows) { if ($r.Enabled -and $null -ne $r.Current) { $vals[$r.Tweak.Id] = $r.Current } }
    if ($vals.Count -eq 0) { return }
    try {
        if (-not (Test-Path -LiteralPath $SnapDir)) { [void](New-Item -ItemType Directory -Path $SnapDir -Force) }
        $now = [DateTime]::Now
        $o = [pscustomobject]@{ Time = $now.ToString('o'); Sid = $UserSid; User = $UserName; Reason = $Reason; Changes = @($Changes); Values = [pscustomobject]$vals }
        Write-FileAtomic (Join-Path $SnapDir ('{0:yyyyMMdd-HHmmss-fff}.json' -f $now)) (ConvertTo-Json -InputObject $o -Depth 3) -NoBackup
        # 30 derniers instantanés gardés par compte (avant : tous comptes confondus, ceux d'un utilisateur disparaissaient
        # après 30 modifications faites pour un autre) ; fichier illisible jamais supprimé
        $all = @(Get-ChildItem -LiteralPath $SnapDir -Filter '*.json' -File | ForEach-Object {
            $sid = try { "$((Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json).Sid)" } catch { $null }
            [pscustomobject]@{ Name = $_.Name; Path = $_.FullName; Sid = $sid }
        })
        foreach ($x in @(Get-SnapshotPurge $all 30)) { Remove-Item -LiteralPath $x.Path -Force -ErrorAction SilentlyContinue }
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
        # valeur applicable sur ce poste seulement : option proposée (ni « Autre plan », ni « Réglage personnalisé », ni version
        # de Windows d'un autre PC), ou vrai / faux pour un interrupteur ; sinon la ligne restait bloquée « en cours » (DNS)
        if ($r -and $r.Tweak.Kind -eq 'Choice' -and -not @($r.Tweak.Options | Where-Object { -not $_.H -and "$($_.V)" -eq "$($pr.Value)" }).Count) { continue }
        if ($r -and $r.Tweak.Kind -ne 'Choice' -and $pr.Value -isnot [bool]) { continue }
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
    # pendant une tâche : refusé (gpupdate, DNS... en parallèle du worker), comme l'import d'une configuration
    if ($Sync.Running) { Show-Info 'Une tâche est en cours. Restaurer les réglages une fois terminée.'; return }
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
    if ($Sync.Running) { Show-Info 'Une tâche est en cours. Restaurer les réglages une fois terminée.'; return }
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


# ---- Configuration du poste (fichier .json) : réglages (identifiant > valeur), applications du catalogue installées,
# onglets et cartes masqués, paramètres de l'application (Interface). Importation : réglages préparés (même circuit que les choix manuels : bandeau Appliquer),
# applications manquantes sélectionnées dans le catalogue, affichage appliqué tout de suite.
function Export-PcConfig {
    New-DeferredPage
    $tw = [ordered]@{}; foreach ($r in @($TweakRows)) { if ($r.Tweak -and $r.Enabled -and $null -ne $r.Current) { $tw["$($r.Tweak.Id)"] = $r.Current } }
    $inst = @(); if (-not $AppsUI.Built) { try { New-AppsPage } catch { Write-Ignored 'Catalogue Applications' $_ } }
    # applications installées : badges du catalogue, sinon dernier inventaire des logiciels (repris de l'ancienne sauvegarde)
    if ($AppsUI.Installed) { $inst = @($AppsUI.Tiles.Keys | Where-Object { $AppsUI.Installed.Contains("$_") }) }
    elseif ($Sync.WgResult) { $ids = @($Sync.WgResult.Apps | ForEach-Object { "$($_.Id)" }); $inst = @($AppsUI.Tiles.Keys | Where-Object { $ids -contains "$_" }) }
    $o = [ordered]@{ Application = 'Oliv_Maintenance'; Version = $AppVersion; Date = (Get-Date).ToString('o'); Poste = $env:COMPUTERNAME; Reglages = $tw; Applications = @($inst); OngletsMasques = @($HiddenTabs); CartesMasquees = @($HiddenCards); Interface = (Get-AppPref) }
    $dlg = [Microsoft.Win32.SaveFileDialog]::new(); $dlg.Title = 'Exporter la configuration'; $dlg.InitialDirectory = [Environment]::GetFolderPath('Desktop'); $dlg.Filter = 'Configuration Oliv_Maintenance (*.json)|*.json'; $dlg.FileName = '{0}_configuration_{1:yyyyMMdd}.json' -f $env:COMPUTERNAME, (Get-Date)
    if (-not $dlg.ShowDialog($Window)) { return }
    [IO.File]::WriteAllText($dlg.FileName, (ConvertTo-Json -InputObject $o -Depth 4), [Text.UTF8Encoding]::new($false))
    Write-UiLog ('Configuration exportée : {0} réglages, {1} applications > {2}' -f $tw.Count, $inst.Count, $dlg.FileName) 'OK'
    Add-SessionEvent 'Configuration' 'Exportation de la configuration' ('{0} réglages, {1} applications' -f $tw.Count, $inst.Count) 'ok'
    Show-Info ("Configuration exportée.`n`n{0} réglages, {1} applications du catalogue.`n`n{2}" -f $tw.Count, $inst.Count, $dlg.FileName) 'Ok'
}
# Paramètres de l'application elle-même (thème, taille, animations, démarrage, fenêtre, zone de notification, alertes,
# recherches au lancement, ordre des cartes) : exportés avec la configuration pour cloner l'application d'un PC à l'autre
function Get-AppPref {
    $st = 'Info'; try { if (Test-Path -LiteralPath $StartFile) { $st = [IO.File]::ReadAllText($StartFile).Trim() } } catch { $null = $_ }
    $ord = [ordered]@{}; foreach ($pg in $CardPages.Keys) { $v = @((Get-RegValue $CardRegKey "CartesOrdre_$pg") | Where-Object { $_ }); if ($v.Count) { $ord[$pg] = $v } }
    [ordered]@{ Theme = "$($Sync.ThemeMode)"; Zoom = $UiZoom; Animations = "$($Anim.Mode)"; Onglet = $st; Positions = [bool]$WinPos.Enabled
        ReduireZone = [bool]$Tray.Min; FermerReduit = [bool]$Tray.Close; DemarrageReduit = [bool]$Tray.StartMin; OuvertureSession = [bool](Get-AutoStartTask)
        Alertes = [bool](Get-AlertOn); MajAuLancement = [bool](Get-UpdAuto); MajLogiciels = [bool](Get-SoftAuto); OrdreCartes = $ord }
}
# lignes du récapitulatif d'importation (différences seulement) et application
function Get-AppPrefDiff($P) {
    if (-not $P) { return @() }
    $cur = Get-AppPref; $l = @()
    $on = { param($b) $(if ($b) { 'activé' } else { 'désactivé' }) }
    if ($P.Theme -and "$($P.Theme)" -ne $cur.Theme -and $ThemeModes.Contains("$($P.Theme)")) { $l += 'Thème : ' + $ThemeModes["$($P.Theme)"].Label }
    if ($P.Zoom -and [double]$P.Zoom -ne [double]$cur.Zoom) { $l += 'Taille de l''interface : {0:N0} %' -f ([double]$P.Zoom * 100) }
    if ($P.Animations -and "$($P.Animations)" -ne $cur.Animations -and "$($P.Animations)" -in 'On', 'Sys', 'Off') { $l += 'Animations : ' + @{ On = 'activées'; Sys = 'comme Windows'; Off = 'désactivées' }["$($P.Animations)"] }
    if ($P.Onglet -and "$($P.Onglet)" -ne $cur.Onglet -and $StartPages.Contains("$($P.Onglet)")) { $l += 'Onglet à l''ouverture : ' + $StartPages["$($P.Onglet)"] }
    foreach ($x in @(@('Positions', 'Taille et position des fenêtres mémorisées'), @('ReduireZone', 'Réduire dans la zone de notification'), @('FermerReduit', 'Bouton Fermer : réduire'), @('DemarrageReduit', 'Démarrage réduit'), @('OuvertureSession', 'Ouverture à l''ouverture de session'), @('Alertes', 'Alertes du poste en notification'), @('MajAuLancement', 'Recherche de mise à jour au lancement'), @('MajLogiciels', 'Recherche des mises à jour des logiciels au lancement'))) {
        if ($null -ne $P.($x[0]) -and [bool]$P.($x[0]) -ne [bool]$cur[$x[0]]) { $l += '{0} : {1}' -f $x[1], (& $on $P.($x[0])) }
    }
    $n = 0; if ($P.OrdreCartes) { foreach ($pp in $P.OrdreCartes.PSObject.Properties) { if ((@($pp.Value) -join '§') -ne (@($cur.OrdreCartes[$pp.Name]) -join '§')) { $n++ } } }
    if ($n) { $l += "Ordre des cartes : $n $(Get-Plural $n 'onglet' 'onglets')" }
    $l
}
function Set-AppPref($P) {
    if (-not $P) { return }
    try { if ($P.Theme -and $ThemeModes.Contains("$($P.Theme)")) { Set-ThemeMode "$($P.Theme)" $true } } catch { Write-Ignored 'Importation : thème' $_ }
    try { if ($P.Zoom) { Set-UiZoom ([double]$P.Zoom) $false } } catch { Write-Ignored 'Importation : taille' $_ }
    try { if ("$($P.Animations)" -in 'On', 'Sys', 'Off') { $Anim.Mode = "$($P.Animations)"; [IO.File]::WriteAllText($AnimFile, $Anim.Mode) } } catch { Write-Ignored 'Importation : animations' $_ }
    try { if ($P.Onglet -and $StartPages.Contains("$($P.Onglet)")) { [IO.File]::WriteAllText($StartFile, "$($P.Onglet)") } } catch { Write-Ignored 'Importation : onglet' $_ }
    try { if ($null -ne $P.Positions) { $WinPos.Enabled = [bool]$P.Positions; Save-WindowPositionStore } } catch { Write-Ignored 'Importation : positions' $_ }
    try { if ($null -ne $P.ReduireZone) { $Tray.Min = [bool]$P.ReduireZone }; if ($null -ne $P.FermerReduit) { $Tray.Close = [bool]$P.FermerReduit; $Tray.CloseSet = $true }; if ($null -ne $P.DemarrageReduit) { $Tray.StartMin = [bool]$P.DemarrageReduit }; Save-TraySetting } catch { Write-Ignored 'Importation : zone de notification' $_ }
    try { if ($null -ne $P.Alertes) { $k = Open-RegKey $CardRegKey $true $true; try { $k.SetValue('AlertesPoste', [int][bool]$P.Alertes, [Microsoft.Win32.RegistryValueKind]::DWord) } finally { $k.Close() } } } catch { Write-Ignored 'Importation : alertes' $_ }
    try { if ($null -ne $P.MajAuLancement) { Set-UpdAuto ([bool]$P.MajAuLancement) }; if ($null -ne $P.MajLogiciels) { Set-SoftAuto ([bool]$P.MajLogiciels) } } catch { Write-Ignored 'Importation : recherches au lancement' $_ }
    try { if ($null -ne $P.OuvertureSession -and [bool]$P.OuvertureSession -ne [bool](Get-AutoStartTask)) { Set-AutoStart ([bool]$P.OuvertureSession) } } catch { Write-UiLog "Importation : ouverture de session - $($_.Exception.Message)" 'WARN' }
    try {
        if ($P.OrdreCartes) {
            $k = Open-RegKey $CardRegKey $true $true
            try { foreach ($pp in $P.OrdreCartes.PSObject.Properties) { if ($CardPages.Contains($pp.Name)) { $k.SetValue("CartesOrdre_$($pp.Name)", [string[]]@($pp.Value), [Microsoft.Win32.RegistryValueKind]::MultiString) } } } finally { $k.Close() }
            foreach ($pg in $CardPages.Keys) { $CardMove.Applied.Remove($pg); try { Restore-CardOrder $pg } catch { Write-Ignored 'Importation : ordre des cartes' $_ } }
        }
    } catch { Write-Ignored 'Importation : ordre des cartes' $_ }
    # Paramètres déjà construits : reconstruits pour refléter les nouveaux choix
    # Paramètres déjà construits : choix actifs remis à jour
    if ($SetUI.Built) {
        $now = Get-AppPref
        $map = @{ Anim = "$($now.Animations)"; Start = "$($now.Onglet)"; WinPos = $(if ($now.Positions) { 'On' } else { 'Off' }); TrayMin = $(if ($now.ReduireZone) { 'Tray' } else { 'Bar' })
                  TrayClose = $(if ($now.FermerReduit) { 'Tray' } else { 'Close' }); StartMin = $(if ($now.DemarrageReduit) { 'Tray' } else { 'Window' }); AutoStart = $(if ($now.OuvertureSession) { 'On' } else { 'Off' })
                  AlertOn = $(if ($now.Alertes) { 'On' } else { 'Off' }); UpdAuto = $(if ($now.MajAuLancement) { 'On' } else { 'Off' }); SoftAuto = $(if ($now.MajLogiciels) { 'On' } else { 'Off' }) }
        foreach ($k in $map.Keys) { foreach ($b in @($SetUI[$k])) { if ($b) { $b.Tag = $(if ("$($b.DataContext)" -eq $map[$k]) { 'on' } else { '' }) } } }
    }
}
# Importation unique (Paramètres > Exporter / Importer et Système > Restaurer une configuration) : lit le format actuel
# (Application, Reglages, Applications, OngletsMasques, CartesMasquees) et l'ancien format de la sauvegarde de l'onglet Système
# (Type, Values, Apps). Récapitulatif, instantané des réglages actuels, application des réglages, puis installation des
# applications ; seules les valeurs applicables sur ce poste sont reprises.
function Import-PcConfig {
    if ($Sync.Running) { Show-Info 'Une tâche est en cours : importer la configuration une fois terminée.'; return }
    $dlg = [Microsoft.Win32.OpenFileDialog]::new(); $dlg.Title = 'Importer une configuration'; $dlg.Filter = 'Configuration Oliv_Maintenance (*.json)|*.json'
    $dlg.InitialDirectory = [Environment]::GetFolderPath('Desktop')
    if (-not $dlg.ShowDialog($Window)) { return }
    $o = try { Get-Content -LiteralPath $dlg.FileName -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop } catch { Show-Info "Fichier illisible.`n`n$($_.Exception.Message)" 'Error'; return }
    $new = "$($o.Application)" -eq 'Oliv_Maintenance'; $old = "$($o.Type)" -in 'Oliv_Maintenance.Configuration', 'Oliv_Maintenance.Recette'
    if (-not $new -and -not $old) { Show-Info 'Ce fichier n''est pas une configuration Oliv_Maintenance.' 'Error'; return }
    $vals = $(if ($new) { $o.Reglages } else { $o.Values }); if (-not $vals) { $vals = [pscustomobject]@{} }
    $diff = Get-SnapshotDiff ([pscustomobject]@{ Values = $vals })
    if (-not $AppsUI.Built) { try { New-AppsPage } catch { Write-Ignored 'Catalogue Applications' $_ } }
    $todo = @(@($(if ($new) { $o.Applications } else { $o.Apps })) | Where-Object { $_ -and $AppsUI.Tiles.ContainsKey("$_") -and -not ($AppsUI.Installed -and $AppsUI.Installed.Contains("$_")) } | ForEach-Object { "$_" } | Select-Object -Unique)
    $tabs = @(@($o.OngletsMasques) | Where-Object { $_ -and -not $HiddenTabs.Contains("$_") } | ForEach-Object { "$_" })
    $cards = @(@($o.CartesMasquees) | Where-Object { $_ -and -not $HiddenCards.Contains("$_") } | ForEach-Object { "$_" })
    $pref = @(Get-AppPrefDiff $o.Interface)
    if (-not $diff.Count -and -not $todo.Count -and -not $tabs.Count -and -not $cards.Count -and -not $pref.Count) { Show-Info 'Ce PC a déjà cette configuration : réglages identiques, applications présentes.' 'Ok'; return }
    $lines = @($diff | ForEach-Object { $_.Line }) + @($todo | ForEach-Object { 'Installer : ' + $AppsUI.Tiles["$_"].A[0] }) +
             @($tabs | ForEach-Object { 'Onglet masqué : ' + $(if ($TabLabels -and $TabLabels[$_]) { $TabLabels[$_] } else { $_ }) }) + $(if ($cards.Count) { @("Cartes masquées : $($cards.Count)") } else { @() }) + @($pref | ForEach-Object { 'Application : ' + $_ })
    $head = 'Importer la configuration de {0} ? {1} {2}, {3} {4} à installer :' -f $o.Poste, $diff.Count, (Get-Plural $diff.Count 'réglage modifié' 'réglages modifiés'), $todo.Count, (Get-Plural $todo.Count 'application' 'applications')
    if (-not (Confirm-List $head $lines 'Un instantané des réglages actuels est enregistré avant (Paramètres > Restauration des réglages). Les applications s''installent ensuite, une après l''autre.' 'Importer')) { return }
    if ($diff.Count) {
        Save-TweakSnapshot "Avant la configuration de $($o.Poste)" @($diff | ForEach-Object { $_.Line })
        foreach ($d in $diff) { Invoke-TweakChange $d.R $d.V }
        Update-ApplyButton
    }
    if ($tabs.Count) { foreach ($x in $tabs) { [void]$HiddenTabs.Add($x) }; Save-HiddenTab; Update-TabVisibility }
    if ($cards.Count) { foreach ($x in $cards) { [void]$HiddenCards.Add($x) }; Save-HiddenCard }
    if ($pref.Count) { Set-AppPref $o.Interface; Write-UiLog ('Paramètres de l''application importés : ' + ($pref -join ' ; ')) 'APP' }
    Write-UiLog ('Configuration de {0} importée ({1}) : {2} réglages, {3} onglets et {4} cartes masqués{5}.' -f $o.Poste, [IO.Path]::GetFileName($dlg.FileName), $diff.Count, $tabs.Count, $cards.Count, $(if ($todo.Count) { ", installation de $($todo.Count) applications" } else { '' })) 'OK'
    Add-SessionEvent 'Configuration' 'Importation de la configuration' ('{0} réglages, {1} applications' -f $diff.Count, $todo.Count) 'ok'
    if ($todo.Count) {
        $AppsUI.Sel.Clear(); foreach ($i in $todo) { [void]$AppsUI.Sel.Add("$i") }
        foreach ($x in $AppsUI.Tiles.Values) { Set-AppTileLook $x }
        Set-AppsMode 'Inst'; Show-Page 'Apps'
        Invoke-AppsInstall -NoConfirm
    }
}

# En-tête de Paramètres : logo sur fond blanc, nom, version et date, état de la mise à jour, bouton de recherche
function New-SettingsHero {
    $b = [Windows.Controls.Border]::new(); $b.Style = $Window.FindResource('Panel'); $b.Padding = New-Thickness 20 18 20 18; $b.Margin = New-Thickness 0 0 0 4
    $g = [Windows.Controls.Grid]::new()
    foreach ($w in 'Auto', '*', 'Auto') { $cd = [Windows.Controls.ColumnDefinition]::new(); $cd.Width = $(if ($w -eq '*') { [Windows.GridLength]::new(1, 'Star') } else { [Windows.GridLength]::Auto }); [void]$g.ColumnDefinitions.Add($cd) }
    $logo = Get-EmbeddedImage $LogoFullB64
    if ($logo) {
        $li = [Windows.Controls.Image]::new(); $li.Source = $logo; $li.Width = 150; $li.Stretch = 'Uniform'; [Windows.Media.RenderOptions]::SetBitmapScalingMode($li, 'HighQuality')
        $lb = [Windows.Controls.Border]::new(); $lb.Background = [Windows.Media.Brushes]::White; $lb.CornerRadius = [Windows.CornerRadius]::new(8); $lb.Padding = New-Thickness 10 6 10 6; $lb.Margin = New-Thickness 0 0 20 0; $lb.VerticalAlignment = 'Center'; $lb.Child = $li
        [void]$g.Children.Add($lb)
    }
    $sp = [Windows.Controls.StackPanel]::new(); $sp.VerticalAlignment = 'Center'; [Windows.Controls.Grid]::SetColumn($sp, 1)
    $t1 = New-Text 'Oliv_Maintenance'; $t1.FontSize = 22; $t1.FontWeight = [Windows.FontWeights]::SemiBold; [void]$sp.Children.Add($t1)
    $bd = $BuildDate; try { $bd = '{0:dd/MM/yyyy}' -f [DateTime]::ParseExact($BuildDate, 'yyyy-MM-dd HH:mm', [Globalization.CultureInfo]::InvariantCulture) } catch { $null = $_ }
    $t2 = New-Text ('Version {0}  ·  {1}  ·  développé par Oliv' -f $AppVersion, $bd) 'Muted'; $t2.Margin = New-Thickness 0 2 0 2; [void]$sp.Children.Add($t2)
    # page des versions publiées (GitHub), lien cliquable
    $gl = New-Text ("github.com/$UpdRepo"); $gl.Cursor = [Windows.Input.Cursors]::Hand; $gl.TextDecorations = [Windows.TextDecorations]::Underline; $gl.Margin = New-Thickness 0 0 0 6; $gl.HorizontalAlignment = 'Left'
    $gl.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'AccentBrush'); $gl.ToolTip = 'Ouvrir la page des versions publiées dans le navigateur'
    $gl.Add_MouseLeftButtonUp({ try { Open-WebPage "https://github.com/$UpdRepo/releases" } catch { Write-UiLog "Ouverture de la page GitHub : $($_.Exception.Message)" 'ERROR' } })
    [void]$sp.Children.Add($gl)
    $SetUI.HeroStatus = New-Text '' 'Muted'; $SetUI.HeroStatus.TextWrapping = 'Wrap'; [void]$sp.Children.Add($SetUI.HeroStatus)
    [void]$g.Children.Add($sp)
    $bt = New-Button 'Rechercher une mise à jour' 'PrimaryBtn'; $bt.Height = 34; $bt.Padding = New-Thickness 16 0 16 0; $bt.VerticalAlignment = 'Center'; $bt.Margin = New-Thickness 16 0 0 0
    $bt.Add_Click({ Start-UpdCheck $true }); [Windows.Controls.Grid]::SetColumn($bt, 2); [void]$g.Children.Add($bt)
    $b.Child = $g
    $b
}
