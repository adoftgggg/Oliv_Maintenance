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
function Add-RunToSession { foreach ($e in @(Get-RunEvent)) { [void]$Session.Events.Add($e) } }
# Traitements en cours au moment du rapport (non encore enregistrés dans le journal de session)
function Get-LiveEvent {
    $ev = [Collections.ArrayList]::new()
    if ($Sync.Running) { foreach ($e in @(Get-RunEvent -Live)) { [void]$ev.Add($e) } }
    if ($Sync.OemInstalling) {
        if ($Sync.OemRun) {
            foreach ($k in @($Sync.OemRun.Items.Keys)) {
                $it = $Sync.OemRun.Items[$k]; $x = Get-OemItemText $it
                [void]$ev.Add(@{ Time = $Sync.OemStart; Cat = 'Constructeur'; Title = $it.Name; Result = $x.Text; Detail = ''
                    Level = $(switch ("$($it.State)") { 'ok' { 'ok' } 'fail' { 'error' } 'skip' { 'warn' } default { 'info' } }) })
            }
        } else { [void]$ev.Add(@{ Time = $Sync.OemStart; Cat = 'Constructeur'; Title = "$($Sync.OemInstStatus)"; Result = 'en cours'; Level = 'info'; Detail = '' }) }
    }
    if ($Sync.OemRunning) {
        [void]$ev.Add(@{ Time = $Sync.OemStart; Cat = 'Constructeur'; Title = 'Recherche des mises à jour constructeur'; Result = 'en cours'; Level = 'info'; Detail = '' })
    }
    if ($Sync.WuSearching -and $Sync.WuOnline -and -not $Sync.WuCancel) {
        [void]$ev.Add(@{ Time = $Sync.WuStartT; Cat = 'Windows Update'; Title = 'Recherche des mises à jour'; Result = 'en cours'; Level = 'info'; Detail = '' })
    }
    if ($Sync.WgRunning -and -not $Sync.WgCancel) {
        [void]$ev.Add(@{ Time = $Sync.WgStart; Cat = 'Logiciels'; Title = 'Recherche des mises à jour des logiciels'; Result = 'en cours'; Level = 'info'; Detail = '' })
    }
    if ($TreeUI.Job) {
        [void]$ev.Add(@{ Time = $TreeUI.Start; Cat = 'Espace disque'; Title = "Analyse de $($TreeUI.Target)"; Result = 'en cours'; Level = 'info'; Detail = '' })
    }
    $ev.ToArray()
}
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
function Get-WuImportance($Item) {
    $sv = "$($Item.Severity)".Trim()
    $lv = $(switch ($sv) { 'Critical' { 1 } 'Important' { 2 } 'Moderate' { 3 } 'Low' { 3 } default { 0 } })
    if ($lv) { return @{ Level = $lv; Label = $ImportanceLabels[$lv]; Basis = "gravité Microsoft : $sv" } }
    $cl = "$($Item.Class)"
    $lv, $why = $(switch -Regex ($cl) {
        'Critical Updates' { 2, 'classification Microsoft : mise à jour critique'; break }
        'Security Updates' { 2, 'classification Microsoft : mise à jour de sécurité'; break }
        'Definition Updates' { 3, 'classification Microsoft : définitions (antivirus)'; break }
        'Update Rollups|^Updates$|Updates' { 3, "classification Microsoft : $cl"; break }
        'Feature Packs|Tools|Upgrades|Drivers' { 4, "classification Microsoft : $cl"; break }
        default { 3, 'classification non communiquée' }
    })
    @{ Level = $lv; Label = $ImportanceLabels[$lv]; Basis = $why }
}
# mises à jour en attente, triées par importance : @{ Level; Label; Basis; Title; Detail }
function Get-PendingUpdateRow {
    $wu = foreach ($x in @($Sync.WuPending.Items | Where-Object { $_ })) {
        $i = Get-WuImportance $x
        $d = @(); if ($x.KB) { $d += $x.KB }; if ($x.Size -gt 0) { $d += Format-SizeUi $x.Size }; if ($x.Done) { $d += 'déjà téléchargée' }
        @{ Level = $i.Level; Label = $i.Label; Basis = $i.Basis; Title = "$($x.Title)"; Detail = $d -join '  ·  ' }
    }
    $oem = @()
    if ($Sync.OemResult -and -not $Sync.OemResult.Error) {
        $oem = foreach ($x in @($Sync.OemResult.Items | Where-Object { $_ })) {
            $i = Get-OemImportance $x
            $d = @(); if ($x.Category) { $d += "$($x.Category)" }; if ($x.Version) { $d += "version $($x.Version)" }; if ($x.Date) { $d += "$($x.Date)" }
            if ("$($x.Size)" -match '^\d+$' -and [double]$x.Size -gt 0) { $d += Format-SizeUi ([double]$x.Size) }
            if ("$($x.Source)" -eq 'WU') { $d += 'via Windows Update' }
            @{ Level = $i.Level; Label = $i.Label; Basis = $i.Basis; Title = "$($x.Title)"; Detail = $d -join '  ·  ' }
        }
    }
    $sw = @()
    try {
        $sw = foreach ($x in @(Get-SoftUpdate | Where-Object { -not $SoftExcl[(Get-SoftKey $_)] })) {
            @{ Level = 0; Label = 'Non indiquée'; Basis = 'winget ne publie pas de gravité'; Title = "$($x.Name)"; Detail = ('{0} > {1}  ·  {2}' -f $x.From, $x.To, $x.SrcLabel) }
        }
    } catch { Write-Ignored 'Rapport : logiciels à mettre à jour' $_ }
    @{ Wu = @($wu | Sort-Object { $_.Level }); Oem = @($oem | Sort-Object { $_.Level }); Soft = @($sw | Sort-Object { $_.Title }) }
}
# résumé par importance : « 3 constructeur : 2 importantes, 1 facultative »
function Get-ImportanceSummary([object[]]$Rows) {
    @($Rows | Group-Object { $_.Level } | Sort-Object { [int]$_.Name } | ForEach-Object {
        $l = "$($_.Group[0].Label)".ToLower(); '{0} {1}' -f $_.Count, $(if ($_.Count -gt 1 -and $l -notmatch 'non ') { $l + 's' } else { $l }) }) -join ', '
}

