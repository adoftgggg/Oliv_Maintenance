# Barre de titre dessinée par l'application (comme la fenêtre principale) : icône, titre, réduire / agrandir / fermer,
# thème clair / sombre ; fenêtre sans cadre Windows (WindowChrome) et agrandissement calé exactement sur la zone de travail
# (WinPlace.MaxHook, découpage WindowChrome retiré) : avec la barre native, la fenêtre agrandie laissait une ligne de
# pixels non couverte en haut de l'écran.
function Add-AppChrome($W) {
    $ch = [Windows.Shell.WindowChrome]::new(); $ch.CaptionHeight = 40; $ch.ResizeBorderThickness = New-Thickness 6 6 6 6
    $ch.GlassFrameThickness = New-Thickness 0 0 0 0; $ch.CornerRadius = [Windows.CornerRadius]::new(0); $ch.UseAeroCaptionButtons = $false
    [Windows.Shell.WindowChrome]::SetWindowChrome($W, $ch)
    $old = $W.Content; $W.Content = $null
    $rb = [Windows.Controls.Border]::new()
    $rb.BorderThickness = New-Thickness 1 1 1 1
    $rb.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, 'LineBrush')
    $dp = [Windows.Controls.DockPanel]::new(); $dp.LastChildFill = $true; $rb.Child = $dp
    $bar = [Windows.Controls.Grid]::new(); $bar.Height = 40; $bar.SetResourceReference([Windows.Controls.Panel]::BackgroundProperty, 'PanelBrush')
    [Windows.Controls.DockPanel]::SetDock($bar, 'Top')
    [void]$bar.ColumnDefinitions.Add([Windows.Controls.ColumnDefinition]::new())
    $c2 = [Windows.Controls.ColumnDefinition]::new()
    $c2.Width = [Windows.GridLength]::Auto
    [void]$bar.ColumnDefinitions.Add($c2)
    $tp = [Windows.Controls.StackPanel]::new(); $tp.Orientation = 'Horizontal'; $tp.VerticalAlignment = 'Center'; $tp.Margin = New-Thickness 12 0 0 0
    if ($AppIcon) {
        $im = [Windows.Controls.Image]::new()
        $im.Source = $AppIcon
        $im.Width = 16
        $im.Height = 16
        $im.Margin = New-Thickness 0 0 10 0
        [void]$tp.Children.Add($im)
    }
    $tt = New-Text "$($W.Title)"; $tt.FontSize = 12; $tt.VerticalAlignment = 'Center'; $tt.TextTrimming = 'CharacterEllipsis'; [void]$tp.Children.Add($tt)
    [void]$bar.Children.Add($tp)
    $bp = [Windows.Controls.StackPanel]::new()
    $bp.Orientation = 'Horizontal'
    $bp.VerticalAlignment = 'Center'
    $bp.Margin = New-Thickness 0 0 4 0
    [Windows.Controls.Grid]::SetColumn($bp, 1)
    $mk = { param($G, $Tip, $St)
        $b = [Windows.Controls.Button]::new()
        $b.Content = [string][char]$G
        $b.Style = $Window.FindResource($St)
        $b.ToolTip = $Tip
        $b.Height = 30
        $b.Tag = $W
        [void]$bp.Children.Add($b)
        $b
    }
    $bMin = & $mk 0xE921 'Réduire' 'IconBtn'; $bMax = & $mk 0xE922 'Agrandir' 'IconBtn'; $bCl = & $mk 0xE8BB 'Fermer' 'CloseBtn'
    $bMin.Add_Click({ param($s, $e) $s.Tag.WindowState = 'Minimized' })
    $bMax.Add_Click({ param($s, $e) $s.Tag.WindowState = $(if ($s.Tag.WindowState -eq 'Maximized') { 'Normal' } else { 'Maximized' }) })
    $bCl.Add_Click({ param($s, $e) $s.Tag.Close() })
    [void]$bar.Children.Add($bp)
    [void]$dp.Children.Add($bar)
    if ($old) { [void]$dp.Children.Add($old) }
    $W.Content = $rb
    $W.Resources['_olivmChrome'] = @{ Root = $rb; Max = $bMax }
    $W.Add_SourceInitialized({ param($s, $e)
        try { [Windows.Interop.HwndSource]::FromHwnd([Windows.Interop.WindowInteropHelper]::new($s).Handle).AddHook($script:MaxHook) } catch { Write-Ignored 'Agrandissement de la fenêtre' $_ }
        try { [void][_OlivM.WinPlace]::RoundCorners([Windows.Interop.WindowInteropHelper]::new($s).Handle) } catch { Write-Ignored 'Coins arrondis de la fenêtre' $_ }
    })
    $upd = { param($s, $e)
        $c = $s.Resources['_olivmChrome']; if (-not $c) { return }
        if ($s.WindowState -eq 'Maximized') {
            $c.Root.Margin = Get-MaxOverhang $s
            $c.Root.BorderThickness = New-Thickness 0 0 0 0
            $c.Max.Content = [string][char]0xE923
            $c.Max.ToolTip = 'Restaurer'
        }
        else {
            $c.Root.Margin = New-Thickness 0 0 0 0
            $c.Root.BorderThickness = New-Thickness 1 1 1 1
            $c.Max.Content = [string][char]0xE922
            $c.Max.ToolTip = 'Agrandir'
        }
    }
    $W.Add_StateChanged($upd)
    $W.Add_SizeChanged({ param($s, $e)
        if ($s.WindowState -eq 'Maximized') { $c = $s.Resources['_olivmChrome']; if ($c) { $c.Root.Margin = Get-MaxOverhang $s } }
    })
    $W.Add_ContentRendered($upd)
}
function Set-ChildWindow($W, [string]$Name) {
    Add-AppChrome $W
    Add-WindowAnim $W
    $W.Add_PreviewMouseWheel($ZoomWheel); $W.Add_PreviewKeyDown($ZoomKeys); $W.Add_ContentRendered({ param($s, $e) Set-WindowZoom $s })
    if ($Name) {
        $W.Uid = $Name; $W.Add_Closing({ param($s, $e) Save-WindowPlacement "$($s.Uid)" $s })
        if (Restore-WindowPlacement $Name $W) { return }
    }
    try {
        if ($Window.WindowState -eq 'Normal') {
            $W.Left = $Window.Left + [math]::Max([double]0, ($Window.ActualWidth - $W.Width) / 2)
            $W.Top  = $Window.Top + [math]::Max([double]0, ($Window.ActualHeight - $W.Height) / 2)
        } else { $W.WindowStartupLocation = 'CenterScreen' }
    } catch { $W.WindowStartupLocation = 'CenterScreen' }
}
# Boîte de dialogue de l'application (remplace la MessageBox Windows, non thémable et à largeur fixe) :
# icône de type, titre (1er paragraphe du message), texte, liste défilante optionnelle, note, boutons personnalisés.
# Boutons : @{ T = 'texte'; V = 'valeur renvoyée'; S = 'PrimaryBtn|WarnBtn|ActionBtn'; D = défaut (Entrée); C = annulation (Échap) }
function Show-Dialog([string]$Message, [string]$Kind = 'Info', [object[]]$Buttons, [string[]]$List, [string]$Foot, [int]$Width = 0, $Extra, [scriptblock]$OnReady) {
    if (-not $Buttons) { $Buttons = @(@{ T = 'OK'; V = 'OK'; S = 'PrimaryBtn'; D = $true; C = $true }) }
    if (-not $Width) { $Width = $(if ($List) { 760 } else { 600 }) }
    $x = [xml]@"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Oliv_Maintenance" Width="$Width" SizeToContent="Height" MaxHeight="780" WindowStartupLocation="CenterOwner" ResizeMode="NoResize"
        ShowInTaskbar="False" Background="{DynamicResource BgBrush}" Foreground="{DynamicResource FgBrush}" FontFamily="Segoe UI" FontSize="13" UseLayoutRounding="True">
  <DockPanel>
    <Border DockPanel.Dock="Bottom" Background="{DynamicResource PanelBrush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="0,1,0,0" Padding="22,12,22,12">
      <StackPanel x:Name="Btns" Orientation="Horizontal" HorizontalAlignment="Right"/>
    </Border>
    <Grid Margin="22,20,22,18">
      <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
      <TextBlock x:Name="Ico" FontFamily="Segoe MDL2 Assets" FontSize="26" VerticalAlignment="Top" Margin="0,0,16,0"/>
      <DockPanel Grid.Column="1">
        <TextBlock x:Name="Head" DockPanel.Dock="Top" FontSize="15" FontWeight="SemiBold" TextWrapping="Wrap"/>
        <TextBlock x:Name="Body" DockPanel.Dock="Top" TextWrapping="Wrap" Margin="0,8,0,0" Foreground="{DynamicResource FgBrush}"/>
        <TextBlock x:Name="Foot" DockPanel.Dock="Bottom" Foreground="{DynamicResource MutedBrush}" TextWrapping="Wrap" Margin="0,12,0,0"/>
        <ContentControl x:Name="Extra" DockPanel.Dock="Bottom" Margin="0,14,0,0" Focusable="False"/>
        <Border x:Name="ListBox" Background="{DynamicResource PanelBrush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="1" CornerRadius="6" Margin="0,12,0,0">
          <ScrollViewer VerticalScrollBarVisibility="Auto" MaxHeight="460"><StackPanel x:Name="List" Margin="12,8,12,8"/></ScrollViewer>
        </Border>
      </DockPanel>
    </Grid>
  </DockPanel>
</Window>
"@
    $dlg = [Windows.Markup.XamlReader]::Load([System.Xml.XmlNodeReader]::new($x))
    $dlg.Resources.MergedDictionaries.Add($Window.Resources)
    # propriétaire : fenêtre active de l'application (analyseur d'espace disque ou fenêtre principale)
    $own = $(if ($TreeUI.Win -and $TreeUI.Win.IsActive) { $TreeUI.Win } elseif ($SoftUI.Win -and $SoftUI.Win.IsActive) { $SoftUI.Win } elseif ($EnvUI.Win -and $EnvUI.Win.IsActive) { $EnvUI.Win } elseif ($Window.IsVisible) { $Window } else { $null })
    if ($own) { $dlg.Owner = $own } else { $dlg.WindowStartupLocation = 'CenterScreen' }
    if ($AppIcon) { $dlg.Icon = $AppIcon }; Add-WindowAnim $dlg
    $k = @{ Info = @(0xE946, 'AccentBrush'); Question = @(0xE9CE, 'AccentBrush'); Warn = @(0xE7BA, 'WarnFgBrush'); Error = @(0xEA39, 'ErrFgBrush'); Ok = @(0xE930, 'OkFgBrush') }[$Kind]
    if (-not $k) { $k = @(0xE946, 'AccentBrush') }
    $ico = $dlg.FindName('Ico'); $ico.Text = [string][char]$k[0]; $ico.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, $k[1])
    $parts = "$Message" -split "`r?`n`r?`n", 2
    $dlg.FindName('Head').Text = $parts[0].Trim()
    $bd = $dlg.FindName('Body'); if ($parts.Count -gt 1 -and $parts[1].Trim()) { $bd.Text = $parts[1].Trim() } else { $bd.Visibility = 'Collapsed' }
    $ft = $dlg.FindName('Foot'); if ($Foot) { $ft.Text = $Foot } else { $ft.Visibility = 'Collapsed' }
    $lst = $dlg.FindName('List')
    if ($List) {
        foreach ($l in $List) { $t = New-Text $l; $t.TextWrapping = 'Wrap'; $t.Margin = New-Thickness 0 2 0 2; [void]$lst.Children.Add($t) }
    }
    else { $dlg.FindName('ListBox').Visibility = 'Collapsed' }
    $ex = $dlg.FindName('Extra'); if ($Extra) { $ex.Content = $Extra } else { $ex.Visibility = 'Collapsed' }
    $res = @{ V = $null }
    $cancelV = $null
    $bp = $dlg.FindName('Btns')
    # disposition commune à toutes les confirmations : actions à gauche (grises, rouges si irréversibles),
    # bouton d'annulation (Non / Annuler / Plus tard...) tout à droite, en bleu, et validé par Entrée
    $ordered = @(@($Buttons | Where-Object { -not $_.C }) + @($Buttons | Where-Object { $_.C }))
    $hasCancel = @($Buttons | Where-Object { $_.C }).Count -gt 0
    foreach ($b in $ordered) {
        $st = $(if ($b.C) { 'PrimaryBtn' } elseif ($b.S -eq 'WarnBtn') { 'WarnBtn' } else { 'ActionBtn' })
        $btn = New-Button $b.T $st; $btn.MinWidth = 96; $btn.Margin = New-Thickness 8 0 0 0
        if ($(if ($hasCancel) { $b.C } else { $b.D })) { $btn.IsDefault = $true }
        if ($b.C) { $btn.IsCancel = $true; $cancelV = $b.V }
        if ($b.K) { $btn.Name = $b.K }
        $btn.Tag = @{ V = $b.V; R = $res; W = $dlg }
        $btn.Add_Click({ param($s, $e) $s.Tag.R.V = $s.Tag.V; $s.Tag.W.Close() })
        [void]$bp.Children.Add($btn)
    }
    if ($OnReady) { & $OnReady $dlg $bp }
    $dlg.Add_ContentRendered({
        param($s, $e)
        if ($s.Tag -is [Windows.Controls.Control]) { [void]$s.Tag.Focus(); if ($s.Tag -is [Windows.Controls.TextBox]) { $s.Tag.SelectAll() }; return }
        $bt = $s.FindName('Btns'); if ($bt) { foreach ($c in $bt.Children) { if ($c.IsDefault) { [void]$c.Focus() } } }
    })
    [void]$dlg.ShowDialog()
    $(if ($null -ne $res.V) { $res.V } else { $cancelV })
}
function Show-Info([string]$Message, [string]$Kind = 'Info') { [void](Show-Dialog $Message $Kind) }
# Confirmation avec liste longue (restauration d'instantané ou d'usine) : Non par défaut
function Confirm-List([string]$Head, [string[]]$Lines, [string]$Foot, [string]$YesText = 'Oui', [string]$YesStyle = 'WarnBtn') {
    (Show-Dialog $Head 'Warn' @(@{ T = 'Non'; V = $false; D = $true; C = $true }, @{ T = $YesText; V = $true; S = $YesStyle }) $Lines $Foot) -eq $true
}
function Request-AdminAuth([string]$Purpose) {
    $x = [xml]@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Authentification administrateur" Width="440" SizeToContent="Height" WindowStartupLocation="CenterOwner" ResizeMode="NoResize"
        ShowInTaskbar="False" Background="{DynamicResource BgBrush}" Foreground="{DynamicResource FgBrush}" FontFamily="Segoe UI" FontSize="13">
  <StackPanel Margin="22,20,22,18">
    <TextBlock x:Name="Head" FontSize="15" FontWeight="SemiBold" TextWrapping="Wrap"/>
    <TextBlock Text="Identifiants d'un compte administrateur de ce poste." Foreground="{DynamicResource MutedBrush}" Margin="0,4,0,14" TextWrapping="Wrap"/>
    <TextBlock TextWrapping="Wrap" Text="Compte"/>
    <TextBlock Text="DOMAINE\utilisateur, utilisateur@domaine ou compte local" Foreground="{DynamicResource MutedBrush}" FontSize="12" TextWrapping="Wrap" Margin="0,1,0,0"/>
    <TextBox x:Name="User" Margin="0,4,0,10" Padding="6,5" Background="{DynamicResource PanelBrush}" Foreground="{DynamicResource FgBrush}" BorderBrush="{DynamicResource LineBrush}" CaretBrush="{DynamicResource FgBrush}"/>
    <TextBlock TextWrapping="Wrap" Text="Mot de passe"/>
    <PasswordBox x:Name="Pass" Margin="0,4,0,4" Padding="6,5" Background="{DynamicResource PanelBrush}" Foreground="{DynamicResource FgBrush}" BorderBrush="{DynamicResource LineBrush}" CaretBrush="{DynamicResource FgBrush}"/>
    <TextBlock x:Name="Err" Foreground="{DynamicResource ErrFgBrush}" TextWrapping="Wrap" Visibility="Collapsed" Margin="0,6,0,0"/>
    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,16,0,0">
      <Button x:Name="Ok" Content="Valider" Style="{DynamicResource ActionBtn}" Margin="0,0,8,0" IsDefault="True"/>
      <Button x:Name="Cancel" Content="Annuler" Style="{DynamicResource PrimaryBtn}" Margin="0" IsCancel="True"/>
    </StackPanel>
  </StackPanel>
</Window>
'@
    $dlg = [Windows.Markup.XamlReader]::Load([System.Xml.XmlNodeReader]::new($x))
    $dlg.Resources.MergedDictionaries.Add($Window.Resources)
    $dlg.Owner = $Window
    if ($AppIcon) { $dlg.Icon = $AppIcon }; Add-WindowAnim $dlg -NoClose
    $d = @{ User = $dlg.FindName('User'); Pass = $dlg.FindName('Pass'); Err = $dlg.FindName('Err'); Ok = $dlg.FindName('Ok'); Win = $dlg; Account = $null; Tries = 0 }
    $dlg.FindName('Head').Text = $Purpose
    $d.User.Text = "$env:USERDOMAIN\$env:USERNAME"
    $d.Ok.Tag = $d
    $d.Ok.Add_Click({
        param($s, $e)
        $d = $s.Tag
        $r = Test-AdminCredential $d.User.Text $d.Pass.Password
        $d.Pass.Clear()
        if ($r.Ok) { $d.Account = $r.Account; $d.Win.DialogResult = $true; return }
        $d.Tries++
        Write-UiLog ('Authentification administrateur refusée pour {0} : {1}' -f $d.User.Text, $r.Msg) 'WARN'
        $d.Err.Text = $r.Msg; $d.Err.Visibility = 'Visible'
        if ($d.Tries -ge 3) { $d.Win.DialogResult = $false }
    })
    $dlg.Add_ContentRendered({ param($s, $e) $s.FindName('Pass').Focus() })
    if ($dlg.ShowDialog()) { return $d.Account }
    $null
}

