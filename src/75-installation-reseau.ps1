# ---------- Installation propre de Windows (Maintenance) : clé USB d'installation sans compte Microsoft, sauvegarde de la configuration
# 1. Clé USB d'installation (Show-UsbDialog) avec autounattend.xml à la racine : langue, clavier et fuseau du poste actuel, contrat de
#    licence accepté, écrans du compte Microsoft masqués, compte local créé, exigence réseau levée (BypassNRO), contrôles
#    TPM / démarrage sécurisé / mémoire levés en option (LabConfig). Partitionnement et choix de l'édition restent manuels.
# 2. Configuration : réglages de l'application et applications du catalogue présentes sur ce poste, enregistrés dans un fichier
#    .json ; appliquée sur un autre poste en un clic (réglages modifiés puis applications installées).
function New-InstallCard {
    $b = [Windows.Controls.Border]::new(); $b.Style = $Window.FindResource('Panel'); $b.Padding = New-Thickness 16 14 16 14; $b.Margin = New-Thickness 0 12 0 0
    [Windows.Controls.DockPanel]::SetDock($b, 'Bottom')
    $sp = [Windows.Controls.StackPanel]::new(); $b.Child = $sp
    $hd = [Windows.Controls.DockPanel]::new()
    $ic = New-Text ([string][char]0xE7F8); $ic.Style = $Window.FindResource('CardIcon'); [Windows.Controls.DockPanel]::SetDock($ic, 'Left'); [void]$hd.Children.Add($ic)
    $tt = New-Text 'Installation propre de Windows'; $tt.Style = $Window.FindResource('Section'); [void]$hd.Children.Add($tt)
    [void]$sp.Children.Add($hd)
    $d = New-Text 'Clé USB d''installation sans compte Microsoft, et sauvegarde de ta configuration (réglages et applications) pour la remettre sur un autre PC' 'Muted'; $d.Margin = New-Thickness 30 4 0 10
    [void]$sp.Children.Add($d)
    $wp = [Windows.Controls.WrapPanel]::new(); $wp.Margin = New-Thickness 30 0 0 0
    foreach ($x in @(@('Créer une clé USB Windows', { Show-UsbDialog }, 'Télécharge Windows 10 ou 11 chez Microsoft et crée une clé d''installation démarrable, sans compte Microsoft'),
                     @('Sauvegarder ma configuration', { Save-AppConfig }, 'Enregistre dans un fichier les réglages de l''application et les applications installées sur ce PC'),
                     @('Restaurer une configuration', { Restore-AppConfig }, 'Remet les réglages d''une configuration sauvegardée puis installe ses applications'))) {
        $bt = New-Button $x[0]; $bt.Margin = New-Thickness 0 0 8 6; $bt.ToolTip = $x[2]; $bt.Add_Click($x[1]); [void]$wp.Children.Add($bt)
    }
    [void]$sp.Children.Add($wp)
    $Ui.MaintLeft.Children.Insert(0, $b)
}

