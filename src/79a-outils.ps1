# ---------- Onglet Outils : licence Windows, réseaux Wi-Fi enregistrés, fichier hosts, menu clic droit de l'Explorateur,
# variables d'environnement. Cartes construites à la 1re ouverture de l'onglet ; lectures longues en tâche de fond.
$ToolsUI = @{ Built = $false }
$HostsFile = Join-Path $env:windir 'System32\drivers\etc\hosts'
$HostsBackup = Join-Path (Get-LogPath 'Etat') 'hosts.sauvegarde'
$HostsMarkA = '# >>> Oliv_Maintenance : blocage pubs et traqueurs'
$HostsMarkB = '# <<< Oliv_Maintenance'


# ---- éléments communs : ligne (survol, hors index de la recherche), bouton icône, saisie de texte
function New-ToolRow([string]$Main, [string]$Sub, [object[]]$Buttons, [string]$Tip) {
    $b = [Windows.Controls.Border]::new(); $b.Style = $Window.FindResource('SvcRow'); $b.Padding = New-Thickness 10 4 6 4; $b.Margin = New-Thickness 30 1 10 1
    $g = [Windows.Controls.Grid]::new(); foreach ($w in 0, -1) { [void]$g.ColumnDefinitions.Add($(if ($w) { $c = [Windows.Controls.ColumnDefinition]::new(); $c.Width = [Windows.GridLength]::Auto; $c } else { New-SvcCol 0 })) }
    $sp = [Windows.Controls.StackPanel]::new(); $sp.VerticalAlignment = 'Center'; $sp.Margin = New-Thickness 0 0 8 0
    $t1 = New-Text $Main; $t1.FontWeight = [Windows.FontWeights]::SemiBold; $t1.TextTrimming = 'CharacterEllipsis'; [void]$sp.Children.Add((New-LabelWithHelp $t1 $Tip))
    $t2 = $null; if ($Sub) { $t2 = New-Text $Sub 'Muted'; $t2.FontSize = 12; $t2.TextTrimming = 'CharacterEllipsis'; [void]$sp.Children.Add($t2) }
    [void]$g.Children.Add($sp)
    $bp = [Windows.Controls.StackPanel]::new(); $bp.Orientation = 'Horizontal'; $bp.VerticalAlignment = 'Center'
    foreach ($x in $Buttons) { if ($x) { [void]$bp.Children.Add($x) } }
    [Windows.Controls.Grid]::SetColumn($bp, 1); [void]$g.Children.Add($bp)
    $b.Child = $g
    @{ Row = $b; Main = $t1; Sub = $t2; Btns = $bp }
}
function New-ToolIconButton([int]$Glyph, [string]$Tip, $Tag, [scriptblock]$Click) {
    $x = [Windows.Controls.Button]::new(); $x.Style = $Window.FindResource('IconBtn'); $x.Content = [string][char]$Glyph; $x.Width = 32; $x.Height = 28; $x.Margin = New-Thickness 2 0 0 0
    $x.ToolTip = $Tip; $x.Tag = $Tag; $x.Add_Click($Click); $x
}
function New-ToolButton([string]$Text, $Tag, [scriptblock]$Click, [string]$StyleKey = 'ActionBtn') {
    $x = New-Button $Text $StyleKey; $x.Height = 30; $x.MinWidth = 0; $x.Padding = New-Thickness 12 0 12 0; $x.Margin = New-Thickness 0 0 8 0; $x.Tag = $Tag; $x.Add_Click($Click); $x
}
function New-ToolBar([object[]]$Buttons) {
    $w = [Windows.Controls.WrapPanel]::new(); $w.Margin = New-Thickness 38 8 10 12
    foreach ($x in $Buttons) { if ($x) { $x.Margin = New-Thickness 0 0 8 4; [void]$w.Children.Add($x) } }
    $w
}
function New-ToolTextBox([string]$Text, [bool]$Multi, [double]$Height = 0) {
    $t = [Windows.Controls.TextBox]::new(); $t.Text = $Text; $t.Padding = New-Thickness 8 6 8 6; $t.FontSize = 13
    $t.SetResourceReference([Windows.Controls.Control]::BackgroundProperty, 'BgBrush'); $t.SetResourceReference([Windows.Controls.Control]::ForegroundProperty, 'FgBrush')
    $t.SetResourceReference([Windows.Controls.Control]::BorderBrushProperty, 'LineBrush'); $t.SetResourceReference([Windows.Controls.TextBox]::CaretBrushProperty, 'FgBrush')
    if ($Multi) { $t.AcceptsReturn = $true; $t.TextWrapping = 'NoWrap'; $t.VerticalScrollBarVisibility = 'Auto'; $t.HorizontalScrollBarVisibility = 'Auto'; $t.FontFamily = [Windows.Media.FontFamily]::new('Consolas'); $t.Height = $(if ($Height) { $Height } else { 220 }) }
    $t
}
# saisie : champs @(@{ L = libellé; V = valeur; M = multiligne; H = hauteur }) ; renvoie les valeurs, ou $null si annulé
function Read-ToolInput([string]$Message, [object[]]$Fields, [string]$OkText = 'Enregistrer', [int]$Width = 640) {
    $sp = [Windows.Controls.StackPanel]::new(); $boxes = @()
    foreach ($f in $Fields) {
        if ($f.L) { $l = New-Text $f.L 'Muted'; $l.Margin = New-Thickness 0 6 0 4; [void]$sp.Children.Add($l) }
        $tb = New-ToolTextBox "$($f.V)" ([bool]$f.M) ([double]$f.H); if ($f.RO) { $tb.IsReadOnly = $true; $tb.Opacity = 0.7 }
        [void]$sp.Children.Add($tb); $boxes += $tb
    }
    $first = @($boxes | Where-Object { -not $_.IsReadOnly })[0]
    $v = Show-Dialog $Message 'Question' @(@{ T = 'Annuler'; V = 'no'; C = $true }, @{ T = $OkText; V = 'ok'; K = 'OkBtn' }) $null $null $Width $sp { param($d, $bp) $d.Tag = $first; foreach ($c in $bp.Children) { $c.IsDefault = $c.Name -eq 'OkBtn' } }
    if ($v -ne 'ok') { return $null }
    , @($boxes | ForEach-Object { $_.Text })
}

