# ---------- Zone de notification et bouton Fermer : réglages propres à chaque compte
# Registre de l'utilisateur ciblé (HKCU\Software\Oliv_Maintenance\Maintenance) :
#   ReduireZoneNotification = 1 : réduire masque la fenêtre, icône dans la zone de notification
#   FermerReduit            = 1 : le bouton Fermer réduit dans la zone de notification ; Quitter (clic droit sur l'icône) ferme
#                             absente : choix demandé au premier clic sur la croix (Request-CloseChoice), modifiable ensuite
#                             dans Paramètres > Démarrage
# Fenêtre masquée par Hide() : boucle de messages Dispatcher.Run (99-demarrage), pas ShowDialog.
$TrayKey = 'HKCU\Software\Oliv_Maintenance\Maintenance'
$Tray = @{ StartMin = $false; Min = $false; Close = $false; CloseSet = $false; Quit = $false; Hidden = $false; Tip = $false; LastState = 'Normal' }
$AutoTaskName = 'Maintenance - ouverture de session ' + ($(if ($HkuSidOk) { $UserName } else { [Security.Principal.WindowsIdentity]::GetCurrent().Name }) -replace '[\\/:*?"<>|]', '_')

function Read-TraySetting {
    $k = Open-RegKey $TrayKey
    if (-not $k) { return }
    try {
        $Tray.Min = [int]$k.GetValue('ReduireZoneNotification', 0) -eq 1
        $Tray.StartMin = [int]$k.GetValue('DemarrageReduit', 0) -eq 1
        $c = $k.GetValue('FermerReduit', $null)
        $Tray.CloseSet = $null -ne $c; $Tray.Close = $Tray.CloseSet -and [int]$c -eq 1
    } finally { $k.Close() }
}
function Save-TraySetting {
    $k = Open-RegKey $TrayKey $true $true
    try {
        $k.SetValue('ReduireZoneNotification', [int]$Tray.Min, [Microsoft.Win32.RegistryValueKind]::DWord)
        $k.SetValue('DemarrageReduit', [int]$Tray.StartMin, [Microsoft.Win32.RegistryValueKind]::DWord)
        if ($Tray.CloseSet) { $k.SetValue('FermerReduit', [int]$Tray.Close, [Microsoft.Win32.RegistryValueKind]::DWord) }
    } finally { $k.Close() }
    # icône présente dès qu'un des deux réglages est actif (sinon seulement pour les notifications de fin de tâche)
    if ($Tray.Min -or $Tray.Close) { [void](Initialize-AppNotifier) }
}

function Show-MainWindow {
    if (-not $Window.IsVisible) { $Window.Show() }
    if ($Window.WindowState -eq 'Minimized') { $Window.WindowState = $Tray.LastState }
    $Tray.Hidden = $false
    # premier plan : Activate seul peut être refusé par Windows (verrou de premier plan) ; Topmost bref en secours
    if (-not $Window.Activate()) { $Window.Topmost = $true; $Window.Topmost = $false; [void]$Window.Activate() }
}
function Hide-MainWindow {
    if (-not (Initialize-AppNotifier)) { $Window.WindowState = 'Minimized'; return }
    $Window.Hide(); $Tray.Hidden = $true
    if (-not $Tray.Tip) {
        $Tray.Tip = $true
        try { $script:Notif.ShowBalloonTip(5000, 'Oliv_Maintenance', 'L''application reste ouverte dans la zone de notification. Clic sur l''icône pour l''afficher, clic droit > Quitter pour la fermer.', [System.Windows.Forms.ToolTipIcon]::Info) } catch { Write-Ignored 'Notification Windows' $_ }
    }
}
# Premier clic sur la croix (choix jamais fait pour ce compte) : réduire dans la zone de notification ou fermer,
# choix enregistré puis appliqué ; Annuler = rien. Appelé hors de l'événement Closing (Hide / Close interdits dedans).
function Request-CloseChoice {
    $msg = "Que faire quand vous cliquez sur la croix ?`n`nRéduire : Oliv_Maintenance reste ouvert dans la zone de notification, près de l'horloge (clic droit sur l'icône > Quitter pour le fermer).`n`nChoix modifiable ensuite dans Paramètres > Démarrage > Bouton Fermer."
    $v = Show-Dialog $msg 'Question' @(@{ T = 'Annuler'; V = 'Cancel'; C = $true }, @{ T = 'Réduire dans la zone de notification'; V = 'Tray' }, @{ T = 'Fermer l''application'; V = 'Close'; S = 'PrimaryBtn'; D = $true })
    if ($v -notin 'Tray', 'Close') { return }
    $Tray.Close = $v -eq 'Tray'; $Tray.CloseSet = $true
    try { Save-TraySetting } catch { Write-UiLog "Bouton Fermer : $($_.Exception.Message)" 'ERROR' }
    if ($SetUI.TrayClose) { foreach ($b in $SetUI.TrayClose) { $b.Tag = $(if ($b.DataContext -eq $v) { 'on' } else { '' }) } }
    Write-UiLog $(if ($Tray.Close) { 'Bouton Fermer : réduit dans la zone de notification (modifiable dans Paramètres).' } else { 'Bouton Fermer : ferme l''application (modifiable dans Paramètres).' }) 'APP'
    if ($Tray.Close) { Hide-MainWindow }
    else { $Tray.Quit = $true; $Window.Close(); if ($Window.IsVisible) { $Tray.Quit = $false } }
}
# Quitter (menu de l'icône) : fenêtre jamais affichée (rien lancé) = arrêt direct ;
# sinon fenêtre ramenée puis fermée normalement (avertissement si une tâche tourne, position enregistrée)
function Exit-FromTray {
    if (-not $Sync.Started -and -not $Window.IsVisible) { Exit-App 0 }
    $Tray.Quit = $true
    Show-MainWindow
    $Window.Close()
    if ($Window.IsVisible) { $Tray.Quit = $false }
}

