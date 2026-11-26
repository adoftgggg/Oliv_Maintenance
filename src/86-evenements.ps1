# position et taille mémorisées de la fenêtre principale (sinon taille par défaut, ramenée à la zone de travail)
$script:MainRestored = Restore-WindowPlacement 'Principale' $Window
Add-WindowAnim $Window -NoClose
$Window.Add_Loaded({
    $a = [System.Windows.SystemParameters]::WorkArea
    if (-not $script:MainRestored -and ($Window.Height -gt $a.Height -or $Window.Width -gt $a.Width)) {
        $Window.Width  = [math]::Min($Window.Width, $a.Width)
        $Window.Height = [math]::Min($Window.Height, $a.Height)
        $Window.Left = $a.Left + ($a.Width - $Window.Width) / 2
        $Window.Top  = $a.Top + ($a.Height - $Window.Height) / 2
    }
    Update-Responsive
})

foreach ($p in $PageNames) {
    $Ui["Nav$p"].Add_Click({ param($s, $e) Show-Page ($s.Name -replace '^Nav', '') })
}

$Ui.ThemeBtn.Add_Click({ if ($Sync.CurPage -eq 'Settings') { Show-Page $Sync.LastPage } else { Show-Page 'Settings' } })
$Ui.MinBtn.Add_Click({ $Window.WindowState = 'Minimized' })
$Ui.MaxBtn.Add_Click({ $Window.WindowState = $(if ($Window.WindowState -eq 'Maximized') { 'Normal' } else { 'Maximized' }) })
$Ui.CloseBtn.Add_Click({ $Window.Close() })

function Confirm-Repair([string]$Verb, [string[]]$Tools) {
    $live = @($Tools | Where-Object { $_ -ne 'CHKDSK' })
    $fix  = $Verb -eq 'la réparation'
    if (-not $live.Count) {
        if ($fix) { return Confirm-Action "Programmer l'analyse du disque au prochain démarrage du poste ?" } else { return $true }
    }
    $msg = "Lancer $Verb : $($live -join ', ') ?`n`nAttention : la durée dépend du poste (état du système, type de disque) ; le poste reste utilisable mais peut être ralenti."
    if ($fix -and $Tools -contains 'CHKDSK') { $msg += "`n`nCHKDSK : l'analyse du disque sera programmée au prochain démarrage du poste." }
    Confirm-Action $msg
}
$Ui.RepairScanBtn.Add_Click({
    $ids = @(); $tools = @()
    if ($RepDism.IsChecked) { $ids += 'DismScan';  $tools += 'DISM' }
    if ($RepSfc.IsChecked)  { $ids += 'SfcVerify'; $tools += 'SFC' }
    if ($RepChk.IsChecked)  { $ids += 'ChkState';  $tools += 'CHKDSK' }
    if (-not $ids) { return }
    if (-not (Confirm-Repair "l'analyse" $tools)) { return }
    $Sync.RepairRun = @{ Mode = 'Analyse'; Tools = ($tools -join ', ') }
    [void](Start-Worker $ids)
})
$Ui.RepairFixBtn.Add_Click({
    $ids = @(); $tools = @()
    if ($RepDism.IsChecked) { $ids += 'DismRestore'; $tools += 'DISM' }
    if ($RepSfc.IsChecked)  { $ids += 'Sfc';         $tools += 'SFC' }
    if ($RepChk.IsChecked)  { $ids += 'ChkBoot';     $tools += 'CHKDSK' }
    if (-not $ids) { return }
    if (-not (Confirm-Repair 'la réparation' $tools)) { return }
    $Sync.RepairRun = @{ Mode = 'Réparation'; Tools = ($tools -join ', ') }
    [void](Start-Worker $ids)
})

