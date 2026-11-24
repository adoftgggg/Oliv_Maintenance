# ---------- Onglet Applications : catalogue d'applications installables par winget
# Présentation en vignettes par catégorie (icône, nom, description courte), pastilles de catégorie et recherche en haut,
# clic sur une vignette = sélection. Installation de la sélection par la tâche AppInstall (même moteur que les mises à
# jour de logiciels : winget install -e --id, une application après l'autre, suivi en direct sur chaque vignette).
# Applications déjà installées repérées par l'inventaire winget (Get-WinGetPackage, tâche de fond) : badge « Installé ».
# Icônes : favicon du site de l'éditeur (service favicon de Google, 64 px), téléchargées en tâche de fond une seule fois
# dans _etat\icones ; en attendant ou à défaut, pastille colorée avec les initiales.
# Entrée : nom, identifiant winget, site de l'éditeur (icône), description, source imposée (msstore = Microsoft Store).
$AppCatalog = [ordered]@{
    'Navigateurs' = @{ G = 0xE774; A = @(
        @('Google Chrome', 'Google.Chrome', 'google.com/chrome', 'Le navigateur de Google'),
        @('Mozilla Firefox', 'Mozilla.Firefox', 'mozilla.org', 'Libre et respectueux de la vie privée'),
        @('Brave', 'Brave.Brave', 'brave.com', 'Bloqueur de pubs intégré'),
        @('Opera', 'Opera.Opera', 'opera.com', 'VPN gratuit intégré'),
        @('Vivaldi', 'Vivaldi.Vivaldi', 'vivaldi.com', 'Personnalisable à l''infini'),
        @('Microsoft Edge', 'Microsoft.Edge', 'microsoft.com/edge', 'Le navigateur de Windows')) }
    'Messagerie' = @{ G = 0xE8BD; A = @(
        @('Discord', 'Discord.Discord', 'discord.com', 'Vocal et chat entre amis'),
        @('WhatsApp', '9NKSQGP7F2NH', 'whatsapp.com', 'Messages et appels', 'msstore'),
        @('Telegram', 'Telegram.TelegramDesktop', 'telegram.org', 'Messagerie rapide et synchronisée'),
        @('Signal', 'OpenWhisperSystems.Signal', 'signal.org', 'Messagerie chiffrée'),
        @('Zoom', 'Zoom.Zoom', 'zoom.us', 'Visioconférence'),
        @('Microsoft Teams', 'Microsoft.Teams', 'teams.microsoft.com', 'Réunions et travail d''équipe'),
        @('Slack', 'SlackTechnologies.Slack', 'slack.com', 'Messagerie d''équipe'),
        @('Thunderbird', 'Mozilla.Thunderbird', 'thunderbird.net', 'Client de messagerie')) }
    'Multimédia' = @{ G = 0xE8B2; A = @(
        @('VLC', 'VideoLAN.VLC', 'videolan.org', 'Lit absolument tout'),
        @('Spotify', 'Spotify.Spotify', 'spotify.com', 'Musique en streaming'),
        @('MPC-HC', 'clsid2.mpc-hc', 'github.com/clsid2/mpc-hc', 'Lecteur vidéo léger'),
        @('AIMP', 'AIMP.AIMP', 'aimp.ru', 'Lecteur audio'),
        @('foobar2000', 'PeterPawlowski.foobar2000', 'foobar2000.org', 'Lecteur audio audiophile'),
        @('Audacity', 'Audacity.Audacity', 'audacityteam.org', 'Édition audio'),
        @('OBS Studio', 'OBSProject.OBSStudio', 'obsproject.com', 'Enregistrement et streaming'),
        @('HandBrake', 'HandBrake.HandBrake', 'handbrake.fr', 'Conversion vidéo'),
        @('K-Lite Codec Pack', 'CodecGuide.K-LiteCodecPack.Standard', 'codecguide.com', 'Tous les codecs vidéo')) }
    'Jeux' = @{ G = 0xE7FC; A = @(
        @('Steam', 'Valve.Steam', 'steampowered.com', 'La bibliothèque PC de référence'),
        @('Epic Games', 'EpicGames.EpicGamesLauncher', 'epicgames.com', 'Jeux gratuits chaque semaine'),
        @('EA app', 'ElectronicArts.EADesktop', 'ea.com', 'Jeux Electronic Arts'),
        @('Ubisoft Connect', 'Ubisoft.Connect', 'ubisoft.com', 'Jeux Ubisoft'),
        @('GOG Galaxy', 'GOG.Galaxy', 'gog.com', 'Jeux sans DRM'),
        @('Battle.net', 'Blizzard.BattleNet', 'blizzard.com', 'Jeux Blizzard')) }
    'Utilitaires' = @{ G = 0xE90F; A = @(
        @('PowerToys', 'Microsoft.PowerToys', 'learn.microsoft.com', 'Super-pouvoirs pour Windows'),
        @('Everything', 'voidtools.Everything', 'voidtools.com', 'Recherche de fichiers instantanée'),
        @('WizTree', 'AntibodySoftware.WizTree', 'diskanalyzer.com', 'Qui prend la place sur le disque'),
        @('TeraCopy', 'CodeSector.TeraCopy', 'codesector.com', 'Copies rapides et vérifiées'),
        @('Revo Uninstaller', 'RevoUninstaller.RevoUninstaller', 'revouninstaller.com', 'Désinstallation complète'),
        @('Bulk Crap Uninstaller', 'Klocman.BulkCrapUninstaller', 'bcuninstaller.com', 'Désinstallation en masse'),
        @('CPU-Z', 'CPUID.CPU-Z', 'cpuid.com', 'Détail du matériel'),
        @('HWMonitor', 'CPUID.HWMonitor', 'cpuid.com', 'Températures et tensions'),
        @('CrystalDiskInfo', 'CrystalDewWorld.CrystalDiskInfo', 'crystalmark.info', 'Santé des disques'),
        @('CrystalDiskMark', 'CrystalDewWorld.CrystalDiskMark', 'crystalmark.info', 'Vitesse des disques'),
        @('Rufus', 'Rufus.Rufus', 'rufus.ie', 'Clés USB démarrables'),
        @('Ventoy', 'Ventoy.Ventoy', 'ventoy.net', 'Plusieurs ISO sur une clé'),
        @('Advanced IP Scanner', 'Famatech.AdvancedIPScanner', 'advanced-ip-scanner.com', 'Scanner du réseau local')) }
    'Compression' = @{ G = 0xE7B8; A = @(
        @('7-Zip', '7zip.7zip', '7-zip.org', 'Le classique gratuit'),
        @('NanaZip', 'M2Team.NanaZip', 'github.com/M2Team/NanaZip', '7-Zip moderne pour Windows 11'),
        @('PeaZip', 'Giorgiotani.Peazip', 'peazip.github.io', 'Plus de 200 formats'),
        @('WinRAR', 'RARLab.WinRAR', 'win-rar.com', 'Archives RAR')) }
    'Accès à distance' = @{ G = 0xE703; A = @(
        @('AnyDesk', 'AnyDesk.AnyDesk', 'anydesk.com', 'Prise en main à distance'),
        @('TeamViewer', 'TeamViewer.TeamViewer', 'teamviewer.com', 'Prise en main à distance'),
        @('Tailscale', 'Tailscale.Tailscale', 'tailscale.com', 'VPN entre tes appareils'),
        @('WireGuard', 'WireGuard.WireGuard', 'wireguard.com', 'VPN moderne'),
        @('TightVNC', 'GlavSoft.TightVNC', 'tightvnc.com', 'Bureau à distance VNC')) }
    'Sécurité' = @{ G = 0xE72E; A = @(
        @('Bitwarden', 'Bitwarden.Bitwarden', 'bitwarden.com', 'Gestionnaire de mots de passe'),
        @('KeePassXC', 'KeePassXCTeam.KeePassXC', 'keepassxc.org', 'Mots de passe hors ligne'),
        @('KeePass 2', 'DominikReichl.KeePass', 'keepass.info', 'Mots de passe hors ligne'),
        @('1Password', 'AgileBits.1Password', '1password.com', 'Gestionnaire de mots de passe'),
        @('Malwarebytes', 'Malwarebytes.Malwarebytes', 'malwarebytes.com', 'Anti-malware')) }
    'Bureautique' = @{ G = 0xE8A5; A = @(
        @('LibreOffice', 'TheDocumentFoundation.LibreOffice', 'libreoffice.org', 'Suite bureautique gratuite'),
        @('Acrobat Reader', 'Adobe.Acrobat.Reader.64-bit', 'adobe.com', 'Lecteur PDF d''Adobe'),
        @('SumatraPDF', 'SumatraPDF.SumatraPDF', 'sumatrapdfreader.org', 'Lecteur PDF ultra léger'),
        @('Foxit PDF Reader', 'Foxit.FoxitReader', 'foxit.com', 'Lecteur PDF'),
        @('Notepad++', 'Notepad++.Notepad++', 'notepad-plus-plus.org', 'Éditeur de texte'),
        @('Obsidian', 'Obsidian.Obsidian', 'obsidian.md', 'Notes et second cerveau'),
        @('Notion', 'Notion.Notion', 'notion.so', 'Notes et organisation')) }
    'Image et 3D' = @{ G = 0xE91B; A = @(
        @('Paint.NET', 'dotPDN.PaintDotNet', 'getpaint.net', 'Retouche photo simple'),
        @('Krita', 'KDE.Krita', 'krita.org', 'Peinture numérique'),
        @('Inkscape', 'Inkscape.Inkscape', 'inkscape.org', 'Dessin vectoriel'),
        @('Blender', 'BlenderFoundation.Blender', 'blender.org', 'Modélisation et animation 3D'),
        @('IrfanView', 'IrfanSkiljan.IrfanView', 'irfanview.com', 'Visionneuse d''images'),
        @('ShareX', 'ShareX.ShareX', 'getsharex.com', 'Captures d''écran avancées'),
        @('Greenshot', 'Greenshot.Greenshot', 'getgreenshot.org', 'Captures d''écran'),
        @('Bambu Studio', 'Bambulab.Bambustudio', 'bambulab.com', 'Impression 3D Bambu Lab'),
        @('UltiMaker Cura', 'Ultimaker.Cura', 'ultimaker.com', 'Impression 3D')) }
    'Stockage en ligne' = @{ G = 0xE753; A = @(
        @('Google Drive', 'Google.GoogleDrive', 'drive.google.com', 'Fichiers Google synchronisés'),
        @('Dropbox', 'Dropbox.Dropbox', 'dropbox.com', 'Fichiers synchronisés'),
        @('OneDrive', 'Microsoft.OneDrive', 'onedrive.live.com', 'Le cloud de Microsoft'),
        @('pCloud Drive', 'pCloudAG.pCloudDrive', 'pcloud.com', 'Cloud européen')) }
    'Développement' = @{ G = 0xE943; A = @(
        @('Visual Studio Code', 'Microsoft.VisualStudioCode', 'code.visualstudio.com', 'L''éditeur de code'),
        @('Git', 'Git.Git', 'git-scm.com', 'Gestion de versions'),
        @('GitHub Desktop', 'GitHub.GitHubDesktop', 'github.com', 'Git sans la ligne de commande'),
        @('Python 3.13', 'Python.Python.3.13', 'python.org', 'Langage Python'),
        @('Node.js LTS', 'OpenJS.NodeJS.LTS', 'nodejs.org', 'JavaScript côté serveur'),
        @('Docker Desktop', 'Docker.DockerDesktop', 'docker.com', 'Conteneurs'),
        @('Windows Terminal', 'Microsoft.WindowsTerminal', 'github.com/microsoft/terminal', 'Terminal moderne'),
        @('PowerShell 7', 'Microsoft.PowerShell', 'learn.microsoft.com', 'La dernière version de PowerShell'),
        @('WinSCP', 'WinSCP.WinSCP', 'winscp.net', 'Transferts SFTP / SCP'),
        @('PuTTY', 'PuTTY.PuTTY', 'putty.org', 'Client SSH'),
        @('Sublime Text', 'SublimeHQ.SublimeText.4', 'sublimetext.com', 'Éditeur de texte rapide')) }
    'Composants' = @{ G = 0xE74C; A = @(
        @('Visual C++ x64', 'Microsoft.VCRedist.2015+.x64', 'visualstudio.microsoft.com', 'Redistribuable 2015-2022'),
        @('Visual C++ x86', 'Microsoft.VCRedist.2015+.x86', 'visualstudio.microsoft.com', 'Redistribuable 2015-2022'),
        @('.NET Desktop 8', 'Microsoft.DotNet.DesktopRuntime.8', 'dotnet.microsoft.com', 'Runtime .NET 8'),
        @('.NET Desktop 9', 'Microsoft.DotNet.DesktopRuntime.9', 'dotnet.microsoft.com', 'Runtime .NET 9'),
        @('Java 21', 'EclipseAdoptium.Temurin.21.JRE', 'adoptium.net', 'Runtime Java (Temurin)'),
        @('Edge WebView2', 'Microsoft.EdgeWebView2Runtime', 'developer.microsoft.com', 'Moteur web des applis')) }
    'Autres' = @{ G = 0xE734; A = @(
        @('Claude', 'Anthropic.Claude', 'claude.ai', 'L''assistant IA d''Anthropic'),
        @('ChatGPT', '9NT1R1C2HH7J', 'chatgpt.com', 'L''assistant IA d''OpenAI', 'msstore'),
        @('Google Earth Pro', 'Google.EarthPro', 'earth.google.com', 'La planète en 3D'),
        @('Evernote', 'Evernote.Evernote', 'evernote.com', 'Prise de notes')) }
}
# Paquets installés pour le compte de l'utilisateur (manifestes winget-pkgs relus le 24/11/2026 : « Scope: user » seul,
# ou « ElevationRequirement: elevationProhibited », ou MSIX par utilisateur) : lancés sous le compte de l'utilisateur, sans
# élévation (Spotify refuse de s'installer en administrateur ; sinon installation dans le profil du compte administrateur)
$AppUserScope = [Collections.Generic.HashSet[string]]::new([string[]]@('Discord.Discord', 'Telegram.TelegramDesktop', 'OpenWhisperSystems.Signal', 'SlackTechnologies.Slack',
    'Spotify.Spotify', 'Notion.Notion', 'Microsoft.WindowsTerminal', 'Anthropic.Claude', 'Microsoft.Teams'), [StringComparer]::OrdinalIgnoreCase)
