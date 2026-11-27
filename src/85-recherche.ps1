# ---------- Recherche globale (en-tête) : index de toutes les pages (cartes, lignes, réglages, options, logiciels installés),
# moteur tolérant (accents, pluriels, fautes de frappe, synonymes, mots dans le désordre), résultats cliquables
$SearchUI = @{ Units = @(); Dirty = $true; Sel = -1 }
# expressions ramenées à un seul mot, puis groupes de synonymes (le premier mot sert de référence)
$SearchPhrases = @(
    @('mises a jour', 'maj'), @('mise a jour', 'maj'), @('windows update', 'windowsupdate'), @('ecrans bleus', 'bsod'), @('ecran bleu', 'bsod'),
    @('barre des taches', 'barretaches'), @('menu demarrer', 'menudemarrer'), @('point de restauration', 'restauration'), @('points de restauration', 'restauration'),
    @('mot de passe', 'motdepasse'), @('cle de recuperation', 'clerecuperation'), @('espace disque', 'espacedisque'), @('a propos', 'apropos'))
$SearchSyn = @(
    'maj|update|updates|upgrade|actualisation|patch|correctif', 'windowsupdate|wu', 'pub|publicite|publicitaire|annonce|ads|advertising|promo|promotionnel',
    'bsod|bluescreen|plantage|crash|minidump', 'veille|hibernation|hiberner|sleep|hiberfil', 'demarrage|boot|startup|demarrer|ouverture',
    'redemarrage|reboot|restart|redemarrer|reboote', 'nettoyage|nettoyer|clean|cleanup|menage|purge|purger|vider', 'disque|disk|ssd|hdd|nvme|stockage|drive|volume',
    'reseau|network|ethernet|wifi|internet|connexion|lan|dns|ip|winsock', 'imprimante|printer|impression|spouleur|spooler|imprimer',
    'telemetrie|telemetry|tracking|pistage|espionnage|collecte', 'ia|ai|copilot|recall|intelligence|ki', 'navigateur|browser|chrome|edge|firefox|brave|cache',
    'logiciel|application|app|programme|software|appli', 'batterie|battery|autonomie|charge', 'bitlocker|chiffrement|encryption|clerecuperation',
    'explorateur|explorer|fichier', 'barretaches|taskbar', 'menudemarrer|startmenu|start', 'antivirus|defender|sophos|securite|protection',
    'pilote|driver|drivers|gpu|graphique|carte', 'constructeur|oem|lenovo|dell|hp|asus|fabricant|bios', 'journal|log|logs|historique|trace',
    'theme|sombre|clair|dark|light|couleur', 'reparation|reparer|repair|sfc|dism|chkdsk|corruption', 'confidentialite|privacy|vie privee|donnees',
    'restauration|restore|sauvegarde|instantane|snapshot', 'debloat|preinstallee|bloatware|desinstaller|supprimer', 'session|utilisateur|user|compte|sid',
    'gpo|strategie|gpupdate|policy', 'camera|webcam', 'localisation|location|gps|position', 'widget|meteo|actualite', 'recherche|search|bing|web',
    'performance|rapide|lent|lenteur|ralenti|optimiser|optimisation', 'apropos|version|compilation', 'motdepasse|password')
