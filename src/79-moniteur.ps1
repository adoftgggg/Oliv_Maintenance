# Moniteur de ressources, présentation du Gestionnaire des tâches de Windows : ouvert par un clic sur Processeur, Mémoire
# ou Réseau (bandeau d'activité de l'Accueil), trié sur la colonne correspondante.
# Sections Applications / Processus en arrière-plan / Processus Windows (classement natif, _OlivM.ProcMon) ; processus de
# même exécutable regroupés (« Brave Browser (21) »), groupe déplié par la flèche. Colonnes Processeur, Mémoire, Disque,
# Réseau : total du poste dans l'en-tête, cellules teintées selon la charge (bleu clair = faible, bleu soutenu = forte), tri par
# clic sur l'en-tête. Relevé toutes les secondes tant que la fenêtre est ouverte et non réduite ; lignes réutilisées
# d'un relevé à l'autre (texte et teinte modifiés seulement s'ils changent).
# Clic droit : terminer la tâche (tous les processus du groupe), le processus ou son arborescence, afficher l'exécutable
# dans l'Explorateur. Processus critiques de Windows et l'application elle-même protégés.
$MonUI = @{ Sort = 'Name'; Desc = $false; Groups = @{}; Kids = @{}; Open = @{}; Sel = $null; NetPrev = $null; Icons = @{} }
$MonProtected = 'System', 'Idle', 'Registry', 'Secure System', 'Memory Compression', 'smss', 'csrss', 'wininit', 'winlogon', 'services', 'lsass', 'LsaIso', 'svchost', 'fontdrvhost', 'dwm', 'MsMpEng', 'NisSrv', 'SgrmBroker', 'audiodg'
$MonSections = @(@{ K = 0; T = 'Applications' }, @{ K = 1; T = 'Processus en arrière-plan' }, @{ K = 2; T = 'Processus Windows' })
# colonnes de valeurs : clé de tri, libellé, largeur ; teinte pleine à : processeur 50 %, mémoire 25 % de la mémoire
# physique, disque 50 Mo/s, réseau 100 Mbit/s
$MonCols = @(
    @{ K = 'Cpu'; T = 'Processeur'; W = 96 }
    @{ K = 'Mem'; T = 'Mémoire'; W = 110 }
    @{ K = 'Disk'; T = 'Disque'; W = 100 }
    @{ K = 'Net'; T = 'Réseau'; W = 110 }
)
$MonXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Oliv_Maintenance - Moniteur de ressources" Width="1040" Height="760" MinWidth="760" MinHeight="460" WindowStartupLocation="Manual"
        Background="{DynamicResource BgBrush}" Foreground="{DynamicResource FgBrush}" FontFamily="Segoe UI" FontSize="13">
  <Grid Margin="16,14,16,12">
    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
    <DockPanel Margin="0,0,0,10">
      <Border x:Name="FindBox" DockPanel.Dock="Right" Width="240" Height="30" CornerRadius="15" Background="{DynamicResource BgBrush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="1.5" VerticalAlignment="Center" Cursor="IBeam">
        <Grid>
          <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
          <TextBlock Text="&#xE721;" FontFamily="Segoe MDL2 Assets" FontSize="12" Foreground="{DynamicResource AccentBrush}" Margin="12,0,8,0" VerticalAlignment="Center"/>
          <TextBox x:Name="Find" Grid.Column="1" BorderThickness="0" Background="Transparent" Foreground="{DynamicResource FgBrush}" CaretBrush="{DynamicResource FgBrush}" VerticalAlignment="Center" Margin="0,0,12,0" FontSize="13"/>
          <TextBlock x:Name="FindHint" Grid.Column="1" Text="Filtrer les processus" Foreground="{DynamicResource MutedBrush}" VerticalAlignment="Center" IsHitTestVisible="False"/>
        </Grid>
      </Border>
      <Button x:Name="EndTask" DockPanel.Dock="Right" Content="Terminer la tâche" Style="{DynamicResource ActionBtn}" Height="30" Padding="14,0" Margin="0,0,10,0" IsEnabled="False"/>
      <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
        <TextBlock Text="Processus" FontSize="16" FontWeight="SemiBold" VerticalAlignment="Center"/>
        <TextBlock x:Name="Count" FontSize="16" Foreground="{DynamicResource MutedBrush}" VerticalAlignment="Center" Margin="10,0,0,0"/>
        <!-- vitesse d'actualisation (comme le Gestionnaire des tâches), mémorisée -->
        <Button x:Name="RateBtn" Style="{DynamicResource ActionBtn}" Height="30" Padding="12,0" Margin="16,0,0,0" VerticalAlignment="Center"/>
      </StackPanel>
    </DockPanel>
    <Border Grid.Row="1" Background="{DynamicResource PanelBrush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="1" CornerRadius="6">
      <Grid>
        <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
        <Grid x:Name="Head" Margin="5,0,22,0"/>
        <Border Grid.Row="1" Height="1" VerticalAlignment="Top" Background="{DynamicResource LineBrush}"/>
        <ScrollViewer x:Name="Scroll" Grid.Row="1" VerticalScrollBarVisibility="Visible" Focusable="False"><StackPanel x:Name="List" Margin="4,2,4,4"/></ScrollViewer>
        <TextBlock x:Name="Hint" Grid.Row="1" Foreground="{DynamicResource MutedBrush}" HorizontalAlignment="Center" VerticalAlignment="Center" TextAlignment="Center" TextWrapping="Wrap" Margin="20"/>
      </Grid>
    </Border>
    <DockPanel Grid.Row="2" Margin="0,10,0,0" LastChildFill="False">
      <Border DockPanel.Dock="Left" Height="30" Padding="2,0" Margin="0,0,12,0" CornerRadius="6" Background="{DynamicResource BgBrush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="1" VerticalAlignment="Center"
              ToolTip="Taille du texte de la liste (80 à 150 %) : Ctrl + molette ou Ctrl + / Ctrl -, clic sur le pourcentage ou Ctrl + 0 pour revenir à 100 %">
        <StackPanel Orientation="Horizontal">
          <Button x:Name="ZoomOut" Style="{DynamicResource IconBtn}" Width="28" Height="26" FontSize="12" Content="&#xE71F;"/>
          <TextBlock x:Name="ZoomTxt" Foreground="{DynamicResource MutedBrush}" FontSize="12" Width="44" TextAlignment="Center" VerticalAlignment="Center" Cursor="Hand" Text="100 %"/>
          <Button x:Name="ZoomIn" Style="{DynamicResource IconBtn}" Width="28" Height="26" FontSize="12" Content="&#xE8A3;"/>
        </StackPanel>
      </Border>
    </DockPanel>
  </Grid>