$Ui.RunBtn.Add_Click({
    $staged = @(Get-StagedRow)
    $sel = @(Get-CleanSelection)
    $apx = @(Get-AppxChecked | ForEach-Object { $_.Tag })
    if ($staged.Count -eq 0 -and $sel.Count -eq 0 -and $apx.Count -eq 0) { return }
    $lines = @()
    $tw = @($staged | Where-Object { $_.Tweak })
    $st = @($staged | Where-Object { $_.Entry })
    if ($tw.Count) {
        $lines += "Réglages ($($tw.Count)) :"
        $lines += $tw | ForEach-Object { '   - {0} : {1}' -f $_.Tweak.Label, (Format-TweakValue $_.Tweak $_.Staged) }
        $lines += ''
    }
    if ($st.Count) {
        $lines += "Applications au démarrage ($($st.Count)) :"
        $lines += $st | ForEach-Object { '   - {0} : {1}' -f $_.Entry.Name, $(if ($_.Staged) { 'activer' } else { 'désactiver' }) }
        $lines += ''
    }
    if ($sel.Count) {
        $lines += "Nettoyage ($($sel.Count)) :"
        $lines += $sel | ForEach-Object { '   - {0} / {1}{2}' -f $CleanUI[$_].Group, $CleanUI[$_].Item.Label, $(if ($Sync.CleanSizes.ContainsKey($_)) { '  (' + (Format-SizeUi $Sync.CleanSizes[$_]) + ')' } else { '' }) }
        $lines += ''
    }
    if ($apx.Count) {
        $lines += "Applications à désinstaller pour tous les utilisateurs ($($apx.Count)) :"
        $lines += $apx | ForEach-Object { '   - {0}' -f $_.Check.Uid }
        $lines += ''
    }
    $risky = @()
    if ($apx.Count) {
        $risky += $(if ($apx.Count -eq 1) { '- Application retirée aussi du provisionnement : réinstallation via le Microsoft Store ou winget uniquement' } else { '- Applications retirées aussi du provisionnement : réinstallation via le Microsoft Store ou winget uniquement' })
    }
    if ($sel -contains 'WindowsOld')  { $risky += '- Suppression de Windows.old (retour à la version précédente impossible)' }
    if ($sel -contains 'Recycle')     { $risky += '- Vidage des corbeilles de tous les utilisateurs' }
    if ($sel -contains 'RestorePoints') { $risky += '- Suppression des anciens points de restauration (le plus récent est conservé)' }
    if ($risky.Count) { $lines += 'Attention, actions sans retour arrière :'; $lines += $risky; $lines += '' }
    $nb = $tw.Count + $st.Count + $sel.Count + $apx.Count
    $q = $(
        if ($apx.Count -eq 1 -and $nb -eq 1) { 'Désinstaller l''application suivante ?' }
        elseif ($apx.Count -and $nb -eq $apx.Count) { "Désinstaller les $($apx.Count) applications suivantes ?" }
        elseif ($nb -lt 2) { 'Appliquer la modification suivante ?' }
        else { 'Appliquer les modifications suivantes ?' }
    )
    if (-not (Confirm-Action ($q + "`n`n" + ($lines -join "`n")))) { return }
    if ($tw.Count) {
        Save-TweakSnapshot 'Avant application' @($tw | ForEach-Object { '{0} : {1} > {2}' -f $_.Tweak.Label, (Format-TweakValue $_.Tweak $_.Current), (Format-TweakValue $_.Tweak $_.Staged) })
    }
    foreach ($r in $tw) { Invoke-TweakChange $r $r.Staged }
    foreach ($r in $st) { Invoke-StartupChange $r }
    if ($staged.Count) { Write-UiLog ('{0} {1}.' -f $staged.Count, (Get-Plural $staged.Count 'changement appliqué' 'changements appliqués')) 'OK' }
    Update-ApplyButton
    # nettoyage et désinstallation dans le même traitement si les deux sont sélectionnés
    $jobs = @(); $prm = @{}
    if ($sel.Count) { $jobs += 'Clean'; $prm.Clean = $sel }
    if ($apx.Count) { $jobs += 'AppxRemove'; $prm.Appx = @($apx | ForEach-Object { "$($_.Check.Tag)" }) }
    if ($jobs.Count) { $Sync.Params = $prm; [void](Start-Worker $jobs) }
})
function Confirm-RecentReport([string]$Btn, [string]$What) {
    $path = "$($Ui[$Btn].Tag)"
    if (-not $path -or -not (Test-Path -LiteralPath $path)) { return $true }
    $age = [DateTime]::Now - (Get-Item -LiteralPath $path).LastWriteTime
    if ($age.TotalDays -ge 7) { return $true }
    $quand = if ($age.TotalHours -lt 1) { 'il y a moins d''une heure' } elseif ($age.TotalDays -lt 1) { 'il y a {0:N0} h' -f [math]::Floor($age.TotalHours) } else {
        $d = [math]::Floor($age.TotalDays)
        'il y a {0:N0} {1}' -f $d, (Get-Plural $d 'jour' 'jours')
    }
    $r = Show-Dialog ('Un {0} a déjà été généré {1} ({2:dd/MM/yyyy HH:mm}).' -f $What, $quand, (Get-Item -LiteralPath $path).LastWriteTime) 'Question' @(
        @{ T = 'Fermer'; V = 'Cancel'; C = $true }, @{ T = 'Ouvrir le rapport existant'; V = 'No' }, @{ T = 'Générer un nouveau rapport'; V = 'Yes'; S = 'PrimaryBtn'; D = $true })
    if ("$r" -eq 'No') { Start-Process explorer.exe -ArgumentList ('"{0}"' -f $path) }
    "$r" -eq 'Yes'
}
$Ui.SmartBtn.Add_Click({ if (Confirm-RecentReport 'SmartOpenBtn' 'rapport SMART') { [void](Start-Worker @('Smart')) } })
# poste fixe : pas de rapport de batterie ni de batterie dans le titre de la carte. Capot présent = portable, décidé tout
# de suite ; sinon décision à l'arrivée de la détection d'arrière-plan (type de châssis), sans requête WMI au premier plan
function Update-BatteryCard {
    if ($script:BatteryCardDone) { return }
    $pc = Get-PowerCapability
    if (-not ($pc -and $pc.Lid) -and $null -eq (Get-NeedPre 'LaptopCim') -and -not $Sync.InfoBaseDone) { return }
    $script:BatteryCardDone = $true
    if (-not (Test-IsLaptop)) { $Ui.BatteryBtn.Parent.Parent.Parent.Visibility = 'Collapsed'; $Window.FindName('DiskCardTitle').Text = 'Disques' }
}
Update-BatteryCard
$Ui.BatteryBtn.Add_Click({ if (Confirm-RecentReport 'BatteryOpenBtn' 'rapport de batterie') { [void](Start-Worker @('Battery')) } })
$Ui.SmartOpenBtn.Add_Click({ if ($Ui.SmartOpenBtn.Tag) { Start-Process explorer.exe -ArgumentList ('"{0}"' -f $Ui.SmartOpenBtn.Tag) } })
$Ui.BatteryOpenBtn.Add_Click({ if ($Ui.BatteryOpenBtn.Tag) { Start-Process explorer.exe -ArgumentList ('"{0}"' -f $Ui.BatteryOpenBtn.Tag) } })
$Ui.OptimizeBtn.Add_Click({ [void](Start-Worker @('Optimize')) })
$Ui.WuResetBtn.Add_Click({
    if (Confirm-Action "Réinitialiser les composants Windows Update ?`n`n- Arrêt des services BITS, Windows Update et Services de chiffrement`n- Suppression des files BITS (qmgr*.dat)`n- Renommage de SoftwareDistribution\DataStore, SoftwareDistribution\Download et catroot2 en .bak_<date>`n`nL'historique Windows Update est remis à zéro, les mises à jour installées ne sont pas affectées.") {
        [void](Start-Worker @('WuReset'))
    }
})
$Ui.NetCheckBtn.Add_Click({ [void](Start-Worker @('NetCheck')) })
$Ui.GpForceBtn.Add_Click({
    if (Confirm-Action "Réappliquer toutes les stratégies de groupe (gpupdate /force) ?`n`nPeut prendre plusieurs minutes sur un poste du domaine. Si une stratégie demande une déconnexion ou un redémarrage, l'application répond non : à faire ensuite manuellement.") {
        [void](Start-Worker @('GpForce'))
    }
})
$Ui.StoreResetBtn.Add_Click({
    if (Confirm-Action "Vider le cache du Microsoft Store de $UserName ?`n`nLe Store est fermé s'il est ouvert. Les applications installées et le compte Microsoft ne sont pas affectés.") {
        [void](Start-Worker @('StoreReset'))
    }
})
$Ui.GpuResetBtn.Add_Click({
    if (Confirm-Action "Redémarrer le pilote graphique ?`n`nL'écran s'éteint quelques secondes. Les jeux, applications 3D et visioconférences en cours peuvent se fermer : enregistrer le travail au préalable.") {
        [void](Start-Worker @('GpuReset'))
    }
})
$Ui.NetResetBtn.Add_Click({
    if (Confirm-Action "Réinitialiser le réseau ?`n`n- Vidage du cache DNS (ipconfig /flushdns)`n- Réinitialisation du catalogue Winsock (netsh winsock reset)`n`nUn redémarrage du poste sera nécessaire. Certains VPN, antivirus ou proxys peuvent devoir être réparés ensuite.") {
        [void](Start-Worker @('NetReset'))
    }
})
$Ui.SpoolResetBtn.Add_Click({
    if (Confirm-Action "Purger le spouleur d'impression ?`n`nTous les travaux en attente sur le poste sont supprimés, puis le service est redémarré.") {
        [void](Start-Worker @('SpoolReset'))
    }
})
$Ui.TimeSyncBtn.Add_Click({
        if (Confirm-Action "Synchroniser l'heure du poste ?`n`n- Poste du domaine : sur le contrôleur de domaine`n- Autre poste : sur sa source de temps, ou time.windows.com s'il n'en a aucune`n`nL'horloge est corrigée immédiatement.") {
            [void](Start-Worker @('TimeSync'))
        }
    })
