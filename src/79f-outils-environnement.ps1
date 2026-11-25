# ================= Variables d'environnement : fenêtre dédiée, 2 portées bien séparées
# Utilisateur (compte ciblé, HKCU\Environment) et Système (tous les comptes, HKLM\...\Session Manager\Environment).
# Listes (PATH...) présentées un dossier par ligne, dossiers introuvables signalés. Carte de l'onglet Outils : résumé et
# bouton d'ouverture.
$EnvSys = 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment'
$EnvUsr = 'HKCU\Environment'
$EnvProtected = @('Path', 'ComSpec', 'windir', 'SystemRoot', 'OS', 'PATHEXT', 'PSModulePath', 'TEMP', 'TMP', 'NUMBER_OF_PROCESSORS', 'PROCESSOR_ARCHITECTURE', 'PROCESSOR_IDENTIFIER', 'PROCESSOR_LEVEL', 'PROCESSOR_REVISION', 'DriverData', 'USERNAME', 'OneDrive')
$EnvUI = @{ Win = $null; Scope = 'U' }
function Get-EnvVar([string]$Path) {
    $k = Open-RegKey $Path; if (-not $k) { return @() }
    try { @($k.GetValueNames() | Where-Object { $_ } | Sort-Object | ForEach-Object { [pscustomobject]@{ Name = $_; Value = "$($k.GetValue($_, '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames))"; Kind = "$($k.GetValueKind($_))" } }) } finally { $k.Close() }
}
function Test-EnvList($V) { $V.Value -like '*;*' -or $V.Name -in 'Path', 'PSModulePath', 'PATHEXT' }
# dossier introuvable = seulement si on peut l'affirmer : variables du profil remplacées par celles du compte ciblé (et non du
# compte administrateur qui a élevé l'application), lecteur absent pour ce processus (lecteur réseau de l'utilisateur, clé
# débranchée) ou chemin réseau (\\serveur, lent ou injoignable en administrateur) = considéré présent, jamais proposé au retrait
function Test-EnvDir([string]$P) {
    $x = "$P"
    if ($UserProfilePath) {
        foreach ($m in @(@('%USERPROFILE%', $UserProfilePath), @('%LOCALAPPDATA%', "$UserProfilePath\AppData\Local"), @('%APPDATA%', "$UserProfilePath\AppData\Roaming"), @('%HOMEPATH%', ($UserProfilePath -replace '^[A-Za-z]:', '')), @('%TEMP%', "$UserProfilePath\AppData\Local\Temp"), @('%TMP%', "$UserProfilePath\AppData\Local\Temp"))) {
            $x = [regex]::Replace($x, [regex]::Escape($m[0]), $m[1].Replace('$', '$$'), 'IgnoreCase')
        }
    }
    $x = [Environment]::ExpandEnvironmentVariables($x)
    if ($x -notmatch '^[A-Za-z]:\\') { return $true }
    if (-not [IO.Directory]::Exists($x.Substring(0, 3))) { return $true }
    Test-Path -LiteralPath $x
}
function Update-EnvCard {
    $b = $ToolsUI.EnvBody; if (-not $b) { return }; $b.Children.Clear()
    $u = @(Get-EnvVar $EnvUsr); $s = @(Get-EnvVar $EnvSys)
    $miss = 0; foreach ($v in @($u + $s | Where-Object { $_.Name -eq 'Path' })) { $miss += @($v.Value -split ';' | Where-Object { $_ -and -not (Test-EnvDir $_) }).Count }
    [void](Add-KV $b "Utilisateur ($UserName)" ('{0} variables' -f $u.Count))
    [void](Add-KV $b 'Système (tous les comptes)' ('{0} variables' -f $s.Count))
    [void](Add-KV $b 'Dossiers du PATH introuvables' $(if ($miss) { "$miss" } else { 'aucun' }) $(if ($miss) { 'WarnFgBrush' } else { '' }))
    [void]$b.Children.Add((New-ToolBar @((New-ToolButton 'Gérer les variables...' $null { Show-EnvWindow } 'PrimaryBtn'))))
}
function Update-EnvView { Update-EnvCard; if ($EnvUI.Win) { Update-EnvList } }
$EnvXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Oliv_Maintenance - Variables d'environnement" Width="1000" Height="700" MinWidth="560" MinHeight="460"
        Background="{DynamicResource BgBrush}" Foreground="{DynamicResource FgBrush}" FontFamily="Segoe UI" FontSize="13">
  <Grid Margin="16,12,16,12">
    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
    <!-- haut : 2 portées sur toute la largeur (moitié chacune, texte raccourci si besoin), puis filtre et ajout -->
    <StackPanel Margin="0,0,0,10">
      <Grid>
        <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="8"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
        <Button x:Name="ScopeU" Style="{DynamicResource ActionBtn}" Height="36" Padding="14,0" MinWidth="0" HorizontalContentAlignment="Left" Tag="on">
          <DockPanel><TextBlock Text="&#xE77B;" FontFamily="Segoe MDL2 Assets" FontSize="13" VerticalAlignment="Center" Margin="0,0,8,0"/><TextBlock x:Name="ScopeUTxt" VerticalAlignment="Center" TextTrimming="CharacterEllipsis"/></DockPanel>
        </Button>
        <Button x:Name="ScopeS" Grid.Column="2" Style="{DynamicResource ActionBtn}" Height="36" Padding="14,0" MinWidth="0" HorizontalContentAlignment="Left">
          <DockPanel><TextBlock Text="&#xE7F4;" FontFamily="Segoe MDL2 Assets" FontSize="13" VerticalAlignment="Center" Margin="0,0,8,0"/><TextBlock x:Name="ScopeSTxt" VerticalAlignment="Center" TextTrimming="CharacterEllipsis"/></DockPanel>
        </Button>
      </Grid>
      <Grid Margin="0,8,0,0">
        <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
        <Border x:Name="FindBox" Height="34" CornerRadius="17" Background="{DynamicResource BgBrush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="1.5" VerticalAlignment="Center" Cursor="IBeam">
          <Grid>
            <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
            <TextBlock Text="&#xE721;" FontFamily="Segoe MDL2 Assets" FontSize="12" Foreground="{DynamicResource AccentBrush}" Margin="12,0,8,0" VerticalAlignment="Center"/>
            <TextBox x:Name="Find" Grid.Column="1" BorderThickness="0" Background="Transparent" Foreground="{DynamicResource FgBrush}" CaretBrush="{DynamicResource FgBrush}" VerticalAlignment="Center" Margin="0,0,12,0">
              <TextBox.Template><ControlTemplate TargetType="TextBox"><ScrollViewer x:Name="PART_ContentHost" Focusable="False" HorizontalScrollBarVisibility="Hidden" VerticalScrollBarVisibility="Hidden" Background="Transparent"/></ControlTemplate></TextBox.Template>
            </TextBox>
            <TextBlock x:Name="FindHint" Grid.Column="1" Text="Filtrer (nom ou valeur)" Foreground="{DynamicResource MutedBrush}" VerticalAlignment="Center" IsHitTestVisible="False" TextTrimming="CharacterEllipsis"/>
          </Grid>
        </Border>
        <Button x:Name="Add" Grid.Column="1" Style="{DynamicResource PrimaryBtn}" Height="34" Padding="14,0" Margin="8,0,0,0" Content="Ajouter une variable"/>
      </Grid>
    </StackPanel>
    <!-- portée affichée : bandeau de couleur différente pour l'utilisateur et pour l'ordinateur -->
    <Border x:Name="Info" Grid.Row="1" Margin="0,0,0,10" Padding="14,8" CornerRadius="6" BorderThickness="4,0,0,0" Background="{DynamicResource PanelBrush}">
      <StackPanel>
        <TextBlock x:Name="InfoHead" FontWeight="SemiBold" FontSize="14"/>
        <TextBlock x:Name="InfoText" Foreground="{DynamicResource MutedBrush}" TextWrapping="Wrap" Margin="0,2,0,0"/>
      </StackPanel>
    </Border>
    <Border Grid.Row="2" Background="{DynamicResource PanelBrush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="1" CornerRadius="6">
      <Grid>
        <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
        <Grid x:Name="Head" Margin="14,8,28,6">
          <Grid.ColumnDefinitions><ColumnDefinition Width="260"/><ColumnDefinition Width="*"/><ColumnDefinition Width="76"/></Grid.ColumnDefinitions>
          <TextBlock Text="NOM" Foreground="{DynamicResource MutedBrush}" FontSize="11" FontWeight="SemiBold"/>
          <TextBlock Grid.Column="1" Text="VALEUR" Foreground="{DynamicResource MutedBrush}" FontSize="11" FontWeight="SemiBold"/>
        </Grid>
        <Border Grid.Row="1" Height="1" VerticalAlignment="Top" Background="{DynamicResource LineBrush}"/>
        <ScrollViewer x:Name="Scroll" Grid.Row="1" VerticalScrollBarVisibility="Visible" Focusable="False"><StackPanel x:Name="List" Margin="4"/></ScrollViewer>
      </Grid>
    </Border>
    <TextBlock x:Name="Status" Grid.Row="3" Margin="0,8,0,0" Foreground="{DynamicResource MutedBrush}" TextWrapping="Wrap"
               Text="Clic sur une variable pour la modifier. Effectif pour les programmes ouverts ensuite (fenêtres et programmes déjà ouverts : à relancer)."/>
  </Grid>