function Initialize-Search {
    [_OlivM.Fuzzy]::ResetSyn()
    foreach ($p in $SearchPhrases) { [_OlivM.Fuzzy]::AddPhrase($p[0], $p[1]) }
    foreach ($g in $SearchSyn) { [_OlivM.Fuzzy]::AddSyn($g) }
}
# texte d'un élément d'interface (TextBlock, TextBox, contenu de case ou de bouton, info-bulle) et de ses descendants logiques
function Get-UiText($El, $Acc) {
    if ($null -eq $El) { return }
    # glyphes d'icônes (zone privée Unicode, police Segoe MDL2) ignorés
    if ($El -is [string]) { if ($El.Trim() -and $El -notmatch '^[\uE000-\uF8FF\s]+$') { [void]$Acc.Add($El) }; return }
    if ($El -is [Windows.Controls.TextBlock] -or $El -is [Windows.Controls.TextBox]) {
        $t = "$($El.Text)"
        if ($t.Trim() -and $t -notmatch '^[\uE000-\uF8FF\s]+$') { [void]$Acc.Add($t) }
        return
    }
    if ($El -is [Windows.DependencyObject]) {
        foreach ($c in [Windows.LogicalTreeHelper]::GetChildren($El)) { Get-UiText $c $Acc }
    }
}
$SearchPageNames = @{ Info = 'Accueil'; Maint = 'Maintenance'; Perf = 'Système'; Secu = 'Sécurité'; Perso = 'Personnalisation'; Apps = 'Applications'; Svc = 'Services et tâches'; Tools = 'Outils'; Log = 'Journal'; Settings = 'Paramètres' }
# parcours des pages : cartes (Tag « card:... » ou titre de section) et lignes (styles de ligne, lignes clé / valeur)
function Add-SearchUnit($Root, [string]$Page, [string]$Card, $List) {
    if ($null -eq $Root -or $Root -isnot [Windows.DependencyObject]) { return }
    $Card = $Card
    if ($Root -is [Windows.Controls.Border]) {
        $tag = "$($Root.Tag)"; $st = $Root.Style
        if ($tag -like 'card:*') {
            $Card = $tag.Substring(5)
            [void]$List.Add(@{ Page = $Page; Card = $Card; Title = $Card; Body = ''; El = $Root; Kind = 'card' })
        }
        elseif ($st -and ($st -eq $Window.TryFindResource('Panel'))) {
            # carte décrite en XAML : titre = premier texte de style Section
            $acc = [Collections.ArrayList]::new(); Get-UiText $Root $acc
            if ($acc.Count) {
                $Card = "$($acc[0])"
                [void]$List.Add(@{ Page = $Page; Card = $Card; Title = $Card; Body = (@($acc | Select-Object -Skip 1) -join ' '); El = $Root; Kind = 'card' })
            }
        }
        elseif ($tag -eq 'kv' -or ($st -and ($st -eq $Window.TryFindResource('HoverPlain') -or $st -eq $Window.TryFindResource('HoverLine') -or $st -eq $Window.TryFindResource('HoverRow')))) {
            $acc = [Collections.ArrayList]::new(); Get-UiText $Root $acc
            if ($acc.Count) {
                $tip = "$($Root.ToolTip)"; if ($Root.ToolTip -isnot [string]) { $tip = '' }
                [void]$List.Add(@{ Page = $Page; Card = $Card; Title = "$($acc[0])"; Body = ((@($acc | Select-Object -Skip 1) + $tip + $Card) -join ' '); El = $Root; Kind = 'row' })
            }
            return
        }
    }
    if ($Root -is [Windows.Controls.StackPanel] -and "$($Root.Tag)" -eq 'meter') {
        $acc = [Collections.ArrayList]::new(); Get-UiText $Root $acc
        if ($acc.Count) {
            [void]$List.Add(@{ Page = $Page; Card = $Card; Title = "$($acc[0])"; Body = ((@($acc | Select-Object -Skip 1) + $Card) -join ' '); El = $Root; Kind = 'row' })
        }
        return
    }
    foreach ($c in [Windows.LogicalTreeHelper]::GetChildren($Root)) {
        if ($c -is [Windows.DependencyObject]) { Add-SearchUnit $c $Page $Card $List }
    }
}
function Update-SearchIndex {
    Initialize-Search
    if (-not $Lazy.Done) { New-DeferredPage }
    if (-not $SetUI.Built) { New-SettingsPage }
    $list = [Collections.ArrayList]::new()
    foreach ($p in $PageNames) { Add-SearchUnit $Ui["Page$p"] $p '' $list }
    Add-SearchUnit $Ui.SettingsPanel 'Settings' '' $list
    # Paramètres : cartes des rubriques non affichées (détachées) indexées aussi
    if ($SetUI.SecCards) { foreach ($c in $SetUI.SecCards.Values) { if (-not $c.Parent) { Add-SearchUnit $c 'Settings' '' $list } } }
    # logiciels installés (dernier inventaire) : ouverture de la fenêtre Logiciels filtrée sur le nom
    $r = $Sync.WgResult
    if ($r -and -not $r.Error) {
        foreach ($a in @($r.Apps | Where-Object { $_ })) {
            [void]$list.Add(@{ Page = 'Soft'; Card = 'Logiciels'; Title = "$($a.Name)"; Body = ('{0} logiciel installé {1}' -f $a.Id, $(if ($a.To -and $a.Src) { 'mise à jour disponible ' + $a.To } else { '' })); App = $a; Kind = 'app' })
        }
    }
    [_OlivM.Fuzzy]::Clear()
    for ($i = 0; $i -lt $list.Count; $i++) {
        [_OlivM.Fuzzy]::Add($i, $list[$i].Title, ('{0} {1} {2}' -f $list[$i].Body, $list[$i].Card, $SearchPageNames[$list[$i].Page]))
    }
    $SearchUI.Units = $list; $SearchUI.Dirty = $false; $SearchUI.Stamp = [DateTime]::Now
}
function Show-SearchResult {
    $q = "$($Ui.GlobalSearch.Text)".Trim()
    $Ui.SearchHint.Visibility = $(if ($Ui.GlobalSearch.Text) { 'Collapsed' } else { 'Visible' })
    $Ui.SearchList.Children.Clear(); $SearchUI.Sel = -1; $SearchUI.Shown = @()
    if ($q.Length -lt 2) { $Ui.SearchPop.IsOpen = $false; return }
    if ($SearchUI.Dirty -or -not $SearchUI.Stamp -or ([DateTime]::Now - $SearchUI.Stamp).TotalSeconds -gt 30) {
        $Window.Cursor = [Windows.Input.Cursors]::Wait
        try { Update-SearchIndex } finally { $Window.Cursor = $null }
    }
    $ids = @([_OlivM.Fuzzy]::Query($q, 12))
    # une seule entrée par élément affiché (titre identique dans la même carte)
    $seen = @{}
    foreach ($id in $ids) {
        $u = $SearchUI.Units[$id]; $k = '{0}|{1}|{2}' -f $u.Page, $u.Card, $u.Title
        if ($seen.ContainsKey($k)) { continue }; $seen[$k] = 1
        $SearchUI.Shown += $u
    }
    if (-not $SearchUI.Shown.Count) {
        $sp0 = [Windows.Controls.StackPanel]::new(); $sp0.Margin = New-Thickness 10 10 10 10
        $t = New-Text "Aucun résultat pour « $q »"; $t.FontWeight = [Windows.FontWeights]::SemiBold; [void]$sp0.Children.Add($t)
        $t = New-Text 'Essayer un autre mot ou un terme plus général : « réseau », « mises à jour », « nettoyage », « démarrage »...' 'Muted'
        $t.Margin = New-Thickness 0 4 0 0
        [void]$sp0.Children.Add($t)
        [void]$Ui.SearchList.Children.Add($sp0)
    }
    # résultats regroupés par page (ordre de pertinence conservé), icône de la page, mots trouvés surlignés dans le titre
    $order = [Collections.ArrayList]::new()
    foreach ($u in $SearchUI.Shown) {
        $pk = $(if ($u.Kind -eq 'app') { 'Soft' } else { $u.Page })
        if (-not $order.Contains($pk)) { [void]$order.Add($pk) }
    }
    $sorted = @(); foreach ($pk in $order) { $sorted += @($SearchUI.Shown | Where-Object { $(if ($_.Kind -eq 'app') { 'Soft' } else { $_.Page }) -eq $pk }) }
    $SearchUI.Shown = $sorted
    $glyph = @{ Info = 0xE80F; Maint = 0xE90F; Perf = 0xE770; Perso = 0xE771; Log = 0xE81C; Settings = 0xE713; Soft = 0xE7B8 }
    $i = 0; $last = $null
    foreach ($u in $SearchUI.Shown) {
        $pk = $(if ($u.Kind -eq 'app') { 'Soft' } else { $u.Page })
        if ($pk -ne $last) {
            $h = New-Text $(if ($pk -eq 'Soft') { 'LOGICIELS INSTALLÉS' } else { "$($SearchPageNames[$pk])".ToUpper() }) 'Muted'
            $h.FontSize = 11
            $h.FontWeight = [Windows.FontWeights]::SemiBold
            $h.Margin = New-Thickness 10 $(if ($last) { 10 } else { 4 }) 10 4; [void]$Ui.SearchList.Children.Add($h); $last = $pk
        }
        $b = [Windows.Controls.Border]::new()
        $b.Padding = New-Thickness 10 6 10 6
        $b.CornerRadius = [Windows.CornerRadius]::new(6)
        $b.Cursor = [Windows.Input.Cursors]::Hand
        $b.Background = [Windows.Media.Brushes]::Transparent; $b.Tag = $i
        $g = [Windows.Controls.Grid]::new()
        $c0 = [Windows.Controls.ColumnDefinition]::new()
        $c0.Width = [Windows.GridLength]::new(30)
        [void]$g.ColumnDefinitions.Add($c0)
        [void]$g.ColumnDefinitions.Add([Windows.Controls.ColumnDefinition]::new())
        $ic = New-Text ([string][char]$glyph[$pk])
        $ic.FontFamily = $FontIcon
        $ic.FontSize = 15
        $ic.VerticalAlignment = 'Center'
        $ic.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'AccentBrush')
        $sp = [Windows.Controls.StackPanel]::new(); [Windows.Controls.Grid]::SetColumn($sp, 1)
        $t1 = [Windows.Controls.TextBlock]::new(); $t1.TextTrimming = 'CharacterEllipsis'; Add-SearchRun $t1 "$($u.Title)" $q
        $sep = '  {0}  ' -f [char]0x203A
        if ($u.Kind -eq 'app') {
            $path = "Applications${sep}Mettre à jour"
            if ($u.App.To -and $u.App.Src) { $path += "  ·  mise à jour disponible ($($u.App.To))" }
        } else {
            $path = @(@($SearchPageNames[$u.Page], $(if ($u.Kind -ne 'card' -and $u.Card) { $u.Card })) | Where-Object { $_ }) -join $sep
        }
        $t2 = New-Text $path 'Muted'; $t2.FontSize = 11; $t2.TextWrapping = 'NoWrap'; $t2.TextTrimming = 'CharacterEllipsis'
        [void]$sp.Children.Add($t1); [void]$sp.Children.Add($t2)
        [void]$g.Children.Add($ic); [void]$g.Children.Add($sp); $b.Child = $g
        $b.Add_MouseEnter({ param($s, $e) Set-SearchSel ([int]$s.Tag) })
        $b.Add_MouseLeftButtonUp({ param($s, $e) Open-SearchResult ([int]$s.Tag) })
        [void]$Ui.SearchList.Children.Add($b); $i++
    }
    $Ui.SearchPop.IsOpen = $true
    if ($SearchUI.Shown.Count) { Set-SearchSel 0 }
}
# titre avec les mots de la recherche en gras et en couleur d'accent (comparaison sans accents ni majuscules)
# un caractère par caractère d'origine (positions identiques) ; moitié d'une paire de substitution (emoji...) gardée telle
# quelle : Normalize levait une exception sur un caractère isolé et la recherche échouait à chaque frappe
function Get-FlatText([string]$T) { -join ($T.ToCharArray() | ForEach-Object { if ([char]::IsSurrogate($_)) { "$_" } else { $d = "$_".Normalize([Text.NormalizationForm]::FormD); "$($d[0])".ToLowerInvariant() } }) }
function Add-SearchRun($Tb, [string]$Text, [string]$Query) {
    $flat = Get-FlatText $Text
    $mark = New-Object bool[] $Text.Length
    foreach ($w in ($Query -split '\s+')) {
        $wn = Get-FlatText $w
        if ($wn.Length -lt 2) { continue }
        $k = $flat.IndexOf($wn); if ($k -lt 0 -and $wn.Length -gt 3) { $wn = $wn.Substring(0, $wn.Length - 1); $k = $flat.IndexOf($wn) }
        if ($k -ge 0) { for ($x = $k; $x -lt $k + $wn.Length; $x++) { $mark[$x] = $true } }
    }
    $i = 0
    while ($i -lt $Text.Length) {
        $j = $i; while ($j -lt $Text.Length -and $mark[$j] -eq $mark[$i]) { $j++ }
        $r = [Windows.Documents.Run]::new($Text.Substring($i, $j - $i))
        if ($mark[$i]) {
            $r.FontWeight = [Windows.FontWeights]::Bold
            $r.SetResourceReference([Windows.Documents.TextElement]::ForegroundProperty, 'AccentBrush')
        } else {
            $r.FontWeight = [Windows.FontWeights]::SemiBold
        }
        $Tb.Inlines.Add($r); $i = $j
    }
}
function Set-SearchSel([int]$I) {
    $SearchUI.Sel = $I
    foreach ($c in $Ui.SearchList.Children) {
        if ($c -is [Windows.Controls.Border]) {
            if ([int]$c.Tag -eq $I) {
                $c.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, 'BtnBrush')
                $c.BringIntoView()
            } else {
                $c.Background = [Windows.Media.Brushes]::Transparent
            }
        }
    }
}
# ouverture : page de l'élément, défilement jusqu'à lui et surbrillance temporaire (2 s)
function Open-SearchResult([int]$I) {
    if ($I -lt 0 -or $I -ge $SearchUI.Shown.Count) { return }
    $u = $SearchUI.Shown[$I]
    $Ui.SearchPop.IsOpen = $false; $Ui.GlobalSearch.Text = ''
    if ($u.Kind -eq 'app') { Set-AppsMode 'Mine'; Show-Page 'Apps'; if ($SoftUI.Win) { $SoftUI.Find.Text = "$($u.App.Name)" }; return }
    Show-Page $u.Page
    $el = $u.El
    # Paramètres : rubrique contenant l'élément affichée d'abord
    if ($u.Page -eq 'Settings' -and $SetUI.SecCards) {
        foreach ($k in $SettingsSections.Keys) { foreach ($t in $SettingsSections[$k].C) { $c = $SetUI.SecCards[$t]; $x = $el; while ($x -and $x -ne $c) { $x = [Windows.LogicalTreeHelper]::GetParent($x) }; if ($x) { Show-SettingsSection $k } } }
    }
    [void]$Window.Dispatcher.BeginInvoke([Action]{
        try {
            # parents repliés (catégorie du Nettoyage, liste réduite) : rouverts pour rendre l'élément visible
            $p = $el
            while ($p) {
                if ($p -is [Windows.UIElement] -and "$($p.Visibility)" -eq 'Collapsed' -and $p -ne $el) { $p.Visibility = 'Visible' }
                $p = [Windows.LogicalTreeHelper]::GetParent($p)
            }
            $el.BringIntoView()
            Set-SearchFlash $el
        } catch { Write-Ignored 'Recherche : affichage de l''élément' $_ }
    }.GetNewClosure(), [Windows.Threading.DispatcherPriority]::Loaded)
}
function Set-SearchFlash($El) {
    if ($El -isnot [Windows.Controls.Border]) { return }
    $bp = [Windows.Controls.Border]::BackgroundProperty
    $orig = $El.ReadLocalValue($bp)
    $El.SetResourceReference($bp, 'PendBgBrush')
    $tm = [Windows.Threading.DispatcherTimer]::new(); $tm.Interval = [TimeSpan]::FromSeconds(2)
    $tm.Tag = @{ El = $El; Orig = $orig }
    $tm.Add_Tick({ param($s, $e)
        $s.Stop()
        $d = $s.Tag
        if ($d.Orig -eq [Windows.DependencyProperty]::UnsetValue) { $d.El.ClearValue([Windows.Controls.Border]::BackgroundProperty) } else { $d.El.SetValue([Windows.Controls.Border]::BackgroundProperty, $d.Orig) }
    })
    $tm.Start()
}
$Ui.GlobalSearch.Add_TextChanged({ Show-SearchResult })
# champ actif : contour d'accent, fond clair ; clic n'importe où dans la pastille = curseur dans le champ
$Ui.GlobalSearch.Add_GotKeyboardFocus({
    # seul le contour change (bleu) : fond et épaisseur fixes, le champ reste contrasté sur l'en-tête
    $Ui.SearchBox.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, 'AccentBrush'); $Ui.SearchKey.Visibility = 'Collapsed'
    if ("$($Ui.GlobalSearch.Text)".Trim().Length -ge 2) { $Ui.SearchPop.IsOpen = $true }
})
$Ui.GlobalSearch.Add_LostKeyboardFocus({
    $Ui.SearchBox.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, 'LineBrush')
    if (-not $Ui.GlobalSearch.Text -and $SearchLay.ShowKey) { $Ui.SearchKey.Visibility = 'Visible' }
    if ($SearchLay.Expanded) { Hide-SearchOverlay }
})
# ---------- Champ de recherche adaptatif : largeur 360 px au plus, rétréci avec la fenêtre (raccourci Ctrl+F puis texte
# d'aide raccourcis au besoin) ; sous 170 px disponibles, remplacé par une icône qui ouvre le champ par-dessus les onglets
$SearchLay = @{ Compact = $false; Expanded = $false; ShowKey = $true }
function Update-SearchLayout {
    # bandeau Point de restauration (Système) : description masquée en fenêtre étroite, le titre et le bouton restent lisibles
    if ($Ui.RestoreDesc) { $Ui.RestoreDesc.Visibility = $(if ($Window.ActualWidth -lt 1000) { 'Collapsed' } else { 'Visible' }) }
    if ($SearchLay.Expanded) { return }
    $avail = $Ui.HeaderBar.ColumnDefinitions[1].ActualWidth - 24
    # hystérésis de 20 px : pas de bascule répétée autour du seuil (l'icône prend elle-même de la place)
    $compact = $(if ($SearchLay.Compact) { $avail -lt 190 } else { $avail -lt 170 })
    $was = $SearchLay.Compact; $SearchLay.Compact = $compact
    $Ui.SearchBox.Visibility = $(if ($compact) { 'Collapsed' } else { 'Visible' })
    $Ui.SearchIconBtn.Visibility = $(if ($compact) { 'Visible' } else { 'Collapsed' })
    # largeur suivie en douceur (pas de saut quand les onglets changent de format) ; passage icône <-> champ en fondu
    if ($compact -ne $was) {
        if ($compact) { Start-Transition $Ui.SearchIconBtn -Scale 0.8 -Ms 160 }
        else {
            $Ui.SearchBox.BeginAnimation([Windows.FrameworkElement]::WidthProperty, $null)
            $Ui.SearchBox.Width = 120
            Start-Transition $Ui.SearchBox -Scale 0.92 -Ms 200
        }
    }
    if (-not $compact) {
        # centré sur toute la largeur de l'en-tête dès que la place le permet de part et d'autre : le champ ne bouge plus
        # quand les onglets changent de largeur (pastille de modifications en attente, format des onglets) ;
        # sinon centré dans l'espace libre entre les onglets et les boutons de droite
        $hb = $Ui.HeaderBar; $hw = $hb.ActualWidth
        $l = $hb.ColumnDefinitions[0].ActualWidth + 12; $r = $hw - $hb.ColumnDefinitions[2].ActualWidth - $hb.ColumnDefinitions[3].ActualWidth - 12
        $sym = 2 * [math]::Min($hw / 2 - $l, $r - $hw / 2)
        if ($sym -ge 220) {
            [Windows.Controls.Grid]::SetColumn($Ui.SearchBox, 0)
            [Windows.Controls.Grid]::SetColumnSpan($Ui.SearchBox, 4)
            $w = $sym
        }
        else { [Windows.Controls.Grid]::SetColumn($Ui.SearchBox, 1); [Windows.Controls.Grid]::SetColumnSpan($Ui.SearchBox, 1); $w = $avail }
        Set-SearchWidth ([math]::Min([double]360, [math]::Max([double]120, $w)))
    }
    $SearchLay.ShowKey = $avail -ge 300
    if (-not $Ui.GlobalSearch.IsKeyboardFocusWithin) {
        $Ui.SearchKey.Visibility = $(if ($SearchLay.ShowKey -and -not $Ui.GlobalSearch.Text) { 'Visible' } else { 'Collapsed' })
    }
    $Ui.SearchHint.Text = $(if ($avail -lt 250) { 'Rechercher' } else { 'Rechercher dans l''application' })
}
function Set-SearchWidth([double]$To) {
    $b = $Ui.SearchBox; $from = $b.ActualWidth
    if ([math]::Abs($from - $To) -lt 1) { return }
    # rétrécissement immédiat (le champ ne déborde jamais sur les onglets), élargissement animé
    if (-not (Test-Anim) -or $from -le 0 -or $To -lt $from) {
        $b.BeginAnimation([Windows.FrameworkElement]::WidthProperty, $null)
        $b.Width = $To
        return
    }
    $b.BeginAnimation([Windows.FrameworkElement]::WidthProperty, (New-Anim $from $To 200))
}
# icône (ou Ctrl+F) en fenêtre étroite : champ affiché sur toute la largeur des onglets jusqu'à la perte du focus / Échap
function Show-SearchOverlay {
    $SearchLay.Expanded = $true
    $b = $Ui.SearchBox
    [Windows.Controls.Grid]::SetColumn($b, 0); [Windows.Controls.Grid]::SetColumnSpan($b, 2); [Windows.Controls.Panel]::SetZIndex($b, 10)
    $b.BeginAnimation([Windows.FrameworkElement]::WidthProperty, $null)
    $b.Width = [double]::NaN
    $b.HorizontalAlignment = 'Stretch'
    $b.Visibility = 'Visible'
    $Ui.SearchIconBtn.Visibility = 'Collapsed'
    $Ui.SearchKey.Visibility = 'Collapsed'
    $Ui.SearchHint.Text = 'Rechercher dans l''application'
    Start-Transition $b -Dx 16 -Ms 180
    [void]$Ui.GlobalSearch.Focus(); $Ui.GlobalSearch.SelectAll()
}
function Hide-SearchOverlay {
    $SearchLay.Expanded = $false
    $b = $Ui.SearchBox
    [Windows.Controls.Grid]::SetColumn($b, 1); [Windows.Controls.Grid]::SetColumnSpan($b, 1); [Windows.Controls.Panel]::SetZIndex($b, 0)
    $b.HorizontalAlignment = 'Center'; $b.Width = 120; $SearchLay.Compact = $true
    Update-SearchLayout
}
$Ui.SearchIconBtn.Add_Click({ Show-SearchOverlay })
$Ui.HeaderBar.Add_SizeChanged({ [void]$Window.Dispatcher.BeginInvoke([Action]{ Update-SearchLayout }, [Windows.Threading.DispatcherPriority]::Loaded) })
$Ui.TabStrip.Add_SizeChanged({ [void]$Window.Dispatcher.BeginInvoke([Action]{ Update-SearchLayout }, [Windows.Threading.DispatcherPriority]::Loaded) })
$Ui.SearchBox.Add_MouseLeftButtonDown({ [void]$Ui.GlobalSearch.Focus() })
$Ui.GlobalSearch.Add_PreviewKeyDown({
    param($s, $e)
    $n = @($SearchUI.Shown).Count
    switch ("$($e.Key)") {
        'Down'   { if ($n) { Set-SearchSel (($SearchUI.Sel + 1) % $n) }; $e.Handled = $true }
        'Up'     { if ($n) { Set-SearchSel (($SearchUI.Sel - 1 + $n) % $n) }; $e.Handled = $true }
        'Return' { Open-SearchResult $SearchUI.Sel; $e.Handled = $true }
        'Escape' {
            $Ui.SearchPop.IsOpen = $false
            $Ui.GlobalSearch.Text = ''
            [void]$Window.Focus()
            if ($SearchLay.Expanded) { Hide-SearchOverlay }
            $e.Handled = $true
        }
    }
})
# clic en dehors d'un champ de saisie : le champ perd le focus (curseur qui ne clignote plus, contour normal)
$ClearTextFocus = {
    param($s, $e)
    $f = [Windows.Input.Keyboard]::FocusedElement
    if ($f -isnot [Windows.Controls.TextBox]) { return }
    $o = $e.OriginalSource
    while ($o) {
        if ($o -eq $f) { return }
        $o = $(if ($o -is [Windows.Media.Visual] -or $o -is [Windows.Media.Media3D.Visual3D]) { [Windows.Media.VisualTreeHelper]::GetParent($o) } else { [Windows.LogicalTreeHelper]::GetParent($o) })
    }
    [Windows.Input.Keyboard]::ClearFocus()
    [Windows.Input.FocusManager]::SetFocusedElement($s, $null)
}
$Window.Add_PreviewMouseLeftButtonDown($ClearTextFocus)
# Ctrl+F : placer le curseur dans la recherche globale
$Window.Add_PreviewMouseWheel($ZoomWheel); $Window.Add_PreviewKeyDown($ZoomKeys)
Set-WindowZoom $Window
$Window.Add_PreviewKeyDown({
    param($s, $e)
    if ($e.Key -eq 'F' -and ([Windows.Input.Keyboard]::Modifiers -band [Windows.Input.ModifierKeys]::Control)) {
        if ($Ui.SearchBox.Visibility -ne 'Visible') { Show-SearchOverlay } else { [void]$Ui.GlobalSearch.Focus(); $Ui.GlobalSearch.SelectAll() }
        $e.Handled = $true
    }
})

