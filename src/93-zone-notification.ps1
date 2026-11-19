# ---------- Zone de notification et bouton Fermer : réglages propres à chaque compte
# Registre de l'utilisateur ciblé (HKCU\Software\Oliv_Maintenance\Maintenance) :
#   ReduireZoneNotification = 1 : réduire masque la fenêtre, icône dans la zone de notification
#   FermerReduit            = 1 : le bouton Fermer réduit dans la zone de notification ; Quitter (clic droit sur l'icône) ferme
#                             absente : choix demandé au premier clic sur la croix (Request-CloseChoice), modifiable ensuite
#                             dans Paramètres > Démarrage
# Fenêtre masquée par Hide() : boucle de messages Dispatcher.Run (99-demarrage), pas ShowDialog.
$TrayKey = 'HKCU\Software\Oliv_Maintenance\Maintenance'
$Tray = @{ Min = $false; Close = $false; CloseSet = $false; Quit = $false; Hidden = $false; Tip = $false; LastState = 'Normal' }
$AutoTaskName = 'Maintenance - ouverture de session ' + ($(if ($HkuSidOk) { $UserName } else { [Security.Principal.WindowsIdentity]::GetCurrent().Name }) -replace '[\\/:*?"<>|]', '_')

function Read-TraySetting {
    $k = Open-RegKey $TrayKey
    if (-not $k) { return }
    try {
        $Tray.Min = [int]$k.GetValue('ReduireZoneNotification', 0) -eq 1
        $c = $k.GetValue('FermerReduit', $null)
        $Tray.CloseSet = $null -ne $c; $Tray.Close = $Tray.CloseSet -and [int]$c -eq 1
    } finally { $k.Close() }
}
function Save-TraySetting {
    $k = Open-RegKey $TrayKey $true $true
    try {
        $k.SetValue('ReduireZoneNotification', [int]$Tray.Min, [Microsoft.Win32.RegistryValueKind]::DWord)
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

# Lancement à l'ouverture de session (0.118.0, retiré en 0.118.1) : tâche planifiée créée par cette version supprimée
function Remove-AutoStartTask {
    try {
        $svc = New-Object -ComObject Schedule.Service; $svc.Connect()
        $f = $null; try { $f = $svc.GetFolder('\Oliv_Maintenance') } catch { return }
        $t = $null; try { $t = $f.GetTask($AutoTaskName) } catch { return }
        if ($t) { $f.DeleteTask($AutoTaskName, 0); Write-UiLog "Tâche planifiée \Oliv_Maintenance\$AutoTaskName (lancement à l'ouverture de session) supprimée." 'APP' }
    } catch { Write-Ignored 'Suppression du lancement à l''ouverture de session' $_ }
}

function Start-MainWindow {
    try { Read-TraySetting } catch { Write-Ignored 'Réglages de la zone de notification' $_ }
    if ($Tray.Min -or $Tray.Close) { [void](Initialize-AppNotifier) }
    $Window.Show()
    [void]$Window.Dispatcher.BeginInvoke([Action]{ Remove-AutoStartTask }, [Windows.Threading.DispatcherPriority]::ApplicationIdle)
}