# Versions portables (vérifiées dans les manifestes winget-pkgs le 19/11/2026 : programme d'installation de type « portable »,
# ou archive zip contenant un exécutable portable) : identifiant winget -> exécutable à lancer (motif, recherche récursive)
$AppPortable = @{
    'Telegram.TelegramDesktop' = 'Telegram.exe'; 'VideoLAN.VLC' = 'vlc.exe'; 'OBSProject.OBSStudio' = 'obs64.exe'; 'voidtools.Everything' = 'Everything.exe'
    'Rufus.Rufus' = 'rufus*.exe'; 'Ventoy.Ventoy' = 'Ventoy2Disk.exe'; 'Giorgiotani.Peazip' = 'peazip.exe'; 'Bitwarden.Bitwarden' = 'Bitwarden*.exe'
    'SumatraPDF.SumatraPDF' = 'SumatraPDF*.exe'; 'Notepad++.Notepad++' = 'notepad++.exe'; 'dotPDN.PaintDotNet' = 'paintdotnet.exe'
}
# dossier de l'utilisateur ciblé : il garde les droits d'écriture (réglages enregistrés à côté de l'exécutable)
$PortableRoot = Join-Path $UserProfilePath 'AppData\Local\Oliv_Maintenance\Portables'
$PortScript = @'
$p = $Sync.PortParams; $st = $Sync.Port
$wg = Find-Winget
$res = [Collections.Generic.List[string]]::new()
foreach ($a in $p.Items) {
    $st.Name = $a.Name; $st.Phase = 'préparation'; $st.T0 = [DateTime]::Now
    $dir = Join-Path $p.Root ($a.Id -replace '[^\w\.\-\+]', '_')
    try {
        $find = { @(Get-ChildItem -LiteralPath $dir -Recurse -File -Filter $a.Exe -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch '(?i)(setup|install|uninst)' } | Sort-Object { $_.FullName.Length })[0] }
        # copie de moins de 30 jours réutilisée, sinon nouveau téléchargement (dernière version)
        $exe = $null
        if ((Test-Path -LiteralPath $dir) -and (Get-Item -LiteralPath $dir).LastWriteTime -gt (Get-Date).AddDays(-30)) { $exe = & $find }
        if (-not $exe) {
            if (-not $wg) { throw 'winget introuvable' }
            if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction Stop }
            [void][IO.Directory]::CreateDirectory($dir)
            $st.Phase = 'téléchargement'
            # programme portable, sinon archive zip (exécutable portable à l'intérieur)
            $out = $null; $rc = 1
            foreach ($t in 'portable', 'zip') {
                $out = & $wg download --id $a.Id -e --source winget --installer-type $t -d $dir --accept-package-agreements --accept-source-agreements --disable-interactivity 2>&1
                $rc = $LASTEXITCODE; if ($rc -eq 0) { break }
            }
            if ($rc -ne 0) { throw ('winget download, code 0x{0:X8} : {1}' -f $rc, ((@($out) | ForEach-Object { "$_".Trim() } | Where-Object { $_ -and $_ -notmatch '^[-\\|/ ]+$' } | Select-Object -Last 2) -join ' ')) }
            foreach ($z in @(Get-ChildItem -LiteralPath $dir -Filter *.zip -File)) {
                $st.Phase = 'extraction'
                Expand-Archive -LiteralPath $z.FullName -DestinationPath (Join-Path $dir 'app') -Force
                Remove-Item -LiteralPath $z.FullName -Force
            }
            (Get-Item -LiteralPath $dir).LastWriteTime = Get-Date
            $exe = & $find
            if (-not $exe) { throw "$($a.Exe) absent du téléchargement" }
        }
        $st.Phase = 'lancement'
        # lancement par l'Explorateur : programme ouvert dans la session de l'utilisateur, sans les droits d'administrateur
        Start-Process -FilePath (Join-Path $env:windir 'explorer.exe') -ArgumentList ('"{0}"' -f $exe.FullName)
        $res.Add(('OK|{0}|{1}' -f $a.Name, $exe.FullName))
    } catch { $res.Add(('KO|{0}|{1}' -f $a.Name, $_.Exception.Message)) }
}
$st.Res = $res.ToArray()
'@
function Invoke-AppsPortable {
    if ($Sync.PortRunning) { return }
    $items = @(foreach ($id in @($AppsUI.Sel)) { if ($AppPortable.Contains("$id")) { @{ Id = "$id"; Name = "$($AppsUI.Tiles["$id"].A[0])"; Exe = $AppPortable["$id"] } } })
    if (-not $items.Count) { return }
    $Sync.PortParams = @{ Items = $items; Root = $PortableRoot }; $Sync.Port = [hashtable]::Synchronized(@{ Name = ''; Phase = ''; T0 = [DateTime]::Now; Res = $null })
    $Sync.PortRunning = $true; Update-AppsSelection
    Write-UiLog ('Ouverture en version portable : {0}.' -f (($items | ForEach-Object { $_.Name }) -join ', ')) 'APP'
    Start-BgJob 'Port' $PortScript
    # avancement : application en cours, étape, temps écoulé
    if (-not $AppsUI.PortTimer) {
        $AppsUI.PortTimer = [Windows.Threading.DispatcherTimer]::new(); $AppsUI.PortTimer.Interval = [TimeSpan]::FromMilliseconds(500)
        $AppsUI.PortTimer.Add_Tick({ $s = $Sync.Port; if ($s -and $s.Name) { $Ui.AppsStatus.Text = 'Version portable de {0} : {1}  ·  {2:mm\:ss}' -f $s.Name, $s.Phase, ([DateTime]::Now - $s.T0) } })
    }
    $AppsUI.PortTimer.Start()
}
$BgJobDone['Port'] = {
    if ($AppsUI.PortTimer) { $AppsUI.PortTimer.Stop() }
    $Sync.PortRunning = $false
    $res = @($(if ($Sync.Port) { $Sync.Port.Res }))
    $ok = @(); $ko = @()
    foreach ($l in $res) {
        $f = "$l" -split '\|', 3
        if ($f[0] -eq 'OK') { $ok += $f[1]; Write-UiLog ('Version portable de {0} lancée : {1}' -f $f[1], $f[2]) 'OK' }
        else { $ko += '{0} : {1}' -f $f[1], $f[2]; Write-UiLog ('Version portable de {0} : échec - {1}' -f $f[1], $f[2]) 'ERROR' }
    }
    if (-not $res.Count) { $ko += 'tâche interrompue' }
    Update-AppsSelection
    $Ui.AppsStatus.Text = $(if (-not $ko.Count) { 'Version portable lancée : {0}  ·  copie gardée 30 jours dans {1}' -f ($ok -join ', '), $PortableRoot } else { 'Version portable : {0} lancée(s), échec pour {1}' -f $ok.Count, ($ko -join ' ; ') })
    if ($ko.Count) { Show-Info ("Ouverture en version portable impossible :`n`n" + ($ko -join "`n")) 'Warn' }
}
$AppsUI = @{ Built = $false; Tiles = @{}; Sel = [Collections.Generic.HashSet[string]]::new(); Installed = $null; Cat = ''; IconDir = (Join-Path (Get-LogPath 'Etat') 'icones') }
# couleurs des pastilles d'initiales (choisies par l'identifiant : toujours la même pour une application)
$AppsPalette = @('#2563EB', '#7C3AED', '#DB2777', '#EA580C', '#16A34A', '#0891B2', '#CA8A04', '#DC2626', '#4F46E5', '#0D9488')

