# ---------- Notifications Windows en fin de tâche longue
# Icône dans la zone de notification + bulle (affichée comme notification par Windows 10 / 11), seulement si la fenêtre
# n'est pas au premier plan et si l'opération a duré au moins 20 s : inutile quand on regarde déjà l'écran.
# Clic sur la notification ou l'icône : fenêtre ramenée au premier plan. Icône retirée à la fermeture (Exit-App).
$script:Notif = $null
function Initialize-AppNotifier {
    if ($script:Notif) { return $true }
    try {
        if (-not $Sync.FormsLoaded) { Add-Type -AssemblyName System.Windows.Forms, System.Drawing; $Sync.FormsLoaded = $true }
        $ni = [System.Windows.Forms.NotifyIcon]::new()
        try {
            $ms = [IO.MemoryStream]::new([Convert]::FromBase64String($LogoIcoB64))
            $ni.Icon = [System.Drawing.Icon]::new($ms, 32, 32)
        } catch {
            $ni.Icon = [System.Drawing.SystemIcons]::Information
        }
        $ni.Text = 'Oliv_Maintenance'
        $ni.Add_BalloonTipClicked({ try { Show-MainWindow } catch { Write-Ignored 'Ouverture de la fenêtre' $_ } })
        $ni.Add_MouseClick({ param($s, $e) if ($e.Button -eq 'Left') { try { Show-MainWindow } catch { Write-Ignored 'Ouverture de la fenêtre' $_ } } })
        # clic droit : ouvrir / quitter (utile quand la fenêtre est réduite dans la zone de notification)
        $cm = [System.Windows.Forms.ContextMenuStrip]::new()
        $mo = $cm.Items.Add('Ouvrir Oliv_Maintenance'); $mo.Font = [System.Drawing.Font]::new($mo.Font, [System.Drawing.FontStyle]::Bold)
        $mo.Add_Click({ try { Show-MainWindow } catch { Write-Ignored 'Ouverture de la fenêtre' $_ } })
        [void]$cm.Items.Add([System.Windows.Forms.ToolStripSeparator]::new())
        $mq = $cm.Items.Add('Quitter'); $mq.Add_Click({ Exit-FromTray })
        $ni.ContextMenuStrip = $cm
        $ni.Visible = $true
        $script:Notif = $ni
        $true
    } catch { Write-UiLog "Notifications Windows indisponibles : $($_.Exception.Message)" 'WARN'; $false }
}
# Kind : Info | Warning | Error ; Duration : durée de l'opération (pas de notification sous 20 s)
function Send-AppNotification([string]$Title, [string]$Text, [string]$Kind = 'Info', $Duration = $null) {
    if ($Duration -and $Duration.TotalSeconds -lt 20) { return }
    if ($Window.IsActive -and $Window.WindowState -ne 'Minimized') { return }
    if (-not (Initialize-AppNotifier)) { return }
    if ($Text.Length -gt 240) { $Text = $Text.Substring(0, 237) + '...' }
    try {
        $script:Notif.ShowBalloonTip(10000, $Title, $(if ($Text) { $Text } else { ' ' }), [System.Windows.Forms.ToolTipIcon]$Kind)
    } catch {
        Write-Ignored 'Notification Windows' $_
    }
}
# « Redémarrer à la fin si nécessaire » (pied de page pendant une tâche, carte constructeur pendant une installation) :
# choix gardé pour toute la session, appliqué par Request-Reboot
$Sync.AutoReboot = $false
$Ui.AutoReboot.Add_Click({ param($s, $e)
    $Sync.AutoReboot = [bool]$s.IsChecked
    if ($InfoUI.OemPanel) { try { Show-OemResult } catch { Write-Ignored 'Carte constructeur' $_ } }
    Write-UiLog $(if ($Sync.AutoReboot) { 'Redémarrage automatique en fin de tâche activé (si un redémarrage est nécessaire).' } else { 'Redémarrage automatique en fin de tâche désactivé.' }) 'APP'
})
# Alertes du poste en notification Windows (application réduite ou dans la zone de notification) : redémarrage en
# attente, mises à jour Windows, mises à jour de logiciels, disque presque plein. Une notification par alerte nouvelle
# (rien de répété tant que l'alerte reste la même), contrôle toutes les 60 s. Réglage : Paramètres > Démarrage et fermeture.
$AlertSeen = @{}
function Get-AlertOn { $v = Get-RegValue $CardRegKey 'AlertesPoste'; $null -eq $v -or [int]$v -eq 1 }
function Watch-PcAlert {
    if ($SelfTest -or -not (Get-AlertOn)) { return }
    $al = [ordered]@{}
    try { $rs = Get-RebootState; if ($rs -and @($rs.Why).Count) { $al['reboot|' + (@($rs.Why) -join ';')] = @('Redémarrage en attente', (@($rs.Why) -join ' ; '), 'Warning') } } catch { $null = $_ }
    try { $n = @($Sync.WuPending.Items | Where-Object { $_ }).Count; if ($n) { $al["wu|$n"] = @('Mises à jour Windows', ('{0} {1} : Accueil > Mises à jour Windows.' -f $n, (Get-Plural $n 'mise à jour disponible' 'mises à jour disponibles')), 'Info') } } catch { $null = $_ }
    try { $n = @(Get-SoftUpdate | Where-Object { -not $SoftExcl[(Get-SoftKey $_)] }).Count; if ($n) { $al["soft|$n"] = @('Mises à jour de logiciels', ('{0} {1} : Applications > Mettre à jour.' -f $n, (Get-Plural $n 'logiciel à mettre à jour' 'logiciels à mettre à jour')), 'Info') } } catch { $null = $_ }
    try {
        foreach ($v in @($Sync.Vols)) {
            if (-not $v -or -not $v.Total) { continue }
            if ($v.Free / $v.Total -lt 0.1) { $al["disk|$($v.Name)"] = @('Disque presque plein', ('{0} : {1:N1} Go libres sur {2:N0} Go. Maintenance > Nettoyage.' -f $v.Name.TrimEnd('\'), ($v.Free / 1GB), ($v.Total / 1GB)), 'Warning') }
        }
    } catch { $null = $_ }
    foreach ($k in $al.Keys) {
        if ($AlertSeen.ContainsKey($k)) { continue }
        $AlertSeen[$k] = 1; $a = $al[$k]
        Send-AppNotification $a[0] $a[1] $a[2]
    }
}
