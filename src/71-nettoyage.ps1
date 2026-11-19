$CleanUI  = [ordered]@{}
$GroupUI  = [ordered]@{}
$Sync.CleanSizes = [hashtable]::Synchronized(@{})
# éléments absents du poste, signalés par la mesure des tailles (test Present) : lignes retirées de l'affichage
$Sync.CleanAbsent = [hashtable]::Synchronized(@{})

# taille affichée ; jamais « 0 o » : $Zero (« vide » par défaut) pour une taille nulle
function Format-SizeUi([double]$Bytes, [string]$Zero = 'vide') {
    if ($Bytes -le 0) { return $Zero }
    if ($Bytes -ge 1GB) {
        '{0:N2} Go' -f ($Bytes / 1GB)
    } elseif ($Bytes -ge 1MB) {
        '{0:N2} Mo' -f ($Bytes / 1MB)
    } elseif ($Bytes -ge 1KB) {
        '{0:N0} Ko' -f ($Bytes / 1KB)
    } else {
        '{0:N0} o' -f $Bytes
    }
}

function Invoke-CleanGroupToggle([string]$Grp) {
    $g = $GroupUI[$Grp]
    $v = [bool]$g.Check.IsChecked
    foreach ($id in $g.Items) { $CleanUI[$id].Check.IsChecked = $v }
    Update-GroupState $Grp; Update-CleanSummary
}
function Invoke-CleanItemToggle([string]$Id) {
    $c = $CleanUI[$Id]
    Update-GroupState $c.Group; Update-CleanSummary
}
$CleanGroupClick = { param($s, $e) Invoke-CleanGroupToggle ([string]$s.Tag) }
$CleanItemClick  = { param($s, $e) Invoke-CleanItemToggle ([string]$s.Tag) }
$CleanArrowClick = {
    param($s, $e)
    $g = $GroupUI[[string]$s.Tag]
    $open = $g.Panel.Visibility -ne 'Visible'
    Set-Fold $g.Panel $open
    $s.Content = [string][char]$(if ($open) { 0xE70D } else { 0xE76C })
}
$CleanRowUp = {
    param($s, $e)
    if (Test-InButton $e.OriginalSource) { return }
    $info = $s.Tag
    if (-not $info.Check.IsEnabled) { return }
    $info.Check.IsChecked = -not [bool]$info.Check.IsChecked
    if ($info.Kind -eq 'G') { Invoke-CleanGroupToggle $info.Key } else { Invoke-CleanItemToggle $info.Key }
}

function New-CleanLine([double]$Indent, $Check, [string]$Kind, [string]$Key) {
    $b = [Windows.Controls.Border]::new()
    $b.Style = $Window.FindResource('HoverRow')
    $b.Tag = @{ Check = $Check; Kind = $Kind; Key = $Key }
    $b.Add_MouseLeftButtonUp($CleanRowUp)
    $g = [Windows.Controls.Grid]::new()
    $g.Margin = New-Thickness $Indent 3 8 3
    foreach ($w in 'Auto', 'Auto', '*', 'Auto') {
        $cd = [Windows.Controls.ColumnDefinition]::new()
        if ($w -eq 'Auto') { $cd.Width = [Windows.GridLength]::Auto }
        [void]$g.ColumnDefinitions.Add($cd)
    }
    $b.Child = $g
    @{ Border = $b; Grid = $g }
}