function New-AppTile($A, [string]$Cat) {
    $id = "$($A[1])"
    $t = [Windows.Controls.Border]::new(); $t.Width = 248; $t.Height = 70; $t.Margin = New-Thickness 0 0 10 10
    $t.CornerRadius = [Windows.CornerRadius]::new(10); $t.BorderThickness = New-Thickness 1 1 1 1; $t.Cursor = [Windows.Input.Cursors]::Hand
    $t.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, 'PanelBrush')
    $t.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, 'LineBrush')
    $root = [Windows.Controls.Grid]::new(); $t.Child = $root
    # fond teinté de sélection (couleur d'accent, opacité animée par l'état) sous le contenu
    $sel = [Windows.Controls.Border]::new(); $sel.CornerRadius = [Windows.CornerRadius]::new(9); $sel.Opacity = 0
    $sel.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, 'AccentBrush'); [void]$root.Children.Add($sel)
    $g = [Windows.Controls.Grid]::new(); $g.Margin = New-Thickness 12 0 12 0
    foreach ($w in 'Auto', '*') { $cd = [Windows.Controls.ColumnDefinition]::new(); $cd.Width = $(if ($w -eq 'Auto') { [Windows.GridLength]::Auto } else { [Windows.GridLength]::new(1, 'Star') }); [void]$g.ColumnDefinitions.Add($cd) }
    [void]$root.Children.Add($g)
    # icône : image téléchargée ou pastille d'initiales
    $ic = [Windows.Controls.Border]::new(); $ic.Width = 40; $ic.Height = 40; $ic.CornerRadius = [Windows.CornerRadius]::new(10); $ic.VerticalAlignment = 'Center'
    $h = 0; foreach ($ch in $id.ToCharArray()) { $h = ($h * 31 + [int]$ch) % 1000003 }
    $ic.Background = [Windows.Media.BrushConverter]::new().ConvertFromString($AppsPalette[$h % $AppsPalette.Count])
    $ini = (($A[0] -replace '[^\p{L}\p{N} ]', '' -split ' ' | Where-Object { $_ } | Select-Object -First 2 | ForEach-Object { $_.Substring(0, 1) }) -join '').ToUpper()
    $it = New-Text $ini; $it.Foreground = [Windows.Media.Brushes]::White; $it.FontWeight = [Windows.FontWeights]::Bold; $it.FontSize = 15
    $it.HorizontalAlignment = 'Center'; $it.VerticalAlignment = 'Center'; $ic.Child = $it
    [void]$g.Children.Add($ic)
    $tx = [Windows.Controls.StackPanel]::new(); $tx.VerticalAlignment = 'Center'; $tx.Margin = New-Thickness 12 0 22 0
    [Windows.Controls.Grid]::SetColumn($tx, 1)
    $n = New-Text "$($A[0])"; $n.FontSize = 14; $n.FontWeight = [Windows.FontWeights]::SemiBold; $n.TextWrapping = 'NoWrap'; $n.TextTrimming = 'CharacterEllipsis'
    $d = New-Text "$($A[3])" 'Muted'; $d.FontSize = 12; $d.TextWrapping = 'NoWrap'; $d.TextTrimming = 'CharacterEllipsis'; $d.Margin = New-Thickness 0 2 0 0
    [void]$tx.Children.Add($n); [void]$tx.Children.Add($d); [void]$g.Children.Add($tx)
    # coche de sélection en haut à droite
    $ck = [Windows.Controls.Border]::new(); $ck.Width = 20; $ck.Height = 20; $ck.CornerRadius = [Windows.CornerRadius]::new(10)
    $ck.HorizontalAlignment = 'Right'; $ck.VerticalAlignment = 'Top'; $ck.Margin = New-Thickness 0 7 8 0; $ck.BorderThickness = New-Thickness 1.5 1.5 1.5 1.5
    $ck.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, 'LineBrush')
    $cg = New-Text ''; $cg.FontFamily = [Windows.Media.FontFamily]::new('Segoe MDL2 Assets'); $cg.FontSize = 10; $cg.Foreground = [Windows.Media.Brushes]::White
    $cg.HorizontalAlignment = 'Center'; $cg.VerticalAlignment = 'Center'; $ck.Child = $cg
    [void]$root.Children.Add($ck)
    $t.ToolTip = '{0}  ·  winget {1}{2}{3}' -f $A[0], $id, $(if ($A.Count -gt 4) { ' (Microsoft Store)' } else { '' }), $(if ($AppPortable.Contains($id)) { "`nVersion portable disponible : ouverture sans installation" } else { '' })
    $o = @{ A = $A; Id = $id; Cat = $Cat; Tile = $t; Sel = $sel; Check = $ck; CheckGlyph = $cg; Icon = $ic; Desc = $d; DescText = "$($A[3])"; Hover = $false }
    $t.Tag = $o
    $t.Add_MouseEnter({ param($s, $e) $s.Tag.Hover = $true; Set-AppTileLook $s.Tag })
    $t.Add_MouseLeave({ param($s, $e) $s.Tag.Hover = $false; Set-AppTileLook $s.Tag })
    $t.Add_MouseLeftButtonUp({ param($s, $e) Switch-AppTile $s.Tag })
    $AppsUI.Tiles[$id] = $o
    $t
}
# aspect d'une vignette : sélectionnée (fond et bord d'accent, coche pleine), installée (badge vert), survol
function Set-AppTileLook($O) {
    $inst = $AppsUI.Installed -and $AppsUI.Installed.Contains($O.Id)
    $on = $AppsUI.Sel.Contains($O.Id)
    $O.Sel.Opacity = $(if ($on) { 0.14 } elseif ($O.Hover -and -not $inst) { 0.06 } else { 0 })
    $O.Tile.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, $(if ($on) { 'AccentBrush' } else { 'LineBrush' }))
    if ($inst) {
        $O.Check.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, 'OkFgBrush'); $O.Check.BorderThickness = New-Thickness 0 0 0 0
        $O.CheckGlyph.Text = [string][char]0xE73E; $O.Tile.Cursor = [Windows.Input.Cursors]::Arrow; $O.Tile.Opacity = 0.75
    } elseif ($on) {
        $O.Check.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, 'AccentBrush'); $O.Check.BorderThickness = New-Thickness 0 0 0 0
        $O.CheckGlyph.Text = [string][char]0xE73E; $O.Tile.Cursor = [Windows.Input.Cursors]::Hand; $O.Tile.Opacity = 1
    } else {
        $O.Check.Background = [Windows.Media.Brushes]::Transparent; $O.Check.BorderThickness = New-Thickness 1.5 1.5 1.5 1.5
        $O.CheckGlyph.Text = ''; $O.Tile.Cursor = [Windows.Input.Cursors]::Hand; $O.Tile.Opacity = 1
    }
}
function Switch-AppTile($O) {
    if ($Sync.Running) { return }
    if ($AppsUI.Installed -and $AppsUI.Installed.Contains($O.Id)) { return }
    if (-not $AppsUI.Sel.Remove($O.Id)) { [void]$AppsUI.Sel.Add($O.Id) }
    Set-AppTileLook $O
    Update-AppsSelection
}
function New-AppsChip([string]$Key, [string]$Label) {
    $b = [Windows.Controls.Border]::new(); $b.CornerRadius = [Windows.CornerRadius]::new(15); $b.Padding = New-Thickness 12 5 12 5
    $b.Margin = New-Thickness 0 0 6 6; $b.Cursor = [Windows.Input.Cursors]::Hand; $b.BorderThickness = New-Thickness 1 1 1 1; $b.Tag = $Key
    $t = New-Text $Label; $t.FontSize = 12.5; $b.Child = $t
    $b.Add_MouseLeftButtonUp({ param($s, $e) $AppsUI.Cat = "$($s.Tag)"; Update-AppsFilter })
    [void]$Ui.AppsChips.Children.Add($b)
}
function New-AppsPage {
    $AppsUI.Built = $true
    New-AppsChip '' 'Toutes'
    foreach ($cat in $AppCatalog.Keys) {
        New-AppsChip $cat $cat
        $sec = [Windows.Controls.StackPanel]::new(); $sec.Tag = $cat; $sec.Margin = New-Thickness 0 6 0 8
        $hd = [Windows.Controls.StackPanel]::new(); $hd.Orientation = 'Horizontal'; $hd.Margin = New-Thickness 2 0 0 10
        $gl = New-Text ([string][char]$AppCatalog[$cat].G); $gl.FontFamily = [Windows.Media.FontFamily]::new('Segoe MDL2 Assets'); $gl.FontSize = 16
        $gl.VerticalAlignment = 'Center'; $gl.Margin = New-Thickness 0 0 10 0; $gl.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'AccentBrush')
        $ht = New-Text $cat; $ht.FontSize = 17; $ht.FontWeight = [Windows.FontWeights]::SemiBold; $ht.VerticalAlignment = 'Center'
        $hc = New-Text ('{0}' -f @($AppCatalog[$cat].A).Count) 'Muted'; $hc.FontSize = 12.5; $hc.Margin = New-Thickness 8 2 0 0; $hc.VerticalAlignment = 'Center'
        [void]$hd.Children.Add($gl); [void]$hd.Children.Add($ht); [void]$hd.Children.Add($hc); [void]$sec.Children.Add($hd)
        $wp = [Windows.Controls.WrapPanel]::new()
        foreach ($a in $AppCatalog[$cat].A) { [void]$wp.Children.Add((New-AppTile $a $cat)) }
        [void]$sec.Children.Add($wp); [void]$Ui.AppsPanel.Children.Add($sec)
    }
    $Ui.AppsFind.Add_TextChanged({ $Ui.AppsFindHint.Visibility = $(if ($Ui.AppsFind.Text) { 'Collapsed' } else { 'Visible' }); Update-AppsFilter })
    $Ui.AppsFind.Add_GotKeyboardFocus({ $Ui.AppsFindBox.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, 'AccentBrush') })
    $Ui.AppsFind.Add_LostKeyboardFocus({ $Ui.AppsFindBox.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, 'LineBrush') })
    $Ui.AppsClear.Add_Click({ $AppsUI.Sel.Clear(); foreach ($o in $AppsUI.Tiles.Values) { Set-AppTileLook $o }; Update-AppsSelection })
    $Ui.AppsInstall.Add_Click({ Invoke-AppsInstall })
    $Ui.AppsPortable.Add_Click({ Invoke-AppsPortable })
    Update-AppsFilter; Update-AppsSelection
    Set-AppsIcon; Start-AppsIconDownload
    Start-AppsInventory
}
# pastille de catégorie + recherche : sections et vignettes affichées
function Update-AppsFilter {
    foreach ($c in $Ui.AppsChips.Children) {
        $on = "$($c.Tag)" -eq $AppsUI.Cat
        $c.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, $(if ($on) { 'AccentBrush' } else { 'BgBrush' }))
        $c.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, $(if ($on) { 'AccentBrush' } else { 'LineBrush' }))
        $c.Child.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, $(if ($on) { 'OnAccentBrush' } else { 'FgBrush' }))
    }
    $q = "$($Ui.AppsFind.Text)".Trim()
    foreach ($sec in $Ui.AppsPanel.Children) {
        $n = 0
        foreach ($t in $sec.Children[1].Children) {
            $a = $t.Tag.A
            $show = (-not $AppsUI.Cat -or $AppsUI.Cat -eq $sec.Tag) -and (-not $q -or "$($a[0])" -like "*$q*" -or "$($a[1])" -like "*$q*" -or "$($a[3])" -like "*$q*")
            $t.Visibility = $(if ($show) { 'Visible' } else { 'Collapsed' }); if ($show) { $n++ }
        }
        $sec.Visibility = $(if ($n) { 'Visible' } else { 'Collapsed' })
    }
    $Ui.AppsScroll.ScrollToTop()
}
# icônes : fichiers déjà téléchargés appliqués aux vignettes (pastille d'initiales remplacée)
# icône d'une vignette : icône réelle du programme installé (extraite de son exécutable, fichier <id>.app.png) en priorité,
# sinon favicon du site de l'éditeur (<id>.png), sinon initiales
function Set-AppsIcon {
    foreach ($o in $AppsUI.Tiles.Values) {
        if ($o.IconReal) { continue }
        $b = Join-Path $AppsUI.IconDir ($o.Id -replace '[^\w.+-]', '_')
        $real = [IO.File]::Exists("$b.app.png")
        if ($o.IconSet -and -not $real) { continue }
        $f = $(if ($real) { "$b.app.png" } else { "$b.png" })
        if (-not [IO.File]::Exists($f) -or (Get-Item -LiteralPath $f).Length -lt 200) { continue }
        try {
            $bi = [Windows.Media.Imaging.BitmapImage]::new(); $bi.BeginInit(); $bi.CacheOption = 'OnLoad'; $bi.UriSource = [Uri]::new($f); $bi.DecodePixelWidth = 64; $bi.EndInit(); $bi.Freeze()
            if ($bi.PixelWidth -lt 32 -and -not $real) { continue }   # icône générique 16 px du service = site sans icône : initiales gardées
            $im = [Windows.Controls.Image]::new(); $im.Source = $bi; $im.Width = 30; $im.Height = 30
            [Windows.Media.RenderOptions]::SetBitmapScalingMode($im, 'HighQuality')
            $o.Icon.Background = [Windows.Media.Brushes]::White; $o.Icon.Child = $im; $o.IconSet = $true; $o.IconReal = $real
        } catch { Write-Ignored 'Icône d''application' $_ }
    }
}
function Start-AppsIconDownload {
    if ($BgJobs.ContainsKey('AppsIcons')) { return }
    $todo = @(foreach ($o in $AppsUI.Tiles.Values) {
            $f = Join-Path $AppsUI.IconDir (($o.Id -replace '[^\w.+-]', '_') + '.png')
            # favicon absent, ou générique (16 px) téléchargé il y a plus de 7 jours : nouvel essai
            $old = $(if ([IO.File]::Exists($f)) { $fi = [IO.FileInfo]::new($f); $fi.Length -lt 200 -and $fi.LastWriteTime -lt [DateTime]::Now.AddDays(-7) } else { $true })
            if ($old) { @{ F = $f; D = "$($o.A[2])" } } })
    # programmes installés sans icône réelle extraite : nom de la vignette cherché dans les entrées de désinstallation
    $real = @(foreach ($o in $AppsUI.Tiles.Values) {
            $b = Join-Path $AppsUI.IconDir ($o.Id -replace '[^\w.+-]', '_')
            if ($AppsUI.Installed -and $AppsUI.Installed.Contains($o.Id) -and -not [IO.File]::Exists("$b.app.png")) { @{ F = "$b.app.png"; N = "$($o.A[0])" } } })
    if (-not $todo.Count -and -not $real.Count) { return }
    $Sync.AppsIconTodo = $todo; $Sync.AppsIconReal = $real; $Sync.AppsIconDir = $AppsUI.IconDir
    Start-BgJob 'AppsIcons' @'
[void][IO.Directory]::CreateDirectory($Sync.AppsIconDir)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$wc = [Net.WebClient]::new()
foreach ($x in @($Sync.AppsIconTodo)) {
    try { $wc.DownloadFile(('https://www.google.com/s2/favicons?domain={0}&sz=64' -f [uri]::EscapeDataString(($x.D -split '/')[0])), $x.F) } catch {}
}
$wc.Dispose()
if (@($Sync.AppsIconReal).Count) {
    [void][Reflection.Assembly]::LoadWithPartialName('System.Drawing')
    $norm = { param($n) ("$n".ToLower() -replace '[^a-z0-9]', '') }
    $arp = [Collections.Generic.List[object]]::new()
    foreach ($root in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*') {
        foreach ($k in @(Get-ItemProperty -Path $root -ErrorAction SilentlyContinue)) {
            if (-not $k.DisplayName) { continue }
            $ic = "$($k.DisplayIcon)".Trim() -replace ',\s*-?\d+$', '' -replace '"', ''
            $arp.Add(@{ N = (& $norm $k.DisplayName); Icon = [Environment]::ExpandEnvironmentVariables($ic) })
        }
    }
    foreach ($x in @($Sync.AppsIconReal)) {
        $n = & $norm $x.N; if ($n.Length -lt 3) { continue }
        $hit = @($arp | Where-Object { $_.Icon -and $_.N.StartsWith($n) -and [IO.File]::Exists($_.Icon) -and $_.Icon -match '(?i)\.(exe|ico|dll)$' } | Select-Object -First 1)
        if (-not $hit.Count) { continue }
        try { $ico = [Drawing.Icon]::ExtractAssociatedIcon($hit[0].Icon); $bm = $ico.ToBitmap(); try { $bm.Save($x.F, [Drawing.Imaging.ImageFormat]::Png) } finally { $bm.Dispose(); $ico.Dispose() } } catch {}
    }
}
'@
}
$BgJobDone['AppsIcons'] = { if ($AppsUI.Built) { Set-AppsIcon } }
# applications déjà installées : identifiants winget de l'inventaire de l'onglet Logiciels s'il existe, sinon
# Get-WinGetPackage en tâche de fond
# Application du catalogue déjà présente : identifiant winget, ou nom installé = nom de la vignette (installation par le
# Microsoft Store, par l'installeur de l'éditeur : « Brave Browser », « Mozilla Firefox (x64 fr) »), version, architecture,
# langue et suffixes Browser / Desktop / App / Client ignorés
function Get-AppsNormName([string]$N) {
    $t = $N -replace '\([^)]*\)', '' -replace '\s+v?\d+([._]\d+)+.*$', ''
    ($t.ToLower() -replace '[^a-z0-9]', '') -replace '(browser|desktop|app|client)$', ''
}
function Add-AppsInstalledName([string[]]$Names) {
    $set = [Collections.Generic.HashSet[string]]::new(); foreach ($n in $Names) { if ($n) { [void]$set.Add((Get-AppsNormName $n)) } }
    foreach ($o in $AppsUI.Tiles.Values) { $k = Get-AppsNormName "$($o.A[0])"; if ($k.Length -ge 3 -and $set.Contains($k)) { [void]$AppsUI.Installed.Add($o.Id) } }
}
# badges « Installé » du catalogue d'après l'inventaire des logiciels (enregistré ou relu)
function Update-AppsInstalledFromInv {
    if (-not $AppsUI.Built -or -not $Sync.WgResult -or -not @($Sync.WgResult.Apps).Count) { return }
    $AppsUI.Installed = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($x in @($Sync.WgResult.Apps)) { [void]$AppsUI.Installed.Add("$($x.Id)"); if ($x.LocalId) { [void]$AppsUI.Installed.Add("$($x.LocalId)") } }
    Add-AppsInstalledName @($Sync.WgResult.Apps | ForEach-Object { "$($_.Name)" })
    foreach ($o in $AppsUI.Tiles.Values) { Set-AppTileLook $o }
    if (-not ($Sync.Running -and $Sync.Selected -contains 'AppInstall')) { Update-AppsSelection }
    Start-AppsIconDownload
}
function Start-AppsInventory {
    if ($Sync.WgResult -and @($Sync.WgResult.Apps).Count) {
        Update-AppsInstalledFromInv
        # liste enregistrée affichée : relecture des applications installées en arrière-plan (au plus toutes les 2 min),
        # badges « Installé » actualisés à l'arrivée (Update-SoftCard > Update-AppsInstalledFromInv)
        if (-not $Sync.WgRunning -and -not $Sync.Running -and (-not $SoftUI.ListRead -or ([DateTime]::Now - $SoftUI.ListRead).TotalMinutes -ge 2)) { Start-SoftSearch -ListOnly }
        return
    }
    if ($BgJobs.ContainsKey('AppsInv')) { return }
    $Sync.AppsInv = $null
    Start-BgJob 'AppsInv' @'
$ids = @(); $names = @()
try { Import-Module Microsoft.WinGet.Client -ErrorAction Stop; $pk = @(Get-WinGetPackage -ErrorAction Stop); $ids = @($pk | ForEach-Object { "$($_.Id)" }); $names = @($pk | ForEach-Object { "$($_.Name)" }) } catch { $ids = $null }
$Sync.AppsInv = @{ Ids = $ids; Names = $names }
'@
}
$BgJobDone['AppsInv'] = {
    $r = $Sync.AppsInv
    $AppsUI.Installed = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    if ($r -and $null -ne $r.Ids) { foreach ($i in @($r.Ids)) { [void]$AppsUI.Installed.Add("$i") }; Add-AppsInstalledName @($r.Names) }
    else { Write-UiLog 'Applications : liste des applications installées indisponible (module Microsoft.WinGet.Client absent : il s''installe à la 1re recherche de l''onglet Logiciels).' 'WARN' }
    foreach ($id in @($AppsUI.Sel)) { if ($AppsUI.Installed.Contains($id)) { [void]$AppsUI.Sel.Remove($id) } }
    foreach ($o in $AppsUI.Tiles.Values) { Set-AppTileLook $o }
    Update-AppsSelection
    Start-AppsIconDownload
}
function Update-AppsSelection {
    $n = $AppsUI.Sel.Count
    $busy = $Sync.Running -and $Sync.Selected -contains 'AppInstall'
    $Ui.AppsInstall.Content = $(if ($n) { "Installer la sélection ($n)" } else { 'Installer la sélection' })
    $Ui.AppsInstall.IsEnabled = $n -gt 0 -and -not $Sync.Running
    $Ui.AppsClear.Visibility = $(if ($n -and -not $Sync.Running) { 'Visible' } else { 'Collapsed' })
    # version portable : bouton affiché si la sélection contient au moins une application qui en a une
    $np = @($AppsUI.Sel | Where-Object { $AppPortable.Contains("$_") }).Count
    $Ui.AppsPortable.Visibility = $(if ($np) { 'Visible' } else { 'Collapsed' })
    $Ui.AppsPortable.Content = $(if ($np -eq $n) { 'Ouvrir en portable ({0})' -f $np } else { 'Ouvrir en portable ({0} sur {1})' -f $np, $n })
    $Ui.AppsPortable.IsEnabled = -not $Sync.PortRunning
    $Ui.AppsPortable.ToolTip = 'Sans installation : téléchargée par winget dans ' + $PortableRoot + ', puis lancée' + $(if ($np -lt $n) { "`nSans version portable : " + (@($AppsUI.Sel | Where-Object { -not $AppPortable.Contains("$_") } | ForEach-Object { $AppsUI.Tiles["$_"].A[0] }) -join ', ') } else { '' })
    if ($busy) { return }
    $tot = $AppsUI.Tiles.Count
    $ni = $(if ($AppsUI.Installed) { @($AppsUI.Tiles.Keys | Where-Object { $AppsUI.Installed.Contains($_) }).Count } else { 0 })
    $Ui.AppsStatus.Text = $(if ($n) { '{0} {1}  ·  dernière version, installation silencieuse, une après l''autre' -f $n, (Get-Plural $n 'application sélectionnée' 'applications sélectionnées') }
        elseif (-not $AppsUI.Installed) { "$tot applications prêtes à installer  ·  recherche de celles déjà présentes..." }
        else { '{0} applications  ·  {1} déjà {2}  ·  clic sur une vignette pour la sélectionner' -f $tot, $ni, (Get-Plural $ni 'installée' 'installées') })
}
function Invoke-AppsInstall([switch]$NoConfirm) {
    if ($Sync.Running) { Show-Info 'Une tâche est déjà en cours. Relancer l''installation une fois terminée.'; return }
    $sel = @(foreach ($id in @($AppsUI.Sel)) { , $AppsUI.Tiles[$id].A })
    if (-not $sel.Count) { return }
    $one = $sel.Count -eq 1
    $head = $(if ($one) { "Installer $($sel[0][0]) ?" } else { "Installer ces $($sel.Count) applications ?" })
    $lines = @($sel | ForEach-Object { '{0}  ·  {1}' -f $_[0], $_[3] })
    if (-not $NoConfirm -and -not (Confirm-List $head $lines ('Dernière version, installation silencieuse' + $(if ($one) { '.' } else { ', une application après l''autre.' }) + ' Conditions de licence des éditeurs acceptées automatiquement.') 'Installer' 'PrimaryBtn')) { return }
    $Sync.Params = @{ Soft = @($sel | ForEach-Object { @{ Name = "$($_[0])"; Id = "$($_[1])"; Src = 'winget'; Source = $(if ($_.Count -gt 4) { "$($_[4])" } else { '' }); Pfn = ''; From = ''; To = 'dernière version'; Match = $true; Install = $true; Unknown = $false; User = ($AppUserScope.Contains("$($_[1])") -or ($_.Count -gt 4 -and "$($_[4])" -eq 'msstore')) } }) }
    [void](Start-Worker @('AppInstall'))
    Update-AppsRunState
}
# pendant l'installation : la description de chaque vignette sélectionnée devient son état (en attente, téléchargement
# 45 %, installation 1:12, installé, échec)
function Update-AppsRunState {
    $r = $Sync.SoftRun; if (-not $r) { return }
    foreach ($id in @($r.Items.Keys)) {
        $o = $AppsUI.Tiles[$id]; if (-not $o) { continue }
        $x = Get-SoftItemText $r.Items[$id]; if (-not $x) { continue }
        $t = $(if ("$($r.Items[$id].State)" -eq 'ok') { 'Installé' } else { $x.Text.Substring(0, 1).ToUpper() + $x.Text.Substring(1) })
        if ($o.Desc.Text -ne $t) { $o.Desc.Text = $t; $o.Desc.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, $x.Brush) }
    }
    $Ui.AppsStatus.Text = (Get-SoftRunSummary $true) -replace '^Mise à jour', 'Installation' -replace 'mis à jour', 'installée(s)'
    Update-AppsSelection
}
# fin de l'installation : vignettes installées passées en « Installé », sélection vidée, bilan
function Complete-AppsInstall {
    if (-not $AppsUI.Built) { return }
    Update-AppsRunState
    if (-not $AppsUI.Installed) { $AppsUI.Installed = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase) }
    $ok = 0; $ko = 0
    foreach ($id in @($Sync.SoftRun.Items.Keys)) {
        $it = $Sync.SoftRun.Items[$id]; $o = $AppsUI.Tiles[$id]
        if ("$($it.State)" -in 'ok', 'pend') { $ok++; [void]$AppsUI.Installed.Add($id); [void]$AppsUI.Sel.Remove($id) }
        elseif ("$($it.State)" -eq 'fail') { $ko++; if ($o) { $o.Tile.ToolTip = 'Échec : ' + ((@($it.Out) | Select-Object -Last 6) -join "`n") } }
        if ($o) { Set-AppTileLook $o }
    }
    Update-AppsSelection
    $Ui.AppsStatus.Text = $(if (-not $ko) { 'Installation terminée : {0} {1}.' -f $ok, (Get-Plural $ok 'application installée' 'applications installées') } else { 'Installation terminée : {0} {1}, {2} en échec (détail au survol de la vignette).' -f $ok, (Get-Plural $ok 'installée' 'installées'), $ko })
}

