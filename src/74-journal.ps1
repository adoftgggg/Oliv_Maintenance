# ---------- Journal : lignes colorées par niveau, filtre par niveau (tout / avertissements et erreurs / erreurs),
# messages de l'application (affichés par défaut, masquables) et recherche de texte (surlignée).
# Toutes les lignes reçues depuis le lancement sont gardées en mémoire (20 000 au plus) ; la zone n'affiche que les
# $LogView.Max dernières lignes qui passent le filtre (au-delà : RichTextBox trop lente), le fichier journal garde tout.
$LogView = @{ Lines = [Collections.Generic.List[string]]::new(); Pending = [Collections.Generic.List[string]]::new(); Rebuild = $false
             Cnt = @{ E = 0; W = 0; A = 0; Shown = 0 }; Level = 'All'; Text = ''; App = $true; Max = 3000; Hidden = 0 }
# découpe d'une ligne « HH:mm:ss [NIVEAU] message » ; $null pour une ligne libre (sortie multi-ligne, séparateur)
function Get-LogLinePart([string]$L) {
    if ($L -match '^(\d{2}:\d{2}:\d{2}) \[([A-Z]+)\s*\] ?(.*)$') { @{ Time = $Matches[1]; Level = $Matches[2]; Msg = $Matches[3] } } else { $null }
}
function Test-LogLine([string]$L) {
    if (-not $LogView.App -and $L -match '^\d{2}:\d{2}:\d{2} \[APP  \]') { return $false }
    if ($LogView.Level -eq 'Err' -and $L -notmatch '\[ERROR\]') { return $false }
    if ($LogView.Level -eq 'Warn' -and $L -notmatch '\[(WARN |ERROR)\]') { return $false }
    if ($LogView.Text -and $L.IndexOf($LogView.Text, [StringComparison]::OrdinalIgnoreCase) -lt 0) { return $false }
    $true
}
# couleur du niveau et du message (clés de ressources : suivent le thème clair / sombre)
$LogLevelBrush = @{ BILAN = 'OkFgBrush'; OK = 'OkFgBrush'; WARN = 'WarnFgBrush'; ERROR = 'ErrFgBrush'; STEP = 'HeadBrush'; CMD = 'HeadBrush' }
$LogMsgBrush = @{ WARN = 'WarnFgBrush'; ERROR = 'ErrFgBrush'; STEP = 'HeadBrush'; OUT = 'MutedBrush'; APP = 'MutedBrush' }
function Add-LogRun($Inlines, [string]$Text, [string]$Brush) {
    $t = $LogView.Text; $i = 0
    while ($t -and $i -lt $Text.Length) {
        $j = $Text.IndexOf($t, $i, [StringComparison]::OrdinalIgnoreCase); if ($j -lt 0) { break }
        if ($j -gt $i) {
            $r = [Windows.Documents.Run]::new($Text.Substring($i, $j - $i))
            if ($Brush) { $r.SetResourceReference([Windows.Documents.TextElement]::ForegroundProperty, $Brush) }
            $Inlines.Add($r)
        }
        $h = [Windows.Documents.Run]::new($Text.Substring($j, $t.Length)); $h.FontWeight = 'Bold'
        $h.SetResourceReference([Windows.Documents.TextElement]::BackgroundProperty, 'SelBrush')
        $h.SetResourceReference([Windows.Documents.TextElement]::ForegroundProperty, 'OnAccentBrush')
        $Inlines.Add($h); $i = $j + $t.Length
    }
    if ($i -lt $Text.Length) {
        $r = [Windows.Documents.Run]::new($Text.Substring($i))
        if ($Brush) { $r.SetResourceReference([Windows.Documents.TextElement]::ForegroundProperty, $Brush) }
        $Inlines.Add($r)
    }
}
# police : message en Segoe UI (police de l'application), heure et niveau en Consolas (colonnes alignées).
# Zoom de la zone (Ctrl + molette, Ctrl + / -, Ctrl + 0, boutons) : tailles de base x $LogView.Zoom, mémorisé dans _etat.
$LogMono = [Windows.Media.FontFamily]::new('Consolas')
$LogZoomFile = Join-Path (Get-LogPath 'Etat') 'journal_zoom.txt'
$LogView.Zoom = 1.0
try {
    $z = [double]::Parse([IO.File]::ReadAllText($LogZoomFile).Trim(), [Globalization.CultureInfo]::InvariantCulture)
    if ($z -ge 0.7 -and $z -le 2) { $LogView.Zoom = $z }
} catch {
    if (Test-Path -LiteralPath $LogZoomFile) { Write-Ignored 'Lecture du zoom du journal' $_ }
}
# tailles et retrait suspendu (largeur réelle de « 00:00:00  BILAN  » en Consolas gras) pour le zoom courant
function Set-LogMetric {
    $LogView.MsgSize = [math]::Round(13 * $LogView.Zoom, 1); $LogView.MonoSize = [math]::Round(12 * $LogView.Zoom, 1)
    $LogView.Indent = try {
        $ft = [Windows.Media.FormattedText]::new('00:00:00  BILAN  ', [Globalization.CultureInfo]::InvariantCulture, [Windows.FlowDirection]::LeftToRight,
            [Windows.Media.Typeface]::new($LogMono, [Windows.FontStyles]::Normal, [Windows.FontWeights]::Bold, [Windows.FontStretches]::Normal), $LogView.MonoSize, [Windows.Media.Brushes]::Black)
        [math]::Ceiling($ft.WidthIncludingTrailingWhitespace)
    } catch { [math]::Ceiling(117 * $LogView.Zoom) }
}
Set-LogMetric
# $Prev : niveau de la ligne précédente (espacement avant une étape ou un bloc de bilan)
function New-LogParagraph([string]$L, [string]$Prev) {
    # taille portée par chaque paragraphe (valeur locale) : le zoom s'applique quel que soit le document de la RichTextBox
    $p = [Windows.Documents.Paragraph]::new(); $in = $LogView.Indent; $p.FontSize = $LogView.MsgSize
    $x = Get-LogLinePart $L; $p.Tag = $(if ($x) { $x.Level } else { '' })
    $p.Margin = [Windows.Thickness]::new($in, 0, 0, 0)
    # ligne vide (séparateur entre tâches) : simple espace de quelques pixels
    if (-not $x -and -not $L.Trim()) { $p.FontSize = [math]::Max([double]2, 4 * $LogView.Zoom); $p.Tag = 'sep'; return $p }
    if (-not $x) { Add-LogRun $p.Inlines $L 'MutedBrush'; return $p }
    $p.TextIndent = -$in
    $gap = $(if ($Prev -and $Prev -ne 'sep' -and $Prev -ne $x.Level) { [math]::Round(4 * $LogView.Zoom) } else { 0 })
    if ($x.Level -eq 'STEP') { $p.Margin = [Windows.Thickness]::new($in, $gap, 0, 0); $p.FontWeight = 'SemiBold' }
    # bilan (total libéré, durée, espace après) : détaché des actions, gras, message en couleur pleine
    elseif ($x.Level -eq 'BILAN') { $p.Margin = [Windows.Thickness]::new($in, $gap, 0, 0); $p.FontWeight = 'Bold' }
    $r = [Windows.Documents.Run]::new($x.Time + '  '); $r.FontFamily = $LogMono; $r.FontSize = $LogView.MonoSize; $r.FontWeight = 'Normal'
    $r.SetResourceReference([Windows.Documents.TextElement]::ForegroundProperty, 'MutedBrush'); $p.Inlines.Add($r)
    $r = [Windows.Documents.Run]::new($x.Level.PadRight(5) + '  '); $r.FontFamily = $LogMono; $r.FontSize = $LogView.MonoSize; $r.FontWeight = 'Bold'
    $r.SetResourceReference([Windows.Documents.TextElement]::ForegroundProperty, $(if ($LogLevelBrush[$x.Level]) { $LogLevelBrush[$x.Level] } else { 'MutedBrush' }))
    $p.Inlines.Add($r)
    Add-LogRun $p.Inlines $x.Msg $LogMsgBrush[$x.Level]
    $p
}
# zoom borné à 70-200 %, arrondi au dixième. [double] explicite : avec Min(2, ...) PowerShell choisit les surcharges
# Decimal, et Round(Decimal, 1) lit 1 comme MidpointRounding.AwayFromZero (arrondi à l'entier) : le zoom restait à 100 %
function Get-LogZoomValue([double]$Zoom) { [math]::Round([double][math]::Min([double]2, [math]::Max([double]0.7, $Zoom)), [int]1) }
function Set-LogZoom([double]$Zoom) {
    try {
        $z = Get-LogZoomValue $Zoom
        $Ui.LogZoomTxt.Text = '{0} %' -f [int](100 * $z)
        if ($z -eq $LogView.Zoom -and $LogView.ZoomDone) { return }
        $LogView.Zoom = $z; $LogView.ZoomDone = $true; Set-LogMetric
        $Ui.LogBox.FontSize = $LogView.MsgSize
        try {
            [IO.File]::WriteAllText($LogZoomFile, $z.ToString([Globalization.CultureInfo]::InvariantCulture))
        } catch {
            Write-Ignored 'Enregistrement du zoom du journal' $_
        }
        Update-LogView
    } catch { Write-UiLog ('Zoom du journal impossible : {0}' -f $_.Exception.Message) 'ERROR' }
}
function Test-LogAtEnd { $b = $Ui.LogBox; ($b.VerticalOffset + $b.ViewportHeight) -ge ($b.ExtentHeight - 24) }
# bandeau « lignes plus anciennes non affichées » en tête de zone
function Set-LogHiddenHead {
    $blocks = $Ui.LogBox.Document.Blocks
    if ($blocks.FirstBlock -and $blocks.FirstBlock.Tag -eq 'head') { $blocks.Remove($blocks.FirstBlock) }
    if ($LogView.Hidden -le 0) { return }
    $p = [Windows.Documents.Paragraph]::new(); $p.Tag = 'head'; $p.Margin = [Windows.Thickness]::new(0, 0, 0, 8); $p.FontStyle = 'Italic'
    $r = [Windows.Documents.Run]::new(('{0} {1} : affiner la recherche ou ouvrir le dossier des journaux pour tout lire' -f $LogView.Hidden, (Get-Plural $LogView.Hidden 'ligne plus ancienne non affichée' 'lignes plus anciennes non affichées')))
    $r.SetResourceReference([Windows.Documents.TextElement]::ForegroundProperty, 'MutedBrush'); $p.Inlines.Add($r)
    if ($blocks.FirstBlock) { $blocks.InsertBefore($blocks.FirstBlock, $p) } else { $blocks.Add($p) }
}
function Update-LogEmpty {
    $shown = $Ui.LogBox.Document.Blocks.Count
    $Ui.LogEmpty.Text = $(if ($LogView.Lines.Count -eq 0) { 'Aucune ligne pour l''instant : les actions lancées depuis l''application apparaissent ici.' }
        elseif ($LogView.Text) { 'Aucune ligne ne contient « {0} » avec ce filtre.' -f $LogView.Text }
        elseif ($LogView.Level -eq 'Err') { 'Aucune erreur dans cette session.' }
        elseif ($LogView.Level -eq 'Warn') { 'Aucun avertissement ni erreur dans cette session.' }
        else { 'Aucune action sur le poste pour l''instant : cocher « Messages de l''application » pour voir le démarrage et les actualisations.' })
    $Ui.LogEmpty.Visibility = $(if ($shown) { 'Collapsed' } else { 'Visible' })
}
# compteurs d'une liste de lignes (erreurs, avertissements, messages de l'application, lignes qui passent le filtre)
function Measure-LogLine($Lines) {
    $c = @{ E = 0; W = 0; A = 0; Shown = 0 }
    foreach ($l in $Lines) {
        if ($l -match '\[ERROR\]') { $c.E++ } elseif ($l -match '\[WARN \]') { $c.W++ } elseif ($l -match '^\d{2}:\d{2}:\d{2} \[APP  \]') { $c.A++ }
        if (Test-LogLine $l) { $c.Shown++ }
    }
    $c
}
# lignes reçues du minuteur (texte multi-lignes) : mémorisées, compteurs mis à jour de façon incrémentale (pas de
# relecture des 20 000 lignes à chaque tick) ; affichage différé tant que l'onglet Journal n'est pas visible
function Add-LogLine([string]$Text) {
    $new = $Text -split "`r?`n"; if ($new.Count -and $new[-1] -eq '') { $new = $new[0..($new.Count - 2)] }
    $LogView.Lines.AddRange([string[]]$new)
    if ($LogView.Lines.Count -gt 20000) { $LogView.Lines.RemoveRange(0, $LogView.Lines.Count - 15000); $LogView.Rebuild = $true }
    else { $c = Measure-LogLine $new; foreach ($k in 'E', 'W', 'A', 'Shown') { $LogView.Cnt[$k] += $c[$k] } }
    if ($Ui.PageLog.Visibility -ne 'Visible') { if (-not $LogView.Rebuild) { $LogView.Pending.AddRange([string[]]$new) }; Update-LogCount; return }
    if ($LogView.Rebuild) { Update-LogView; return }
    Show-LogLine $new
    Update-LogFilterInfo
}
# ajout en fin de zone des lignes qui passent le filtre (plafond $LogView.Max : les plus anciennes sortent)
function Show-LogLine($Lines) {
    $show = @($Lines | Where-Object { Test-LogLine $_ })
    if (-not $show.Count) { return }
    $end = Test-LogAtEnd; $blocks = $Ui.LogBox.Document.Blocks
    $prev = $(if ($blocks.LastBlock) { "$($blocks.LastBlock.Tag)" } else { '' })
    foreach ($l in $show) { $np = New-LogParagraph $l $prev; $blocks.Add($np); $prev = "$($np.Tag)" }
    $over = $blocks.Count - $LogView.Max - $(if ($LogView.Hidden) { 1 } else { 0 })
    if ($over -gt 0) {
        if ($blocks.FirstBlock.Tag -eq 'head') { $blocks.Remove($blocks.FirstBlock) }
        for ($i = 0; $i -lt $over; $i++) { $blocks.Remove($blocks.FirstBlock) }
        $LogView.Hidden += $over; Set-LogHiddenHead
    }
    if ($end) { $Ui.LogBox.ScrollToEnd() }
}
# onglet Journal affiché : lignes reçues pendant qu'il était masqué
function Sync-LogView {
    if ($LogView.Rebuild) { Update-LogView; return }
    if ($LogView.Pending.Count) {
        $p = $LogView.Pending.ToArray()
        $LogView.Pending.Clear()
        Show-LogLine $p
        $Ui.LogBox.ScrollToEnd()
        Update-LogFilterInfo
    }
}
# compteurs sur les boutons de niveau et sur la case des messages de l'application
function Update-LogCount {
    $nE = $LogView.Cnt.E; $nW = $LogView.Cnt.W; $nA = $LogView.Cnt.A
    $Ui.LogFErr.Content = $(if ($nE) { "Erreurs ($nE)" } else { 'Erreurs' })
    $Ui.LogFWarn.Content = $(if ($nE + $nW) { 'Avertissements ({0})' -f ($nE + $nW) } else { 'Avertissements' })
    $Ui.LogFApp.Content = $(if ($nA) { "Messages de l'application ($nA)" } else { "Messages de l'application" })
}
function Update-LogFilterInfo {
    Update-LogCount
    $n = $LogView.Cnt.Shown
    $Ui.LogFilterInfo.Text = $(if ($n -ne $LogView.Lines.Count) { '{0} {1} sur {2}' -f $n, (Get-Plural $n 'ligne affichée' 'lignes affichées'), $LogView.Lines.Count } else { '' })
    Update-LogEmpty
}
# reconstruction complète (changement de filtre, de recherche ou de zoom, dépassement des 20 000 lignes)
function Update-LogView {
    $LogView.Cnt = Measure-LogLine $LogView.Lines; $LogView.Pending.Clear(); $LogView.Rebuild = $false
    $ok = [Collections.Generic.List[string]]::new()
    foreach ($l in $LogView.Lines) { if (Test-LogLine $l) { $ok.Add($l) } }
    $LogView.Hidden = [Math]::Max(0, $ok.Count - $LogView.Max)
    $doc = [Windows.Documents.FlowDocument]::new(); $doc.PagePadding = [Windows.Thickness]::new(0)
    $doc.FontFamily = $Ui.LogBox.FontFamily; $doc.FontSize = $LogView.MsgSize
    $prev = ''
    for ($i = $LogView.Hidden; $i -lt $ok.Count; $i++) { $np = New-LogParagraph $ok[$i] $prev; $doc.Blocks.Add($np); $prev = "$($np.Tag)" }
    $Ui.LogBox.Document = $doc
    Set-LogHiddenHead
    $Ui.LogBox.ScrollToEnd()
    Update-LogFilterInfo
}
$LogLevelClick = {
    param($s, $e)
    $LogView.Level = "$($s.DataContext)"
    foreach ($b in $Ui.LogFAll, $Ui.LogFWarn, $Ui.LogFErr) { $b.Tag = $(if ($b.DataContext -eq $LogView.Level) { 'on' } else { '' }) }
    Update-LogView
}
$Ui.LogFAll.DataContext = 'All'; $Ui.LogFWarn.DataContext = 'Warn'; $Ui.LogFErr.DataContext = 'Err'
$Ui.LogFWarn.ToolTip = 'Avertissements et erreurs'; $Ui.LogFErr.ToolTip = 'Erreurs seules'
foreach ($b in $Ui.LogFAll, $Ui.LogFWarn, $Ui.LogFErr) { $b.Add_Click($LogLevelClick) }
$Ui.LogFApp.IsChecked = $LogView.App
$Ui.LogFApp.Add_Click({ $LogView.App = [bool]$Ui.LogFApp.IsChecked; Update-LogView })
# recherche : rendu différé de 250 ms après la dernière frappe (reconstruction de la zone)
$LogFindTimer = [Windows.Threading.DispatcherTimer]::new(); $LogFindTimer.Interval = [TimeSpan]::FromMilliseconds(250)
$LogFindTimer.Add_Tick({ $LogFindTimer.Stop(); Update-LogView })
$Ui.LogFind.Add_TextChanged({
    $LogView.Text = "$($Ui.LogFind.Text)".Trim()
    $Ui.LogFindHint.Visibility = $(if ($Ui.LogFind.Text) { 'Collapsed' } else { 'Visible' })
    $LogFindTimer.Stop(); $LogFindTimer.Start()
})
$Ui.LogFind.Add_GotKeyboardFocus({ $Ui.LogFindBox.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, 'AccentBrush') })
$Ui.LogFind.Add_LostKeyboardFocus({ $Ui.LogFindBox.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, 'LineBrush') })
$Ui.LogFindBox.Add_MouseLeftButtonDown({ [void]$Ui.LogFind.Focus() })
$Ui.LogFind.Add_PreviewKeyDown({ param($s, $e)
    if ("$($e.Key)" -eq 'Escape') {
        $Ui.LogFind.Text = ''
        $e.Handled = $true
    } elseif ("$($e.Key)" -eq 'Return') {
        $LogFindTimer.Stop()
        Update-LogView
        $e.Handled = $true
    }
})
Update-LogEmpty
# zoom : boutons de la zone ; Ctrl + molette et Ctrl + touches sur la zone : gestionnaires de la fenêtre ($ZoomWheel, $ZoomKeys)
$Ui.LogZoomOut.Add_Click({ Set-LogZoom ($LogView.Zoom - 0.1) })
$Ui.LogZoomIn.Add_Click({ Set-LogZoom ($LogView.Zoom + 0.1) })
$Ui.LogZoomTxt.Add_MouseLeftButtonUp({ Set-LogZoom 1 })
$Ui.LogZoomTxt.Text = '{0} %' -f [int](100 * $LogView.Zoom); $Ui.LogBox.FontSize = $LogView.MsgSize; $LogView.ZoomDone = $true