function Initialize-CleanTree {
    $Ui.CleanTree.Children.Clear()
    $present = @($CleanItems | ForEach-Object { $_.Group } | Select-Object -Unique)
    foreach ($grp in @(@($CleanGroupOrder | Where-Object { $_ -in $present }) + @($present | Where-Object { $_ -notin $CleanGroupOrder }))) {
        $gcb = [Windows.Controls.CheckBox]::new()
        $gcb.Style = $Window.FindResource('TaskCheck'); $gcb.Tag = $grp; $gcb.VerticalAlignment = 'Center'; $gcb.Margin = New-Thickness 0 0 4 0
        $gcb.Add_Click($CleanGroupClick)
        $line = New-CleanLine 0 $gcb 'G' $grp
        $hdr = $line.Grid; $head = $line.Border
        $arrow = [Windows.Controls.Button]::new()
        $arrow.Style = $Window.FindResource('IconBtn'); $arrow.Width = 26; $arrow.Height = 26; $arrow.FontSize = 10; $arrow.Margin = New-Thickness 0 0 2 0
        $arrow.Content = [string][char]0xE70D; $arrow.Tag = $grp; $arrow.Add_Click($CleanArrowClick)
        # intertitre de catégorie : 14 (titres de carte 16, texte courant 13, texte secondaire 12)
        $lbl = New-Text $grp; $lbl.FontSize = 14; $lbl.FontWeight = [Windows.FontWeights]::SemiBold; $lbl.VerticalAlignment = 'Center'
        $sz = New-Text ''; $sz.FontSize = 14; $sz.FontWeight = [Windows.FontWeights]::SemiBold; $sz.VerticalAlignment = 'Center'
        [Windows.Controls.Grid]::SetColumn($gcb, 1); [Windows.Controls.Grid]::SetColumn($lbl, 2); [Windows.Controls.Grid]::SetColumn($sz, 3)
        [void]$hdr.Children.Add($arrow); [void]$hdr.Children.Add($gcb); [void]$hdr.Children.Add($lbl); [void]$hdr.Children.Add($sz)
        # séparateur discret avant chaque catégorie, sauf la première
        $sp = $null
        if ($Ui.CleanTree.Children.Count) {
            $sp = [Windows.Controls.Border]::new()
            $sp.Height = 1
            $sp.Margin = New-Thickness 8 6 8 6
            $sp.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, 'LineBrush')
            $sp.Opacity = 0.6
            [void]$Ui.CleanTree.Children.Add($sp)
        }
        [void]$Ui.CleanTree.Children.Add($line.Border)
        $panel = [Windows.Controls.StackPanel]::new()
        [void]$Ui.CleanTree.Children.Add($panel)
        $ids = [System.Collections.ArrayList]::new()
        foreach ($it in (Get-SortedByLabel ($CleanItems | Where-Object { $_.Group -eq $grp }))) {
            $cb = [Windows.Controls.CheckBox]::new()
            $cb.Style = $Window.FindResource('TaskCheck'); $cb.Tag = $it.Id; $cb.VerticalAlignment = 'Center'; $cb.Margin = New-Thickness 0 0 4 0
            $cb.Add_Click($CleanItemClick)
            $line = New-CleanLine 52 $cb 'I' $it.Id
            $row = $line.Grid
            $line.Border.ToolTip = $it.Tip; [Windows.Controls.ToolTipService]::SetShowDuration($line.Border, 30000)
            $t = New-Text $it.Label; $t.VerticalAlignment = 'Center'
            $s2 = New-Text '' 'Muted'; $s2.FontSize = 13; $s2.VerticalAlignment = 'Center'; Set-CleanSizePending $s2
            [Windows.Controls.Grid]::SetColumn($cb, 1); [Windows.Controls.Grid]::SetColumn($t, 2); [Windows.Controls.Grid]::SetColumn($s2, 3)
            [void]$row.Children.Add($cb); [void]$row.Children.Add($t); [void]$row.Children.Add($s2)
            [void]$panel.Children.Add($line.Border)
            $CleanUI[$it.Id] = @{ Check = $cb; Size = $s2; Row = $line.Border; Group = $grp; Item = $it; Label = "$grp $($it.Label)" }
            [void]$ids.Add($it.Id)
        }
        $GroupUI[$grp] = @{ Check = $gcb; Size = $sz; Panel = $panel; Arrow = $arrow; Items = $ids; Head = $head; Sep = $sp }
    }
}

function Update-GroupState([string]$Grp) {
    $g = $GroupUI[$Grp]
    $n = @($g.Items | Where-Object { $CleanUI[$_].Check.IsChecked }).Count
    $g.Check.IsChecked = $(if ($n -eq 0) { $false } elseif ($n -eq $g.Items.Count) { $true } else { $null })
}

function Get-CleanSelection { @($CleanUI.Keys | Where-Object { $CleanUI[$_].Check.IsChecked }) }

