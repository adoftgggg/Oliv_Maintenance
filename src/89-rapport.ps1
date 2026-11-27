# =====================================================================================================================
# Journal de session et historique du poste
#   - journal de session ($Session.Events) : chaque action réalisée depuis l'ouverture de l'application (tâches, mises à
#     jour Windows / constructeur / logiciels, réglages, applications au démarrage, redémarrage programmé), reportée dans
#     l'historique du poste (Journal > Historique du poste) ;
#   - le rapport d'intervention HTML a été retiré (1.2.0) ; la clé de récupération BitLocker n'est jamais consignée.
# =====================================================================================================================
# journal de session et Add-SessionEvent : définis avec les briques d'interface (32-interface-base.ps1)
# fin d'une exécution du worker : une ligne par tâche terminée avec son résultat, détail des mises à jour Windows et des
# logiciels, espace libéré
function Get-RunEvent {
    $ev = [Collections.ArrayList]::new()
    foreach ($t in @($Sync.TaskResults)) {
        if ($t.Id -in 'WuInstall', 'SoftUpgrade') { continue }
        $lv = $(if ($t.Err) { 'error' } elseif ($t.Warn -or $t.Cancel) { 'warn' } else { 'ok' })
        $res = $(if ($t.Cancel) { 'interrompu' } elseif ($t.Err) { '{0} {1}' -f $t.Err, (Get-Plural $t.Err 'erreur' 'erreurs') } elseif ($t.Warn) { 'terminé avec {0} {1}' -f $t.Warn, (Get-Plural $t.Warn 'avertissement' 'avertissements') } else { 'terminé' })
        [void]$ev.Add(@{ Time = $t.Start; Cat = 'Maintenance'; Title = $t.Label; Result = $res; Level = $lv; Detail = "$($t.Last)" })
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
    if ($null -ne $Sync.SpaceGain -and $Sync.SpaceGain -gt 0) {
        [void]$ev.Add(@{ Time = [DateTime]::Now; Cat = 'Maintenance'; Title = 'Espace disque libéré'; Result = ('{0} sur {1}' -f (Format-SizeUi $Sync.SpaceGain), $env:SystemDrive); Level = 'ok'; Detail = '' })
    }
    $ev.ToArray()
}
function Add-RunToSession { foreach ($e in @(Get-RunEvent)) { [void]$Session.Events.Add($e); Save-HistoryEvent $e } }
# fin d'une installation constructeur : une ligne par mise à jour dans le journal de session (appelée par le minuteur)
function Add-OemRunToSession {
    if (-not $Sync.OemRun) { return }
    foreach ($k in @($Sync.OemRun.Items.Keys)) {
        $it = $Sync.OemRun.Items[$k]; $x = Get-OemItemText $it
        Add-SessionEvent 'Constructeur' $it.Name $x.Text $(switch ("$($it.State)") { 'ok' { 'ok' } 'fail' { 'error' } default { 'warn' } }) $(if ($it.State -eq 'fail') { "$($it.Phase)" } else { '' })
    }
}

# ---------- Importance des mises à jour constructeur en attente
# Niveau 1 critique, 2 importante, 3 recommandée, 4 facultative. Basis = d'où vient le niveau : gravité publiée par l'éditeur
# (Microsoft MsrcSeverity, Lenovo Severity, Dell urgency, HP RecommendationValue) ou, à défaut, estimation d'après le type
# (classe de pilote, classification Windows Update), toujours indiquée comme telle.
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

$Ui.HistoryBtn.Add_Click({ try { Show-History } catch { Write-UiLog "Historique du poste : $($_.Exception.Message)" 'ERROR' } })
