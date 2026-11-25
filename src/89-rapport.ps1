# =====================================================================================================================
# Rapport d'intervention
#   - journal de session ($Session.Events) : chaque action réalisée depuis l'ouverture de l'application (tâches, mises à
#     jour Windows / constructeur / logiciels, réglages, applications au démarrage, redémarrage programmé) ;
#   - New-InterventionReport : page HTML autonome (logo intégré, mise en page imprimable A4, « Imprimer > PDF » du
#     navigateur) dans <journaux>\Rapports, ouverte dans le navigateur par défaut.
#   - Clé de récupération BitLocker jamais reprise dans le rapport.
# =====================================================================================================================
# journal de session et Add-SessionEvent : définis avec les briques d'interface (32-interface-base.ps1)
# fin d'une exécution du worker : une ligne par tâche, détail des mises à jour Windows et des logiciels, espace libéré
# Lignes d'une exécution des tâches : tâches terminées avec leur résultat ; avec -Live (rapport demandé pendant l'exécution),
# tâche en cours (avancement, processus) et tâches suivantes en attente
function Get-RunEvent([switch]$Live) {
    $ev = [Collections.ArrayList]::new(); $done = @{}
    foreach ($t in @($Sync.TaskResults)) {
        $done["$($t.Id)"] = 1
        if ($t.Id -in 'WuInstall', 'SoftUpgrade') { continue }
        $lv = $(if ($t.Err) { 'error' } elseif ($t.Warn -or $t.Cancel) { 'warn' } else { 'ok' })
        $res = $(if ($t.Cancel) { 'interrompu' } elseif ($t.Err) { '{0} {1}' -f $t.Err, (Get-Plural $t.Err 'erreur' 'erreurs') } elseif ($t.Warn) { 'terminé avec {0} {1}' -f $t.Warn, (Get-Plural $t.Warn 'avertissement' 'avertissements') } else { 'terminé' })
        [void]$ev.Add(@{ Time = $t.Start; Cat = 'Maintenance'; Title = $t.Label; Result = $res; Level = $lv; Detail = "$($t.Last)" })
    }
    if ($Live) {
        $i = 0
        foreach ($id in @($Sync.Selected)) {
            $i++; if ($done.ContainsKey("$id")) { continue }
            if ($id -eq 'SoftUpgrade' -and $Sync.SoftRun) { continue }
            $lbl = $(if ($Sync.Labels[$id]) { $Sync.Labels[$id] } else { "$id" })
            if ($i -eq [int]$Sync.TaskIdx) {
                $pct = [double]$Sync.TaskPct
                [void]$ev.Add(@{ Time = $Sync.TaskStart; Cat = 'Maintenance'; Title = $lbl; Level = 'info'
                    Result = 'en cours' + $(if ($pct -gt 0) { ' ({0:N0} %)' -f [math]::Floor($pct) } else { '' })
                    Detail = ('démarré à {0:HH:mm}{1}' -f $Sync.TaskStart, $(if ($Sync.ChildName) { ", processus $($Sync.ChildName)" } else { '' })) })
            } else { [void]$ev.Add(@{ Time = $null; Cat = 'Maintenance'; Title = $lbl; Result = $(if ($Sync.Cancel) { 'annulé' } else { 'en attente' }); Level = 'info'; Detail = '' }) }
        }
    }
    foreach ($u in @($Sync.WuInstalled)) {
        [void]$ev.Add(@{ Time = [DateTime]::Now; Cat = 'Windows Update'; Title = $(if ($u.Kb) { "$($u.Kb) - $($u.Title)" } else { $u.Title }); Result = $(if ($u.Ok) { 'installée' } else { "échec ($($u.Code))" }); Level = $(if ($u.Ok) { 'ok' } else { 'error' }); Detail = '' })
    }
    if ($Sync.Selected -contains 'SoftUpgrade' -and $Sync.SoftRun) {
        $quiet = 0
        foreach ($k in @($Sync.SoftRun.Items.Keys)) {
            $it = $Sync.SoftRun.Items[$k]
            if ($Sync.SoftRun.Store -and "$($it.State)" -eq 'ok' -and "$($it.Note)" -in 'à jour', 'hors Store') { $quiet++; continue }
            $res = switch ("$($it.State)") { 'ok' {
                if ($it.Note) { "$($it.Note)" } else { "$($it.From) > $($it.To)" }
            } 'pend' { 'installé, version inchangée (finalisée au prochain lancement du logiciel)' } 'fail' { 'échec ({0})' -f (Format-WingetCode $it.Code) } 'skip' { 'non mis à jour (arrêt demandé)' } 'run' { (Get-SoftItemText $it).Text } 'wait' { 'en attente' } default { 'non traité' } }
            [void]$ev.Add(@{ Time = $(if ($it.End) { $it.End } else { $Sync.RunStart }); Cat = 'Logiciels'; Title = $it.Name; Result = $res; Detail = ''
                Level = $(switch ("$($it.State)") { 'ok' { 'ok' } 'fail' { 'error' } 'run' { 'info' } 'wait' { 'info' } default { 'warn' } }) })
        }
        if ($Sync.SoftRun.Store -and $quiet) {
            [void]$ev.Add(@{ Time = $Sync.RunStart; Cat = 'Logiciels'; Title = 'Microsoft Store'; Result = ('{0} {1} sans mise à jour (à jour ou hors Store)' -f $quiet, (Get-Plural $quiet 'application vérifiée' 'applications vérifiées')); Detail = ''; Level = 'ok' })
        }
    }
    if (-not $Live -and $null -ne $Sync.SpaceGain -and $Sync.SpaceGain -gt 0) {
        [void]$ev.Add(@{ Time = [DateTime]::Now; Cat = 'Maintenance'; Title = 'Espace disque libéré'; Result = ('{0} sur {1}' -f (Format-SizeUi $Sync.SpaceGain), $env:SystemDrive); Level = 'ok'; Detail = '' })
    }
    $ev.ToArray()
}
function Add-RunToSession { foreach ($e in @(Get-RunEvent)) { [void]$Session.Events.Add($e); Save-HistoryEvent $e } }
# Traitements en cours au moment du rapport (non encore enregistrés dans le journal de session)
function Add-OemRunToSession {
    if (-not $Sync.OemRun) { return }
    foreach ($k in @($Sync.OemRun.Items.Keys)) {
        $it = $Sync.OemRun.Items[$k]; $x = Get-OemItemText $it
        Add-SessionEvent 'Constructeur' $it.Name $x.Text $(switch ("$($it.State)") { 'ok' { 'ok' } 'fail' { 'error' } default { 'warn' } }) $(if ($it.State -eq 'fail') { "$($it.Phase)" } else { '' })
    }
}