function Get-CleanSize([string]$Id) {
    if ($Sync.CleanSizes.ContainsKey($Id)) { return [double]$Sync.CleanSizes[$Id] }
    $null
}

# lignes des éléments absents (protection système désactivée, pas de Windows.old...) retirées ; catégorie vide masquée
function Remove-AbsentCleanItem {
    foreach ($id in @($Sync.CleanAbsent.Keys)) {
        $c = $CleanUI[$id]; if (-not $c) { continue }
        $c.Check.IsChecked = $false; $c.Row.Visibility = 'Collapsed'
        $g = $GroupUI[$c.Group]; [void]$g.Items.Remove($id); $CleanUI.Remove($id)
        if (-not $g.Items.Count) { foreach ($e in $g.Head, $g.Panel, $g.Sep) { if ($e) { $e.Visibility = 'Collapsed' } } }
        else { Update-GroupState $c.Group }
    }
}
# navigateurs détectés par la mesure en arrière-plan : lignes ajoutées (arbre reconstruit, sélection conservée), une seule
# fois par liste différente
function Sync-CleanBrowser {
    $br = @($Sync.CleanBrowsers); if (-not $Sync.CleanBrowsers) { return }
    $sig = (@($br | ForEach-Object { $_.Id }) -join '|')
    if ($sig -eq $script:CleanBrSig) { return }
    $script:CleanBrSig = $sig
    $keep = @(Get-CleanSelection)
    $script:CleanItems = @($CleanItems | Where-Object { $_.Group -ne 'Cache des navigateurs' }) + @($br | ForEach-Object { [pscustomobject]@{ Id = $_.Id; Group = $_.Group; Label = $_.Label; Tip = $_.Tip; Paths = $_.Paths; Targets = { } } })
    $CleanUI.Clear(); $GroupUI.Clear()
    Initialize-CleanTree
    foreach ($id in $keep) { if ($CleanUI[$id]) { $CleanUI[$id].Check.IsChecked = $true } }
    foreach ($g in @($GroupUI.Keys)) { Update-GroupState $g }
    $busy = [bool]$Sync.Running; foreach ($c in $CleanUI.Values) { $c.Check.IsEnabled = -not $busy }
    $SearchUI.Dirty = $true
}
# taille en cours de calcul : « ... » qui pulse doucement (animations activées), puis valeur affichée en fondu
function Set-CleanSizePending($Tb) {
    $Tb.Text = '...'; $Tb.Tag = 'pending'
    if (Test-Anim) {
        $a = [Windows.Media.Animation.DoubleAnimation]::new(1, 0.25, [Windows.Duration]::new([TimeSpan]::FromMilliseconds(700)))
        $a.AutoReverse = $true; $a.RepeatBehavior = [Windows.Media.Animation.RepeatBehavior]::Forever
        $Tb.BeginAnimation([Windows.UIElement]::OpacityProperty, $a)
    }
}
function Set-CleanSizeValue($Tb, [string]$Text) {
    if ($Tb.Text -eq $Text -and $Tb.Tag -ne 'pending') { return }
    $was = $Tb.Tag -eq 'pending'; $Tb.Tag = $null; $Tb.Text = $Text
    $Tb.BeginAnimation([Windows.UIElement]::OpacityProperty, $null)
    if ($was -and (Test-Anim)) { $Tb.BeginAnimation([Windows.UIElement]::OpacityProperty, [Windows.Media.Animation.DoubleAnimation]::new(0, 1, [Windows.Duration]::new([TimeSpan]::FromMilliseconds(200)))) }
    else { $Tb.Opacity = 1 }
}
function Update-CleanSize {
    if ($Sync.CleanBrowsers) { Sync-CleanBrowser }
    if ($Sync.CleanAbsent.Count) { Remove-AbsentCleanItem }
    foreach ($id in @($CleanUI.Keys)) {
        $c = $CleanUI[$id]
        if ($Sync.CleanSizes.ContainsKey($id)) { Set-CleanSizeValue $c.Size $(if ($Sync.CleanSizes[$id] -gt 0) { Format-SizeUi $Sync.CleanSizes[$id] } else { 'vide' }) }
        elseif ($Sync.CleanScanDone) { Set-CleanSizeValue $c.Size 'taille inconnue' }
    }
    foreach ($grp in @($GroupUI.Keys)) {
        $known = @($GroupUI[$grp].Items | Where-Object { $Sync.CleanSizes.ContainsKey($_) })
        $sum = [double]0; foreach ($id in $known) { $sum += $Sync.CleanSizes[$id] }
        $GroupUI[$grp].Size.Text = $(if (-not $known.Count) { '' } elseif ($sum -gt 0) { Format-SizeUi $sum } else { 'vide' })
    }
    try {
        $d = [IO.DriveInfo]::new($env:SystemDrive.TrimEnd(':'))
        # espace à nettoyer : somme de tous les éléments mesurés (si tout est coché)
        $all = [double]0; foreach ($id in @($CleanUI.Keys)) { if ($Sync.CleanSizes.ContainsKey($id)) { $all += $Sync.CleanSizes[$id] } }
        $rc = $(if ($all -gt 0) { '{0} à nettoyer{1}' -f (Format-SizeUi $all), $(if ($Sync.CleanScanDone) { '' } else { ' (calcul en cours)' }) } elseif ($Sync.CleanScanDone) { 'rien à nettoyer' } else { 'calcul de l''espace à nettoyer en cours' })
        $Ui.CleanFree.Text = '{0} d''espace libre sur {1}  ·  {2}' -f (Format-SizeUi $d.AvailableFreeSpace 'Aucun espace libre'), $env:SystemDrive, $rc
    } catch {}
    $Ui.CleanScanText.Text = $(if (-not $Sync.CleanScanDone) { 'Calcul des tailles...' } else { '' })
    Update-CleanSummary
}