# Clé USB d'installation de Windows (façon Rufus) : ISO téléchargée chez Microsoft ou fichier ISO existant, clé effacée
# puis rendue démarrable (MBR, partition FAT32 active : démarrage UEFI et BIOS), fichiers de l'ISO copiés, install.wim de
# plus de 4 Go découpé en .swm (DISM /Split-Image, format accepté par l'installation de Windows), secteur de démarrage
# BIOS (bootsect /nt60 de l'ISO), fichier de réponses autounattend.xml à la racine (compte local, sans compte Microsoft).
# Lien de téléchargement : script Fido (Pete Batard, auteur de Rufus, GPLv3) téléchargé depuis son dépôt GitHub au
# moment de l'usage et lancé tel quel (-GetUrl) : Microsoft change régulièrement l'accès à ses ISO, Fido suit ces
# changements. Signature Authenticode vérifiée si le script est signé ; signature invalide = refus.
$UsbUI = @{}
function Get-UsbDisk { @(Get-Disk -ErrorAction Stop | Where-Object { "$($_.BusType)" -eq 'USB' -and $_.Size -ge 7GB -and -not $_.IsSystem -and -not $_.IsBoot } | Sort-Object Number) }
function Show-UsbDialog {
    if ($BgJobs.ContainsKey('Usb')) { if ($UsbUI.Win) { $UsbUI.Win.Activate() }; return }
    $x = [xml]@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Clé USB d'installation de Windows" Width="560" SizeToContent="Height" WindowStartupLocation="CenterOwner" ResizeMode="NoResize"
        ShowInTaskbar="False" Background="{DynamicResource BgBrush}" Foreground="{DynamicResource FgBrush}" FontFamily="Segoe UI" FontSize="13">
  <StackPanel Margin="24,20,24,18">
    <TextBlock Text="Créer une clé USB d'installation de Windows" FontSize="16" FontWeight="SemiBold"/>
    <TextBlock Foreground="{DynamicResource MutedBrush}" Margin="0,4,0,14" TextWrapping="Wrap"
               Text="ISO officielle téléchargée chez Microsoft (ou ISO déjà présente), clé démarrable en UEFI et BIOS, installation sans compte Microsoft avec un compte local."/>
    <StackPanel x:Name="Form">
      <Grid Margin="0,0,0,10">
        <Grid.ColumnDefinitions><ColumnDefinition Width="140"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
        <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
        <TextBlock Text="Windows" VerticalAlignment="Center" Margin="0,0,0,8"/>
        <ComboBox x:Name="Ver" Grid.Column="1" Margin="0,0,0,8" Height="30" VerticalContentAlignment="Center"/>
        <TextBlock Grid.Row="1" Text="Image" VerticalAlignment="Top" Margin="0,4,0,8"/>
        <StackPanel Grid.Row="1" Grid.Column="1" Margin="0,0,0,8">
          <RadioButton x:Name="SrcDl" GroupName="src" IsChecked="True" Margin="0,4,0,4" Foreground="{DynamicResource FgBrush}"><TextBlock TextWrapping="Wrap" MaxWidth="360" Text="Télécharger chez Microsoft (dernière version, langue de ce PC, environ 6 Go)"/></RadioButton>
          <DockPanel>
            <Button x:Name="IsoBrowse" DockPanel.Dock="Right" Content="Parcourir..." Style="{DynamicResource ActionBtn}" MinWidth="96" Height="28" Margin="8,0,0,0"/>
            <RadioButton x:Name="SrcIso" GroupName="src" VerticalAlignment="Center" Foreground="{DynamicResource FgBrush}"><TextBlock x:Name="IsoTxt" TextWrapping="Wrap" MaxWidth="250" Text="Fichier ISO déjà téléchargé"/></RadioButton>
          </DockPanel>
        </StackPanel>
        <TextBlock Grid.Row="2" Text="Clé USB" VerticalAlignment="Center" Margin="0,0,0,8"/>
        <DockPanel Grid.Row="2" Grid.Column="1" Margin="0,0,0,8">
          <Button x:Name="UsbRefresh" DockPanel.Dock="Right" Content="&#xE72C;" Style="{DynamicResource IconBtn}" Width="32" Height="30" ToolTip="Relire les clés USB"/>
          <ComboBox x:Name="Usb" Height="30" VerticalContentAlignment="Center"/>
        </DockPanel>
        <TextBlock Grid.Row="3" Text="Compte local" VerticalAlignment="Center" Margin="0,0,0,8"/>
        <TextBox x:Name="User" Grid.Row="3" Grid.Column="1" Margin="0,0,0,8" Padding="6,5" Background="{DynamicResource PanelBrush}" Foreground="{DynamicResource FgBrush}" BorderBrush="{DynamicResource LineBrush}" CaretBrush="{DynamicResource FgBrush}"/>
        <TextBlock Grid.Row="4" Text="Mot de passe" VerticalAlignment="Top" Margin="0,6,0,0"/>
        <StackPanel Grid.Row="4" Grid.Column="1">
          <PasswordBox x:Name="Pass" Padding="6,5" Background="{DynamicResource PanelBrush}" Foreground="{DynamicResource FgBrush}" BorderBrush="{DynamicResource LineBrush}" CaretBrush="{DynamicResource FgBrush}"/>
          <TextBlock Text="Facultatif, écrit en clair sur la clé : à changer après l'installation." Foreground="{DynamicResource MutedBrush}" FontSize="12" TextWrapping="Wrap" Margin="0,3,0,0"/>
        </StackPanel>
      </Grid>
      <CheckBox x:Name="Bypass" Margin="0,4,0,0"><TextBlock TextWrapping="Wrap" MaxWidth="460" Text="Autoriser l'installation sur un PC non compatible Windows 11 (TPM 2.0, démarrage sécurisé, mémoire)"/></CheckBox>
      <TextBlock x:Name="Warn" Foreground="{DynamicResource WarnFgBrush}" TextWrapping="Wrap" Margin="0,12,0,0" Text="Tout le contenu de la clé USB choisie sera effacé."/>
      <TextBlock x:Name="Err" Foreground="{DynamicResource ErrFgBrush}" TextWrapping="Wrap" Visibility="Collapsed" Margin="0,8,0,0"/>
    </StackPanel>
    <StackPanel x:Name="Run" Visibility="Collapsed">
      <TextBlock x:Name="Phase" FontSize="14" FontWeight="SemiBold" TextWrapping="Wrap"/>
      <ProgressBar x:Name="Bar" Height="10" Margin="0,10,0,6" Minimum="0" Maximum="100"/>
      <TextBlock x:Name="Detail" Foreground="{DynamicResource MutedBrush}" TextWrapping="Wrap"/>
    </StackPanel>
    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,18,0,0">
      <Button x:Name="Ok" Content="Créer la clé" Style="{DynamicResource PrimaryBtn}" Margin="0,0,8,0" MinWidth="140" IsDefault="True"/>
      <Button x:Name="Cancel" Content="Annuler" Style="{DynamicResource ActionBtn}" Margin="0" MinWidth="110"/>
    </StackPanel>
  </StackPanel>
</Window>
'@
    $dlg = [Windows.Markup.XamlReader]::Load([System.Xml.XmlNodeReader]::new($x))
    $dlg.Resources.MergedDictionaries.Add($Window.Resources); $dlg.Owner = $Window
    if ($AppIcon) { $dlg.Icon = $AppIcon }
    foreach ($n in 'Form', 'Run', 'Ver', 'SrcDl', 'SrcIso', 'IsoTxt', 'IsoBrowse', 'Usb', 'UsbRefresh', 'User', 'Pass', 'Bypass', 'Err', 'Phase', 'Bar', 'Detail', 'Ok', 'Cancel') { $UsbUI[$n] = $dlg.FindName($n) }
    $UsbUI.Win = $dlg; $UsbUI.Iso = $null
    $UsbUI.Bypass.Style = $Window.FindResource('TaskCheck')
    foreach ($v in 'Windows 11', 'Windows 10') { [void]$UsbUI.Ver.Items.Add($v) }; $UsbUI.Ver.SelectedIndex = 0
    $UsbUI.Ver.Add_SelectionChanged({ $UsbUI.Bypass.Visibility = $(if ($UsbUI.Ver.SelectedIndex -eq 0) { 'Visible' } else { 'Collapsed' }) })
    $UsbUI.User.Text = ($env:USERNAME -replace '[^\w.-]', '')
    $UsbUI.IsoBrowse.Add_Click({
        $o = [Microsoft.Win32.OpenFileDialog]::new(); $o.Title = 'Image ISO de Windows'; $o.Filter = 'Image disque (*.iso)|*.iso'; $o.InitialDirectory = (Join-Path $UserProfilePath 'Downloads')
        if ($o.ShowDialog($UsbUI.Win)) { $UsbUI.Iso = $o.FileName; $UsbUI.IsoTxt.Text = [IO.Path]::GetFileName($o.FileName); $UsbUI.SrcIso.IsChecked = $true }
    })
    $fill = {
        $UsbUI.Usb.Items.Clear()
        try { foreach ($d in (Get-UsbDisk)) { $it = [Windows.Controls.ComboBoxItem]::new(); $it.Content = '{0}  ·  {1:N1} Go  (disque {2})' -f "$($d.FriendlyName)".Trim(), ($d.Size / 1GB), $d.Number; $it.Tag = [int]$d.Number; [void]$UsbUI.Usb.Items.Add($it) } } catch { Write-Ignored 'Clés USB' $_ }
        if ($UsbUI.Usb.Items.Count) { $UsbUI.Usb.SelectedIndex = 0 } else { $it = [Windows.Controls.ComboBoxItem]::new(); $it.Content = 'Aucune clé USB de 8 Go ou plus branchée'; $it.IsEnabled = $false; [void]$UsbUI.Usb.Items.Add($it) }
    }
    $UsbUI.Fill = $fill; & $fill
    $UsbUI.UsbRefresh.Add_Click({ & $UsbUI.Fill })
    $UsbUI.Cancel.Add_Click({
        if ($BgJobs.ContainsKey('Usb')) { $Sync.UsbCancel = $true; $UsbUI.Cancel.IsEnabled = $false; $UsbUI.Detail.Text = 'Arrêt demandé...'; return }
        $UsbUI.Win.Close()
    })
    $dlg.Add_Closing({ param($s, $e) if ($BgJobs.ContainsKey('Usb')) { $e.Cancel = $true } })
    $dlg.Add_Closed({ $UsbUI.Win = $null; if ($UsbUI.Timer) { $UsbUI.Timer.Stop() } })
    $UsbUI.Ok.Add_Click({ Start-UsbCreation })
    [void]$dlg.ShowDialog()
}
function Start-UsbCreation {
    $u = "$($UsbUI.User.Text)".Trim(); $err = $null
    $sel = $UsbUI.Usb.SelectedItem
    if (-not $sel -or $null -eq $sel.Tag) { $err = 'Brancher une clé USB de 8 Go ou plus, puis bouton Relire.' }
    elseif ($UsbUI.SrcIso.IsChecked -and -not $UsbUI.Iso) { $err = 'Choisir le fichier ISO (Parcourir...).' }
    elseif ($u -notmatch '^[\w][\w .-]{0,19}$' -or $u -match '(?i)^(administrateur|administrator|invité|guest|system)$') { $err = 'Nom de compte invalide : 20 caractères au plus, lettres, chiffres, espace, point ou tiret, pas un nom réservé de Windows.' }
    if ($err) { $UsbUI.Err.Text = $err; $UsbUI.Err.Visibility = 'Visible'; return }
    if ((Show-Dialog ("Effacer entièrement la clé « {0} » et y installer {1} ?`n`nToutes les données de la clé seront perdues." -f $sel.Content, $UsbUI.Ver.SelectedItem) 'Warn' @(@{ T = 'Annuler'; V = $false; D = $true; C = $true }, @{ T = 'Effacer et créer'; V = $true; S = 'WarnBtn' })) -ne $true) { return }
    # identité de la clé relevée au clic (le numéro de disque change si une clé est retirée ou un disque USB branché pendant
    # le téléchargement : effacement refusé si le disque n° N n'est plus la même clé)
    $did = try { $g = Get-Disk -Number ([int]$sel.Tag) -ErrorAction Stop; if ("$($g.BusType)" -ne 'USB' -or $g.IsSystem -or $g.IsBoot) { $null } else { @{ U = "$($g.UniqueId)"; S = "$($g.SerialNumber)".Trim(); Z = [long]$g.Size } } } catch { $null }
    if (-not $did) { $UsbUI.Err.Text = 'La clé choisie n''est plus détectée à ce numéro : bouton Relire.'; $UsbUI.Err.Visibility = 'Visible'; return }
    $win11 = $UsbUI.Ver.SelectedIndex -eq 0
    $Sync.UsbCancel = $false
    $Sync.UsbParams = @{ Win = $(if ($win11) { '11' } else { '10' }); Iso = $(if ($UsbUI.SrcIso.IsChecked) { $UsbUI.Iso } else { $null }); Disk = [int]$sel.Tag; DiskId = $did
        Xml = (New-UnattendXml $u $UsbUI.Pass.Password ($win11 -and [bool]$UsbUI.Bypass.IsChecked)); Dl = (Join-Path $UserProfilePath 'Downloads'); Tools = $GameDir }
    $Sync.Usb = [hashtable]::Synchronized(@{ Phase = 'Préparation'; Pct = -1; Detail = ''; Done = $false; Ok = $false; Msg = '' })
    $UsbUI.Form.Visibility = 'Collapsed'; $UsbUI.Run.Visibility = 'Visible'; $UsbUI.Ok.Visibility = 'Collapsed'; $UsbUI.Cancel.Content = 'Interrompre'
    Write-UiLog ('Clé USB Windows {0} : création lancée sur « {1} ».' -f $Sync.UsbParams.Win, $sel.Content) 'APP'
    Start-BgJob 'Usb' $UsbScript
    $t = [Windows.Threading.DispatcherTimer]::new(); $t.Interval = [TimeSpan]::FromMilliseconds(400)
    $t.Add_Tick({
        $s = $Sync.Usb; if (-not $s -or -not $UsbUI.Win) { return }
        $UsbUI.Phase.Text = $s.Phase; $UsbUI.Detail.Text = $s.Detail
        $UsbUI.Bar.IsIndeterminate = $s.Pct -lt 0; if ($s.Pct -ge 0) { $UsbUI.Bar.Value = $s.Pct }
    })
    $UsbUI.Timer = $t; $t.Start()
}
$BgJobDone['Usb'] = {
    $s = $Sync.Usb
    if ($UsbUI.Timer) { $UsbUI.Timer.Stop() }
    $ok = $s -and $s.Ok
    Write-UiLog $(if ($ok) { "Clé USB Windows prête : $($s.Msg)" } else { "Clé USB Windows : échec - $(if ($s) { $s.Msg } else { 'tâche interrompue' })" }) $(if ($ok) { 'OK' } else { 'ERROR' })
    Add-SessionEvent 'Maintenance' 'Clé USB d''installation de Windows' $(if ($ok) { 'créée' } else { 'échec' }) $(if ($ok) { 'ok' } else { 'error' })
    if ($UsbUI.Win) {
        $UsbUI.Phase.Text = $(if ($ok) { 'Clé prête' } else { 'Échec' }); $UsbUI.Bar.IsIndeterminate = $false; $UsbUI.Bar.Value = $(if ($ok) { 100 } else { 0 })
        $UsbUI.Detail.Text = $(if ($ok) { "$($s.Msg)`n`nDémarrer le PC à installer sur la clé (menu de démarrage : F12, F11, F8 ou Échap selon la marque)." } else { "$(if ($s) { $s.Msg } else { 'tâche interrompue' })" })
        $UsbUI.Cancel.Content = 'Fermer'; $UsbUI.Cancel.IsEnabled = $true
    }
}
$UsbScript = @'
$p = $Sync.UsbParams; $st = $Sync.Usb
function Set-UsbState([string]$Phase, [double]$Pct, [string]$Detail) { $st.Phase = $Phase; $st.Pct = $Pct; $st.Detail = $Detail }
function Test-UsbCancel { if ($Sync.UsbCancel) { throw 'interrompu à la demande.' } }
$img = $null
try {
    $iso = $p.Iso
    if (-not $iso) {
        # 1. lien officiel : Fido (dépôt GitHub de Pete Batard), signature Akeo Consulting exigée
        Set-UsbState 'Recherche du lien de téléchargement chez Microsoft' -1 'Script Fido (github.com/pbatard/Fido)'
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        [void][IO.Directory]::CreateDirectory($p.Tools)
        $fido = Join-Path $p.Tools 'Fido.ps1'
        (New-Object Net.WebClient).DownloadFile('https://raw.githubusercontent.com/pbatard/Fido/master/Fido.ps1', $fido)
        $sig = Get-AuthenticodeSignature -FilePath $fido
        # script exécuté en administrateur : signature Authenticode valide d'Akeo Consulting (éditeur de Fido et Rufus) exigée ;
        # avant, un script non signé était aussi accepté (dépôt compromis = code exécuté en administrateur)
        if ("$($sig.Status)" -ne 'Valid' -or "$($sig.SignerCertificate.Subject)" -notmatch '(?i)O=Akeo Consulting') { throw "signature du script Fido absente ou d'un autre éditeur ($($sig.Status), $($sig.SignerCertificate.Subject)) : script refusé." }
        $out = & "$env:windir\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File $fido -Win $p.Win -Rel Latest -Ed Pro -Arch x64 -GetUrl 2>&1 | Out-String
        $url = @([regex]::Matches($out, 'https://\S+\.iso\S*') | ForEach-Object { $_.Value })[0]
        if ($url -and ([uri]$url).Host -notmatch '(?i)(^|\.)microsoft\.com$') { throw "lien hors des serveurs Microsoft refusé : $(([uri]$url).Host)" }
        if (-not $url) { throw ('Microsoft n''a pas donné de lien (blocage possible : VPN, réseau d''entreprise, trop de demandes). Réponse : ' + ($out.Trim() -replace '\s+', ' ')) }
        Test-UsbCancel
        # 2. téléchargement de l'ISO dans Téléchargements (réutilisable), avancement réel
        $name = ([uri]$url).Segments[-1]; if ($name -notlike '*.iso') { $name = "Windows$($p.Win).iso" }
        $iso = Join-Path $p.Dl $name
        $req = [Net.HttpWebRequest]::Create($url); $req.Timeout = 30000; $req.ReadWriteTimeout = 60000
        $resp = $req.GetResponse(); $tot = [double]$resp.ContentLength
        $in = $resp.GetResponseStream(); $fs = [IO.File]::Create($iso + '.part'); $buf = [byte[]]::new(1MB); $done = [double]0; $t0 = [DateTime]::Now; $tl = $t0
        # téléchargement interrompu, en erreur ou incomplet : fichier .part (jusqu'à 6 Go) supprimé de Téléchargements
        $dlOk = $false
        try {
            while (($n = $in.Read($buf, 0, $buf.Length)) -gt 0) {
                $fs.Write($buf, 0, $n); $done += $n
                if (([DateTime]::Now - $tl).TotalMilliseconds -ge 500) {
                    $tl = [DateTime]::Now; Test-UsbCancel
                    $sp = $done / [math]::Max([double]1, ([DateTime]::Now - $t0).TotalSeconds)
                    Set-UsbState "Téléchargement de Windows $($p.Win)" $(if ($tot -gt 0) { 100 * $done / $tot } else { -1 }) ('{0:N2} Go sur {1:N2} Go  ·  {2:N1} Mo/s' -f ($done / 1GB), ($tot / 1GB), ($sp / 1MB))
                }
            }
            $dlOk = -not ($tot -gt 0 -and $done -lt $tot)
        } finally {
            $fs.Dispose(); $in.Dispose(); $resp.Dispose()
            if (-not $dlOk) { Remove-Item -LiteralPath ($iso + '.part') -Force -ErrorAction SilentlyContinue }
        }
        if (-not $dlOk) { throw 'téléchargement incomplet.' }
        if (Test-Path -LiteralPath $iso) { Remove-Item -LiteralPath $iso -Force }
        Rename-Item -LiteralPath ($iso + '.part') -NewName $name
    }
    Test-UsbCancel
    # 3. clé : effacée, MBR, partition FAT32 active (32 Go au plus : limite du formatage FAT32 de Windows)
    Set-UsbState 'Préparation de la clé USB' -1 'Effacement et formatage (FAT32)'
    $d = Get-Disk -Number $p.Disk -ErrorAction Stop
    if ("$($d.BusType)" -ne 'USB') { throw 'le disque choisi n''est plus une clé USB : arrêt.' }
    if ($d.IsSystem -or $d.IsBoot -or "$($d.UniqueId)" -ne $p.DiskId.U -or "$($d.SerialNumber)".Trim() -ne $p.DiskId.S -or [long]$d.Size -ne $p.DiskId.Z) { throw ('le disque n° {0} n''est plus la clé choisie (clé retirée ou autre disque USB branché) : rien n''a été effacé, relancer après avoir rebranché la clé.' -f $p.Disk) }
    if ($d.IsReadOnly) { Set-Disk -Number $p.Disk -IsReadOnly $false }
    # clé déjà en GPT (préparée par un autre outil) : Clear-Disk / Initialize-Disk échouaient sans bruit, la clé restait en
    # GPT et New-Partition -IsActive était refusé (« MbrType and IsActive cannot be used on a GPT disk »). Tout par diskpart :
    # effacement, conversion MBR, partition principale active (32 Go au plus : limite FAT32 de Windows), formatage FAT32 rapide,
    # lettre ; style de partition et lettre contrôlés ensuite (variable $pst : $st est l'état partagé avec l'interface)
    $mb = [math]::Floor(([math]::Min([double]$d.Size, [double]32GB) - 8MB) / 1MB)
    # script diskpart dans le dossier protégé de l'application ($GameDir, écriture réservée aux administrateurs) : dans %TEMP%,
    # un programme sans élévation pouvait le réécrire avant son exécution (select disk 0 + clean)
    [void][IO.Directory]::CreateDirectory($p.Tools)
    $dp = Join-Path $p.Tools ('olivm-usb-{0}.txt' -f [guid]::NewGuid().ToString('N'))
    [IO.File]::WriteAllText($dp, ("select disk {0}`r`nattributes disk clear readonly noerr`r`nclean`r`nconvert mbr`r`ncreate partition primary size={1}`r`nactive`r`nformat fs=fat32 quick label=WIN{2}`r`nassign`r`nrescan`r`n" -f $p.Disk, $mb, $p.Win), [Text.Encoding]::ASCII)
    Set-UsbState 'Préparation de la clé USB' -1 'diskpart : effacement, MBR, partition FAT32 active'
    try { $dpo = & "$env:windir\System32\diskpart.exe" /s $dp 2>&1; $dpc = $LASTEXITCODE } finally { Remove-Item -LiteralPath $dp -Force -ErrorAction SilentlyContinue }
    $dpTxt = ((@($dpo) | ForEach-Object { "$_".Trim() } | Where-Object { $_ } | Select-Object -Last 4) -join ' ')
    Start-Sleep -Seconds 3
    $pst = "$((Get-Disk -Number $p.Disk -ErrorAction Stop).PartitionStyle)"
    if ($pst -ne 'MBR') { throw ('conversion de la clé en MBR impossible (style actuel : {0}, diskpart code {1}) : {2}' -f $pst, $dpc, $dpTxt) }
    $part = @(Get-Partition -DiskNumber $p.Disk -ErrorAction Stop | Where-Object { $_.Size -gt 1GB } | Sort-Object Size -Descending)[0]
    if (-not $part) { throw "partition non créée sur la clé (diskpart code $dpc) : $dpTxt" }
    if (-not $part.DriveLetter -or "$($part.DriveLetter)" -eq [char]0) { Add-PartitionAccessPath -DiskNumber $p.Disk -PartitionNumber $part.PartitionNumber -AssignDriveLetter -ErrorAction Stop; Start-Sleep -Seconds 2; $part = Get-Partition -DiskNumber $p.Disk -PartitionNumber $part.PartitionNumber }
    $fs = "$((Get-Volume -Partition $part -ErrorAction SilentlyContinue).FileSystem)"
    if ($fs -ne 'FAT32') { throw "formatage FAT32 non effectué (système de fichiers : $(if ($fs) { $fs } else { 'aucun' }), diskpart code $dpc) : $dpTxt" }
    $dst = "$($part.DriveLetter):\"
    Test-UsbCancel
    # 4. copie des fichiers de l'ISO (install.wim > 4 Go découpé par DISM)
    Set-UsbState 'Copie des fichiers de Windows' 0 'Montage de l''image ISO'
    $img = Mount-DiskImage -ImagePath $iso -PassThru -ErrorAction Stop
    # lettre attribuée parfois avec un léger retard après le montage : relue 10 s au plus (avant : « :\ », copie en échec
    # après l'effacement de la clé)
    $letter = ''
    for ($k = 0; $k -lt 20 -and -not $letter; $k++) { $letter = "$((Get-DiskImage -ImagePath $iso | Get-Volume -ErrorAction SilentlyContinue).DriveLetter)".Trim(); if (-not $letter) { Start-Sleep -Milliseconds 500 } }
    if (-not $letter) { throw 'image ISO montée sans lettre de lecteur : copie impossible.' }
    $src = "${letter}:\"
    $files = @(Get-ChildItem -LiteralPath $src -Recurse -File -Force)
    $wim = @($files | Where-Object { $_.FullName -ieq (Join-Path $src 'sources\install.wim') })[0]
    $split = $wim -and $wim.Length -ge 4GB - 1MB
    $tot = [double]0; foreach ($f in $files) { if (-not ($split -and $f -eq $wim)) { $tot += $f.Length } }
    $done = [double]0; $tc = [DateTime]::Now
    foreach ($f in $files) {
        if ($split -and $f -eq $wim) { continue }
        Test-UsbCancel
        $rel = $f.FullName.Substring($src.Length); $to = Join-Path $dst $rel
        [void][IO.Directory]::CreateDirectory((Split-Path $to))
        $pc = 100 * $done / [math]::Max([double]1, $tot)
        Set-UsbState 'Copie des fichiers de Windows' $pc ('{0:N0} %  ·  {1:N2} Go sur {2:N2} Go  ·  {3}' -f $pc, ($done / 1GB), ($tot / 1GB), $rel)
        # copie par blocs de 4 Mo : avancement mis à jour pendant les gros fichiers (boot.wim, install.wim...), pas seulement entre deux fichiers
        $fin = [IO.File]::OpenRead($f.FullName); $fout = [IO.File]::Create($to)
        try {
            $buf = New-Object byte[] 4194304; $tl = [DateTime]::Now
            while (($n = $fin.Read($buf, 0, $buf.Length)) -gt 0) {
                $fout.Write($buf, 0, $n); $done += $n
                if (([DateTime]::Now - $tl).TotalMilliseconds -ge 400) {
                    $tl = [DateTime]::Now; Test-UsbCancel
                    $pc = 100 * $done / [math]::Max([double]1, $tot); $sp = $done / [math]::Max([double]1, ([DateTime]::Now - $tc).TotalSeconds)
                    Set-UsbState 'Copie des fichiers de Windows' $pc ('{0:N0} %  ·  {1:N2} Go sur {2:N2} Go  ·  {3:N1} Mo/s  ·  {4}' -f $pc, ($done / 1GB), ($tot / 1GB), ($sp / 1MB), $rel)
                }
            }
        } finally { $fout.Dispose(); $fin.Dispose() }
    }
    if ($split) {
        Set-UsbState 'Découpage de l''image Windows (plus de 4 Go)' 0 'DISM /Split-Image : install.wim en morceaux de 3,8 Go'
        $psi = [Diagnostics.ProcessStartInfo]::new("$env:windir\System32\dism.exe", ('/Split-Image /ImageFile:"{0}" /SWMFile:"{1}" /FileSize:3800' -f $wim.FullName, (Join-Path $dst 'sources\install.swm')))
        $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.CreateNoWindow = $true
        $pr = [Diagnostics.Process]::Start($psi)
        # DISM n'écrit son pourcentage qu'avec des retours chariot (aucune ligne lue tant qu'il travaille) : avancement réel =
        # taille des morceaux install*.swm déjà écrits sur la clé rapportée à la taille de install.wim
        $outTask = $pr.StandardOutput.ReadToEndAsync(); $t0 = [DateTime]::Now; $swmDir = Join-Path $dst 'sources'
        while (-not $pr.WaitForExit(500)) {
            $w = [double]0; foreach ($sf in @(Get-ChildItem -LiteralPath $swmDir -Filter 'install*.swm' -File -ErrorAction SilentlyContinue)) { $w += $sf.Length }
            $pc = [math]::Min([double]99, 100 * $w / [math]::Max([double]1, $wim.Length))
            $sp = $w / [math]::Max([double]1, ([DateTime]::Now - $t0).TotalSeconds)
            Set-UsbState 'Découpage de l''image Windows (plus de 4 Go)' $pc ('{0:N0} %  ·  {1:N2} Go sur {2:N2} Go écrits sur la clé  ·  {3:N1} Mo/s  ·  {4:N0} s' -f $pc, ($w / 1GB), ($wim.Length / 1GB), ($sp / 1MB), ([DateTime]::Now - $t0).TotalSeconds)
            if ($Sync.UsbCancel) { try { $pr.Kill() } catch {} ; Test-UsbCancel }
        }
        $pr.WaitForExit(); [void]$outTask.Wait(5000); if ($pr.ExitCode -ne 0) { throw "DISM /Split-Image : code $($pr.ExitCode)." }
    }
    # 5. démarrage BIOS (secteur de démarrage de l'ISO) et fichier de réponses
    Set-UsbState 'Finalisation' 99 'Secteur de démarrage et fichier de réponses'
    $bs = Join-Path $src 'boot\bootsect.exe'
    if (Test-Path -LiteralPath $bs) { & $bs /nt60 $dst.TrimEnd('\') /mbr 2>&1 | Out-Null }
    [IO.File]::WriteAllText((Join-Path $dst 'autounattend.xml'), $p.Xml, [Text.UTF8Encoding]::new($false))
    $st.Msg = 'Windows {0} sur {1} ({2}).' -f $p.Win, $dst.TrimEnd('\'), [IO.Path]::GetFileName($iso)
    $st.Ok = $true
} catch {
    $m = "$($_.Exception.Message)".Trim(); if (-not $m -and $_.ErrorDetails) { $m = "$($_.ErrorDetails.Message)".Trim() }
    if (-not $m) { $m = '{0} ({1})' -f $_.Exception.GetType().Name, $_.FullyQualifiedErrorId }
    $st.Msg = '{0} - étape : {1}{2}' -f $m, $st.Phase, $(if ($_.InvocationInfo) { ' (ligne {0} : {1})' -f $_.InvocationInfo.ScriptLineNumber, "$($_.InvocationInfo.Line)".Trim() } else { '' })
}
finally {
    if ($img) { try { Dismount-DiskImage -ImagePath $img.ImagePath -ErrorAction Stop | Out-Null } catch {} }
    $st.Done = $true
}
'@
# Fichier de réponses : passes windowsPE (langue, contrat, contrôles levés en option), specialize (BypassNRO), oobeSystem
# (langue, écrans de compte en ligne masqués, compte local administrateur, fuseau horaire). Architecture amd64.
function New-UnattendXml([string]$User, [string]$Pass, [bool]$Bypass) {
    $e = { param($t) [Security.SecurityElement]::Escape("$t") }
    $lang = [Globalization.CultureInfo]::CurrentCulture.Name; if (-not $lang) { $lang = 'fr-FR' }
    $ui = [Globalization.CultureInfo]::CurrentUICulture.Name; if (-not $ui) { $ui = $lang }
    $kb = '040c:0000040c'
    try { $t = @((Get-WinUserLanguageList)[0].InputMethodTips)[0]; if ($t -match '^[0-9A-Fa-f]{4}:[0-9A-Fa-f]{8}$') { $kb = $t.ToLower() } } catch { Write-Ignored 'Clavier pour autounattend.xml' $_ }
    $tz = [TimeZoneInfo]::Local.Id
    $cmp = 'processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS"'
    $intl = "<InputLocale>$kb</InputLocale><SystemLocale>$lang</SystemLocale><UILanguage>$ui</UILanguage><UserLocale>$lang</UserLocale>"
    $lab = ''
    if ($Bypass) {
        $i = 0
        $cmds = @('BypassTPMCheck', 'BypassSecureBootCheck', 'BypassRAMCheck') | ForEach-Object { $i++; "<RunSynchronousCommand wcm:action=`"add`"><Order>$i</Order><Path>reg add HKLM\SYSTEM\Setup\LabConfig /v $_ /t REG_DWORD /d 1 /f</Path></RunSynchronousCommand>" }
        $lab = '<RunSynchronous>' + ($cmds -join '') + '</RunSynchronous>'
    }
    @"
<?xml version="1.0" encoding="utf-8"?>
<!-- Généré par Oliv_Maintenance $AppVersion le $(Get-Date -Format 'dd/MM/yyyy HH:mm') : installation sans compte Microsoft -->
<unattend xmlns="urn:schemas-microsoft-com:unattend" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
  <settings pass="windowsPE">
    <component name="Microsoft-Windows-International-Core-WinPE" $cmp>
      <SetupUILanguage><UILanguage>$ui</UILanguage></SetupUILanguage>
      $intl
    </component>
    <component name="Microsoft-Windows-Setup" $cmp>
      $lab
      <UserData><AcceptEula>true</AcceptEula></UserData>
    </component>
  </settings>
  <settings pass="specialize">
    <component name="Microsoft-Windows-Deployment" $cmp>
      <RunSynchronous><RunSynchronousCommand wcm:action="add"><Order>1</Order><Path>reg add HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE /v BypassNRO /t REG_DWORD /d 1 /f</Path></RunSynchronousCommand></RunSynchronous>
    </component>
  </settings>
  <settings pass="oobeSystem">
    <component name="Microsoft-Windows-International-Core" $cmp>
      $intl
    </component>
    <component name="Microsoft-Windows-Shell-Setup" $cmp>
      <OOBE>
        <HideEULAPage>true</HideEULAPage>
        <HideOEMRegistrationScreen>true</HideOEMRegistrationScreen>
        <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
        <HideWirelessSetupInOOBE>false</HideWirelessSetupInOOBE>
        <ProtectYourPC>3</ProtectYourPC>
      </OOBE>
      <UserAccounts>
        <LocalAccounts>
          <LocalAccount wcm:action="add">
            <Name>$(& $e $User)</Name>
            <DisplayName>$(& $e $User)</DisplayName>
            <Group>Administrators</Group>
            <Password><Value>$(& $e $Pass)</Value><PlainText>true</PlainText></Password>
          </LocalAccount>
        </LocalAccounts>
      </UserAccounts>
      <TimeZone>$(& $e $tz)</TimeZone>
    </component>
  </settings>
</unattend>
"@
}

# ---- configuration sauvegardée : même exportation et même importation que Paramètres (81-parametres.ps1), un seul format
function Save-AppConfig { Export-PcConfig }
function Restore-AppConfig { Import-PcConfig }

# ---------- Ports ouverts et connexions (onglet Sécurité) : écoutes TCP accessibles depuis le réseau (hors boucle locale)
# avec le programme qui écoute ; ports connus de Windows nommés et en gris, les autres en orange (à vérifier).
$KnownPorts = @{ 135 = 'appel de procédure à distance (RPC)'; 139 = 'NetBIOS'; 445 = 'partage de fichiers (SMB)'; 3389 = 'Bureau à distance'; 5040 = 'appareils connectés (CDP)'
    5357 = 'découverte d''appareils (WSD)'; 7680 = 'partage des mises à jour (Optimisation de distribution)'; 5985 = 'gestion à distance (WinRM)'; 2869 = 'UPnP'; 1900 = 'UPnP'
    49664 = 'service système Windows (RPC)'; 49665 = 'service système Windows (RPC)'; 49666 = 'service système Windows (RPC)'; 49667 = 'service système Windows (RPC)'; 49668 = 'service système Windows (RPC)'; 49669 = 'service système Windows (RPC)'; 49670 = 'service système Windows (RPC)' }
# section de la carte Réseau de l'accueil : intertitre, ports, liens Actualiser / Connexions actives
# carte Réseau de l'accueil : un seul bouton, ports ouverts et connexions actives dans une fenêtre
function New-NetPortSection($Body) {
    $hd = [Windows.Controls.DockPanel]::new(); $hd.Margin = New-Thickness 46 10 18 2
    $bt = New-Button 'Ports et connexions'; $bt.Height = 30; $bt.MinWidth = 140; $bt.HorizontalAlignment = 'Left'
    $bt.ToolTip = 'Ports ouverts sur le réseau (programmes joignables depuis d''autres postes) et connexions actives'
    $bt.Add_Click({ Show-NetConnection })
    [void]$hd.Children.Add($bt); [void]$Body.Children.Add($hd)
}
function Get-ProcName([int]$ProcId) {
    if ($ProcId -eq 4) { return 'System' }
    $p = Get-Process -Id $ProcId -ErrorAction SilentlyContinue; $(if ($p) { $p.ProcessName } else { "processus $ProcId" })
}
# ports en écoute (hors boucle locale) : lignes « Port 445 : System · partage de fichiers (SMB) », non standard signalés
function Get-NetPortLine {
    $ls = @(Get-NetTCPConnection -State Listen -ErrorAction Stop | Where-Object { $_.LocalAddress -notin '127.0.0.1', '::1' -and $_.LocalAddress -notlike '127.*' })
    $byPort = $ls | Group-Object LocalPort | Sort-Object { [int]$_.Name }
    $sys = @($byPort | Where-Object { [int]$_.Name -ge 49664 -and [int]$_.Name -le 49680 -and (Get-ProcName $_.Group[0].OwningProcess) -in 'lsass', 'wininit', 'services', 'svchost', 'spoolsv' })
    $out = @(foreach ($g in $byPort) {
            if ($sys -contains $g) { continue }
            $port = [int]$g.Name; $known = $KnownPorts[$port]
            'Port {0,-6} {1}{2}' -f $port, (Get-ProcName $g.Group[0].OwningProcess), $(if ($known) { '  ·  ' + $known } else { '  ·  port non standard : vérifier que ce programme doit être joignable' })
        })
    if ($sys.Count) { $out += '+ {0} ports système de Windows (RPC dynamiques)' -f $sys.Count }
    if (-not $out.Count) { $out = @('aucun') }
    $out
}
function Show-NetConnection {
    try {
        $ports = @(Get-NetPortLine)
        $cn = @(Get-NetTCPConnection -State Established -ErrorAction Stop | Where-Object { $_.RemoteAddress -notin '127.0.0.1', '::1' })
    } catch { Show-Info "Lecture impossible : $($_.Exception.Message)" 'Error'; return }
    $lines = @($cn | ForEach-Object { '{0}  >  {1} : {2}' -f (Get-ProcName $_.OwningProcess), $_.RemoteAddress, $_.RemotePort } | Sort-Object)
    $all = @('PORTS OUVERTS SUR LE RÉSEAU') + $ports + @('', ('CONNEXIONS ACTIVES ({0})  ·  programme  >  adresse distante : port' -f $lines.Count)) + $(if ($lines.Count) { $lines } else { @('aucune') })
    [void](Show-Dialog 'Ports ouverts et connexions actives' 'Info' $null $all)
}

New-InstallCard
