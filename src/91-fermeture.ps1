# Message de fermeture selon ce qui tourne réellement : tâche en cours, processus externe, tâches restantes, installation constructeur
# « La tâche suivante sera annulée. » / « Les N tâches suivantes seront annulées. » / rien
function Get-RestNote {
    $rest = @($Sync.Selected).Count - [math]::Max(1, [int]$Sync.TaskIdx)
    if ($rest -le 0) { '' } elseif ($rest -eq 1) { "`n`nLa tâche suivante sera annulée." } else { "`n`nLes $rest tâches suivantes seront annulées." }
}
# Réinitialisation de l'outil : refus si un traitement tourne ; sinon confirmation, fermeture (tâches de fond arrêtées),
# suppression de tout le dossier de l'outil (paramètres, journaux, rapports, instantanés, sauvegardes, résultats) sauf le suivi
# des modifications en attente de redémarrage, puis relance. Aucun réglage Windows n'est annulé.
# conservés aussi : ce qui sert à ANNULER un changement fait au poste (sinon impossible à défaire après réinitialisation) -
# copie d'origine du fichier hosts, liste des services désactivés par l'outil, redémarrage programmé
$ResetKeep = @($PendingFile, $VersionFile, $HostsBackup, $SvcStateFile, $RebootFile)
# Traitements en cours, nommés (réinitialisation, fermeture)
function Get-RunningTask {
    if (-not $Sync.Running) { return $null }
    $i = [math]::Max(1, [int]$Sync.TaskIdx); $id = "$(@($Sync.Selected)[$i - 1])"
    $(if ($TaskLabels.ContainsKey($id)) { $TaskLabels[$id] } elseif ($id) { $id } else { 'tâche de maintenance' })
}
function Get-ActiveWork {
    $l = @()
    $t = Get-RunningTask
    if ($t) { $l += $t + $(if ($Sync.ChildName -and $t -notmatch [regex]::Escape("$($Sync.ChildName)")) { " ($($Sync.ChildName))" } else { '' }) }
    if ($Sync.OemInstalling) {
        $l += $(if ($Sync.OemToolName -and "$($Sync.OemInstStatus)" -like 'installation de*') { "Installation de $($Sync.OemToolName)" } else { 'Installation des mises à jour constructeur' })
    }
    if ($Sync.OemRunning) { $l += 'Recherche des mises à jour constructeur' }
    if ($Sync.WuSearching) { $l += 'Recherche des mises à jour Windows' }
    if ($Sync.WgRunning) { $l += 'Recherche des mises à jour des logiciels' }
    if ($TreeUI.Job) { $l += "Analyse de l'espace disque ($($TreeUI.Target))" }
    if ($TreeUI.DelJob -or $BgJobs.ContainsKey('TreeDel')) { $l += "Suppression en cours dans l'analyseur d'espace disque" }
    , $l
}
function Invoke-AppReset {
    # bloquant : ce qui modifie le poste (tâche, installation, suppression) ; les recherches et analyses sont simplement arrêtées
    $work = @(); foreach ($w in (Get-ActiveWork)) { if ($w -notlike 'Recherche*' -and $w -notlike 'Analyse*') { $work += $w } }
    if ($work.Count) {
        $head = $(if ($work.Count -eq 1) { "Réinitialisation impossible : « $($work[0]) » est en cours." } else { 'Réinitialisation impossible : plusieurs traitements sont en cours.' })
        [void](Show-Dialog ($head + "`n`nRelancer la réinitialisation une fois terminé.") 'Info' $null $(if ($work.Count -gt 1) { $work } else { $null }))
        return
    }
    $msg = "Réinitialiser l'application ?`n`n" +
           "Les paramètres de l'application (thème, onglet de démarrage, zone de notification) reviennent à leur état d'origine et tout son historique est supprimé : journaux, rapports, instantanés des réglages, sauvegardes de la stratégie locale et résultats mémorisés.`n" +
           "Dossier vidé : $LogDir`n`n" +
           "Conservés : onglets et cartes masqués, ordre des cartes, recherches au lancement et alertes (Paramètres > Onglets et cartes, Mises à jour).`n" +
           "Les réglages Windows déjà appliqués ne sont pas annulés.`n`nL'application va redémarrer."
    if ((Show-Dialog $msg 'Warn' @(@{ T = 'Annuler'; V = $false; D = $true; C = $true }, @{ T = 'Réinitialiser'; V = $true; S = 'WarnBtn' })) -ne $true) {
        return
    }
    $Sync.ResetPending = $true
    $Window.Close()
}
function Complete-AppReset {
    # réglages du compte : zone de notification
    try { $k = Open-RegKey 'HKCU\Software\Oliv_Maintenance' $true; if ($k) { try { $k.DeleteSubKeyTree('Maintenance', $false) } finally { $k.Close() } } } catch { Write-Ignored 'Réglages de la zone de notification' $_ }
    # parcours de bas en haut : fichiers puis dossiers vidés ; le suivi des redémarrages en attente est conservé
    foreach ($x in @(Get-ChildItem -LiteralPath $LogDir -Recurse -Force -File -ErrorAction SilentlyContinue)) {
        if ($x.FullName -in $ResetKeep) { continue }
        try { Remove-Item -LiteralPath $x.FullName -Force -ErrorAction Stop } catch {}
    }
    foreach ($d in @(Get-ChildItem -LiteralPath $LogDir -Recurse -Force -Directory -ErrorAction SilentlyContinue | Sort-Object { $_.FullName.Length } -Descending)) {
        if (-not @(Get-ChildItem -LiteralPath $d.FullName -Force -ErrorAction SilentlyContinue).Count) {
            try { Remove-Item -LiteralPath $d.FullName -Force -ErrorAction Stop } catch {}
        }
    }
    # relance : lancée par l'exe, par l'exe (sinon l'instance relancée se croyait lancée par le .cmd : mise à jour dans
    # Téléchargements, exe stable non synchronisé) ; sinon même commande que l'auto-relance du démarrage, empreinte du script
    # comprise (déjà administrateur, donc sans RunAs)
    $exe = "$env:_OLIVM_EXE"
    try {
        if ($exe -and (Test-Path -LiteralPath $exe)) { $np = Start-Process -FilePath $exe -PassThru }
        else {
            if (-not $SelfPath) { return }
            $psExe = "$env:windir\System32\WindowsPowerShell\v1.0\powershell.exe"; $argLine = Get-RelaunchCommand $SelfPath
            $con = "$env:windir\System32\conhost.exe"
            $np = $(if (Test-Path -LiteralPath $con) { Start-Process -FilePath $con -ArgumentList "`"$psExe`" $argLine" -WindowStyle Hidden -PassThru }
                    else { Start-Process -FilePath $psExe -ArgumentList $argLine -WindowStyle Hidden -PassThru })
        }
        $Sync.RelaunchPid = $np.Id
    } catch { Write-Ignored 'Relance de l''application' $_ }
}
function Get-CloseWarning {
    $q = 'êtes-vous sûr de vouloir fermer l''application ?'
    $head = $null; $more = @()
    if ($Sync.Running) {
        $i = [math]::Max(1, [int]$Sync.TaskIdx); $id = "$(@($Sync.Selected)[$i - 1])"
        $name = Get-RunningTask
        if ($id -eq 'WuInstall') { $head = "Des mises à jour Windows sont en cours d'installation, $q" }
        elseif ($Sync.ChildName -in 'DISM', 'SFC') {
            $head = "$($Sync.ChildName) est en cours d'exécution, $q"
            $more += "$($Sync.ChildName) se poursuivra en arrière-plan jusqu'à sa fin."
        }
        elseif ($Sync.ChildName) {
            $head = "La tâche « $name » est en cours, $q"
            $more += "Le processus $($Sync.ChildName) se poursuivra en arrière-plan."
        }
        else { $head = "La tâche « $name » est en cours, $q"; $more += 'Elle sera interrompue.' }
        $next = @(@($Sync.Selected) | Select-Object -Skip $i | ForEach-Object { $(if ($TaskLabels.ContainsKey("$_")) { $TaskLabels["$_"] } else { "$_" }) })
        if ($next.Count) {
            $more += $(if ($next.Count -eq 1) { "Tâche suivante annulée : $($next[0])." } else { "Tâches suivantes annulées : $($next -join ', ')." })
        }
    }
    if ($Sync.OemInstalling) {
        if ($head) { $more += "Des mises à jour constructeur sont aussi en cours d'installation." }
        else { $head = "Des mises à jour constructeur sont en cours d'installation, $q" }
        $more += 'L''installation en cours (BIOS, micrologiciel, pilote) se poursuit en arrière-plan jusqu''à sa fin : ne pas éteindre ni redémarrer le PC avant. Les mises à jour constructeur suivantes ne seront pas installées.'
    }
    if ($TreeUI.DelJob -or $BgJobs.ContainsKey('TreeDel')) {
        if ($head) { $more += "Une suppression est aussi en cours dans l'analyseur d'espace disque." }
        else { $head = "Une suppression est en cours dans l'analyseur d'espace disque, $q"; $more += 'Elle sera interrompue.' }
    }
    # recherches et analyses : sans conséquence, mais nommées si un avertissement est déjà affiché
    if ($head) {
        if ($Sync.OemRunning) { $more += 'La recherche des mises à jour constructeur sera interrompue.' }
        if ($Sync.WuSearching) { $more += 'La recherche des mises à jour Windows sera interrompue.' }
        if ($Sync.WgRunning) { $more += 'La recherche des mises à jour des logiciels sera interrompue.' }
        if ($TreeUI.Job) { $more += 'L''analyse de l''espace disque sera interrompue.' }
    }
    if (-not $head) { return $null }
    $head.Substring(0, 1).ToUpper() + $head.Substring(1) + $(if ($more.Count) { "`n`n" + ($more -join "`n") } else { '' })
}
$Window.Add_Closing({
    param($s, $e)
    # bouton Fermer = réduire dans la zone de notification (réglage de l'utilisateur) ; Quitter du menu de l'icône ferme
    # premier clic sur la croix, choix jamais fait pour ce compte : question posée juste après (hors de Closing)
    if (-not $Tray.CloseSet -and -not $Tray.Quit -and -not $Sync.ResetPending) {
        $e.Cancel = $true; [void]$Window.Dispatcher.BeginInvoke([Action]{ Request-CloseChoice }); return
    }
    if ($Tray.Close -and -not $Tray.Quit -and -not $Sync.ResetPending) {
        # Hide interdit pendant l'événement Closing : masquage juste après
        $e.Cancel = $true; [void]$Window.Dispatcher.BeginInvoke([Action]{ Hide-MainWindow }); return
    }
    $warn = Get-CloseWarning
    if ($warn -and -not (Confirm-Action $warn)) { $e.Cancel = $true; return }
    if ($Sync.Running) {
        $Sync.Cancel = $true
        try { [void]$Sync.PS.BeginStop($null, $null) } catch {}
    }
    $Timer.Stop()
    try { Save-TweakReference } catch { Write-Ignored 'Réglages de référence' $_ }
    Save-WindowPlacement 'Principale' $Window
    # fenêtres secondaires sans propriétaire : fermées explicitement
    foreach ($cw in @($TreeUI.Win, $SoftUI.Win, $MonUI.Win)) { if ($cw) { try { $cw.Close() } catch {} } }
    $Sync.InfoStop = $true
    $Sync.CleanScanStop = $true
    # arrêt non bloquant (Stop() attendait la fin d'un appel COM en cours, fenêtre figée à la fermeture)
    foreach ($k in @($BgJobs.Keys)) { try { [void]$BgJobs[$k].PS.BeginStop($null, $null) } catch {} }
    if ($Sync.ResetPending) { Complete-AppReset }
})