# échappement HTML minimal (& < > ") : les accents restent lisibles dans le fichier (UTF-8)
function ConvertTo-HtmlText([string]$T) { ("$T" -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;' -replace '"', '&quot;') -replace "`r?`n", '<br>' }
# valeur affichée d'un champ de l'Accueil (vide si absent ou masqué)
function Get-InfoField([string]$K) {
    $f = $InfoUI.F[$K]; if (-not $f) { return '' }
    try { if ("$($f.Parent.Parent.Visibility)" -eq 'Collapsed') { return '' } } catch {}
    $t = "$($f.Text)".Trim(); if ($t -eq '...') { '' } else { $t }
}
function New-InterventionReport {
    $now = [DateTime]::Now; $l = [Collections.Generic.List[string]]::new()
    $h = { param($t) ConvertTo-HtmlText $t }
    $tbl = {
        param([object[]]$Rows)
        $o = '<table class="kv">'
        foreach ($r in $Rows) { if ("$($r[1])".Trim()) { $o += '<tr><th>{0}</th><td>{1}</td></tr>' -f (& $h $r[0]), (& $h $r[1]) } }
        $o + '</table>'
    }
    $logo = $(if ($LogoFullB64) { '<img class="logo" src="data:image/png;base64,{0}" alt="Oliv">' -f $LogoFullB64 } else { '' })
    $l.Add(('<!DOCTYPE html><html lang="fr"><head><meta charset="utf-8"><title>Rapport d''intervention - {0}</title>' -f (& $h $env:COMPUTERNAME)))
    $l.Add('<style>
body{font-family:"Segoe UI",Arial,sans-serif;font-size:13px;color:#1f2328;margin:0;background:#f3f4f6}
.page{max-width:900px;margin:24px auto;background:#fff;padding:36px 44px;border-radius:10px;box-shadow:0 2px 10px rgba(0,0,0,.08)}
header{display:flex;justify-content:space-between;align-items:center;border-bottom:2px solid #1f6feb;padding-bottom:14px;margin-bottom:18px}
.logo{height:56px}h1{font-size:22px;margin:0 0 4px}.sub{color:#57606a}
h2{font-size:15px;margin:22px 0 8px;color:#1f6feb;border-bottom:1px solid #d0d7de;padding-bottom:4px}
table{border-collapse:collapse;width:100%}th,td{text-align:left;vertical-align:top;padding:5px 8px;border-bottom:1px solid #eaeef2}
table.kv th{width:210px;color:#57606a;font-weight:500}table.list th{background:#f6f8fa;font-weight:600;color:#57606a;font-size:12px}
.ok{color:#15803d;font-weight:600}.warn{color:#b45309;font-weight:600}.error{color:#b91c1c;font-weight:600}.info{color:#1f6feb;font-weight:600}
.muted{color:#57606a}.att li{margin:3px 0}
.pill{display:inline-block;padding:1px 9px;border-radius:10px;font-size:11px;font-weight:600;border:1px solid;white-space:nowrap}
.p1{color:#b91c1c;background:#fde8e8;border-color:#b91c1c}.p2{color:#b45309;background:#fef3e2;border-color:#b45309}
.p3{color:#1f6feb;background:#e8f0fe;border-color:#1f6feb}.p4,.p0{color:#57606a;background:#f3f4f6;border-color:#8c959f}.p0{border-style:dashed}
.basis{display:block;color:#57606a;font-size:11px;margin-top:3px}footer{margin-top:26px;color:#8c959f;font-size:11px;text-align:center}
@media print{body{background:#fff}.page{box-shadow:none;margin:0;max-width:none;padding:0}h2{break-after:avoid}tr{break-inside:avoid}}
</style></head><body><div class="page">')
    $l.Add(('<header><div><h1>Rapport d''intervention</h1><div class="sub">{0} &middot; {1:dddd dd MMMM yyyy} &middot; {2:HH:mm} &ndash; {3:HH:mm}</div></div>{4}</header>' -f (& $h $env:COMPUTERNAME), $now, $Session.Start, $now, $logo))
    # poste
    $l.Add('<h2>Poste</h2>')
    $l.Add((& $tbl @(
        @('Nom du poste', $env:COMPUTERNAME), @('Domaine', (Get-InfoField 'Domaine')), @('Utilisateur ciblé', $UserName), @('Technicien', "$env:USERDOMAIN\$env:USERNAME"),
        @('Fabricant', (Get-InfoField 'Fabricant')), @('Modèle', (Get-InfoField 'Modèle')), @('N° de série', (Get-InfoField 'N° de série')), @('BIOS / UEFI', (Get-InfoField 'BIOS / UEFI')),
        @('Système', (Get-InfoField 'Édition')), @('Version', (Get-InfoField 'Version')), @('Processeur', (Get-InfoField 'Processeur')), @('Carte graphique', (Get-InfoField 'Carte graphique')),
        @('Mémoire', (Get-InfoField 'Mémoire')), @('Batterie', (Get-InfoField 'Batterie')), @('Dernier démarrage', (Get-InfoField 'Dernier démarrage')))))
    # état
    $l.Add('<h2>État à la fin de l''intervention</h2>')
    $st = [Collections.Generic.List[object]]::new()
    if ($Sync.Diag) { foreach ($it in @($Sync.Diag.Items)) { if ($it.K -ne 'Clé de récupération') { $st.Add(@($it.K, $it.V)) } } }
    $st.Add(@('Redémarrage en attente', (Get-InfoField 'Redémarrage en attente')))
    $l.Add((& $tbl $st.ToArray()))
    $vols = @($Sync.Vols | Where-Object { $_ -and $_.Total })
    if ($vols.Count) {
        $l.Add('<table class="list"><tr><th>Lecteur</th><th>Nom</th><th>Libre</th><th>Taille</th><th>Occupation</th></tr>')
        foreach ($v in $vols) {
            $pc = [math]::Round(100 * ($v.Total - $v.Free) / $v.Total)
            $l.Add(('<tr><td>{0}</td><td>{1}</td><td>{2}</td><td>{3}</td><td class="{4}">{5} %</td></tr>' -f (& $h $v.Name), (& $h $v.Label), (Format-SizeUi $v.Free 'plein'), (Format-SizeUi $v.Total), $(if ($pc -ge 90) { 'error' } elseif ($pc -ge 80) { 'warn' } else { 'ok' }), $pc))
        }
        $l.Add('</table>')
    }
    # actions
    $live = @(Get-LiveEvent)
    $ev = @(@($Session.Events) + $live | Sort-Object { if ($_.Time) { [DateTime]$_.Time } else { [DateTime]::MaxValue } })
    $l.Add('<h2>Actions réalisées</h2>')
    if ($live.Count) {
        $l.Add(('<p class="info">Rapport généré pendant l''intervention : {0} {1} au moment du rapport.</p>' -f @($live | Where-Object { $_.Level -eq 'info' }).Count, (Get-Plural @($live | Where-Object { $_.Level -eq 'info' }).Count 'élément en cours ou en attente' 'éléments en cours ou en attente')))
    }
    if (-not $ev.Count) { $l.Add('<p class="muted">Aucune action réalisée par l''application pendant cette session.</p>') }
    else {
        $l.Add('<table class="list"><tr><th>Heure</th><th>Domaine</th><th>Action</th><th>Résultat</th></tr>')
        foreach ($e in $ev) {
            $l.Add(('<tr><td>{0}</td><td>{1}</td><td>{2}{3}</td><td class="{4}">{5}</td></tr>' -f $(if ($e.Time) { '{0:HH:mm}' -f $e.Time } else { '' }), (& $h $e.Cat), (& $h $e.Title), $(if ($e.Detail) { '<br><span class="muted">' + (& $h $e.Detail) + '</span>' } else { '' }), $e.Level, (& $h $e.Result)))
        }
        $l.Add('</table>')
    }
    # mises à jour en attente : détail de chacune avec son importance (indiquée par l'éditeur ou estimée d'après le type)
    $pend = Get-PendingUpdateRow
    $l.Add('<h2>Mises à jour en attente</h2>')
    $blocks = @(@('Windows Update', $pend.Wu), @('Constructeur', $pend.Oem), @('Logiciels', $pend.Soft) | Where-Object { @($_[1]).Count })
    if (-not $blocks.Count) { $l.Add('<p class="ok">Aucune mise à jour en attente détectée.</p>') }
    foreach ($b in $blocks) {
        $rows = @($b[1])
        $l.Add(('<p><b>{0}</b> &middot; {1} {2}</p>' -f (& $h $b[0]), $rows.Count, (Get-Plural $rows.Count 'mise à jour' 'mises à jour')))
        $l.Add('<table class="list"><colgroup><col style="width:230px"><col><col style="width:32%"></colgroup><tr><th>Importance</th><th>Mise à jour</th><th>Détail</th></tr>')
        foreach ($r in $rows) {
            # pastille d'importance (couleur + bordure + libellé : lisible aussi imprimée en noir et blanc)
            $l.Add(('<tr><td><span class="pill p{0}">{1}</span><span class="basis">{2}</span></td><td>{3}</td><td class="muted">{4}</td></tr>' -f [int]$r.Level, (& $h $r.Label), (& $h $r.Basis), (& $h $r.Title), (& $h $r.Detail)))
        }
        $l.Add('</table>')
    }
    if ($Sync.WuPending -and -not $Sync.WuPending.Online) {
        $l.Add('<p class="muted">Windows Update : liste lue dans le cache local de Windows (pas de recherche en ligne lancée pendant la session).</p>')
    }
    if ($Sync.OemResult.Error) { $l.Add(('<p class="warn">Constructeur : recherche impossible ({0}).</p>' -f (& $h $Sync.OemResult.Error))) }
    if ($Sync.WgResult.Error) { $l.Add(('<p class="warn">Logiciels : inventaire impossible ({0}).</p>' -f (& $h $Sync.WgResult.Error))) }
    # points d'attention : ce qui reste à faire ou à surveiller
    $att = [Collections.Generic.List[string]]::new()
    foreach ($b in @(@('Windows Update', $pend.Wu), @('constructeur', $pend.Oem))) {
        $rows = @($b[1]); if (-not $rows.Count) { continue }
        $att.Add(('{0} {1} {2} : {3}' -f $rows.Count, (Get-Plural $rows.Count 'mise à jour' 'mises à jour'), $b[0], (Get-ImportanceSummary $rows)))
    }
    if ($pend.Soft.Count) { $att.Add(('{0} {1}' -f $pend.Soft.Count, (Get-Plural $pend.Soft.Count 'logiciel à mettre à jour' 'logiciels à mettre à jour'))) }
    $rb = Get-InfoField 'Redémarrage en attente'; if ($rb -and $rb -notmatch '^Non') { $att.Add("Redémarrage en attente : $rb") }
    foreach ($v in $vols) {
        $pc = 100 * ($v.Total - $v.Free) / $v.Total
        if ($pc -ge 85) {
            $att.Add(('Lecteur {0} occupé à {1:N0} % ({2})' -f $v.Name, $pc, $(if ($v.Free -gt 0) { '{0} libres' -f (Format-SizeUi $v.Free) } else { 'plein' })))
        }
    }
    $open = @($live | Where-Object { $_.Level -eq 'info' })
    if ($open.Count) { $att.Add(('Non terminé au moment du rapport : {0}' -f (@($open | ForEach-Object { '{0} ({1})' -f $_.Title, $_.Result }) -join ', '))) }
    foreach ($e in @($ev | Where-Object { $_.Level -eq 'error' })) { $att.Add(('Échec : {0} - {1}' -f $e.Title, $e.Result)) }
    if ($Sync.Diag) {
        foreach ($it in @($Sync.Diag.Items | Where-Object { $_.B -eq 'ErrFgBrush' -and $_.K -ne 'Clé de récupération' })) {
            $att.Add(('{0} : {1}' -f $it.K, ($it.V -replace "`r?`n", ' / ')))
        }
    }
    $l.Add('<h2>Points d''attention</h2>')
    if ($att.Count) {
        $l.Add('<ul class="att">')
        foreach ($a in ($att | Select-Object -Unique)) { $l.Add('<li class="warn">' + (& $h $a) + '</li>') }
        $l.Add('</ul>')
    }
    else { $l.Add('<p class="ok">Aucun point d''attention.</p>') }
    $l.Add(('<footer>Généré par Oliv_Maintenance {0} le {1:dd/MM/yyyy à HH:mm} &middot; Oliv</footer></div></body></html>' -f (& $h $AppVersion), $now))
    $dir = Get-LogPath 'Rapports'; [void][IO.Directory]::CreateDirectory($dir)
    $file = Join-Path $dir ('{0}_{1:yyyyMMdd-HHmm}_rapport-intervention.html' -f $env:COMPUTERNAME, $now)
    [IO.File]::WriteAllText($file, ($l -join "`n"), [Text.UTF8Encoding]::new($true))
    $file
}
$Ui.ReportBtn.Add_Click({
    try {
        $f = New-InterventionReport
        Write-UiLog "Rapport d'intervention : $f" 'OK'
        Start-Process -FilePath $f
    } catch {
        Write-UiLog "Rapport d'intervention : $($_.Exception.Message)" 'ERROR'
        Show-Info "Impossible de générer le rapport d'intervention.`n`n$($_.Exception.Message)" 'Error'
    }
})