$Ui.CleanRescan.Add_Click({ Start-CleanScan })
# ---------- Raccourcis clavier : Ctrl+1 à Ctrl+9 = onglets, F5 = actualiser la page affichée, Ctrl+Entrée = appliquer la sélection
# (Ctrl+F : recherche globale, Ctrl+molette / Ctrl+ / Ctrl- / Ctrl+0 : taille de l'interface, définis ailleurs)
function Invoke-PageRefresh {
    switch ($Sync.CurPage) {
        # collecteur d'informations déjà en boucle : relectures demandées par drapeaux (imprimantes, disques)
        'Info'  {
            try { Update-InfoFast -Force } catch { Write-Ignored 'Accueil' $_ }
            Start-DiagCollector
            $Sync.PrnRequest = $true
            $Sync.DiskRequest = $true
            Write-FileLog 'Accueil actualisé (F5).' 'APP'
        }
        'Maint' { Start-CleanScan; Write-FileLog 'Tailles du nettoyage recalculées (F5).' 'APP' }
        'Perf'  { if ($Lazy.Done) { Update-StartupList; Update-PendingBar; Write-FileLog 'Applications au démarrage relues (F5).' 'APP' } }
        'Perso' { if ($AppxList) { Update-AppxList; Write-FileLog 'Applications préinstallées relues (F5).' 'APP' } }
        'Svc'   { if ($SvcUI.Mode -eq 'Tsk') { Start-TskRead } else { Start-SvcRead } }
        'Tools' { Update-ToolsPage }
        'Log'   { [void](Update-LogStatistic) }
    }
}
$Window.Add_PreviewKeyDown({
    param($s, $e)
    $ctrl = [bool]([Windows.Input.Keyboard]::Modifiers -band [Windows.Input.ModifierKeys]::Control)
    $k = "$($e.Key)"
    if ($ctrl -and $k -match '^(D|NumPad)([1-9])$') { Show-Page $PageNames[[int]$Matches[2] - 1]; $e.Handled = $true; return }
    if ($k -eq 'F5' -and -not $ctrl) { Invoke-PageRefresh; $e.Handled = $true; return }
    if ($ctrl -and $k -eq 'Return' -and $Ui.RunBtn.IsVisible -and $Ui.RunBtn.IsEnabled) {
        $Ui.RunBtn.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent)); $e.Handled = $true
    }
})
$Ui.RunBtn.ToolTip = 'Appliquer la sélection (Ctrl+Entrée)'