</Window>
'@
# teinte de charge : bleu de l'application dont l'opacité suit la charge (au plus 55 % : texte lisible en thème clair et
# sombre), 20 niveaux en cache
$MonHeat = @{}
function Get-HeatBrush([double]$Frac) {
    $lv = [int][math]::Round([math]::Max([double]0, [math]::Min([double]1, $Frac)) * 20)
    $b = $MonHeat[$lv]
    if (-not $b) {
        $b = [Windows.Media.SolidColorBrush]::new([Windows.Media.Color]::FromArgb([byte](16 + 6 * $lv), 59, 130, 246)); $b.Freeze(); $MonHeat[$lv] = $b
    }
    $b
}
function Format-MonValue([string]$Col, [double]$V) {
    switch ($Col) {
        'Cpu' { '{0:N1} %' -f $V }
        'Mem' { $(if ($V -ge 1GB) { '{0:N2} Go' -f ($V / 1GB) } else { '{0:N1} Mo' -f ($V / 1MB) }) }
        'Disk' { $(if ($V -lt 0.05MB) { '0 Mo/s' } else { '{0:N1} Mo/s' -f ($V / 1MB) }) }
        'Net' { $(if ($V * 8 -lt 50000) { '0 Mbit/s' } else { '{0:N1} Mbit/s' -f ($V * 8 / 1e6) }) }
    }
}
function Get-MonFrac([string]$Col, [double]$V) {
    switch ($Col) {
        'Cpu' { $V / 50 }
        'Mem' { $(if ($MonUI.RamTotal) { 4 * $V / $MonUI.RamTotal } else { 0 }) }
        'Disk' { $V / 50MB }
        'Net' { $V * 8 / 100e6 }
    }
}
# icône de l'exécutable (16 px, cache par chemin) ; sans chemin lisible : icône générique
function Get-MonIcon([string]$Path) {
    if (-not $Path) { return $null }
    if ($MonUI.Icons.ContainsKey($Path)) { return $MonUI.Icons[$Path] }
    $src = $null
    try {
        if (-not $Sync.FormsLoaded) { Add-Type -AssemblyName System.Windows.Forms, System.Drawing; $Sync.FormsLoaded = $true }
        $ic = [System.Drawing.Icon]::ExtractAssociatedIcon($Path)
        if ($ic) {
            try { $src = [Windows.Interop.Imaging]::CreateBitmapSourceFromHIcon($ic.Handle, [Windows.Int32Rect]::Empty, [Windows.Media.Imaging.BitmapSizeOptions]::FromWidthAndHeight(16, 16)); $src.Freeze() } finally { $ic.Dispose() }
        }
    } catch { $src = $null }
    $MonUI.Icons[$Path] = $src
    $src
}
function Show-ResourceMonitor([string]$Tab = 'Cpu') {
    $MonUI.Sort = $(switch ($Tab) { 'Mem' { 'Mem' } 'Net' { 'Net' } default { 'Cpu' } }); $MonUI.Desc = $true
    if ($MonUI.Win) {
        if ($MonUI.Win.WindowState -eq 'Minimized') { $MonUI.Win.WindowState = 'Normal' }
        $MonUI.Win.Activate(); Update-MonHead; Update-MonList; return
    }
    $w = [Windows.Markup.XamlReader]::Parse($MonXaml)
    $w.Resources.MergedDictionaries.Add($Window.Resources)
    Set-ChildWindow $w 'Moniteur'
    Initialize-ChildZoom $w
    if ($AppIcon) { $w.Icon = $AppIcon }
    foreach ($n in 'FindBox', 'Find', 'FindHint', 'EndTask', 'Head', 'Scroll', 'List', 'Hint', 'Count', 'RateBtn') { $MonUI[$n] = $w.FindName($n) }
    $MonUI.Win = $w; $MonUI.Groups = @{}; $MonUI.Kids = @{}; $MonUI.Sel = $null; $MonUI.NetPrev = $null; $MonUI.Order = ''; $MonUI.Data = $null
    $MonUI.Find.Add_TextChanged({
            $MonUI.FindHint.Visibility = $(if ($MonUI.Find.Text) { 'Hidden' } else { 'Visible' })
            Update-MonList
        })
    $MonUI.FindBox.Add_MouseLeftButtonDown({ [void]$MonUI.Find.Focus() })
    $MonUI.EndTask.Add_Click({ if ($MonUI.Sel) { Stop-MonTarget $MonUI.Sel $false } })
    New-MonHead
    $tm = [Windows.Threading.DispatcherTimer]::new(); $tm.Interval = [TimeSpan]::FromMilliseconds([math]::Max([int]500, [int]$MonUI.Rate))
    $tm.Add_Tick({ if ($MonUI.Win -and $MonUI.Win.WindowState -ne 'Minimized') { Invoke-TickStep 'moniteur de ressources' { Update-MonData } } })
    $MonUI.Timer = $tm
    $w.Add_Closed({
            $MonUI.Timer.Stop(); $MonUI.Win = $null; $MonUI.Groups = @{}; $MonUI.Kids = @{}; $MonUI.Data = $null; $MonUI.Sel = $null
            try { [_OlivM.ProcMon]::Reset(); [_OlivM.DiskMon]::Close() } catch { Write-Ignored 'Moniteur de ressources (arrêt)' $_ }
        })
    try { [_OlivM.ProcMon]::Reset() } catch { Write-Ignored 'Moniteur de ressources' $_ }
    # premier relevé (le plus long : icônes, descriptions) fait avant l'affichage : interface libre dès l'ouverture, premier
    # rendu immédiat et complet (processeur, disque et réseau au relevé suivant)
    New-MonRateBar
    Update-MonData
    $w.Show()
    if ($MonUI.Rate -gt 0) { $tm.Start() }
}
# en-tête : Nom puis, par colonne, total du poste (grand, teinté) et libellé ; clic = tri (nouveau clic : sens inverse)
function New-MonHead {
    $h = $MonUI.Head; $h.Children.Clear(); $h.ColumnDefinitions.Clear(); $MonUI.HeadCells = @{}
    $c0 = [Windows.Controls.ColumnDefinition]::new(); [void]$h.ColumnDefinitions.Add($c0)
    foreach ($c in $MonCols) { $cd = [Windows.Controls.ColumnDefinition]::new(); $cd.Width = [Windows.GridLength]::new($c.W); [void]$h.ColumnDefinitions.Add($cd) }
    $cells = @(@{ K = 'Name'; T = 'Nom' }) + $MonCols
    for ($i = 0; $i -lt $cells.Count; $i++) {
        $c = $cells[$i]
        $b = [Windows.Controls.Border]::new(); $b.Padding = New-Thickness 8 6 8 6; $b.Cursor = [Windows.Input.Cursors]::Hand; $b.Background = [Windows.Media.Brushes]::Transparent; $b.Tag = $c.K
        if ($i) { $b.BorderThickness = New-Thickness 1 0 0 0; $b.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, 'LineBrush') }
        $sp = [Windows.Controls.StackPanel]::new(); $sp.VerticalAlignment = 'Bottom'
        $big = New-Text ''; $big.FontSize = 17; $big.HorizontalAlignment = $(if ($i) { 'Right' } else { 'Left' })
        $lab = New-Text $c.T 'Muted'; $lab.FontSize = 12; $lab.HorizontalAlignment = $(if ($i) { 'Right' } else { 'Left' })
        [void]$sp.Children.Add($big); [void]$sp.Children.Add($lab); $b.Child = $sp
        $b.Add_MouseLeftButtonUp({
                param($s, $e)
                $k = "$($s.Tag)"
                if ($MonUI.Sort -eq $k) { $MonUI.Desc = -not $MonUI.Desc } else { $MonUI.Sort = $k; $MonUI.Desc = ($k -ne 'Name') }
                Update-MonHead; Update-MonList
            })
        [Windows.Controls.Grid]::SetColumn($b, $i); [void]$h.Children.Add($b)
        $b.ToolTip = $(switch ($c.K) {
                'Cpu' { 'Processeur : part du temps processeur (tous les cœurs) ; en tête, charge totale du poste' }
                'Mem' { 'Mémoire privée du processus ; en tête, mémoire physique utilisée' }
                'Disk' { 'Lectures et écritures du processus (fichiers, et certaines entrées/sorties hors disque) ; en tête, activité réelle des disques' }
                'Net' { 'Débit TCP du processus (UDP non mesuré par Windows par processus) ; en tête, part de la vitesse des cartes réseau utilisée' }
                default { 'Trier par nom' }
            })
        $MonUI.HeadCells[$c.K] = @{ Border = $b; Big = $big; Label = $lab; Title = $c.T }
    }
    Update-MonHead
}
# vitesse d'actualisation (comme le Gestionnaire des tâches), choisie dans une liste ouverte par le bouton, mémorisée
$MonRateFile = Join-Path (Get-LogPath 'Etat') 'moniteur-actualisation.txt'
$MonRates = [ordered]@{ 500 = 'Rapide (0,5 s)'; 1000 = 'Normale (1 s)'; 3000 = 'Lente (3 s)'; 0 = 'Pause' }
$MonUI.Rate = 1000
try {
    if (Test-Path -LiteralPath $MonRateFile) { $v = [int][IO.File]::ReadAllText($MonRateFile).Trim(); if ($MonRates.Contains($v)) { $MonUI.Rate = $v } }
} catch { Write-Ignored 'Moniteur de ressources (actualisation mémorisée)' $_ }
function New-MonRateBar {
    $MonUI.RateBtn.ToolTip = 'Vitesse d''actualisation des relevés'
    $MonUI.RateBtn.Add_Click({
            param($s, $e)
            $m = [Windows.Controls.ContextMenu]::new(); $m.PlacementTarget = $s; $m.Placement = 'Bottom'
            foreach ($k in $MonRates.Keys) {
                $mi = [Windows.Controls.MenuItem]::new(); $mi.Header = $MonRates[[object]$k]; $mi.Tag = [int]$k
                $mi.IsCheckable = $true; $mi.IsChecked = ([int]$k -eq $MonUI.Rate)
                $mi.Add_Click({ param($s2, $e2) Set-MonRate ([int]$s2.Tag) })
                [void]$m.Items.Add($mi)
            }
            $m.IsOpen = $true
        })
    Set-MonRate $MonUI.Rate $false
}
function Set-MonRate([int]$Ms, [bool]$Save = $true) {
    $MonUI.Rate = $Ms
    $MonUI.RateBtn.Content = 'Actualisation : {0}  {1}' -f $MonRates[[object]$Ms], [char]0x25BE
    if ($MonUI.Timer) {
        $MonUI.Timer.Stop()
        if ($Ms -gt 0) { $MonUI.Timer.Interval = [TimeSpan]::FromMilliseconds($Ms); $MonUI.Timer.Start() }
    }
    if ($Save) { try { [IO.File]::WriteAllText($MonRateFile, "$Ms") } catch { Write-Ignored 'Moniteur de ressources (actualisation)' $_ } }
}
function Update-MonHead {
    foreach ($k in @($MonUI.HeadCells.Keys)) {
        $hc = $MonUI.HeadCells[$k]
        $arrow = $(if ($MonUI.Sort -eq $k) { $(if ($MonUI.Desc) { ' ' + [char]0x25BE } else { ' ' + [char]0x25B4 }) } else { '' })
        $t = $hc.Title + $arrow; if ($hc.Label.Text -ne $t) { $hc.Label.Text = $t }
        $hc.Label.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, $(if ($MonUI.Sort -eq $k) { 'FgBrush' } else { 'MutedBrush' }))
    }
    $tot = $MonUI.Totals; if (-not $tot) { return }
    foreach ($c in $MonCols) {
        $hc = $MonUI.HeadCells[$c.K]; $v = $tot[$c.K]
        $txt = $(if ($null -eq $v -or $v -lt 0) { '' } else { '{0:N0} %' -f $v })
        if ($hc.Big.Text -ne $txt) { $hc.Big.Text = $txt }
        $hc.Border.Background = $(if ($txt) { Get-HeatBrush ($v / 100) } else { [Windows.Media.Brushes]::Transparent })
    }
}
# relevé : processus (classement, processeur, mémoire, E/S disque, débit TCP) et totaux du poste
function Update-MonData {
    if (-not $MonUI.Win) { return }
    $procs = [_OlivM.ProcMon]::Sample()
    $tot = @{ Cpu = [_OlivM.ProcMon]::SystemCpu; Disk = [_OlivM.DiskMon]::Busy() }
    $m = $null; try { $m = [_OlivM.Perf]::Mem() } catch { Write-Ignored 'Moniteur de ressources (mémoire)' $_ }
    if ($m) { $MonUI.RamTotal = [double]$m[0]; $tot.Mem = 100 * ([double]$m[0] - [double]$m[1]) / [math]::Max([double]1, [double]$m[0]) }
    # réseau : débit total des cartes actives / somme de leurs vitesses de liaison
    $now = [DateTime]::UtcNow; $bytes = [double]0; $speed = [double]0
    foreach ($n in [Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()) {
        if ("$($n.OperationalStatus)" -ne 'Up' -or "$($n.NetworkInterfaceType)" -in 'Loopback', 'Tunnel') { continue }
        try { $st = $n.GetIPStatistics(); $bytes += [double]$st.BytesReceived + [double]$st.BytesSent; if ($n.Speed -gt 0) { $speed += [double]$n.Speed } } catch { Write-Ignored 'Moniteur de ressources (carte réseau)' $_ }
    }
    $pv = $MonUI.NetPrev; $MonUI.NetPrev = @($now, $bytes)
    $tot.Net = $(if ($pv -and $speed -gt 0) { $dt = ($now - $pv[0]).TotalSeconds; $(if ($dt -gt 0.2) { [math]::Min([double]100, 100 * 8 * [math]::Max([double]0, $bytes - $pv[1]) / $dt / $speed) } else { -1 }) } else { -1 })
    $MonUI.Totals = $tot
    # regroupement : même exécutable dans la même section ; section Applications pour tout le groupe si l'un de ses
    # processus a une fenêtre
    $byName = @{}
    foreach ($p in $procs) { $k = "$($p.Name)"; if (-not $byName[$k]) { $byName[$k] = [Collections.Generic.List[object]]::new() }; $byName[$k].Add($p) }
    $groups = @{}
    foreach ($k in $byName.Keys) {
        $list = $byName[$k]
        $hasApp = @($list | Where-Object { $_.Kind -eq 0 }).Count -gt 0
        foreach ($p in $list) {
            $kind = $(if ($p.Kind -eq 2) { 2 } elseif ($hasApp) { 0 } else { 1 })
            $gk = '{0}|{1}' -f $kind, $k
            $g = $groups[$gk]; if (-not $g) { $g = @{ Key = $gk; Kind = $kind; Name = $k; Procs = [Collections.Generic.List[object]]::new() }; $groups[$gk] = $g }
            $g.Procs.Add($p)
        }
    }
    foreach ($g in $groups.Values) {
        $first = @($g.Procs | Sort-Object Created)[0]
        $g.Desc = $(if ($first.Desc) { $first.Desc } else { $first.Name }); $g.Path = $first.Path
        $g.Cpu = [double]0; $g.Mem = [double]0; $g.Disk = [double]0; $g.Net = [double]0
        foreach ($p in $g.Procs) { $g.Cpu += $p.Cpu; $g.Mem += $p.Private; $g.Disk += $p.Disk; $g.Net += $p.Net }
    }
    $MonUI.Data = @{ Groups = $groups; Count = @($procs).Count; Time = [DateTime]::Now }
    Update-MonHead; Update-MonList
    Set-MonText $MonUI.Count "$($MonUI.Data.Count)"
}
# ligne (groupe ou processus) : flèche, icône, nom, 4 cellules de valeur teintées
function New-MonRow([bool]$Child) {
    $b = [Windows.Controls.Border]::new(); $b.Style = $Window.FindResource('HoverLine'); $b.CornerRadius = [Windows.CornerRadius]::new(3)
    $g = [Windows.Controls.Grid]::new(); $b.Child = $g; $g.MinHeight = 28
    $c0 = [Windows.Controls.ColumnDefinition]::new(); [void]$g.ColumnDefinitions.Add($c0)
    foreach ($c in $MonCols) { $cd = [Windows.Controls.ColumnDefinition]::new(); $cd.Width = [Windows.GridLength]::new($c.W); [void]$g.ColumnDefinitions.Add($cd) }
    $sp = [Windows.Controls.StackPanel]::new(); $sp.Orientation = 'Horizontal'; $sp.VerticalAlignment = 'Center'; $sp.Margin = New-Thickness $(if ($Child) { 44 } else { 6 }) 0 8 0
    $ar = New-Text ''; $ar.FontFamily = [Windows.Media.FontFamily]::new('Segoe MDL2 Assets'); $ar.FontSize = 9; $ar.Width = 18; $ar.VerticalAlignment = 'Center'; $ar.Cursor = [Windows.Input.Cursors]::Hand
    $ic = [Windows.Controls.Image]::new(); $ic.Width = 16; $ic.Height = 16; $ic.Margin = New-Thickness 2 0 10 0; $ic.VerticalAlignment = 'Center'
    $nm = New-Text ''; $nm.VerticalAlignment = 'Center'; $nm.TextTrimming = 'CharacterEllipsis'
    if (-not $Child) { [void]$sp.Children.Add($ar) }
    [void]$sp.Children.Add($ic); [void]$sp.Children.Add($nm)
    [void]$g.Children.Add($sp)
    $cells = @{}
    for ($i = 0; $i -lt $MonCols.Count; $i++) {
        $cb = [Windows.Controls.Border]::new(); $cb.Padding = New-Thickness 8 0 8 0
        $t = New-Text ''; $t.HorizontalAlignment = 'Right'; $t.VerticalAlignment = 'Center'; $cb.Child = $t
        [Windows.Controls.Grid]::SetColumn($cb, $i + 1); [void]$g.Children.Add($cb)
        $cells[$MonCols[$i].K] = @{ Border = $cb; Text = $t; Lv = -1 }
    }
    $r = @{ Border = $b; Arrow = $ar; Icon = $ic; Name = $nm; Cells = $cells; Child = $Child }
    $b.Tag = $r
    $b.Add_MouseLeftButtonDown({ param($s, $e) Set-MonSelection $s.Tag; if ($e.ClickCount -eq 2 -and -not $s.Tag.Child) { Switch-MonGroup $s.Tag } })
    $ar.Tag = $r
    $ar.Add_MouseLeftButtonDown({ param($s, $e) Switch-MonGroup $s.Tag; $e.Handled = $true })
    $b.Add_MouseRightButtonUp({ param($s, $e) Set-MonSelection $s.Tag; Show-MonMenu $s.Tag })
    Update-WinTextZoom $MonUI.Win $b
    $r
}
function Switch-MonGroup($R) {
    if (-not $R.G -or $R.G.Procs.Count -lt 2) { return }
    $MonUI.Open[$R.G.Key] = -not [bool]$MonUI.Open[$R.G.Key]
    Update-MonList
}
function Set-MonValue($R, $V) {
    foreach ($c in $MonCols) {
        $cell = $R.Cells[$c.K]; $val = [double]$V[$c.K]
        $txt = Format-MonValue $c.K $val; if ($cell.Text.Text -ne $txt) { $cell.Text.Text = $txt }
        $lv = [int][math]::Round([math]::Max([double]0, [math]::Min([double]1, (Get-MonFrac $c.K $val))) * 20)
        if ($lv -ne $cell.Lv) { $cell.Lv = $lv; $cell.Border.Background = Get-HeatBrush ($lv / 20) }
    }
}
function Set-MonText($T, [string]$Text) { if ($T.Text -ne $Text) { $T.Text = $Text } }
function Set-MonIcon($R, [string]$Path) {
    if ($R.IconPath -eq $Path) { return }
    $R.IconPath = $Path; $R.Icon.Source = Get-MonIcon $Path
}
# liste : sections, groupes triés, processus des groupes dépliés ; enfants réordonnés seulement si l'ordre change
function Update-MonList {
    if (-not $MonUI.Win -or -not $MonUI.Data) { return }
    $q = "$($MonUI.Find.Text)".Trim()
    $sortKey = $(switch ($MonUI.Sort) { 'Name' { { "$($_.Desc)" } } 'Cpu' { { [double]$_.Cpu } } 'Mem' { { [double]$_.Mem } } 'Disk' { { [double]$_.Disk } } default { { [double]$_.Net } } })
    $order = [Collections.Generic.List[object]]::new(); $sig = [Text.StringBuilder]::new()
    $liveG = @{}; $liveK = @{}
    foreach ($sec in $MonSections) {
        $gs = @($MonUI.Data.Groups.Values | Where-Object { $_.Kind -eq $sec.K })
        if ($q) { $gs = @($gs | Where-Object { (Test-TextHas "$($_.Desc)" $q) -or (Test-TextHas "$($_.Name)" $q) -or @($_.Procs | Where-Object { "$($_.Pid)" -eq $q -or (Test-TextHas "$($_.Path)" $q) }).Count }) }
        if (-not $gs.Count) { continue }
        $hk = "sec|$($sec.K)"
        $h = $MonUI.Groups[$hk]
        if (-not $h) {
            $tb = New-Text ''; $tb.FontSize = 15; $tb.FontWeight = [Windows.FontWeights]::SemiBold; $tb.Margin = New-Thickness 8 14 0 6
            $h = @{ Border = $tb; Header = $true }; $MonUI.Groups[$hk] = $h; Update-WinTextZoom $MonUI.Win $tb
        }
        $nProc = 0; foreach ($g in $gs) { $nProc += $g.Procs.Count }
        Set-MonText $h.Border ('{0} ({1})' -f $sec.T, $nProc)
        $liveG[$hk] = 1; $order.Add($h.Border); [void]$sig.Append($hk).Append(',')
        $gs = @($gs | Sort-Object -Property @{ Expression = $sortKey; Descending = [bool]$MonUI.Desc }, @{ Expression = { "$($_.Desc)" } })
        foreach ($g in $gs) {
            $r = $MonUI.Groups[$g.Key]; if (-not $r) { $r = New-MonRow $false; $MonUI.Groups[$g.Key] = $r }
            $r.G = $g; $liveG[$g.Key] = 1
            $n = $g.Procs.Count; $open = $n -gt 1 -and [bool]$MonUI.Open[$g.Key]
            Set-MonText $r.Name $(if ($n -gt 1) { '{0} ({1})' -f $g.Desc, $n } else { "$($g.Desc)" })
            Set-MonText $r.Arrow $(if ($n -lt 2) { '' } elseif ($open) { [string][char]0xE70D } else { [string][char]0xE76C })
            Set-MonIcon $r $g.Path
            Set-MonValue $r $g
            $order.Add($r.Border); [void]$sig.Append($g.Key).Append(',')
            if ($open) {
                foreach ($p in @($g.Procs | Sort-Object -Property @{ Expression = $(switch ($MonUI.Sort) { 'Cpu' { { [double]$_.Cpu } } 'Mem' { { [double]$_.Private } } 'Disk' { { [double]$_.Disk } } 'Net' { { [double]$_.Net } } default { { [int]$_.Pid } } }); Descending = ($MonUI.Sort -ne 'Name' -and [bool]$MonUI.Desc) })) {
                    $kk = '{0}|{1}' -f $p.Pid, $p.Created
                    $c = $MonUI.Kids[$kk]; if (-not $c) { $c = New-MonRow $true; $MonUI.Kids[$kk] = $c }
                    $c.P = $p; $c.G = $g; $liveK[$kk] = 1
                    Set-MonText $c.Name ('{0}  (PID {1})' -f $(if ($p.Desc) { $p.Desc } else { $p.Name }), $p.Pid)
                    Set-MonIcon $c $p.Path
                    Set-MonValue $c @{ Cpu = $p.Cpu; Mem = [double]$p.Private; Disk = $p.Disk; Net = $p.Net }
                    $order.Add($c.Border); [void]$sig.Append($kk).Append(',')
                }
            }
        }
    }
    foreach ($k in @($MonUI.Groups.Keys)) { if (-not $liveG.ContainsKey($k)) { if ($MonUI.Sel -eq $MonUI.Groups[$k]) { Set-MonSelection $null }; $MonUI.Groups.Remove($k) } }
    foreach ($k in @($MonUI.Kids.Keys)) { if (-not $liveK.ContainsKey($k)) { if ($MonUI.Sel -eq $MonUI.Kids[$k]) { Set-MonSelection $null }; $MonUI.Kids.Remove($k) } }
    $s = $sig.ToString()
    if ($s -ne $MonUI.Order) {
        $MonUI.Order = $s
        $MonUI.List.Children.Clear(); foreach ($el in $order) { [void]$MonUI.List.Children.Add($el) }
    }
    $MonUI.Hint.Text = $(if ($order.Count) { '' } elseif ($q) { 'Aucun processus pour ce filtre.' } else { 'Relevé en cours...' })
    $MonUI.Hint.Visibility = $(if ($MonUI.Hint.Text) { 'Visible' } else { 'Collapsed' })
}
function Set-MonSelection($R) {
    if ($MonUI.Sel -and $MonUI.Sel.Border -and -not $MonUI.Sel.Header) { $MonUI.Sel.Border.ClearValue([Windows.Controls.Border]::BackgroundProperty) }
    $MonUI.Sel = $(if ($R -and -not $R.Header) { $R } else { $null })
    if ($MonUI.Sel) { $MonUI.Sel.Border.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, 'HoverBrush') }
    $MonUI.EndTask.IsEnabled = $MonUI.Sel -and -not (Test-MonProtected $MonUI.Sel)
}
# cible d'une action : processus (ligne dépliée) ou tous les processus du groupe
function Get-MonTargetProc($R) { if ($R.Child) { @($R.P) } else { @($R.G.Procs) } }
function Test-MonProtected($R) {
    foreach ($p in @(Get-MonTargetProc $R)) { if ($p.Pid -le 4 -or $p.Pid -eq $PID -or "$($p.Name)" -in $MonProtected) { return $true } }
    $false
}
function Show-MonMenu($R) {
    $prot = Test-MonProtected $R
    $own = @(Get-MonTargetProc $R | Where-Object { $_.Pid -eq $PID }).Count -gt 0
    $why = $(if ($own) { 'Processus de l''application elle-même' } elseif ($prot) { 'Processus critique de Windows : protégé' } else { '' })
    $path = @(Get-MonTargetProc $R | Where-Object { $_.Path } | Select-Object -First 1 | ForEach-Object { $_.Path })
    $m = [Windows.Controls.ContextMenu]::new(); $m.PlacementTarget = $R.Border
    $add = {
        param([string]$Head, [scriptblock]$Act0, [bool]$On, [string]$Tip)
        $mi = [Windows.Controls.MenuItem]::new(); $mi.Header = $Head; $mi.IsEnabled = $On; $mi.Tag = $R
        if ($Tip) { $mi.ToolTip = $Tip; [Windows.Controls.ToolTipService]::SetShowOnDisabled($mi, $true) }
        if ($Act0) { $mi.Add_Click($Act0) }
        [void]$m.Items.Add($mi)
    }
    if ($R.Child) {
        & $add 'Terminer le processus' { param($s, $e) Stop-MonTarget $s.Tag $false } (-not $prot) $why
        & $add 'Terminer l''arborescence de processus' { param($s, $e) Stop-MonTarget $s.Tag $true } (-not $prot) $why
    } else {
        & $add $(if ($R.G.Procs.Count -gt 1) { "Terminer la tâche ($($R.G.Procs.Count) processus)" } else { 'Terminer la tâche' }) { param($s, $e) Stop-MonTarget $s.Tag $false } (-not $prot) $why
    }
    [void]$m.Items.Add([Windows.Controls.Separator]::new())
    $tip = $(if ($path.Count) { '' } else { 'Chemin de l''exécutable non lisible (processus protégé)' })
    $mi = [Windows.Controls.MenuItem]::new(); $mi.Header = 'Afficher dans l''Explorateur'; $mi.IsEnabled = $path.Count -gt 0; $mi.Tag = "$($path | Select-Object -First 1)"
    if ($tip) { $mi.ToolTip = $tip; [Windows.Controls.ToolTipService]::SetShowOnDisabled($mi, $true) }
    $mi.Add_Click({ param($s, $e) Start-Process explorer.exe -ArgumentList ('/select,"{0}"' -f $s.Tag) })
    [void]$m.Items.Add($mi)
    $m.IsOpen = $true
}
# PID descendants (à toute profondeur) d'un processus, d'après la liste { Pid ; Parent } de tous les processus
function Get-MonDescendant([int]$Root, $All) {
    $seen = [Collections.Generic.HashSet[int]]::new(); $todo = [Collections.Generic.Queue[int]]::new(); $todo.Enqueue($Root)
    while ($todo.Count) { $x = $todo.Dequeue(); foreach ($c in @($All | Where-Object { [int]$_.Parent -eq $x -and [int]$_.Pid -ne $x })) { if ($seen.Add([int]$c.Pid)) { $todo.Enqueue([int]$c.Pid) } } }
    @($seen)
}
# processus encore celui du relevé : même PID et même heure de création (FILETIME du moniteur, 1 s de tolérance) ; heure
# inconnue (processus non ouvrable) : non vérifiable, accepté
function Test-MonSameProc([int]$ProcId, [long]$Created) {
    if (-not $Created) { return $true }
    $sp = Get-Process -Id $ProcId -ErrorAction SilentlyContinue; if (-not $sp) { return $false }
    try { [math]::Abs($sp.StartTime.ToFileTime() - $Created) -lt 10000000 } catch { $true }
}
function Stop-MonTarget($R, [bool]$Tree) {
    if (Test-MonProtected $R) { return }
    $ps = @(Get-MonTargetProc $R)
    $name = $(if ($R.Child) { "$($R.P.Name) (PID $($R.P.Pid))" } else { "$($R.G.Desc)" })
    $what = $(if ($Tree) { "le processus $name et tous les processus qu'il a lancés" } elseif ($ps.Count -gt 1) { "la tâche $name ($($ps.Count) processus)" } else { "la tâche $name" })
    # arborescence qui contient l'application elle-même (explorer.exe, console qui l'a lancée) : refusée, taskkill /T
    # l'aurait arrêtée aussi
    if ($Tree) {
        $all = @(Get-CimInstance Win32_Process -Property ProcessId, ParentProcessId -ErrorAction SilentlyContinue | ForEach-Object { @{ Pid = [int]$_.ProcessId; Parent = [int]$_.ParentProcessId } })
        foreach ($p in $ps) { if ($PID -in @(Get-MonDescendant $p.Pid $all)) { Show-Info "Terminer l'arborescence de $name arrêterait aussi Oliv_Maintenance, lancée depuis ce processus : terminer seulement le processus, ou fermer l'application d'abord." 'Warn'; return } }
    }
    if (-not (Confirm-Action ("Terminer $what ?`n`nLes données non enregistrées dans ce programme seront perdues."))) { return }
    $ko = [Collections.Generic.List[string]]::new()
    foreach ($p in $ps) {
        # PID réutilisé par un autre processus pendant la confirmation : ignoré (sinon un autre programme était terminé)
        if (-not (Test-MonSameProc $p.Pid $p.Created)) { continue }
        try {
            if ($Tree) {
                $out = & "$env:windir\System32\taskkill.exe" /PID $p.Pid /T /F 2>&1
                if ($LASTEXITCODE -ne 0) { throw ((@($out) -join ' ').Trim()) }
            } else { Stop-Process -Id $p.Pid -Force -ErrorAction Stop }
        } catch {
            # processus déjà terminé avec son parent : pas une erreur
            if (Get-Process -Id $p.Pid -ErrorAction SilentlyContinue) { $ko.Add(('PID {0} : {1}' -f $p.Pid, $_.Exception.Message)) }
        }
    }
    if ($ko.Count) {
        Write-UiLog ('Moniteur de ressources : {0} non terminé - {1}' -f $what, ($ko -join ' ; ')) 'WARN'
        Show-Info ("Impossible de terminer $what.`n`n" + ($ko -join "`n")) 'Warn'
    } else {
        Write-UiLog ('Moniteur de ressources : {0} terminé.' -f $what)
        Add-SessionEvent 'Moniteur' $name $(if ($Tree) { 'arborescence terminée' } else { 'terminé' }) 'ok'
    }
    Update-MonData
}