# ---------- Lancement à l'ouverture de session, raccourci du menu Démarrer, épinglage
# Exe stable : copie de l'exe en cours dans C:\ProgramData\Oliv_Maintenance\Oliv_Maintenance.exe (écriture réservée aux
# administrateurs) ; tâche planifiée et raccourcis pointent dessus, sans dépendre du nom versionné de l'exe téléchargé.
# Tâche \Oliv_Maintenance\<nom> : déclencheur ouverture de session du compte ciblé (10 s après), droits les plus élevés
# (pas d'invite UAC au démarrage), action = exe stable.
$StableExe = Join-Path $env:ProgramData 'Oliv_Maintenance\Oliv_Maintenance.exe'
$StartLnk = Join-Path $UserProfilePath 'AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Oliv_Maintenance.lnk'
function Sync-StableExe {
    $cur = "$env:_OLIVM_EXE"
    if (-not $cur -or -not (Test-Path -LiteralPath $cur)) { return (Test-Path -LiteralPath $StableExe) }
    if ([string]::Equals([IO.Path]::GetFullPath($cur), $StableExe, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    try {
        $same = (Test-Path -LiteralPath $StableExe) -and ((Get-FileHash -LiteralPath $StableExe -Algorithm SHA256).Hash -eq (Get-FileHash -LiteralPath $cur -Algorithm SHA256).Hash)
        if (-not $same) { Copy-Item -LiteralPath $cur -Destination $StableExe -Force -ErrorAction Stop }
        $true
    } catch { Write-Ignored 'Copie de l''exe dans ProgramData' $_; Test-Path -LiteralPath $StableExe }
}
function Get-AutoStartTask {
    try { $svc = New-Object -ComObject Schedule.Service; $svc.Connect(); $f = $svc.GetFolder('\Oliv_Maintenance'); $f.GetTask($AutoTaskName) } catch { $null }
}
function Set-AutoStart([bool]$On) {
    $svc = New-Object -ComObject Schedule.Service; $svc.Connect()
    $f = $null; try { $f = $svc.GetFolder('\Oliv_Maintenance') } catch { if ($On) { $f = $svc.GetFolder('\').CreateFolder('Oliv_Maintenance') } }
    if (-not $On) { if ($f) { try { $f.DeleteTask($AutoTaskName, 0) } catch { $null = $_ } }; return }
    if (-not (Sync-StableExe)) { throw 'exe de l''application introuvable (lancement par le fichier .cmd : utiliser l''exe)' }
    $acct = $(if ($HkuSidOk) { $UserName } else { [Security.Principal.WindowsIdentity]::GetCurrent().Name })
    $td = $svc.NewTask(0)
    $td.RegistrationInfo.Description = 'Ouvre Oliv_Maintenance à l''ouverture de session (réglage Paramètres > Démarrage et fermeture).'
    $td.Settings.ExecutionTimeLimit = 'PT0S'; $td.Settings.DisallowStartIfOnBatteries = $false; $td.Settings.StopIfGoingOnBatteries = $false; $td.Settings.MultipleInstances = 2
    $tr = $td.Triggers.Create(9); $tr.UserId = $acct; $tr.Delay = 'PT10S'
    $td.Principal.UserId = $acct; $td.Principal.LogonType = 3; $td.Principal.RunLevel = 1
    $ac = $td.Actions.Create(0); $ac.Path = $StableExe
    [void]$f.RegisterTaskDefinition($AutoTaskName, $td, 6, $acct, $null, 3)
}
# au démarrage : exe stable à jour ; tâche existante ramenée sur l'exe stable (anciennes versions : nom versionné)
function Update-AutoStart {
    $ok = Sync-StableExe
    $t = Get-AutoStartTask; if (-not $t) { return }
    try { $p = "$(@($t.Definition.Actions)[0].Path)"; if ($ok -and $p -ne $StableExe) { Set-AutoStart $true; Write-UiLog 'Lancement à l''ouverture de session : tâche mise à jour.' 'APP' } } catch { Write-Ignored 'Lancement à l''ouverture de session' $_ }
}
# Bureau de l'utilisateur ciblé (dossier redirigé vers OneDrive pris en compte)
function Get-UserDesktop {
    $dk = "$(Get-RegValue 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders' 'Desktop')"
    [Environment]::ExpandEnvironmentVariables($(if ($dk) { $dk -replace '(?i)%USERPROFILE%', $UserProfilePath } else { Join-Path $UserProfilePath 'Desktop' }))
}
function New-DesktopShortcut {
    if (-not (Sync-StableExe)) { throw 'exe de l''application introuvable (lancement par le fichier .cmd : utiliser l''exe)' }
    $f = Join-Path (Get-UserDesktop) 'Oliv_Maintenance.lnk'
    $ws = New-Object -ComObject WScript.Shell; $l = $ws.CreateShortcut($f)
    $l.TargetPath = $StableExe; $l.WorkingDirectory = Split-Path $StableExe; $l.IconLocation = "$StableExe,0"; $l.Description = 'Oliv_Maintenance : maintenance et réglages de Windows'; $l.Save()
    [void][Runtime.InteropServices.Marshal]::ReleaseComObject($ws)
    if (-not (Test-Path -LiteralPath $f)) { throw "raccourci non créé ($f)" }
    $f
}
# 1er lancement sur ce poste : raccourci sur le Bureau et mode de démarrage, modifiables ensuite dans Paramètres >
# Démarrage et fermeture
function Show-FirstRun {
    $sp = [Windows.Controls.StackPanel]::new()
    $cb = [Windows.Controls.CheckBox]::new(); $cb.Content = 'Créer un raccourci Oliv_Maintenance sur le Bureau'; $cb.IsChecked = $true; $cb.Margin = New-Thickness 0 0 0 12
    $cb.SetResourceReference([Windows.Controls.Control]::ForegroundProperty, 'FgBrush'); [void]$sp.Children.Add($cb)
    $t = New-Text 'Au lancement de l''application :'; $t.Margin = New-Thickness 0 0 0 4; [void]$sp.Children.Add($t)
    $r1 = [Windows.Controls.RadioButton]::new(); $r1.Content = 'Fenêtre affichée'; $r1.GroupName = 'FrStart'; $r1.IsChecked = $true; $r1.Margin = New-Thickness 0 2 0 2
    $r2 = [Windows.Controls.RadioButton]::new(); $r2.Content = 'Réduite dans la zone de notification (près de l''horloge)'; $r2.GroupName = 'FrStart'; $r2.Margin = New-Thickness 0 2 0 2
    foreach ($r in $r1, $r2) { $r.SetResourceReference([Windows.Controls.Control]::ForegroundProperty, 'FgBrush'); [void]$sp.Children.Add($r) }
    $v = Show-Dialog "Bienvenue dans Oliv_Maintenance`n`nDeux choix avant de commencer, modifiables à tout moment dans Paramètres > Démarrage et fermeture." 'Question' @(@{ T = 'Valider'; V = 'ok'; S = 'PrimaryBtn'; D = $true }) $null $null 560 $sp
    if ($sp.Parent) { $sp.Parent.Content = $null }
    if ($v -ne 'ok') { return }
    $msg = @()
    if ($cb.IsChecked) {
        try { $f = New-DesktopShortcut; Write-UiLog "Raccourci créé sur le Bureau : $f." 'OK'; $msg += 'raccourci créé sur le Bureau' }
        catch { Write-UiLog "Raccourci sur le Bureau : $($_.Exception.Message)" 'ERROR'; Show-Info "Raccourci sur le Bureau impossible.`n`n$($_.Exception.Message)" 'Error' }
    }
    $Tray.StartMin = [bool]$r2.IsChecked
    try { Save-TraySetting; $msg += $(if ($Tray.StartMin) { 'démarrage réduit dans la zone de notification' } else { 'démarrage en fenêtre affichée' }) } catch { Write-UiLog "Mode de démarrage : $($_.Exception.Message)" 'ERROR' }
    foreach ($b in @($SetUI.StartMin)) { if ($b) { $b.Tag = $(if (($b.DataContext -eq 'Tray') -eq $Tray.StartMin) { 'on' } else { '' }) } }
    if ($msg.Count) { Write-UiLog ('Premier lancement : {0}.' -f ($msg -join ', ')) 'APP'; Show-Toast (($msg -join ', ').Substring(0, 1).ToUpper() + ($msg -join ', ').Substring(1)) }
}
function New-StartMenuShortcut {
    if (-not (Sync-StableExe)) { throw 'exe de l''application introuvable (lancement par le fichier .cmd : utiliser l''exe)' }
    [void][IO.Directory]::CreateDirectory((Split-Path $StartLnk))
    $ws = New-Object -ComObject WScript.Shell; $l = $ws.CreateShortcut($StartLnk)
    $l.TargetPath = $StableExe; $l.WorkingDirectory = Split-Path $StableExe; $l.IconLocation = "$StableExe,0"; $l.Description = 'Oliv_Maintenance : maintenance et réglages de Windows'; $l.Save()
}
# épinglage : Windows ne permet à aucun programme de s'épingler lui-même ; raccourci du menu Démarrer créé, puis
# affiché dans l'Explorateur avec la marche à suivre (clic droit > Épingler à la barre des tâches)
function Request-TaskbarPin {
    try { New-StartMenuShortcut } catch { Show-Info "Raccourci impossible.`n`n$($_.Exception.Message)" 'Error'; return }
    Write-UiLog "Raccourci du menu Démarrer : $StartLnk." 'APP'
    Start-Process explorer.exe -ArgumentList ('/select,"{0}"' -f $StartLnk)
    Show-Info "Épingler Oliv_Maintenance à la barre des tâches`n`nWindows réserve l'épinglage à l'utilisateur : aucun programme ne peut s'épingler lui-même. Dans la fenêtre de l'Explorateur qui vient de s'ouvrir, le raccourci Oliv_Maintenance est sélectionné : clic droit dessus > Afficher plus d'options > Épingler à la barre des tâches. Autre chemin : menu Démarrer > Toutes les applications > Oliv_Maintenance > clic droit > Épingler à la barre des tâches. Le raccourci suit les mises à jour de l'application." 'Info'
}

function Start-MainWindow {
    try { Read-TraySetting } catch { Write-Ignored 'Réglages de la zone de notification' $_ }
    if ($Tray.Min -or $Tray.Close -or $Tray.StartMin) { [void](Initialize-AppNotifier) }
    # démarrage réduit (Paramètres > Démarrage et fermeture) : fenêtre construite puis aussitôt rangée dans la zone de
    # notification (barre des tâches si l'icône est indisponible), sans bulle d'explication ; jamais au 1er lancement
    if ($Tray.StartMin -and -not $FirstRun) {
        $Tray.Tip = $true; $Window.ShowActivated = $false; $Window.Show()
        [void]$Window.Dispatcher.BeginInvoke([Action]{ try { Hide-MainWindow } catch { Write-Ignored 'Démarrage réduit' $_ } }, [Windows.Threading.DispatcherPriority]::Loaded)
    } else { $Window.Show() }
    if ($FirstRun) { [void]$Window.Dispatcher.BeginInvoke([Action]{ try { Show-FirstRun } catch { Write-Ignored 'Premier lancement' $_ } }, [Windows.Threading.DispatcherPriority]::ApplicationIdle) }
    [void]$Window.Dispatcher.BeginInvoke([Action]{ try { Update-AutoStart } catch { Write-Ignored 'Lancement à l''ouverture de session' $_ } }, [Windows.Threading.DispatcherPriority]::ApplicationIdle)
}