</Window>
'@
function Show-EnvWindow {
    if ($EnvUI.Win) { if ($EnvUI.Win.WindowState -eq 'Minimized') { $EnvUI.Win.WindowState = 'Normal' }; [void]$EnvUI.Win.Activate(); return }
    $w = [Windows.Markup.XamlReader]::Parse($EnvXaml)
    $w.Resources.MergedDictionaries.Add($Window.Resources)
    Set-ChildWindow $w 'Variables'
    if ($AppIcon) { $w.Icon = $AppIcon }
    foreach ($n in 'FindBox', 'Find', 'FindHint', 'Add', 'ScopeU', 'ScopeS', 'ScopeUTxt', 'ScopeSTxt', 'Info', 'InfoHead', 'InfoText', 'Head', 'Scroll', 'List', 'Status') { $EnvUI[$n] = $w.FindName($n) }
    $EnvUI.Win = $w
    $EnvUI.ScopeU.Add_Click({ $EnvUI.Scope = 'U'; Update-EnvList })
    $EnvUI.ScopeS.Add_Click({ $EnvUI.Scope = 'S'; Update-EnvList })
    $EnvUI.Add.Add_Click({ Edit-EnvVar $(if ($EnvUI.Scope -eq 'S') { $EnvSys } else { $EnvUsr }) $null })
    $EnvUI.Find.Add_TextChanged({ $EnvUI.FindHint.Visibility = $(if ($EnvUI.Find.Text) { 'Collapsed' } else { 'Visible' }); Update-EnvList })
    $EnvUI.FindBox.Add_MouseLeftButtonDown({ [void]$EnvUI.Find.Focus() })
    $EnvUI.Scroll.Add_SizeChanged({ $sb = [math]::Max([double]0, $EnvUI.Scroll.ActualWidth - $EnvUI.Scroll.ViewportWidth); $EnvUI.Head.Margin = New-Thickness 14 8 (10 + $sb) 6 })
    $w.Add_Closed({ $EnvUI.Win = $null })
    Update-EnvList
    $w.Show()
}
function Update-EnvList {
    if (-not $EnvUI.Win) { return }
    $sys = $EnvUI.Scope -eq 'S'; $path = $(if ($sys) { $EnvSys } else { $EnvUsr })
    $u = @(Get-EnvVar $EnvUsr); $s = @(Get-EnvVar $EnvSys)
    $short = ("$UserName" -split '\\')[-1]
    $EnvUI.ScopeUTxt.Text = "Utilisateur : $short ($($u.Count))"; $EnvUI.ScopeSTxt.Text = "Ordinateur : tous les comptes ($($s.Count))"
    $EnvUI.ScopeU.ToolTip = "Variables du compte $UserName"; $EnvUI.ScopeS.ToolTip = 'Variables communes à tous les comptes du PC'
    $EnvUI.ScopeU.Tag = $(if ($sys) { '' } else { 'on' }); $EnvUI.ScopeS.Tag = $(if ($sys) { 'on' } else { '' })
    $EnvUI.Info.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, $(if ($sys) { 'WarnFgBrush' } else { 'AccentBrush' }))
    $EnvUI.InfoHead.Text = $(if ($sys) { 'Variables de l''ordinateur (système)' } else { "Variables de l'utilisateur $UserName" })
    $EnvUI.InfoText.Text = $(if ($sys) { "Communes à tous les comptes du PC ; une erreur ici peut empêcher Windows ou des programmes de démarrer. Registre : $EnvSys" }
        else { "Propres à ce compte. Une variable utilisateur remplace la variable système de même nom, sauf PATH : le PATH utilisateur s'ajoute à la fin du PATH système. Registre : HKCU\Environment" })
    $EnvUI.Add.Content = $(if ($sys) { 'Ajouter une variable système' } else { 'Ajouter une variable utilisateur' })
    $q = "$($EnvUI.Find.Text)".Trim()
    $EnvUI.List.Children.Clear()
    foreach ($v in $(if ($sys) { $s } else { $u })) {
        if ($q -and $v.Name -notlike "*$q*" -and $v.Value -notlike "*$q*") { continue }
        $b = [Windows.Controls.Border]::new(); $b.Style = $Window.FindResource('SvcRow'); $b.Padding = New-Thickness 10 6 6 6; $b.Cursor = [Windows.Input.Cursors]::Hand
        $g = [Windows.Controls.Grid]::new(); foreach ($wd in 260, 0, 76) { [void]$g.ColumnDefinitions.Add((New-SvcCol $wd)) }
        $n = New-Text $v.Name; $n.FontWeight = [Windows.FontWeights]::SemiBold; $n.TextTrimming = 'CharacterEllipsis'; $n.VerticalAlignment = 'Top'; $n.Margin = New-Thickness 0 0 10 0
        [void]$g.Children.Add($n)
        $vp = [Windows.Controls.StackPanel]::new(); [Windows.Controls.Grid]::SetColumn($vp, 1)
        if (Test-EnvList $v) {
            # liste : un élément par ligne, dossier introuvable en rouge
            foreach ($it in @($v.Value -split ';' | Where-Object { $_ })) {
                $ok = $v.Name -eq 'PATHEXT' -or (Test-EnvDir $it)
                $t = New-Text $(if ($ok) { $it } else { $it + '   (dossier introuvable)' }); $t.TextWrapping = 'NoWrap'; $t.TextTrimming = 'CharacterEllipsis'; $t.FontFamily = [Windows.Media.FontFamily]::new('Consolas'); $t.ToolTip = $it
                if (-not $ok) { $t.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'ErrFgBrush') }
                [void]$vp.Children.Add($t)
            }
            # dossiers introuvables (souvent laissés par une désinstallation) : retrait en un clic, avec récapitulatif
            $miss = @($v.Value -split ';' | Where-Object { $_ -and $v.Name -ne 'PATHEXT' -and -not (Test-EnvDir $_) })
            if ($miss.Count) {
                $cl = New-Button ('Retirer les dossiers introuvables ({0})' -f $miss.Count); $cl.Height = 30; $cl.MinWidth = 0; $cl.Padding = New-Thickness 10 0 10 0; $cl.Margin = New-Thickness 0 6 0 2; $cl.HorizontalAlignment = 'Left'
                $cl.Tag = @{ P = $path; V = $v }; $cl.Add_Click({ param($s, $e) Remove-EnvMissingDir $s.Tag.P $s.Tag.V }); [void]$vp.Children.Add($cl)
            }
        } else { $t = New-Text $v.Value; $t.TextWrapping = 'Wrap'; $t.FontFamily = [Windows.Media.FontFamily]::new('Consolas'); [void]$vp.Children.Add($t) }
        [void]$g.Children.Add($vp)
        $bp = [Windows.Controls.StackPanel]::new(); $bp.Orientation = 'Horizontal'; $bp.HorizontalAlignment = 'Right'; $bp.VerticalAlignment = 'Top'; [Windows.Controls.Grid]::SetColumn($bp, 2)
        $tag = @{ P = $path; V = $v }
        [void]$bp.Children.Add((New-ToolIconButton 0xE70F 'Modifier' $tag { param($s, $e) Edit-EnvVar $s.Tag.P $s.Tag.V }))
        $prot = $v.Name -in $EnvProtected
        $dl = New-ToolIconButton 0xE74D $(if ($prot) { 'Variable indispensable : suppression non proposée' } else { 'Supprimer' }) $tag { param($s, $e) Remove-EnvVar $s.Tag.P $s.Tag.V }
        $dl.IsEnabled = -not $prot; [Windows.Controls.ToolTipService]::SetShowOnDisabled($dl, $true); [void]$bp.Children.Add($dl)
        [void]$g.Children.Add($bp)
        $b.Child = $g; $b.Tag = $tag
        $b.Add_MouseLeftButtonUp({ param($s, $e) if (-not (Test-InButton $e.OriginalSource)) { Edit-EnvVar $s.Tag.P $s.Tag.V } })
        [void]$EnvUI.List.Children.Add($b)
    }
}
# édition : listes présentées un élément par ligne ; récapitulatif des changements avant enregistrement
function Edit-EnvVar([string]$Path, $Var) {
    $isNew = -not $Var; $multi = (-not $isNew) -and (Test-EnvList $Var)
    $val = $(if ($isNew) { '' } elseif ($multi) { (@($Var.Value -split ';' | Where-Object { $_ }) -join "`r`n") } else { $Var.Value })
    $where = $(if ($Path -eq $EnvSys) { 'système, tous les comptes' } else { "utilisateur $UserName" })
    $msg = $(if ($isNew) { "Nouvelle variable ($where)" } else { "$($Var.Name) ($where)" }) + $(if ($multi) { "`n`nUn élément par ligne (dossiers du PATH...). %VARIABLE% est remplacé à l'utilisation." } else { "`n`n%VARIABLE% est remplacé à l'utilisation." })
    $f = @(@{ L = 'Nom'; V = $(if ($isNew) { '' } else { $Var.Name }); RO = -not $isNew }, @{ L = 'Valeur'; V = $val; M = $multi; H = 300 })
    $r = Read-ToolInput $msg $f 'Enregistrer' 780
    if (-not $r) { return }
    $name = "$($r[0])".Trim(); if (-not $name -or $name -match '[=\s]') { Show-Info 'Nom invalide : ni espace ni signe =.' 'Warn'; return }
    $value = $(if ($multi) { (@("$($r[1])" -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ }) -join ';') } else { "$($r[1])" })
    if (-not $isNew -and $value -ceq $Var.Value) { return }
    if ($isNew -and @(Get-EnvVar $Path | Where-Object { $_.Name -eq $name }).Count -and -not (Confirm-Action "La variable $name existe déjà ($where) : la remplacer ?")) { return }
    if ($Var -and $Var.Name -eq 'Path' -and $Path -eq $EnvSys -and $value.Length -lt 20) { Show-Info 'PATH système presque vide : enregistrement refusé (Windows ne trouverait plus ses propres programmes).' 'Warn'; return }
    # récapitulatif : éléments ajoutés / retirés (listes) ou ancienne / nouvelle valeur
    $lines = @()
    if ($multi) {
        $a = @($Var.Value -split ';' | Where-Object { $_ }); $b2 = @($value -split ';' | Where-Object { $_ })
        foreach ($x in $b2) { if ($x -notin $a) { $lines += '+ ajouté : ' + $x + $(if (-not (Test-EnvDir $x)) { '   (dossier introuvable)' } else { '' }) } }
        foreach ($x in $a) { if ($x -notin $b2) { $lines += '- retiré : ' + $x } }
        if (-not $lines.Count) { $lines += 'ordre des éléments modifié' }
    } elseif ($isNew) { $lines += "+ $name = $value" }
    else { $lines += "- avant : $($Var.Value)"; $lines += "+ après : $value" }
    if ((Show-Dialog "Enregistrer $name ($where) ?`n`nModifications :" 'Question' @(@{ T = 'Annuler'; V = $false; C = $true }, @{ T = 'Enregistrer'; V = $true; S = 'PrimaryBtn' }) $lines) -ne $true) { return }
    try {
        $k = Open-RegKey $Path $true $true
        try {
            $kind = $(if ($value -match '%[^%]+%' -or ($Var -and $Var.Kind -eq 'ExpandString')) { [Microsoft.Win32.RegistryValueKind]::ExpandString } else { [Microsoft.Win32.RegistryValueKind]::String })
            $k.SetValue($name, $value, $kind)
        } finally { $k.Close() }
        [void][_OlivM.Shell]::NotifySettingChange('Environment')
        Write-UiLog ('Variable d''environnement {0} ({1}) enregistrée : {2}' -f $name, $where, ($lines -join ' ; ')) 'OK'; Add-SessionEvent 'Réglages' 'Variable d''environnement' "$name ($where)" 'ok'
    } catch { Show-Info "Enregistrement impossible.`n`n$($_.Exception.Message)" 'Error' }
    Update-EnvView
}
function Remove-EnvMissingDir([string]$Path, $Var) {
    $all = @($Var.Value -split ';' | Where-Object { $_ }); $miss = @($all | Where-Object { -not (Test-EnvDir $_) })
    if (-not $miss.Count) { return }
    $where = $(if ($Path -eq $EnvSys) { 'système, tous les comptes' } else { "utilisateur $UserName" })
    $lines = @($miss | ForEach-Object { '- retiré : ' + $_ })
    if ((Show-Dialog "Retirer de $($Var.Name) ($where) les dossiers qui n'existent plus ?`n`nCes dossiers ont été supprimés (souvent par la désinstallation d'un logiciel) mais sont restés dans la variable :" 'Question' @(@{ T = 'Annuler'; V = $false; C = $true }, @{ T = 'Retirer'; V = $true; S = 'PrimaryBtn' }) $lines) -ne $true) { return }
    $value = (@($all | Where-Object { $_ -notin $miss }) -join ';')
    try {
        $k = Open-RegKey $Path $true; try { $k.SetValue($Var.Name, $value, $(if ($Var.Kind -eq 'ExpandString' -or $value -match '%[^%]+%') { [Microsoft.Win32.RegistryValueKind]::ExpandString } else { [Microsoft.Win32.RegistryValueKind]::String })) } finally { $k.Close() }
        [void][_OlivM.Shell]::NotifySettingChange('Environment')
        Write-UiLog ('{0} ({1}) : {2} dossier(s) introuvable(s) retiré(s) : {3}' -f $Var.Name, $where, $miss.Count, ($miss -join ' ; ')) 'OK'
    } catch { Show-Info "Modification impossible.`n`n$($_.Exception.Message)" 'Error' }
    Update-EnvView
}
function Remove-EnvVar([string]$Path, $Var) {
    if ($Var.Name -in $EnvProtected) { return }
    $where = $(if ($Path -eq $EnvSys) { 'système, tous les comptes' } else { "utilisateur $UserName" })
    if (-not (Confirm-Action "Supprimer la variable $($Var.Name) ($where) ?`n`nValeur : $($Var.Value)")) { return }
    try {
        $k = Open-RegKey $Path $true; try { $k.DeleteValue($Var.Name, $false) } finally { $k.Close() }
        [void][_OlivM.Shell]::NotifySettingChange('Environment')
        Write-UiLog "Variable d'environnement $($Var.Name) ($where) supprimée (valeur : $($Var.Value))." 'OK'
    } catch { Show-Info "Suppression impossible.`n`n$($_.Exception.Message)" 'Error' }
    Update-EnvView
}

