# Sélecteur de dossier moderne (IFileOpenDialog + FOS_PICKFOLDERS, celui de l'Explorateur) ; FolderBrowserDialog en secours
function Select-Folder([string]$Title, [string]$Start, $Owner) {
    if (-not $Owner) { $Owner = $Window }
    try {
        $h = [Windows.Interop.WindowInteropHelper]::new($Owner).Handle
        return [_OlivM.FolderPick]::Pick($h, $Title, $Start)
    } catch {
        Write-FileLog "Sélecteur de dossier moderne indisponible : $($_.Exception.Message)" 'WARN'
        if (-not $Sync.FormsLoaded) { Add-Type -AssemblyName System.Windows.Forms, System.Drawing; $Sync.FormsLoaded = $true }
        $fb = [Windows.Forms.FolderBrowserDialog]::new(); $fb.Description = $Title; $fb.SelectedPath = $Start
        if ("$($fb.ShowDialog())" -eq 'OK') { return $fb.SelectedPath }
        return $null
    }
}

# Analyseur d'espace disque (fenêtre séparée) : parcours Win32 FindFirstFileEx en arrière-plan, vue en blocs (treemap)
$TreeUI = @{}
# Couleurs par catégorie (plan et liste) : C = couleur de base, T = couleur du texte posé dessus, L = libellé de la légende
$TreeCat = [ordered]@{
    Sys   = @{ C = '#5B6B82'; T = '#FFFFFF'; L = 'Système' }
    Prog  = @{ C = '#7C5CD6'; T = '#FFFFFF'; L = 'Programmes' }
    User  = @{ C = '#0F9488'; T = '#FFFFFF'; L = 'Utilisateurs' }
    Recov = @{ C = '#E0A030'; T = '#1D1F23'; L = 'Temporaires et caches' }
    Data  = @{ C = '#3B82F6'; T = '#FFFFFF'; L = 'Autres dossiers' }
    File  = @{ C = '#A7B3C2'; T = '#1D1F23'; L = 'Fichiers' }
    More  = @{ C = '#C4CBD4'; T = '#1D1F23'; L = 'Petits éléments regroupés' }
    Unk   = @{ C = '#D5DAE0'; T = '#1D1F23'; L = 'Non analysé' }
}
# Catégorie d'un élément. $Names : nom de l'élément puis ceux de ses dossiers parents, jusqu'à la racine du volume.
# Temporaires et caches reconnus à n'importe quel niveau ; sinon le dossier le plus haut décide (Windows, Program Files, Users).
function Get-TreeCategory([string[]]$Names, [bool]$IsDir, [bool]$Other) {
    if ($Other) { if ("$($Names[0])" -like 'Non analys*') { return 'Unk' } else { return 'More' } }
    foreach ($n in $Names) {
        if ($n -match '^(?i)(temp|tmp|\$recycle\.bin|windows\.old|cache|caches|cache2|code cache|gpucache|inetcache|crashdumps|minidump|d3dscache|livekernelreports)$') {
            return 'Recov'
        }
    }
    for ($i = $Names.Count - 1; $i -ge 0; $i--) {
        $n = $Names[$i]
        if ($n -match '^(?i)(windows|system volume information|recovery|boot|\$winreagent|\$windows\.~bt|\$windows\.~ws|perflogs|pagefile\.sys|hiberfil\.sys|swapfile\.sys|dumpstack\.log(\.tmp)?|bootmgr|bootnxt)$') {
            return 'Sys'
        }
        if ($n -match '^(?i)(program files|program files \(x86\)|programdata)$') { return 'Prog' }
        if ($n -match '^(?i)users$') { return 'User' }
    }
    if ($IsDir) { 'Data' } else { 'File' }
}
# couleur éclaircie (Amt : 0 = identique, 1 = blanc)
function Get-LightHex([string]$Hex, [double]$Amt) {
    $v = [Convert]::ToInt32($Hex.TrimStart('#'), 16)
    $r = ($v -shr 16) -band 255; $g = ($v -shr 8) -band 255; $b = $v -band 255
    '#{0:X2}{1:X2}{2:X2}' -f [int]($r + (255 - $r) * $Amt), [int]($g + (255 - $g) * $Amt), [int]($b + (255 - $b) * $Amt)
}
function Show-SpaceAnalyzer {
    if ($TreeUI.Win -and $TreeUI.Win.IsVisible) { $TreeUI.Win.Activate(); return }
    if (-not ('_OlivM.DirScan' -as [type])) { Write-UiLog "Analyseur d'espace indisponible : code natif non chargé." 'ERROR'; return }
    [xml]$x = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Oliv_Maintenance - Analyse de l'espace disque" Width="1120" Height="780" MinWidth="720" MinHeight="520" WindowStartupLocation="Manual"
        Background="{DynamicResource BgBrush}" Foreground="{DynamicResource FgBrush}" FontFamily="Segoe UI" FontSize="13">
  <Grid Margin="16,14,16,12">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="3*" MinHeight="180"/><RowDefinition Height="Auto"/><RowDefinition Height="2*" MinHeight="140"/><RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <DockPanel Margin="0,0,0,10">
      <StackPanel DockPanel.Dock="Right" Orientation="Horizontal">
        <Button x:Name="Pick" Content="Choisir un dossier..." Style="{DynamicResource ActionBtn}" Height="30" Margin="6,0,0,0"/>
        <Button x:Name="Stop" Content="Annuler l'analyse" Style="{DynamicResource WarnBtn}" Height="30" MinWidth="110" Margin="6,0,0,0" Visibility="Collapsed"/>
        <Button x:Name="Go" Content="Analyser" Style="{DynamicResource PrimaryBtn}" Height="30" MinWidth="110" Margin="6,0,0,0"/>
      </StackPanel>
      <TextBlock TextWrapping="Wrap" Text="Emplacement" VerticalAlignment="Center" FontWeight="SemiBold" Margin="0,0,10,0"/>
      <WrapPanel x:Name="Drives" VerticalAlignment="Center"/>
    </DockPanel>
    <DockPanel Grid.Row="1" Margin="0,0,0,8">
      <Button x:Name="Up" DockPanel.Dock="Left" Content="&#xE74A;" Style="{DynamicResource IconBtn}" Width="32" Height="30" ToolTip="Dossier parent" IsEnabled="False"/>
      <Button x:Name="Open" DockPanel.Dock="Right" Content="Ouvrir dans l'Explorateur" Style="{DynamicResource ActionBtn}" Height="28" IsEnabled="False" Visibility="Collapsed"/>
      <TextBlock x:Name="PathText" FontSize="15" FontWeight="SemiBold" VerticalAlignment="Center" Margin="8,0,8,0" TextWrapping="Wrap"/>
    </DockPanel>
    <Border Grid.Row="2" Background="{DynamicResource PanelBrush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="1" CornerRadius="8" Padding="6">
      <DockPanel>
      <WrapPanel x:Name="Legend" DockPanel.Dock="Bottom" Margin="4,8,4,0"/>
      <Grid>
        <Canvas x:Name="Map" ClipToBounds="True"/>
        <TextBlock x:Name="MapHint" Foreground="{DynamicResource MutedBrush}" HorizontalAlignment="Center" VerticalAlignment="Center" TextAlignment="Center" TextWrapping="Wrap" Margin="20"
                   Text="Choisir un volume ou un dossier puis cliquer sur Analyser.&#x0a;Clic sur un bloc : ouvrir le dossier. Clic droit : afficher dans l'Explorateur ou supprimer."/>
      </Grid>
      </DockPanel>
    </Border>
    <Grid Grid.Row="3" Margin="10,12,26,4">
      <!-- colonnes identiques aux lignes (Show-TreeList) : nom limité à 640 px, chiffres près du nom sur grand écran -->
      <Grid.ColumnDefinitions><ColumnDefinition Width="3*" MaxWidth="640"/><ColumnDefinition Width="110"/><ColumnDefinition Width="180"/><ColumnDefinition Width="110"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
      <TextBlock TextWrapping="Wrap" Text="NOM" Foreground="{DynamicResource MutedBrush}" FontSize="11" FontWeight="SemiBold" Margin="24,0,0,0"/>
      <TextBlock TextWrapping="Wrap" Grid.Column="1" Text="TAILLE" Foreground="{DynamicResource MutedBrush}" FontSize="11" FontWeight="SemiBold" HorizontalAlignment="Right"/>
      <TextBlock TextWrapping="Wrap" Grid.Column="2" Text="UTILISATION" Foreground="{DynamicResource MutedBrush}" FontSize="11" FontWeight="SemiBold" Margin="16,0,0,0"/>
      <TextBlock TextWrapping="Wrap" Grid.Column="3" Text="FICHIERS" Foreground="{DynamicResource MutedBrush}" FontSize="11" FontWeight="SemiBold" HorizontalAlignment="Right"/>
    </Grid>
    <Border Grid.Row="4" Background="{DynamicResource PanelBrush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="1" CornerRadius="6">
      <Grid>
        <ScrollViewer VerticalScrollBarVisibility="Auto"><StackPanel x:Name="List" Margin="4"/></ScrollViewer>
        <TextBlock x:Name="ListHint" Foreground="{DynamicResource MutedBrush}" HorizontalAlignment="Center" VerticalAlignment="Center" TextAlignment="Center" TextWrapping="Wrap" Margin="20" Text="Analyse en cours..." Visibility="Collapsed"/>
      </Grid>
    </Border>
    <DockPanel Grid.Row="5" Margin="0,10,0,0">
      <ProgressBar x:Name="Prog" DockPanel.Dock="Bottom" Height="4" Margin="0,6,0,0" IsIndeterminate="True" Visibility="Collapsed" Foreground="{DynamicResource AccentBrush}" Background="Transparent" BorderThickness="0"/>
      <!-- zoom propre à la fenêtre (Ctrl + molette, Ctrl + / Ctrl -, Ctrl + 0, clic sur le pourcentage : 100 %) -->
      <Border DockPanel.Dock="Left" Height="30" Padding="2,0" Margin="0,0,12,0" CornerRadius="6" Background="{DynamicResource BgBrush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="1" VerticalAlignment="Center"
              ToolTip="Taille du texte de la liste (80 à 150 %) : Ctrl + molette ou Ctrl + / Ctrl -, clic sur le pourcentage ou Ctrl + 0 pour revenir à 100 %">
        <StackPanel Orientation="Horizontal">
          <Button x:Name="ZoomOut" Style="{DynamicResource IconBtn}" Width="28" Height="26" FontSize="12" Content="&#xE71F;"/>
          <TextBlock x:Name="ZoomTxt" Foreground="{DynamicResource MutedBrush}" FontSize="12" Width="44" TextAlignment="Center" VerticalAlignment="Center" Cursor="Hand" Text="100 %"/>
          <Button x:Name="ZoomIn" Style="{DynamicResource IconBtn}" Width="28" Height="26" FontSize="12" Content="&#xE8A3;"/>
        </StackPanel>
      </Border>
      <TextBlock x:Name="Status" Foreground="{DynamicResource MutedBrush}" TextWrapping="NoWrap" TextTrimming="CharacterEllipsis"/>
    </DockPanel>
  </Grid>
</Window>
'@
    $w = [Windows.Markup.XamlReader]::Load([System.Xml.XmlNodeReader]::new($x))
    $w.Resources.MergedDictionaries.Add($Window.Resources)
    Set-ChildWindow $w 'EspaceDisque'
    Initialize-ChildZoom $w
    if ($AppIcon) { $w.Icon = $AppIcon }
    $TreeUI.Clear(); $TreeUI.Win = $w
    $TreeUI.CatFilter = [Collections.Generic.HashSet[string]]::new()
    foreach ($n in 'Drives', 'Pick', 'Stop', 'Go', 'Up', 'Open', 'PathText', 'Map', 'MapHint', 'Legend', 'List', 'ListHint', 'Prog', 'Status') {
        $TreeUI[$n] = $w.FindName($n)
    }
    $TreeUI.MapHintIdle = $TreeUI.MapHint.Text
    $TreeUI.Target = "$env:SystemDrive\"
    $TreeUI.DriveBtns = [Collections.ArrayList]::new(); $TreeUI.DriveSig = $null
    Update-TreeDrive
    # volumes branchés / retirés pendant que la fenêtre est ouverte (liste tenue à jour par le collecteur de l'Accueil)
    $TreeUI.DriveTimer = [Windows.Threading.DispatcherTimer]::new(); $TreeUI.DriveTimer.Interval = [TimeSpan]::FromSeconds(2)
    $TreeUI.DriveTimer.Add_Tick({ Update-TreeDrive }); $TreeUI.DriveTimer.Start()
    $TreeUI.PathText.Text = $TreeUI.Target
    $TreeUI.Pick.Add_Click({
        $f = Select-Folder 'Dossier à analyser' $TreeUI.Target $TreeUI.Win
        if ($f) { Set-TreeTarget $f }
    })
    $TreeUI.Go.Add_Click({ Start-TreeScan })
    $TreeUI.Stop.Add_Click({ [_OlivM.DirScan]::Cancel = $true; $TreeUI.Status.Text = 'Annulation en cours...' })
    $TreeUI.Up.Add_Click({ if ($TreeUI.Stack.Count) { $TreeUI.Stack.RemoveAt($TreeUI.Stack.Count - 1); Show-TreeNode } })
    $TreeUI.Open.Add_Click({ if ($TreeUI.Node) { Start-Process explorer.exe -ArgumentList ('"{0}"' -f $TreeUI.Node.Path) } })
    $TreeUI.Map.Add_SizeChanged({ if ($TreeUI.Node) { Show-TreeMap; if ($TreeUI.Sel) { Set-TreeSelection $TreeUI.Sel } } })
    $TreeUI.Timer = [Windows.Threading.DispatcherTimer]::new(); $TreeUI.Timer.Interval = [TimeSpan]::FromMilliseconds(300)
    $TreeUI.Timer.Add_Tick({ Update-TreeScan })
    $w.Add_Closed({
        if ($TreeUI.Job) { [_OlivM.DirScan]::Cancel = $true }
        $TreeUI.Timer.Stop(); $TreeUI.DriveTimer.Stop(); $TreeUI.Root = $null; $TreeUI.Node = $null; $TreeUI.Stack = $null
        if ($TreeUI.Job) {
            try { $TreeUI.Job.PS.EndInvoke($TreeUI.Job.Handle) } catch {}
            try { $TreeUI.Job.PS.Runspace.Dispose(); $TreeUI.Job.PS.Dispose() } catch {}
            $TreeUI.Job = $null
        }
        $TreeUI.Win = $null; [GC]::Collect()
    })
    $w.Show()
}
# volumes pendant une analyse : non désactivés (le style désactivé effaçait le bleu du volume analysé et rendait son nom
# illisible) mais sans clic ni clavier, volume analysé inchangé, autres estompés
function Set-TreeDriveLock($B, [bool]$Lock) {
    $B.IsHitTestVisible = -not $Lock; $B.Focusable = -not $Lock
    $B.Opacity = $(if ($Lock -and "$($B.Tag)" -ne 'on') { 0.5 } else { 1 })
}
function Update-TreeDrive {
    $vols = @($Sync.Vols)
    if (-not $vols.Count) {
        $vols = @(foreach ($v in [IO.DriveInfo]::GetDrives()) {
            try {
                if ("$($v.DriveType)" -in 'Fixed', 'Removable' -and $v.IsReady) { @{ Name = $v.Name; Label = $v.VolumeLabel; Rem = ("$($v.DriveType)" -eq 'Removable'); Total = [double]$v.TotalSize; Free = [double]$v.TotalFreeSpace } }
            } catch {}
        })
    }
    $sig = ($vols | ForEach-Object { "$($_.Name)|$($_.Label)|$($_.Total)" }) -join ','
    if ($sig -eq $TreeUI.DriveSig) { return }
    $TreeUI.DriveSig = $sig
    $TreeUI.Drives.Children.Clear(); $TreeUI.DriveBtns.Clear()
    foreach ($v in $vols) {
        $b = New-Button ('{0}  {1}' -f $v.Name.TrimEnd('\'), $(if ($v.Label) { $v.Label } elseif ($v.Rem) { 'Amovible' } else { 'Disque local' }))
        $b.Height = 30; $b.Padding = New-Thickness 10 0 10 0; $b.Margin = New-Thickness 0 0 6 0
        $fr = Format-SizeUi $v.Free
        $b.ToolTip = '{0} sur {1}{2}' -f $(if ($v.Free -le 0) { 'Plein' } else { '{0} {1}' -f $fr, (Get-PluralOf $fr 'libre' 'libres') }), (Format-SizeUi $v.Total), $(if ($v.Rem) { '  ·  amovible' } else { '' })
        $b.DataContext = $v.Name; $b.Tag = $(if ($v.Name -eq $TreeUI.Target) { 'on' } else { '' }); Set-TreeDriveLock $b ([bool]$TreeUI.Job)
        $b.Add_Click({ param($s, $e) Set-TreeTarget $s.DataContext })
        [void]$TreeUI.Drives.Children.Add($b); [void]$TreeUI.DriveBtns.Add($b)
    }
    # volume choisi retiré (hors analyse en cours) : retour au disque système
    if (-not $TreeUI.Job -and $TreeUI.Target.Length -le 3 -and -not ($vols | Where-Object { $_.Name -eq $TreeUI.Target })) {
        Set-TreeTarget "$env:SystemDrive\"
    }
}
function Set-TreeTarget([string]$Path) {
    if ($TreeUI.Job) { return }
    $TreeUI.Target = $Path; $TreeUI.PathText.Text = $Path
    foreach ($b in $TreeUI.DriveBtns) { $b.Tag = $(if ($b.DataContext -eq $Path) { 'on' } else { '' }) }
}
function Start-TreeScan {
    if ($TreeUI.Job -or -not (Test-Path -LiteralPath $TreeUI.Target)) { return }
    $TreeUI.Root = $null
    $TreeUI.Node = $null
    $TreeUI.Map.Children.Clear()
    $TreeUI.List.Children.Clear()
    $TreeUI.Legend.Children.Clear()
    $TreeUI.CatFilter.Clear()
    # pendant l'analyse : message centré dans le plan et dans la liste
    $TreeUI.MapHint.Text = 'Analyse en cours...'; $TreeUI.MapHint.Visibility = 'Visible'; $TreeUI.ListHint.Visibility = 'Visible'
    $TreeUI.Go.Visibility = 'Collapsed'
    $TreeUI.Pick.IsEnabled = $false
    $TreeUI.Up.IsEnabled = $false
    $TreeUI.Open.IsEnabled = $false
    $TreeUI.Stop.Visibility = 'Visible'
    $TreeUI.Stop.IsEnabled = $true
    foreach ($b in $TreeUI.DriveBtns) { Set-TreeDriveLock $b $true }
    $TreeUI.Prog.IsIndeterminate = $false; $TreeUI.Prog.Value = 0; $TreeUI.Prog.Visibility = 'Visible'; $TreeUI.Start = [DateTime]::Now
    # lecteur entier : espace occupé = référence de l'avancement (octets lus / octets occupés)
    $TreeUI.Used = 0
    if ($TreeUI.Target.Length -le 3) {
        try { $di = [IO.DriveInfo]::new($TreeUI.Target); $TreeUI.Used = [double]($di.TotalSize - $di.TotalFreeSpace) } catch {}
    }
    $Sync.TreePath = $TreeUI.Target; $Sync.TreeResult = $null
    $TreeUI.Job = New-PsJob @'
$deg = [math]::Min(8, [Environment]::ProcessorCount)
try {
    $l = "$($Sync.TreePath)".Substring(0, 1)
    $dn = (Get-Partition -DriveLetter $l -ErrorAction Stop | Get-Disk -ErrorAction Stop).Number
    $pd = Get-PhysicalDisk -ErrorAction Stop | Where-Object { "$($_.DeviceId)" -eq "$dn" } | Select-Object -First 1
    if ("$($pd.MediaType)" -eq 'HDD') { $deg = 1 }
} catch {}
$Sync.TreeDegree = $deg
$Sync.TreeResult = [_OlivM.DirScan]::Scan($Sync.TreePath, $deg)
'@
    $TreeUI.Timer.Start()
    Write-UiLog "Analyse de l'espace disque : $($TreeUI.Target)"
}
# Chemin raccourci au milieu (« C:\Program Files\...\fichier.dll ») pour tenir sur la ligne de statut après le préfixe
function Get-FitPath($Tb, [string]$Prefix, [string]$Path) {
    $w = $Tb.ActualWidth; if ($w -le 0 -or -not $Path) { return $Path }
    $tf = [Windows.Media.Typeface]::new($Tb.FontFamily, $Tb.FontStyle, $Tb.FontWeight, $Tb.FontStretch)
    $m = { param($t) [Windows.Media.FormattedText]::new($t, [Globalization.CultureInfo]::CurrentCulture, [Windows.FlowDirection]::LeftToRight, $tf, $Tb.FontSize, [Windows.Media.Brushes]::Black).WidthIncludingTrailingWhitespace }
    $room = $w - (& $m $Prefix) - 8
    if ((& $m $Path) -le $room) { return $Path }
    $lo = 0; $hi = $Path.Length; $best = '...'
    while ($lo -le $hi) {
        $k = [int][math]::Floor(($lo + $hi) / 2)
        $a = [int][math]::Ceiling($k * 0.4); $b = $k - $a
        $cand = $Path.Substring(0, $a) + '...' + $Path.Substring($Path.Length - $b)
        if ((& $m $cand) -le $room) { $best = $cand; $lo = $k + 1 } else { $hi = $k - 1 }
    }
    $best
}
# Avancement réel de l'analyse : lecteur entier = octets lus / espace occupé du volume (l'espace occupé inclut fichiers
# système, clichés instantanés et métadonnées jamais lus : la fin peut arriver avant 100 %) ; dossier = dossiers de 1er
# niveau terminés / total. Plafonné à 99 % tant que l'analyse n'est pas finie.
function Get-TreeScanProgress([double]$Bytes, [double]$Used, [int]$Done, [int]$Total) {
    if ($Used -gt 0) {
        return @{ Pct = [int][math]::Min([double]99, [math]::Floor(100 * $Bytes / $Used)); Text = $(if ($Bytes -gt 0) { '{0} lus sur {1} occupés' -f (Format-SizeUi $Bytes), (Format-SizeUi $Used) } else { 'Lecture de {0} occupés' -f (Format-SizeUi $Used) }) }
    }
    if ($Total -gt 0) {
        return @{ Pct = [int][math]::Min([double]99, [math]::Floor(100 * $Done / $Total)); Text = '{0} {1} sur {2}' -f $Done, (Get-Plural $Total 'dossier' 'dossiers'), $Total }
    }
    @{ Pct = 0; Text = $(if ($Bytes -gt 0) { '{0} lus' -f (Format-SizeUi $Bytes) } else { 'Lecture en cours' }) }
}
function Update-TreeScan {
    if ($TreeUI.DelJob) { if ($TreeUI.DelJob.Handle.IsCompleted) { Complete-TreeDelete; $TreeUI.Timer.Stop() }; return }
    $j = $TreeUI.Job; if (-not $j) { $TreeUI.Timer.Stop(); return }
    $el = [DateTime]::Now - $TreeUI.Start
    if (-not $j.Handle.IsCompleted) {
        $p = Get-TreeScanProgress ([double][_OlivM.DirScan]::Bytes) $TreeUI.Used ([_OlivM.DirScan]::TopDone) ([_OlivM.DirScan]::TopTotal)
        $TreeUI.Prog.Value = $p.Pct
        $head = ('Analyse en cours  ·  {0}{1}  ·  {2:N0} ' + (Get-Plural ([_OlivM.DirScan]::Scanned) 'fichier' 'fichiers') + '  ·  {3:mm\:ss}  ·  ') -f $(if ($p.Pct -gt 0) { "$($p.Pct) %  ·  " } else { '' }), $p.Text, [_OlivM.DirScan]::Scanned, $el
        $TreeUI.Status.Text = $head + (Get-FitPath $TreeUI.Status $head "$([_OlivM.DirScan]::Current)")
        return
    }
    $TreeUI.Timer.Stop()
    try { [void]$j.PS.EndInvoke($j.Handle) } catch { Write-UiLog "Analyse de l'espace disque : $($_.Exception.Message)" 'ERROR' }
    try { $j.PS.Runspace.Dispose(); $j.PS.Dispose() } catch {}
    $TreeUI.Job = $null
    $TreeUI.MapHint.Text = $TreeUI.MapHintIdle; $TreeUI.MapHint.Visibility = 'Collapsed'; $TreeUI.ListHint.Visibility = 'Collapsed'
    $TreeUI.Prog.Visibility = 'Collapsed'; $TreeUI.Go.Visibility = 'Visible'; $TreeUI.Pick.IsEnabled = $true; $TreeUI.Stop.Visibility = 'Collapsed'
    foreach ($b in $TreeUI.DriveBtns) { Set-TreeDriveLock $b $false }
    $root = $Sync.TreeResult; $Sync.TreeResult = $null
    if (-not $root) { $TreeUI.Status.Text = 'Analyse impossible.'; $TreeUI.MapHint.Visibility = 'Visible'; return }
    $cancel = [_OlivM.DirScan]::Cancel
    if (-not $cancel -and $root.Path.Length -le 3) {
        try {
            $di = [IO.DriveInfo]::new($root.Path); $unk = ($di.TotalSize - $di.TotalFreeSpace) - $root.Size
            if ($unk -gt 0.005 * $di.TotalSize) {
                $o = [_OlivM.DirNode]::new()
                $o.Name = 'Non analysé (fichiers système, accès refusé, métadonnées)'
                $o.Parent = $root
                $o.Size = $unk
                $o.Other = $true
                $root.Children.Add($o); $root.Children.Sort([Comparison[_OlivM.DirNode]]{ param($a, $b) $b.Size.CompareTo($a.Size) })
            }
        } catch {}
    }
    $TreeUI.Root = $root; $TreeUI.Stack = [Collections.ArrayList]::new(); [void]$TreeUI.Stack.Add($root)
    Add-SessionEvent 'Espace disque' "Analyse de $($root.Path)" $(if ($cancel) { 'annulée (résultat partiel)' } else { '{0} analysés, {1:N0} {2}' -f (Format-SizeUi $root.Size), $root.Files, (Get-Plural $root.Files 'fichier' 'fichiers') }) $(if ($cancel) { 'warn' } else { 'ok' })
    if (-not $cancel) {
        Send-AppNotification 'Analyse de l''espace disque terminée' ('{0} : {1} analysés' -f $root.Path, (Format-SizeUi $root.Size)) 'Info' $el
    }
    $msg = ('{0} : {1} dans {2:N0} ' + (Get-Plural $root.Files 'fichier' 'fichiers') + '  ·  analysé en {3:mm\:ss}{4}') -f $root.Path, (Format-SizeUi $root.Size), $root.Files, $el, $(if ([int]$Sync.TreeDegree -gt 1) { "  ·  $($Sync.TreeDegree) dossiers en parallèle" } else { '  ·  séquentiel (disque dur)' })
    if ([_OlivM.DirScan]::Denied) {
        $msg += '  ·  {0:N0} {1}' -f [_OlivM.DirScan]::Denied, (Get-Plural ([_OlivM.DirScan]::Denied) 'dossier inaccessible' 'dossiers inaccessibles')
    }
    if ([_OlivM.DirScan]::Cloud) {
        $msg += '  ·  {0:N0} {1}' -f [_OlivM.DirScan]::Cloud, (Get-Plural ([_OlivM.DirScan]::Cloud) 'fichier cloud non téléchargé compté 0' 'fichiers cloud non téléchargés comptés 0')
    }
    if ($cancel) { $msg = 'Analyse annulée (résultat partiel)  ·  ' + $msg }
    $TreeUI.Status.Text = $msg
    Write-UiLog ("Analyse de l'espace disque terminée - " + $msg)
    Show-TreeNode
}
# Éléments que l'outil refuse de supprimer : racine, Windows, Program Files, ProgramData, Users et profils, dossiers système
function Test-TreeProtected([string]$Path) {
    $p = $Path.TrimEnd('\')
    if ($p.Length -le 2) { return $true }
    $sys = $env:SystemDrive
    $deny = @($env:windir, $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData, "$sys\Users", "$sys\System Volume Information", "$sys\`$Recycle.Bin", "$sys\Recovery", "$sys\Boot", "$sys\pagefile.sys", "$sys\hiberfil.sys", "$sys\swapfile.sys", "$sys\DumpStack.log.tmp")
    foreach ($d in $deny) { if ($d -and $p -ieq $d.TrimEnd('\')) { return $true } }
    if ($p -like "$env:windir\*") { return $true }
    if ($p -match ('^' + [regex]::Escape("$sys\Users") + '\\[^\\]+$')) { return $true }
    # tout lecteur : dossiers et fichiers système à la racine (corbeille, points de restauration, fichiers d'échange)
    if ($p -match '(?i)^[a-z]:\\(System Volume Information|\$Recycle\.Bin|Recovery|pagefile\.sys|hiberfil\.sys|swapfile\.sys)$') { return $true }
    # profil : AppData et ses 3 dossiers (paramètres de tous les logiciels du compte), magasin des applications, données de Windows
    if ($p -match ('(?i)^' + [regex]::Escape("$sys\Users") + '\\[^\\]+\\AppData(\\(Local|Roaming|LocalLow))?$')) { return $true }
    foreach ($d in @("$env:ProgramFiles\WindowsApps", "$env:ProgramData\Microsoft", "$env:ProgramFiles\Common Files", "${env:ProgramFiles(x86)}\Common Files")) { if ($d -and $p -ieq $d) { return $true } }
    $false
}
function Show-TreeMenu($Src) {
    $it = $Src.DataContext
    if (-not $it -or $it.Other) { return }
    Set-TreeSelection $it
    $m = [Windows.Controls.ContextMenu]::new(); $m.PlacementTarget = $Src
    $add = {
        param([string]$Head, [scriptblock]$Act, [bool]$On = $true)
        $mi = [Windows.Controls.MenuItem]::new(); $mi.Header = $Head; $mi.IsEnabled = $On; $mi.Tag = $it
        if ($Act) { $mi.Add_Click($Act) }
        [void]$m.Items.Add($mi)
    }
    if ($it.IsDir -and -not $it.Denied -and $it.Children.Count) { & $add 'Ouvrir' { param($s, $e) Open-TreeItem $s.Tag } }
    & $add 'Afficher dans l''Explorateur' { param($s, $e) Start-Process explorer.exe -ArgumentList ('/select,"{0}"' -f $s.Tag.Path) }
    & $add 'Copier le chemin' { param($s, $e) [void](Set-ClipText "$($s.Tag.Path)" (Get-CopyDone "$($s.Header)")) }
    & $add 'Copier le nom' { param($s, $e) [void](Set-ClipText (Split-Path -Leaf "$($s.Tag.Path)") (Get-CopyDone "$($s.Header)")) }
    & $add 'Copier la taille' { param($s, $e) [void](Set-ClipText ('{0} ({1:N0} octets)' -f (Format-SizeUi $s.Tag.Size), [long]$s.Tag.Size) (Get-CopyDone "$($s.Header)")) }
    [void]$m.Items.Add([Windows.Controls.Separator]::new())
    $ok = -not (Test-TreeProtected $it.Path) -and -not $TreeUI.Job -and -not $TreeUI.DelJob
    & $add 'Mettre à la corbeille' { param($s, $e) Start-TreeDelete $s.Tag $true } $ok
    & $add 'Supprimer définitivement' { param($s, $e) Start-TreeDelete $s.Tag $false } $ok
    $m.IsOpen = $true
}
function Start-TreeDelete($Item, [bool]$Recycle) {
    if ($TreeUI.Job -or $TreeUI.DelJob -or (Test-TreeProtected $Item.Path)) { return }
    $what = $(if ($Item.IsDir) { 'le dossier' } else { 'le fichier' })
    $how = $(if ($Recycle) { "Mettre $what à la corbeille ?" } else { "Supprimer définitivement $what ?" })
    $det = "{0}`n{1}{2}" -f $Item.Path, (Format-SizeUi $Item.Size), $(if ($Item.IsDir) { '  ·  {0:N0} {1}' -f $Item.Files, (Get-Plural $Item.Files 'fichier' 'fichiers') } else { '' })
    $note = $(if ($Recycle) { 'Restauration possible depuis la corbeille. Un élément trop volumineux pour la corbeille peut être supprimé définitivement par Windows.' } else { 'Suppression sans passer par la corbeille : aucune restauration possible.' })
    if (-not (Confirm-Action ("$how`n`n$det`n`n$note"))) { return }
    $Sync.TreeDel = @{ Path = $Item.Path; Recycle = $Recycle }; $Sync.TreeDelResult = $null
    $TreeUI.DelItem = $Item
    $TreeUI.DelJob = New-PsJob '$d = $Sync.TreeDel; $rc = [_OlivM.DirScan]::Delete($d.Path, [bool]$d.Recycle); $Sync.TreeDelResult = @{ Code = $rc; Exists = (Test-Path -LiteralPath $d.Path) }'
    $TreeUI.Status.Text = "Suppression en cours : $($Item.Path)"; $TreeUI.Prog.Visibility = 'Visible'
    Write-UiLog ('{0} : {1} ({2})' -f $(if ($Recycle) { 'Mise à la corbeille' } else { 'Suppression définitive' }), $Item.Path, (Format-SizeUi $Item.Size))
    $TreeUI.Timer.Start()
}
function Complete-TreeDelete {
    $j = $TreeUI.DelJob; $it = $TreeUI.DelItem; $TreeUI.DelJob = $null; $TreeUI.DelItem = $null
    try { [void]$j.PS.EndInvoke($j.Handle) } catch {}
    try { $j.PS.Runspace.Dispose(); $j.PS.Dispose() } catch {}
    $TreeUI.Prog.Visibility = 'Collapsed'
    $r = $Sync.TreeDelResult
    if ($r -and -not $r.Exists) {
        # retrait de l'élément et mise à jour des tailles jusqu'à la racine
        $p = $it.Parent; [void]$p.Children.Remove($it)
        for ($n = $p; $n; $n = $n.Parent) { $n.Size -= $it.Size; $n.Files -= $it.Files }
        $TreeUI.Status.Text = 'Supprimé : {0} ({1}{2})' -f $it.Path, $(if ($it.Size -gt 0) { '{0} libérés' -f (Format-SizeUi $it.Size) } else { 'élément vide' }), $(if ($Sync.TreeDel.Recycle) { ', dans la corbeille' } else { '' })
        Write-UiLog ('Supprimé : {0} ({1}).' -f $it.Path, (Format-SizeUi $it.Size)) 'OK'
        Show-Toast ('{0} : {1} libérés' -f $(if ($Sync.TreeDel.Recycle) { 'Mis à la corbeille' } else { 'Supprimé' }), (Format-SizeUi $it.Size))
        Add-SessionEvent 'Espace disque' $it.Path ('{0} {1}' -f $(if ($Sync.TreeDel.Recycle) { 'mis à la corbeille' } else { 'supprimé définitivement' }), (Format-SizeUi $it.Size)) 'ok'
        Show-TreeNode
    } else {
        $TreeUI.Status.Text = 'Suppression incomplète (code {0}) : fichiers en cours d''utilisation ou accès refusé. Relancer l''analyse pour mettre à jour les tailles.' -f $(if ($r) { $r.Code } else { '?' })
        Write-UiLog ('Suppression incomplète : {0} (code {1}).' -f $it.Path, $(if ($r) { $r.Code } else { '?' })) 'WARN'
        Show-Toast 'Suppression incomplète : fichiers en cours d''utilisation ou accès refusé' $false
        Add-SessionEvent 'Espace disque' $it.Path ('suppression incomplète (code {0})' -f $(if ($r) { $r.Code } else { '?' })) 'warn'
    }
}
function Show-TreeNode {
    $n = $TreeUI.Stack[$TreeUI.Stack.Count - 1]; $TreeUI.Node = $n
    $TreeUI.PathText.Text = '{0}   ({1})' -f $n.Path, (Format-SizeUi $n.Size)
    $TreeUI.Up.IsEnabled = $TreeUI.Stack.Count -gt 1; $TreeUI.Open.IsEnabled = $true; $TreeUI.Open.Visibility = 'Visible'
    Show-TreeMap; Show-TreeList
    if ($TreeUI.Sel) { Set-TreeSelection $TreeUI.Sel }
    Update-WinTextZoom $TreeUI.Win $TreeUI.List
}
function Open-TreeItem($Item) {
    if ($Item.IsDir -and -not $Item.Denied -and $Item.Children.Count) { [void]$TreeUI.Stack.Add($Item); Show-TreeNode }
}
function Get-TreeName($Item) {
    $l = [Collections.Generic.List[string]]::new(); $x = $Item
    while ($x) {
        if ($x.Root) {
            $seg = @("$($x.Root)".TrimEnd('\') -split '\\' | Select-Object -Skip 1)
            [array]::Reverse($seg)
            foreach ($z in $seg) { if ($z) { $l.Add($z) } }
            break
        }
        $l.Add("$($x.Name)"); $x = $x.Parent
    }
    , $l.ToArray()
}
function Get-TreeCatOf($Item) { $TreeCat[(Get-TreeCategory (Get-TreeName $Item) ([bool]$Item.IsDir) ([bool]$Item.Other))] }
# fond de tuile : léger dégradé vertical (haut plus clair), mis en cache par couleur
$TreeBrushes = @{}
function Get-TileBrush([string]$Hex) {
    if ($TreeBrushes.ContainsKey($Hex)) { return $TreeBrushes[$Hex] }
    $g = [Windows.Media.LinearGradientBrush]::new(); $g.StartPoint = [Windows.Point]::new(0, 0); $g.EndPoint = [Windows.Point]::new(0, 1)
    $g.GradientStops.Add([Windows.Media.GradientStop]::new([Windows.Media.Color][Windows.Media.ColorConverter]::ConvertFromString((Get-LightHex $Hex 0.12)), 0))
    $g.GradientStops.Add([Windows.Media.GradientStop]::new([Windows.Media.Color][Windows.Media.ColorConverter]::ConvertFromString($Hex), 1))
    $g.Freeze(); $TreeBrushes[$Hex] = $g; $g
}
# Filtre par type : clic sur un type de la légende = n'afficher que ce type (plan et liste) ; clics suivants = types ajoutés
# ou retirés ; aucun type choisi = tout afficher. Gardé en naviguant dans les dossiers, remis à zéro à chaque analyse.
function Get-TreeCatKey($Item) { Get-TreeCategory (Get-TreeName $Item) ([bool]$Item.IsDir) ([bool]$Item.Other) }
function Test-TreeShown($Item) { -not $TreeUI.CatFilter -or $TreeUI.CatFilter.Count -eq 0 -or $TreeUI.CatFilter.Contains((Get-TreeCatKey $Item)) }
function Set-TreeCatFilter([string]$Key) {
    # [string] : $null arrive en chaîne vide
    if ([string]::IsNullOrEmpty($Key)) { $TreeUI.CatFilter.Clear() }
    elseif (-not $TreeUI.CatFilter.Remove($Key)) { [void]$TreeUI.CatFilter.Add($Key) }
    Show-TreeMap; Show-TreeList
    if ($TreeUI.Sel) { Set-TreeSelection $TreeUI.Sel }
}
function Show-TreeLegend($N) {
    $lg = $TreeUI.Legend; if (-not $lg) { return }
    $lg.Children.Clear(); if (-not $N) { return }
    $sum = @{}; foreach ($c in @($N.Children)) { $k = Get-TreeCatKey $c; $sum[$k] = [double]$sum[$k] + $c.Size }
    $on = $TreeUI.CatFilter -and $TreeUI.CatFilter.Count -gt 0
    foreach ($k in $TreeCat.Keys) {
        if (-not $sum[$k] -or $k -eq 'More') { continue }
        $sel = $on -and $TreeUI.CatFilter.Contains($k)
        $pill = [Windows.Controls.Border]::new()
        $pill.CornerRadius = [Windows.CornerRadius]::new(12)
        $pill.Padding = New-Thickness 10 3 12 3
        $pill.Margin = New-Thickness 0 2 8 2
        $pill.BorderThickness = New-Thickness 1 1 1 1; $pill.Cursor = [Windows.Input.Cursors]::Hand; $pill.Tag = $k
        if ($sel) {
            $pill.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, 'BtnBrush')
            $pill.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, 'AccentBrush')
        }
        else {
            $pill.Background = [Windows.Media.Brushes]::Transparent
            $pill.BorderBrush = [Windows.Media.Brushes]::Transparent
            if ($on) { $pill.Opacity = 0.5 }
        }
        $pill.ToolTip = $(if ($sel) { 'Retirer ce type de l''affichage' } elseif ($on) { 'Ajouter ce type à l''affichage' } else { 'N''afficher que ce type' })
        $sp = [Windows.Controls.StackPanel]::new(); $sp.Orientation = 'Horizontal'
        $d = [Windows.Shapes.Ellipse]::new()
        $d.Width = 10
        $d.Height = 10
        $d.Fill = New-Brush $TreeCat[$k].C
        $d.VerticalAlignment = 'Center'
        $d.Margin = New-Thickness 0 0 7 0
        $t = New-Text $TreeCat[$k].L; $t.FontSize = 12; $t.VerticalAlignment = 'Center'; if ($sel) { $t.FontWeight = [Windows.FontWeights]::SemiBold }
        $v = New-Text ('  ' + (Format-SizeUi $sum[$k])) 'Muted'; $v.FontSize = 12; $v.VerticalAlignment = 'Center'
        [void]$sp.Children.Add($d); [void]$sp.Children.Add($t); [void]$sp.Children.Add($v); $pill.Child = $sp
        $pill.Add_MouseEnter({ param($s, $e)
            if ($s.BorderBrush -eq [Windows.Media.Brushes]::Transparent) { $s.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, 'HoverBrush') }
        })
        $pill.Add_MouseLeave({ param($s, $e)
            if ($s.BorderBrush -eq [Windows.Media.Brushes]::Transparent) { $s.Background = [Windows.Media.Brushes]::Transparent }
        })
        $pill.Add_MouseLeftButtonDown({ param($s, $e) $TreeUI.Press = $s })
        $pill.Add_MouseLeftButtonUp({ param($s, $e)
            if (-not [object]::ReferenceEquals($TreeUI.Press, $s)) { return }
            $TreeUI.Press = $null
            Set-TreeCatFilter "$($s.Tag)"
        })
        [void]$lg.Children.Add($pill)
    }
    if ($on) {
        $all = New-Button 'Afficher tous les types'
        $all.Height = 26
        $all.MinWidth = 0
        $all.Padding = New-Thickness 12 0 12 0
        $all.Margin = New-Thickness 4 2 0 2
        $all.Add_Click({ Set-TreeCatFilter $null }); [void]$lg.Children.Add($all)
    }
}
function Show-TreeMap {
    $cv = $TreeUI.Map; $cv.Children.Clear()
    $n = $TreeUI.Node; $w = $cv.ActualWidth; $h = $cv.ActualHeight
    Show-TreeLegend $n
    if (-not $n -or $w -lt 20 -or $h -lt 20 -or $n.Size -le 0) { return }
    # éléments trop petits pour être lisibles (moins de ~2 200 px²) regroupés en une tuile « N autres éléments »
    $kids = @($n.Children | Where-Object { $_.Size -gt 0 -and (Test-TreeShown $_) })
    $TreeUI.MapHint.Visibility = 'Collapsed'
    if (-not $kids.Count) { $TreeUI.MapHint.Text = 'Aucun élément de ce type dans ce dossier.'; $TreeUI.MapHint.Visibility = 'Visible'; return }
    $tot = [double]0; foreach ($c in $kids) { $tot += $c.Size }; $area = $w * $h; $pcBase = [double]$n.Size
    $keep = [Collections.ArrayList]::new(); $rest = [Collections.ArrayList]::new()
    foreach ($c in $kids) {
        if ($keep.Count -eq 0 -or ($keep.Count -lt 60 -and ($c.Size / $tot * $area) -ge 2200)) { [void]$keep.Add($c) } else { [void]$rest.Add($c) }
    }
    if ($rest.Count -eq 1) { [void]$keep.Add($rest[0]) }
    elseif ($rest.Count -gt 1) {
        $o = [_OlivM.DirNode]::new(); $o.Name = '{0} autres éléments' -f $rest.Count; $o.Parent = $n; $o.Other = $true
        foreach ($c in $rest) { $o.Size += $c.Size; $o.Files += [math]::Max([double]1, $c.Files) }
        $o.Root = $null; [void]$keep.Add($o)
        $TreeUI.MoreTip = (@($rest | Select-Object -First 10 | ForEach-Object { '{0}  ·  {1}' -f $_.Name, (Format-SizeUi $_.Size) }) -join "`n") + $(if ($rest.Count -gt 10) { "`n..." } else { '' })
    }
    $items = @($keep | Sort-Object Size -Descending)
    if (-not $items.Count) { return }
    $scale = ($w * $h) / [double](($items | Measure-Object -Property Size -Sum).Sum)
    $rx = 0.0; $ry = 0.0; $rw = [double]$w; $rh = [double]$h; $i = 0; $rank = @{}
    while ($i -lt $items.Count) {
        $side = [math]::Min($rw, $rh); $row = [Collections.ArrayList]::new(); $sum = 0.0; $worst = [double]::MaxValue
        while ($i -lt $items.Count) {
            $a = $items[$i].Size * $scale; $ns = $sum + $a
            $mx = [math]::Max($(if ($row.Count) { $items[$row[0]].Size * $scale } else { $a }), $a); $mn = $a
            $nW = [math]::Max(($side * $side * $mx) / ($ns * $ns), ($ns * $ns) / ($side * $side * $mn))
            if ($row.Count -and $nW -gt $worst) { break }
            [void]$row.Add($i); $sum = $ns; $worst = $nW; $i++
        }
        $thick = $sum / $side; $off = 0.0
        foreach ($k in $row) {
            $len = ($items[$k].Size * $scale) / $thick
            if ($rw -ge $rh) { $bx = $rx; $by = $ry + $off; $bw = $thick; $bh = $len } else { $bx = $rx + $off; $by = $ry; $bw = $len; $bh = $thick }
            $off += $len
            $it = $items[$k]
            $ck = Get-TreeCategory (Get-TreeName $it) ([bool]$it.IsDir) ([bool]$it.Other); $cat = $TreeCat[$ck]
            # tuiles d'une même catégorie : teinte un peu plus claire à chaque rang, pour les distinguer côte à côte
            $r = [int]$rank[$ck]; $rank[$ck] = $r + 1
            $b = [Windows.Controls.Border]::new()
            $b.Width = [math]::Max([double]0, $bw - 3); $b.Height = [math]::Max([double]0, $bh - 3)
            [Windows.Controls.Canvas]::SetLeft($b, $bx + 1.5); [Windows.Controls.Canvas]::SetTop($b, $by + 1.5)
            $b.Background = Get-TileBrush (Get-LightHex $cat.C ([math]::Min(0.24, 0.08 * $r))); $b.CornerRadius = [Windows.CornerRadius]::new(6)
            $b.BorderBrush = [Windows.Media.Brushes]::Transparent; $b.BorderThickness = New-Thickness 2 2 2 2
            $pc = 100 * $it.Size / $pcBase
            $b.ToolTip = $(if ($it.Other -and $it.Name -like '* autres éléments') { "{0}  ·  {1}  ·  {2:N1} %`n`n{3}" -f $it.Name, (Format-SizeUi $it.Size), $pc, $TreeUI.MoreTip }
                           else { "{0}`n{1}  ·  {2:N1} %  ·  {3}{4}" -f $it.Name, (Format-SizeUi $it.Size), $pc, $cat.L, $(if ($it.IsDir -and -not $it.Other) { "`n{0:N0} {1}`n{2}" -f $it.Files, (Get-Plural $it.Files 'fichier' 'fichiers'), $it.Path } else { '' }) })
            $fg = New-Brush $cat.T
            if ($bw -gt 64 -and $bh -gt 40) {
                $sp = [Windows.Controls.StackPanel]::new(); $sp.Margin = New-Thickness 8 6 6 4
                $t1 = New-Text $it.Name
                $t1.FontSize = 13
                $t1.FontWeight = [Windows.FontWeights]::SemiBold
                $t1.TextWrapping = 'NoWrap'
                $t1.TextTrimming = 'CharacterEllipsis'
                $t1.Foreground = $fg
                $t2 = New-Text ('{0}  ·  {1:N1} %' -f (Format-SizeUi $it.Size), $pc)
                $t2.FontSize = 11
                $t2.Foreground = $fg
                $t2.Opacity = 0.85
                $t2.TextWrapping = 'NoWrap'
                $t2.TextTrimming = 'CharacterEllipsis'
                [void]$sp.Children.Add($t1); [void]$sp.Children.Add($t2); $b.Child = $sp
            } elseif ($bw -gt 46 -and $bh -gt 22) {
                $t1 = New-Text $it.Name
                $t1.FontSize = 11
                $t1.Margin = New-Thickness 6 3 4 2
                $t1.TextWrapping = 'NoWrap'
                $t1.TextTrimming = 'CharacterEllipsis'
                $t1.Foreground = $fg
                $b.Child = $t1
            }
            $b.DataContext = $it
            if ($it.IsDir -and -not $it.Other) { $b.Cursor = [Windows.Input.Cursors]::Hand }
            $b.Add_MouseEnter({ param($s, $e) $s.Opacity = 0.86 })
            $b.Add_MouseLeave({ param($s, $e) $s.Opacity = 1 })
            # clic = appui ET relâchement sur le même bloc : le relâchement d'un double clic sur la barre de titre
            # (agrandissement de la fenêtre) qui tombe sur un bloc après redimensionnement n'ouvre pas de dossier
            $b.Add_MouseLeftButtonDown({ param($s, $e) $TreeUI.Press = $s })
            $b.Add_MouseLeftButtonUp({ param($s, $e)
                if (-not [object]::ReferenceEquals($TreeUI.Press, $s)) { return }
                $TreeUI.Press = $null
                $it = $s.DataContext
                if ($it.IsDir -and -not $it.Other -and -not $it.Denied -and $it.Children.Count) { Open-TreeItem $it } else { Set-TreeSelection $it }
            })
            $b.Add_MouseRightButtonDown({ param($s, $e) $TreeUI.RPress = $s })
            $b.Add_MouseRightButtonUp({ param($s, $e)
                if (-not [object]::ReferenceEquals($TreeUI.RPress, $s)) { return }
                $TreeUI.RPress = $null
                Show-TreeMenu $s
            })
            [void]$cv.Children.Add($b)
        }
        if ($rw -ge $rh) { $rx += $thick; $rw -= $thick } else { $ry += $thick; $rh -= $thick }
    }
}
# Élément sélectionné (clic) : ligne surlignée avec barre d'accent, bloc correspondant entouré (couleur du texte du thème)
function Set-TreeSelection($Item) {
    $TreeUI.Sel = $Item
    foreach ($r in $TreeUI.List.Children) {
        if ($r.DataContext -eq $Item) {
            $r.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, 'BtnBrush')
            $r.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, 'AccentBrush')
            $r.BorderThickness = New-Thickness 3 0 0 0
        }
        else {
            $r.ClearValue([Windows.Controls.Border]::BackgroundProperty)
            $r.ClearValue([Windows.Controls.Border]::BorderBrushProperty)
            $r.BorderThickness = New-Thickness 0 0 0 0
        }
    }
    foreach ($b in $TreeUI.Map.Children) {
        if ($b.DataContext -eq $Item) { $b.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, 'FgBrush') }
        else { $b.BorderBrush = [Windows.Media.Brushes]::Transparent }
    }
}
function Show-TreeList {
    $l = $TreeUI.List; $l.Children.Clear(); $n = $TreeUI.Node
    foreach ($it in @($n.Children | Where-Object { Test-TreeShown $_ } | Select-Object -First 200)) {
        $row = [Windows.Controls.Border]::new(); $row.Style = $Window.FindResource('HoverPlain'); $row.DataContext = $it
        $g = [Windows.Controls.Grid]::new(); $g.Margin = New-Thickness 6 4 16 4
        foreach ($wd in '3*', '110', '180', '110', '*') {
            $cd = [Windows.Controls.ColumnDefinition]::new()
            $cd.Width = $(if ($wd -like '*`*') { [Windows.GridLength]::new($(if ($wd -eq '3*') { 3 } else { 1 }), 'Star') } else { [Windows.GridLength]::new([double]$wd) })
            if ($wd -eq '3*') { $cd.MaxWidth = 640 }
            [void]$g.ColumnDefinitions.Add($cd)
        }
        $nm = [Windows.Controls.DockPanel]::new()
        # pastille pleine de la couleur de la catégorie (comme la légende) : un contour vide ressemblait à une case à cocher
        $cc = (Get-TreeCatOf $it).C
        $ic = [Windows.Shapes.Ellipse]::new()
        $ic.Width = 10
        $ic.Height = 10
        $ic.Fill = New-Brush $cc
        $ic.Margin = New-Thickness 2 0 12 0
        $ic.VerticalAlignment = 'Center'
        $tn = New-Text $(if ($it.Denied) { "$($it.Name)  (accès refusé)" } else { $it.Name })
        $tn.TextWrapping = 'NoWrap'
        $tn.TextTrimming = 'CharacterEllipsis'
        $tn.ToolTip = $it.Path
        $tn.VerticalAlignment = 'Center'
        if ($it.IsDir -and -not $it.Other) { $tn.FontWeight = [Windows.FontWeights]::SemiBold }
        [void]$nm.Children.Add($ic); [void]$nm.Children.Add($tn)
        $sz = New-Text (Format-SizeUi $it.Size)
        $sz.HorizontalAlignment = 'Right'
        $sz.FontWeight = [Windows.FontWeights]::SemiBold
        [Windows.Controls.Grid]::SetColumn($sz, 1)
        $pct = $(if ($n.Size -gt 0) { 100.0 * $it.Size / $n.Size } else { 0 })
        $bar = [Windows.Controls.Grid]::new(); $bar.Margin = New-Thickness 16 0 0 0; [Windows.Controls.Grid]::SetColumn($bar, 2)
        $bg = [Windows.Controls.Border]::new()
        $bg.Height = 6
        $bg.CornerRadius = [Windows.CornerRadius]::new(3)
        $bg.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, 'BtnBrush')
        $bg.Margin = New-Thickness 0 0 48 0
        $fg = [Windows.Controls.Border]::new()
        $fg.Height = 6
        $fg.CornerRadius = [Windows.CornerRadius]::new(3)
        $fg.HorizontalAlignment = 'Left'
        $fg.Background = New-Brush $cc
        $fg.Width = [math]::Max([double]1, 116 * $pct / 100)
        $pt = New-Text ('{0:N1} %' -f $pct) 'Muted'; $pt.FontSize = 11; $pt.HorizontalAlignment = 'Right'; $pt.VerticalAlignment = 'Center'
        [void]$bar.Children.Add($bg); [void]$bar.Children.Add($fg); [void]$bar.Children.Add($pt)
        $fc = New-Text $(if ($it.IsDir -or $it.Other) { '{0:N0}' -f $it.Files } else { '' }) 'Muted'
        $fc.HorizontalAlignment = 'Right'
        [Windows.Controls.Grid]::SetColumn($fc, 3)
        [void]$g.Children.Add($nm); [void]$g.Children.Add($sz); [void]$g.Children.Add($bar); [void]$g.Children.Add($fc)
        $row.Child = $g
        if ($it.IsDir -and -not $it.Other) { $row.Cursor = [Windows.Input.Cursors]::Hand }
        $row.Add_MouseLeftButtonDown({ param($s, $e)
            if ($e.ClickCount -eq 2) { Open-TreeItem $s.DataContext } else { Set-TreeSelection $s.DataContext }
        })
        $row.Add_MouseRightButtonUp({ param($s, $e) Show-TreeMenu $s })
        [void]$l.Children.Add($row)
    }
}