# ---------- Importance des mises à jour en attente (rapport, points d'attention)
# Niveau 1 critique, 2 importante, 3 recommandée, 4 facultative. Basis = d'où vient le niveau : gravité publiée par l'éditeur
# (Microsoft MsrcSeverity, Lenovo Severity, Dell urgency, HP RecommendationValue) ou, à défaut, estimation d'après le type
# (classe de pilote, classification Windows Update), toujours indiquée comme telle dans le rapport.
$ImportanceLabels = @{ 1 = 'Critique'; 2 = 'Importante'; 3 = 'Recommandée'; 4 = 'Facultative' }
function Get-OemImportance($Item) {
    $sv = "$($Item.Severity)".Trim()
    if ($sv) {
        $lv = $(switch -Regex ($sv) { '^(?i)(critical|urgent|critique)' { 1 } '^(?i)(important|high)' { 2 } '^(?i)(recommended|recommand)' { 3 } '^(?i)(optional|routine|low|facultati)' { 4 } default { 0 } })
        if ($lv) { return @{ Level = $lv; Label = $ImportanceLabels[$lv]; Basis = "indiquée par le constructeur ($sv)" } }
    }
    $t = "$($Item.Title) $($Item.Category)"
    $lv, $why = $(switch -Regex ($t) {
        '(?i)\b(bios|uefi|firmware|microprogramme|embedded controller|\bec\b|thunderbolt|me firmware|management engine)\b' {
            2, 'micrologiciel (BIOS, UEFI, firmware)'
            break
        }
        '(?i)(securitydevices|security|tpm|sécurité|psp|pluton)' { 2, 'composant de sécurité'; break }
        '(?i)(chipset|system\b|storage|nvme|sata|display|graphics|video|net\b|network|wlan|wi-?fi|ethernet|bluetooth|usb|power|battery)' {
            3, 'pilote de matériel'
            break
        }
        '(?i)(softwarecomponent|extension|othe?rhardware|audio|media|camera|image|hidclass|mouse|keyboard|printer|software)' {
            4, 'composant logiciel ou pilote secondaire'
            break
        }
        default { 3, 'type non reconnu' }
    })
    @{ Level = $lv; Label = $ImportanceLabels[$lv]; Basis = "estimée : $why" }
}
# mises à jour en attente, triées par importance : @{ Level; Label; Basis; Title; Detail }
# résumé par importance : « 3 constructeur : 2 importantes, 1 facultative »

# échappement HTML minimal (& < > ") : les accents restent lisibles dans le fichier (UTF-8)
# valeur affichée d'un champ de l'Accueil (vide si absent ou masqué)
# rapport d'intervention retiré (1.2.0) : plus de besoin ; événements de session conservés pour le journal

$Ui.HistoryBtn.Add_Click({ try { Show-History } catch { Write-UiLog "Historique du poste : $($_.Exception.Message)" 'ERROR' } })