# modes de l'onglet : Installer (catalogue) / Mettre à jour (logiciels installés, vue intégrée construite à la 1re ouverture)
function Set-AppsMode([string]$Mode) {
    $AppsUI.Mode = $Mode
    $Ui.AppsModeInst.Tag = $(if ($Mode -eq 'Inst') { 'on' } else { '' }); $Ui.AppsModeMine.Tag = $(if ($Mode -eq 'Mine') { 'on' } else { '' }); $Ui.AppsModeUpd.Tag = $(if ($Mode -eq 'Upd') { 'on' } else { '' }); $Ui.AppsModePre.Tag = $(if ($Mode -eq 'Pre') { 'on' } else { '' })
    # Préinstallées : applications fournies avec Windows ou le constructeur, à désinstaller (cases + bandeau Appliquer)
    $Ui.AppsPreHost.Visibility = $(if ($Mode -eq 'Pre') { 'Visible' } else { 'Collapsed' })
    $Ui.AppsInstView.Visibility = $(if ($Mode -eq 'Inst') { 'Visible' } else { 'Collapsed' })
    $Ui.AppsUpdHost.Visibility = $(if ($Mode -in 'Upd', 'Mine') { 'Visible' } else { 'Collapsed' })
    if ($Mode -eq 'Inst' -and -not $AppsUI.Built) { New-AppsPage }
    if ($Mode -in 'Upd', 'Mine') {
        # vue des logiciels installés partagée : « Mes applications » = liste complète, « Mettre à jour » = mises à jour, exclus, historique
        if (-not $SoftUI.Win) { Initialize-SoftView }
        Set-SoftScope $Mode
    }
}
$Ui.AppsModePre.Add_Click({ try { Set-AppsMode 'Pre' } catch { Write-UiLog "Applications préinstallées : $($_.Exception.Message)" 'ERROR' } })
$Ui.AppsModeInst.Add_Click({ try { Set-AppsMode 'Inst' } catch { Write-UiLog "Applications : $($_.Exception.Message)" 'ERROR' } })
$Ui.AppsModeMine.Add_Click({ try { Set-AppsMode 'Mine' } catch { Write-UiLog "Mes applications : $($_.Exception.Message)" 'ERROR' } })
$Ui.AppsModeUpd.Add_Click({ try { Set-AppsMode 'Upd' } catch { Write-UiLog "Mises à jour des logiciels : $($_.Exception.Message)" 'ERROR' } })