function Update-CleanSummary {
    $sel = Get-CleanSelection
    $sum = [double]0; foreach ($id in $sel) { $v = Get-CleanSize $id; if ($null -ne $v) { $sum += $v } }
    $Ui.CleanSel.Text = $(if ($sel.Count) { '{0} {1}  ·  {2}' -f $sel.Count, (Get-Plural $sel.Count 'élément sélectionné' 'éléments sélectionnés'), (Format-SizeUi $sum 'rien à libérer') } else { 'Aucun élément sélectionné' })
    Update-ApplyButton
}

function Start-CleanScan {
    Close-BgJob
    if ($BgJobs.ContainsKey('Clean')) { return }
    $Sync.CleanSizes.Clear()
    $Sync.CleanScanDone = $false; $Sync.CleanScanStop = $false
    foreach ($id in @($CleanUI.Keys)) { Set-CleanSizePending $CleanUI[$id].Size }
    # tailles de groupe, espace à nettoyer et sélection : plus d'anciennes valeurs pendant le nouveau calcul
    Update-CleanSize
    Start-BgJob 'Clean' ($CleanLib + "`n" + $CleanScanScript)
}

Initialize-CleanTree

function Update-RestoreLast {
    $r = $Sync.RestoreLast
    if (-not $r -or $r -eq $Sync.RestoreShown) { return }
    $Sync.RestoreShown = $r
    $Ui.RestoreLast.Text = $(if ($r.Time) { "dernier point`n{0:dd/MM/yyyy HH:mm}" -f $r.Time } elseif ($r.Error) { 'état indisponible' } else { 'aucun point' })
    $Ui.RestoreLast.ToolTip = $(if ($r.Desc) { $r.Desc } else { $null })
    # « Restaurer... » seulement s'il existe au moins un point
    $Ui.RestoreBack.Visibility = $(if ($r.Time) { 'Visible' } else { 'Collapsed' })
}
function Format-LastStamp([string]$Label, $Time, [string]$Suffix = '') {
    if ($null -eq $Time) { if ($Label -like '*rapport*') { 'aucun rapport' } else { 'jamais exécuté' } }
    else { "$Label`n{0:dd/MM/yyyy HH:mm}{1}" -f $Time, $(if ($Suffix) { " ($Suffix)" } else { '' }) }
}

