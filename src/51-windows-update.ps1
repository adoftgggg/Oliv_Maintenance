# Bibliothèque Windows Update partagée par le diagnostic, la recherche et l'installation (runspaces séparés)
# Accord singulier / pluriel (0 et 1 au singulier)
$PluralLib = @'
function Get-Plural([double]$N, [string]$One, [string]$Many) { if ([math]::Abs($N) -lt 2) { $One } else { $Many } }
# accord sur une valeur déjà formatée (« 1,5 Go », « 220,4 Go ») : nombre lu en tête de texte
function Get-PluralOf([string]$Text, [string]$One, [string]$Many) {
    $v = 2; if ($Text -match '^\s*([\d\s\u00A0\u202F]+(?:[.,]\d+)?)') {
        try { $v = [double]::Parse(($Matches[1] -replace '[\s\u00A0\u202F]', '' -replace ',', '.'), [Globalization.CultureInfo]::InvariantCulture) } catch {}
    }
    Get-Plural $v $One $Many
}
'@
. ([scriptblock]::Create($PluralLib))
$WuLib = $PluralLib + @'
# Avancement réel d'une recherche en arrière-plan, lu par l'interface : étape courante / nombre d'étapes, libellé, et
# fraction de l'étape (Sub, 0-100) quand elle est mesurable (nombre d'éléments analysés...) ; -1 = étape en cours, durée inconnue
function Set-JobStep([string]$Key, [int]$Step, [int]$Steps, [string]$Label, [double]$Sub = -1) {
    $Sync["${Key}Step"] = @{ Step = $Step; Steps = [math]::Max(1, $Steps); Label = $Label; Sub = $Sub }
}
# Recherche WUA interruptible : BeginSearch + ISearchJob.RequestAbort quand $Sync.WuCancel passe à vrai.
# BeginSearch exige un objet de rappel (_OlivM.WuSearchCb, native\WindowsUpdate.cs). Échec -> Search synchrone.
function Invoke-WuSearch($Searcher, [string]$Criteria) {
    $job = $null
    try {
        $job = $Searcher.BeginSearch($Criteria, [_OlivM.WuSearchCb]::new(), $null)
    } catch { $job = $null }
    if (-not $job) { return $Searcher.Search($Criteria) }
    $asked = $false
    while (-not $job.IsCompleted) {
        if ($Sync.WuCancel -and -not $asked) { try { $job.RequestAbort() } catch {}; $asked = $true }
        Start-Sleep -Milliseconds 250
    }
    $r = $Searcher.EndSearch($job)
    if ($Sync.WuCancel) { throw 'recherche annulée' }
    $r
}
# winget : alias de l'utilisateur, sinon exécutable du paquet App Installer (contexte administrateur où l'alias manque)
function Find-Winget {
    $c = (Get-Command winget.exe -ErrorAction SilentlyContinue).Source; if ($c -and (Test-Path -LiteralPath $c)) { return $c }
    $c = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'; if (Test-Path -LiteralPath $c) { return $c }
    $pk = Get-AppxPackage -AllUsers -Name Microsoft.DesktopAppInstaller -ErrorAction SilentlyContinue | Sort-Object Version -Descending | Select-Object -First 1
    if ($pk) { $c = Join-Path $pk.InstallLocation 'winget.exe'; if (Test-Path -LiteralPath $c) { return $c } }
    $null
}
function Get-KB([string]$Title) { if ($Title -match '(KB\d{6,8})') { $Matches[1] } else { '' } }
# mises à jour en attente hors facultatives (BrowseOnly=1) et préversions (titre) ; Online = $false : cache local uniquement
function Get-PendingUpdate([bool]$Online) {
    $s = New-Object -ComObject Microsoft.Update.Session
    $s.ClientApplicationID = 'Oliv_Maintenance'
    # 1. service retenu par Windows (ServerSelection = ssDefault) : serveur WSUS si la stratégie UseWUServer est active,
    #    sinon Windows Update ; libellé = service réellement interrogé (nom d'hôte du serveur WSUS)
    # 2. Microsoft Update s'il est enregistré et sans WSUS : c'est lui qui distribue .NET, Office, etc.
    #    (« Recevoir les mises à jour d'autres produits Microsoft »)
    $pol = Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' -ErrorAction SilentlyContinue
    $wsus = "$((Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' -ErrorAction SilentlyContinue).UseWUServer)" -eq '1'
    $main = 'Windows Update'
    if ($wsus) {
        $h = $null
        try { $h = ([uri]"$($pol.WUServer)").Host } catch {}
        $main = $(if ($h) { "le serveur WSUS $h" } else { 'le serveur WSUS' })
    }
    $targets = @(@{ Sel = 0; Id = $null; Name = $main })
    if (-not $wsus) {
        try {
            foreach ($sv in (New-Object -ComObject Microsoft.Update.ServiceManager).Services) {
                if ("$($sv.ServiceID)" -eq '7971f918-a847-4430-9279-4a52d1efe18d') { $targets += @{ Sel = 3; Id = "$($sv.ServiceID)"; Name = 'Microsoft Update (autres produits Microsoft)' } }
            }
        } catch { Write-Ignored 'Services Windows Update enregistrés (Microsoft Update)' $_ }
    }
    # installées mais en attente de redémarrage (IUpdate2.RebootRequired) : séparées, ni affichées en attente ni réinstallées
    $list = @(); $boot = @(); $seen = @{}; $detail = @(); $err = @()
    # étapes : 1 recherche par service (Windows Update ou WSUS, Microsoft Update), puis analyse des résultats de chaque service
    $steps = 2 * $targets.Count; $k = 0
    foreach ($t in $targets) {
        if ($Sync.WuCancel) { throw 'recherche annulée' }
        $k++; Set-JobStep 'Wu' $k $steps $(if ($Online) { "recherche sur $($t.Name)" } else { "lecture locale ($($t.Name))" })
        $q = $s.CreateUpdateSearcher(); $q.Online = $Online; $q.ServerSelection = $t.Sel; if ($t.Id) { $q.ServiceID = $t.Id }
        try { $r = Invoke-WuSearch $q "IsInstalled=0 and IsHidden=0 and Type='Software' and BrowseOnly=0" } catch {
            if ($Sync.WuCancel) { throw }
            $err += "$($t.Name) : $($_.Exception.Message)"
            $k++
            continue
        }
        $k++; $c = 0; $nU = [math]::Max(1, $r.Updates.Count); $iU = 0
        foreach ($u in $r.Updates) {
            $iU++; Set-JobStep 'Wu' $k $steps "analyse de $($r.Updates.Count) $(Get-Plural $r.Updates.Count 'résultat' 'résultats') ($($t.Name))" (100 * $iU / $nU)
            $id = "$($u.Identity.UpdateID)"; if ($seen.ContainsKey($id)) { continue }; $seen[$id] = 1
            if ("$($u.Title)" -match 'Preview|Pr.version|Aper.u') { continue }
            $c++
            $rb = $false; try { $rb = [bool]$u.RebootRequired } catch {}
            if ($rb) { $boot += $u } else { $list += $u }
        }
        $detail += "$($t.Name) : $c"
    }
    if ($err.Count -and $err.Count -eq $targets.Count) { throw ($err -join ' / ') }
    # installées depuis le dernier démarrage par Paramètres > Windows Update ou un tiers (orchestrateur USO) : Windows les
    # renvoie encore comme non installées jusqu'au redémarrage ; historique (installation réussie après le démarrage) = en
    # attente de redémarrage, ni proposées ni réinstallées
    try {
        $boot0 = (Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).LastBootUpTime.ToUniversalTime()
        $hs = $s.CreateUpdateSearcher(); $nh = $hs.GetTotalHistoryCount()
        if ($nh -gt 0) {
            $done = @{}
            foreach ($e in @($hs.QueryHistory(0, [math]::Min($nh, 200)))) {
                # Operation 1 = installation ; ResultCode 2 = réussie, 3 = réussie avec erreurs ; Date en UTC
                # identifiant + révision : les définitions Defender gardent le même UpdateID d'une version à l'autre (la
                # version installée ce matin correspondait à la nouvelle proposée = faux « redémarrage en attente »)
                try { if ([int]$e.Operation -eq 1 -and [int]$e.ResultCode -in 2, 3 -and ([DateTime]$e.Date) -gt $boot0) { $done['{0}|{1}' -f $e.UpdateIdentity.UpdateID, $e.UpdateIdentity.RevisionNumber] = 1 } } catch { Write-Ignored 'Historique Windows Update (entrée)' $_ }
            }
            if ($done.Count) {
                # définitions (antivirus, pilotes de définition) exclues : jamais de redémarrage
                $isDone = { param($u) $done.ContainsKey(('{0}|{1}' -f $u.Identity.UpdateID, $u.Identity.RevisionNumber)) -and "$($u.Title)" -notmatch '(?i)d.finition|security intelligence|renseignements de s.curit|s.lection disjointe' }
                $boot += @($list | Where-Object { & $isDone $_ })
                $list = @($list | Where-Object { -not (& $isDone $_) })
            }
        }
    } catch { Write-Ignored 'Historique Windows Update (installées depuis le démarrage)' $_ }
    [pscustomobject]@{ Session = $s; Updates = $list; Reboot = $boot; Detail = (($detail + $err) -join '  ·  ') }
}
'@
# Mises à jour en attente : par défaut lecture du cache local de Windows Update (Online = $false, aucune recherche réseau),
# recherche en ligne uniquement sur « Actualiser ». Exclues : facultatives (BrowseOnly=1) et préversions (titre).
$WuSearchScript = @'
$res = @{ Items = @(); Reboot = @(); Stamp = [DateTime]::Now; Error = $null; Online = [bool]$Sync.WuOnline; LastScan = $null }
try {
    $pu = Get-PendingUpdate ([bool]$Sync.WuOnline)
    # gravité Microsoft (MsrcSeverity : Critical, Important, Moderate, Low) et classification (Security Updates...) : importance au rapport
    $res.Items = @($pu.Updates | ForEach-Object {
        $cl = ''; try { $cl = @($_.Categories | Where-Object { "$($_.Type)" -eq 'UpdateClassification' } | ForEach-Object { "$($_.Name)" }) -join ', ' } catch { Write-Ignored 'Classification Windows Update' $_ }
        @{ Id = "$($_.Identity.UpdateID)"; KB = (Get-KB $_.Title); Title = "$($_.Title)"; Done = [bool]$_.IsDownloaded; Size = [double]$_.MaxDownloadSize; Severity = "$($_.MsrcSeverity)"; Class = $cl } })
    $res.Reboot = @($pu.Reboot | ForEach-Object { @{ KB = (Get-KB $_.Title); Title = "$($_.Title)" } })
    $res.Detail = $pu.Detail
} catch { $res.Error = $_.Exception.Message }
try {
    $d = (New-Object -ComObject Microsoft.Update.AutoUpdate).Results.LastSearchSuccessDate
    if ($d -and $d.Year -gt 2000) { $res.LastScan = $d.ToLocalTime() }
} catch {}
# recherche lancée par l'outil : LastSearchSuccessDate (recherches automatiques de Windows) ne la reflète pas
if ($res.Online -and -not $res.Error) { $res.OwnScan = [DateTime]::Now }
$res.Stamp = [DateTime]::Now
# annulée : résultat jeté, le précédent (rétabli par l'interface) reste affiché
if (-not $Sync.WuCancel) { $Sync.WuPending = $res }
$Sync.WuSearching = $false
'@
# fichier des durées de recherche (ancienne estimation au temps, v0.99.23 à v0.99.31) : retiré
try { Remove-Item -LiteralPath (Join-Path (Get-LogPath 'Etat') 'durees-recherche.json') -Force -ErrorAction SilentlyContinue } catch {}
# ---------- Avancement réel des recherches en arrière-plan : étape publiée par le script (Set-JobStep) et, pendant une étape
# longue, dernière progression publiée par la commande elle-même (Write-Progress d'Install-Module, d'un module constructeur...).
# Étape sans mesure possible (recherche Windows Update : l'API ne donne aucune progression) : pourcentage du début d'étape.
function Get-JobProgress([string]$Key, [string]$Job) {
    $s = $Sync["${Key}Step"]
    if (-not $s) { return @{ Pct = 0; Text = 'préparation' } }
    $sub = [double]$s.Sub; $detail = ''
    if ($sub -lt 0 -and $Job -and $BgJobs[$Job]) {
        try {
            $pr = $BgJobs[$Job].PS.Streams.Progress
            if ($pr.Count -gt 400) { $pr.Clear() }
            elseif ($pr.Count) {
                $last = $pr[$pr.Count - 1]
                if ("$($last.RecordType)" -ne 'Completed' -and $last.PercentComplete -ge 0) {
                    $sub = [double]$last.PercentComplete
                    $detail = "$($last.StatusDescription)".Trim()
                }
            }
        } catch {}
    }
    $pct = [int][math]::Floor(100 * (($s.Step - 1) + $(if ($sub -ge 0) { [math]::Min([double]100, $sub) / 100 } else { 0 })) / $s.Steps)
    $t = '{0} (étape {1}/{2})' -f $s.Label, $s.Step, $s.Steps
    if ($detail -and $detail.Length -lt 60) { $t += "  ·  $detail" }
    @{ Pct = [math]::Min([double]99, $pct); Text = $t }
}
# ligne d'état + barre fine sous le texte ; renvoie @{ Text; Bar } pour la mise à jour sans reconstruire la carte
function Add-ProgressLine($Panel, [string]$Text) {
    $t = New-Text $Text; $t.FontWeight = [Windows.FontWeights]::SemiBold; $t.Margin = New-Thickness 46 4 18 2
    $t.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'MutedBrush'); [void]$Panel.Children.Add($t)
    $pb = [Windows.Controls.ProgressBar]::new()
    $pb.Height = 4
    $pb.Minimum = 0
    $pb.Maximum = 100
    $pb.Margin = New-Thickness 46 2 18 6
    $pb.BorderThickness = New-Thickness 0 0 0 0
    $pb.SetResourceReference([Windows.Controls.Control]::BackgroundProperty, 'BgBrush')
    $pb.SetResourceReference([Windows.Controls.Control]::ForegroundProperty, 'AccentBrush')
    [void]$Panel.Children.Add($pb)
    @{ Text = $t; Bar = $pb }
}
function Update-WuProgress {
    $g = $InfoUI.WuProg; if (-not $g -or -not $Sync.WuSearching -or $Sync.WuCancel -or -not $Sync.WuStartT) { return }
    $p = Get-JobProgress 'Wu' 'Wu'
    $g.Text.Text = '{0}{1}  ·  {2:mm\:ss}' -f (Format-Pct $p.Pct), $p.Text, ([DateTime]::Now - $Sync.WuStartT)
    $g.Bar.Value = $p.Pct
}
function Start-WuSearch {
    Close-BgJob
    if ($Sync.WuSearching -or $Sync.Running -or $BgJobs.ContainsKey('Wu')) { return $false }
    $Sync.WuCancel = $false
    $Sync.WuSearching = $true; $Sync.WuStartT = [DateTime]::Now; $Sync.WuStep = $null
    Start-BgJob 'Wu' $WuSearchScript
    $true
}
function Stop-WuSearch {
    if (-not $Sync.WuSearching -or $Sync.WuCancel) { return }
    $Sync.WuCancel = $true
    Write-UiLog 'Recherche Windows Update annulée : dernier résultat conservé.' 'WARN'
    if ($Sync.WuPrev) { $Sync.WuPending = $Sync.WuPrev }
    $Sync.WuShown = $null; Show-WuPending
}
# Redémarrage programmé (shutdown.exe /r /t) : choix du moment, annulation (shutdown /a). Heure gardée en mémoire de session.
$RebootFile = Join-Path (Get-LogPath 'Etat') 'redemarrage.txt'
# heure programmée conservée entre deux ouvertures (fichier effacé une fois l'heure passée ou le redémarrage annulé)
function Save-RebootAt { try {
    if ($Sync.RebootAt) { [IO.File]::WriteAllText($RebootFile, $Sync.RebootAt.ToString('o')) } elseif (Test-Path -LiteralPath $RebootFile) { Remove-Item -LiteralPath $RebootFile -Force }
} catch { Write-Ignored 'Enregistrement du redémarrage programmé' $_ } }
try {
    if (Test-Path -LiteralPath $RebootFile) {
        $t = [DateTime]::Parse([IO.File]::ReadAllText($RebootFile).Trim(), [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
        # démarrage du poste postérieur à l'heure prévue : redémarrage effectué, information périmée
        if ($t -gt [DateTime]::Now -and -not ($BootTime -and $BootTime -gt $t)) {
            $Sync.RebootAt = $t
        } else {
            Remove-Item -LiteralPath $RebootFile -Force -ErrorAction SilentlyContinue
        }
    }
} catch { Write-Ignored 'Lecture du redémarrage programmé' $_ }
# Redémarrage en attente, toutes origines : mises à jour Windows installées (par l'outil, par Paramètres > Windows Update
# ou par un tiers : CBS, Auto Update\RebootRequired, Services\Pending, UpdateExeVolatile), fichiers à remplacer au démarrage
# (PendingFileRenameOperations), changement de nom du poste, vérification de disque programmée (chkdsk : bit dirty du
# volume ou BootExecute autre que « autocheck autochk * »). Redémarrage programmé par Windows Update (tâches
# \Microsoft\Windows\UpdateOrchestrator\Reboot*, prochaine exécution) en plus de celui programmé par l'outil.
# Lu au plus toutes les 20 s (registre, tâches planifiées, volumes) ; Force = relecture immédiate.
function Get-RebootState([switch]$Force) {
    if (-not $Force -and $Sync.RebootState -and ([DateTime]::Now - $Sync.RebootState.At).TotalSeconds -lt 20) { return $Sync.RebootState }
    $why = [Collections.Generic.List[string]]::new()
    $cbs = 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing'
    $wu = 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate'
    # une ligne par source, avec son origine exacte (affichée telle quelle dans l'Accueil)
    if (Test-RegKey "$cbs\RebootPending") { $why.Add('Windows Update / composants Windows (CBS\RebootPending)') }
    if (Test-RegKey "$wu\Auto Update\RebootRequired") { $why.Add('Windows Update (Auto Update\RebootRequired)') }
    # Services\Pending : clé souvent présente vide en permanence ; comptée seulement si un service y est inscrit
    $sp = Open-RegKey "$wu\Services\Pending"; if ($sp) { try { if ($sp.SubKeyCount -gt 0) { $why.Add('Windows Update (service d''installation en attente : Services\Pending)') } } finally { $sp.Close() } }
    if ([int]('0' + (Get-RegValue 'HKLM\SOFTWARE\Microsoft\Updates\UpdateExeVolatile' 'Flags')) -ne 0) { $why.Add('programme d''installation Microsoft (UpdateExeVolatile)') }
    $wr = @($Sync.WuPending.Reboot | Where-Object { $_ })
    if ($wr.Count) { $why.Add('Windows Update : ' + ((@($wr | ForEach-Object { if ($_.KB) { $_.KB } else { "$($_.Title)" } }) | Select-Object -Unique) -join ', ') + ' installée(s), finalisée(s) au redémarrage') }
    if ($Sync.OemReboot) { $why.Add('mises à jour constructeur installées') }
    $pfr = @(Get-RegValue 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager' 'PendingFileRenameOperations' | Where-Object { $_ })
    # fichiers à remplacer : programme d'origine déduit du 1er chemin (dossier Program Files / Windows)
    if ($pfr.Count) {
        $f1 = @($pfr | Where-Object { "$_" -match '\\' } | ForEach-Object { "$_" -replace '^\\\?\?\\', '' -replace '^!', '' })
        $who = @($f1 | ForEach-Object { if ($_ -match '(?i)\\Program Files( \(x86\))?\\([^\\]+)') { $Matches[2] } elseif ($_ -match '(?i)\\Windows\\') { 'Windows' } else { Split-Path $_ -Leaf } } | Select-Object -Unique -First 3)
        $why.Add('fichiers à remplacer au démarrage (PendingFileRenameOperations : ' + ($who -join ', ') + ')')
    }
    $cn1 = Get-RegValue 'HKLM\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName' 'ComputerName'; $cn2 = Get-RegValue 'HKLM\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName' 'ComputerName'
    if ($cn1 -and $cn2 -and $cn1 -ne $cn2) { $why.Add("nouveau nom du poste ($cn2)") }
    # vérification de disque : bit dirty (chkdsk /f programmé sur un volume en cours d'utilisation) ou BootExecute modifié (chkntfs)
    $chk = [Collections.Generic.List[string]]::new()
    foreach ($d in [IO.DriveInfo]::GetDrives()) {
        if ($d.DriveType -ne 'Fixed' -or -not $d.IsReady) { continue }
        $l = $d.Name.TrimEnd('\')
        try {
            $h = [_OlivM.VolDirty]::CreateFile("\\.\$l", 0, 3, [IntPtr]::Zero, 3, 0, [IntPtr]::Zero)
            try { $o = [uint32]0; $r = [uint32]0; if (-not $h.IsInvalid -and [_OlivM.VolDirty]::DeviceIoControl($h, 0x90078, [IntPtr]::Zero, 0, [ref]$o, 4, [ref]$r, [IntPtr]::Zero) -and ($o -band 1)) { $chk.Add($l) } } finally { $h.Dispose() }
        } catch { Write-Ignored "Bit dirty de $l" $_ }
    }
    foreach ($b in @(Get-RegValue 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager' 'BootExecute')) {
        if ("$b" -match '(?i)autochk' -and "$b".Trim() -notmatch '(?i)^autocheck\s+autochk\s+\*$' -and "$b" -match '([A-Za-z]:)') { if (-not $chk.Contains($Matches[1].ToUpper())) { $chk.Add($Matches[1].ToUpper()) } }
    }
    if ($chk.Count) { $why.Add('vérification du disque (chkdsk) sur ' + ($chk -join ', ')) }
    # redémarrage programmé par Windows Update (Paramètres > Planifier le redémarrage, ou échéance automatique)
    $wuAt = $null
    try {
        $svc = New-Object -ComObject Schedule.Service; $svc.Connect()
        foreach ($t in @($svc.GetFolder('\Microsoft\Windows\UpdateOrchestrator').GetTasks(1))) {
            if ("$($t.Name)" -notmatch '^Reboot' -or -not $t.Enabled) { continue }
            $n = [DateTime]$t.NextRunTime
            if ($n.Year -gt 2000 -and $n -gt [DateTime]::Now -and (-not $wuAt -or $n -lt $wuAt)) { $wuAt = $n }
        }
    } catch { Write-Ignored 'Tâches UpdateOrchestrator (redémarrage programmé)' $_ }
    $Sync.RebootState = @{ At = [DateTime]::Now; Why = @($why); WuAt = $wuAt; Chk = @($chk) }
    $Sync.RebootState
}
function Invoke-ScheduledReboot([int]$Seconds, [string]$Reason = 'pour finaliser les mises à jour') {
    $sd = "$env:windir\System32\shutdown.exe"
    try { Start-Process -FilePath $sd -ArgumentList '/a' -WindowStyle Hidden -Wait } catch {}
    $at = [DateTime]::Now.AddSeconds($Seconds)
    $msg = $(if ($Seconds -le 60) { "Redémarrage du poste $Reason." } else { 'Redémarrage du poste programmé à {0:HH:mm} {1}. Enregistrer vos documents avant cette heure.' -f $at, $Reason })
    $p = Start-Process -FilePath $sd -ArgumentList @('/r', '/t', "$Seconds", '/d', 'p:2:17', '/c', "`"$msg`"") -WindowStyle Hidden -Wait -PassThru
    if ($p.ExitCode -ne 0) {
        Write-UiLog "Programmation du redémarrage impossible (shutdown.exe, code $($p.ExitCode))." 'ERROR'
        Show-Info "Programmation du redémarrage impossible.`n`nshutdown.exe a renvoyé le code $($p.ExitCode)." 'Error'
        return
    }
    $Sync.RebootAt = $(if ($Seconds -le 60) { $null } else { $at }); Save-RebootAt
    Write-UiLog $(if ($Seconds -le 60) { 'Redémarrage du poste lancé.' } else { 'Redémarrage du poste programmé à {0:dd/MM/yyyy HH:mm}.' -f $at })
    if (-not $Sync.AutoReboot) {
        Add-SessionEvent 'Redémarrage' $(if ($Seconds -le 60) { 'Redémarrage du poste' } else { 'Redémarrage programmé' }) $(if ($Seconds -le 60) { 'lancé' } else { '{0:dd/MM HH:mm}' -f $at }) 'info' $Reason
    }
    $Sync.WuShown = $null
}
# Heure saisie : 20:00, 20h, 20h30, 7 -> prochaine occurrence (demain si l'heure est passée)
function ConvertTo-RebootTime([string]$Text) {
    if ("$Text".Trim() -notmatch '^\s*(\d{1,2})\s*(?:[:hH.]\s*(\d{0,2}))?\s*$') { return $null }
    $h = [int]$Matches[1]; $m = $(if ($Matches[2]) { [int]$Matches[2] } else { 0 })
    if ($h -gt 23 -or $m -gt 59) { return $null }
    $t = [DateTime]::Today.AddHours($h).AddMinutes($m)
    if ($t -le [DateTime]::Now.AddMinutes(1)) { $t = $t.AddDays(1) }
    $t
}
# Sélecteur d'heure façon Windows 11 : champ « HH | mm » qui ouvre deux colonnes défilantes (heures, minutes par 5),
# bande de sélection fixe au centre, molette = 1 cran, clic = centrer la valeur, valider / annuler en bas.
$TimePickXaml = @'
<Border xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Width="220" Background="{DynamicResource PanelBrush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="1" CornerRadius="8">
  <Border.Effect><DropShadowEffect BlurRadius="18" ShadowDepth="3" Opacity="0.28"/></Border.Effect>
  <Grid>
    <Grid.RowDefinitions><RowDefinition Height="280"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
    <Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition/></Grid.ColumnDefinitions>
    <Border Grid.ColumnSpan="2" Height="40" VerticalAlignment="Center" Margin="4,0" CornerRadius="4" Background="{DynamicResource AccentBrush}" Opacity="0.22" IsHitTestVisible="False"/>
    <ScrollViewer x:Name="SvH" VerticalScrollBarVisibility="Hidden" CanContentScroll="False"><StackPanel x:Name="ColH" Margin="0,120,0,120"/></ScrollViewer>
    <ScrollViewer x:Name="SvM" Grid.Column="1" VerticalScrollBarVisibility="Hidden" CanContentScroll="False"><StackPanel x:Name="ColM" Margin="0,120,0,120"/></ScrollViewer>
    <Border Grid.Column="1" Width="1" HorizontalAlignment="Left" Background="{DynamicResource LineBrush}"/>
    <Grid Grid.Row="1" Grid.ColumnSpan="2">
      <Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition/></Grid.ColumnDefinitions>
      <Border Grid.ColumnSpan="2" Height="1" VerticalAlignment="Top" Background="{DynamicResource LineBrush}"/>
      <Button x:Name="Ok" Style="{DynamicResource IconBtn}" Width="Auto" Margin="4" Height="36" HorizontalAlignment="Stretch" FontFamily="Segoe MDL2 Assets" FontSize="14" Content="&#xE8FB;" ToolTip="Valider"/>
      <Button x:Name="No" Grid.Column="1" Style="{DynamicResource IconBtn}" Width="Auto" Margin="4" Height="36" HorizontalAlignment="Stretch" FontFamily="Segoe MDL2 Assets" FontSize="13" Content="&#xE711;" ToolTip="Annuler"/>
    </Grid>
  </Grid>
</Border>
'@
function New-TimePicker([int]$H, [int]$M, [scriptblock]$OnChange) {
    $tp = @{ H = $H; M = $M; OnChange = $OnChange }
    # champ affiché : deux cases séparées par un trait, comme le contrôle Windows
    $btn = [Windows.Controls.Button]::new(); $btn.Style = $Window.FindResource('ActionBtn'); $btn.Width = 158; $btn.Height = 28; $btn.Padding = New-Thickness 0
    $g = [Windows.Controls.Grid]::new(); $g.Width = 150
    foreach ($k in 0..2) {
        $cd = [Windows.Controls.ColumnDefinition]::new()
        if ($k -eq 1) { $cd.Width = [Windows.GridLength]::new(1) }
        [void]$g.ColumnDefinitions.Add($cd)
    }
    $tp.TH = New-Text ''; $tp.TM = New-Text ''
    foreach ($t in $tp.TH, $tp.TM) { $t.FontSize = 13; $t.HorizontalAlignment = 'Center'; $t.VerticalAlignment = 'Center' }
    $sep = [Windows.Controls.Border]::new(); $sep.Height = 16; $sep.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, 'LineBrush')
    [Windows.Controls.Grid]::SetColumn($sep, 1); [Windows.Controls.Grid]::SetColumn($tp.TM, 2)
    [void]$g.Children.Add($tp.TH); [void]$g.Children.Add($sep); [void]$g.Children.Add($tp.TM)
    $btn.Content = $g
    $pop = [Windows.Controls.Primitives.Popup]::new(); $pop.StaysOpen = $false; $pop.AllowsTransparency = $true; $pop.PopupAnimation = 'Fade'
    $pop.PlacementTarget = $btn; $pop.Placement = 'Center'; $pop.VerticalOffset = 20
    $pb = [Windows.Markup.XamlReader]::Parse($TimePickXaml); $pb.Resources.MergedDictionaries.Add($Window.Resources); $pb.Margin = New-Thickness 12
    $pop.Child = $pb
    $tp.Pop = $pop; $tp.SvH = $pb.FindName('SvH'); $tp.SvM = $pb.FindName('SvM')
    foreach ($col in @(@{ P = $pb.FindName('ColH'); N = 24; S = 1; Sv = $tp.SvH }, @{ P = $pb.FindName('ColM'); N = 12; S = 5; Sv = $tp.SvM })) {
        for ($i = 0; $i -lt $col.N; $i++) {
            $t = New-Text ('{0:00}' -f ($i * $col.S)); $t.Height = 40; $t.FontSize = 14; $t.TextAlignment = 'Center'; $t.Padding = New-Thickness 0 10 0 0
            $t.Background = [Windows.Media.Brushes]::Transparent; $t.Cursor = [Windows.Input.Cursors]::Hand; $t.Tag = @{ Sv = $col.Sv; I = $i }
            $t.Add_MouseLeftButtonUp({ param($s, $e) $s.Tag.Sv.ScrollToVerticalOffset($s.Tag.I * 40) })
            [void]$col.P.Children.Add($t)
        }
        $col.Sv.Add_PreviewMouseWheel({ param($s, $e)
            $s.ScrollToVerticalOffset([math]::Round($s.VerticalOffset / 40) * 40 - [math]::Sign($e.Delta) * 40)
            $e.Handled = $true
        })
    }
    $pb.FindName('Ok').Tag = $tp; $pb.FindName('No').Tag = $tp; $btn.Tag = $tp; $pop.Tag = $tp
    $pb.FindName('Ok').Add_Click({
        param($s, $e) $tp = $s.Tag
        $tp.H = [int][math]::Round($tp.SvH.VerticalOffset / 40); $tp.M = 5 * [int][math]::Round($tp.SvM.VerticalOffset / 40)
        Set-TimePickerText $tp; $tp.Pop.IsOpen = $false; if ($tp.OnChange) { & $tp.OnChange }
    })
    $pb.FindName('No').Add_Click({ param($s, $e) $s.Tag.Pop.IsOpen = $false })
    $btn.Add_Click({ param($s, $e) $s.Tag.Pop.IsOpen = $true })
    # positionnement des colonnes une fois la fenêtre surgissante mesurée
    $pop.Add_Opened({
        param($s, $e) $tp = $s.Tag
        $a = { $tp.SvH.ScrollToVerticalOffset($tp.H * 40); $tp.SvM.ScrollToVerticalOffset([math]::Floor($tp.M / 5) * 40) }.GetNewClosure()
        [void]$s.Child.Dispatcher.BeginInvoke([Action]$a, [Windows.Threading.DispatcherPriority]::Loaded)
    })
    Set-TimePickerText $tp
    $tp.Root = [Windows.Controls.Grid]::new(); [void]$tp.Root.Children.Add($btn); [void]$tp.Root.Children.Add($pop)
    $tp
}
function Set-TimePickerText($Tp) { $Tp.TH.Text = '{0:00}' -f $Tp.H; $Tp.TM.Text = '{0:00}' -f $Tp.M }
function Set-TimePickerValue($Tp, [DateTime]$T) {
    $m = [math]::Ceiling($T.Minute / 5) * 5; $h = $T.Hour; if ($m -ge 60) { $m = 0; $h = ($h + 1) % 24 }
    $Tp.H = $h; $Tp.M = $m; Set-TimePickerText $Tp; if ($Tp.OnChange) { & $Tp.OnChange }
}
# $Intro : raison affichée en titre (« Mise à jour installée : ... ») ; $Reason : fin du message Windows à l'utilisateur
function Request-Reboot([string]$Intro, [string]$Reason = 'pour finaliser les mises à jour') {
    # « Redémarrer à la fin si nécessaire » coché : redémarrage dans 2 min sans question (annulable dans la carte Windows Update)
    if ($Intro -and $Sync.AutoReboot) {
        Invoke-ScheduledReboot 120 $Reason
        Add-SessionEvent 'Redémarrage' 'Redémarrage automatique programmé' ('{0:HH:mm}' -f [DateTime]::Now.AddMinutes(2)) 'info' $Intro
        Send-AppNotification 'Redémarrage dans 2 minutes' "$Intro Enregistrer les documents ouverts." 'Warning' ([TimeSpan]::FromMinutes(5))
        return
    }
    $now = [DateTime]::Now
    $sp = [Windows.Controls.StackPanel]::new()
    $row = [Windows.Controls.StackPanel]::new(); $row.Orientation = 'Horizontal'
    $lb = New-Text 'Personnalisé'; $lb.VerticalAlignment = 'Center'; $lb.Margin = New-Thickness 0 0 12 0; $lb.FontWeight = [Windows.FontWeights]::SemiBold
    [void]$row.Children.Add($lb)
    $pv = New-Text '' 'Muted'; $pv.Margin = New-Thickness 162 10 0 0
    $ctx = @{ Prev = $pv; Tp = $null }
    $upd = {
        $t = ConvertTo-RebootTime ('{0}:{1:00}' -f $ctx.Tp.H, $ctx.Tp.M)
        $d = $(if ($t.Date -eq [DateTime]::Today) { "aujourd'hui" } else { 'demain' }); $span = $t - [DateTime]::Now
        $ctx.Prev.Text = 'Redémarrage {0} à {1:HH:mm} (dans {2})' -f $d, $t, $(if ($span.TotalMinutes -lt 60) { '{0} min' -f [math]::Ceiling($span.TotalMinutes) } else { '{0} h {1:00}' -f [math]::Floor($span.TotalHours), $span.Minutes })
    }.GetNewClosure()
    # valeur proposée : 17:30 si pas encore passée, sinon 12:30 (le lendemain)
    $late = $now.TimeOfDay -ge [TimeSpan]::new(17, 29, 0)
    $ctx.Tp = New-TimePicker $(if ($late) { 12 } else { 17 }) 30 $upd
    [void]$row.Children.Add($ctx.Tp.Root)
    # raccourcis sur une 2e ligne, alignés sous le sélecteur : positionnent le sélecteur
    $row2 = [Windows.Controls.WrapPanel]::new(); $row2.Margin = New-Thickness 0 8 0 0
    $ql = New-Text 'Raccourcis' 'Muted'; $ql.VerticalAlignment = 'Center'; $ql.Margin = New-Thickness 0 0 12 0
    [void]$row2.Children.Add($ql)
    foreach ($q in @(@{ T = 'Dans 1 h'; A = 60 }, @{ T = '12:30'; H = 12; M = 30 }, @{ T = '17:30'; H = 17; M = 30 })) {
        $qb = New-Button $q.T
        $qb.MinWidth = 0
        $qb.Width = 76
        $qb.Height = 28
        $qb.Margin = New-Thickness 0 0 6 0
        $qb.Padding = New-Thickness 10 0 10 0
        $qb.Tag = @{ Q = $q; Tp = $ctx.Tp }
        $qb.Add_Click({ param($s, $e)
            $q = $s.Tag.Q
            $t = $(if ($q.A) { [DateTime]::Now.AddMinutes($q.A) } else { [DateTime]::Today.AddHours($q.H).AddMinutes($q.M) })
            Set-TimePickerValue $s.Tag.Tp $t
        })
        [void]$row2.Children.Add($qb)
    }
    # colonne d'étiquettes de même largeur sur les 2 lignes
    $lb.Width = 150; $ql.Width = 150
    [void]$sp.Children.Add($row); [void]$sp.Children.Add($row2); [void]$sp.Children.Add($pv)
    & $upd
    $b = @(@{ T = $(if ($Intro) { 'Plus tard' } else { 'Annuler' }); V = $null; C = $true }, @{ T = 'Maintenant'; V = 'now'; S = 'WarnBtn' }, @{ T = 'Programmer'; V = 'at'; S = 'PrimaryBtn'; D = $true })
    $msg = $(if ($Intro) { "$Intro`n`nQuand redémarrer le poste ? L'utilisateur sera prévenu par Windows. Les documents non enregistrés au moment du redémarrage seront perdus." } else { "Quand redémarrer le poste ?`n`nL'utilisateur sera prévenu par Windows. Les documents non enregistrés au moment du redémarrage seront perdus." })
    $r = Show-Dialog $msg $(if ($Intro) { 'Warn' } else { 'Question' }) $b $null $null 0 $sp
    if ($r -eq 'now') { Invoke-ScheduledReboot 30 $Reason }
    elseif ($r -eq 'at') {
        $t = ConvertTo-RebootTime ('{0}:{1:00}' -f $ctx.Tp.H, $ctx.Tp.M)
        if ($t) { Invoke-ScheduledReboot ([int][math]::Ceiling(($t - [DateTime]::Now).TotalSeconds)) $Reason }
    }
    elseif ($Intro) { Write-UiLog 'Redémarrage reporté : à faire plus tard.' 'WARN' }
}
function Stop-ScheduledReboot {
    try {
        Start-Process -FilePath "$env:windir\System32\shutdown.exe" -ArgumentList '/a' -WindowStyle Hidden -Wait
    } catch {
        Write-Ignored 'Annulation du redémarrage programmé (shutdown /a)' $_
    }
    $Sync.RebootAt = $null; $Sync.WuShown = $null; Save-RebootAt
    Write-UiLog 'Redémarrage programmé annulé.'
    Add-SessionEvent 'Redémarrage' 'Redémarrage programmé' 'annulé' 'warn'
}
# Recherche Windows Update en ligne (bouton Rechercher de la carte, ou « Tout rechercher »)
function Start-WuOnlineSearch {
    $Sync.WuOnline = $true
    $prev = $Sync.WuPending
    if (Start-WuSearch) { $Sync.WuPrev = $prev; $Sync.WuPending = $null; $Sync.WuShown = $null; Show-WuPending; return $true }
    Write-UiLog 'Recherche Windows Update impossible pour l''instant : une recherche ou une tâche est déjà en cours.' 'WARN'
    $false
}
# « Tout rechercher » : Windows Update + mises à jour constructeur (outil du constructeur et pilotes Windows Update) en parallèle ;
# une recherche déjà en cours est laissée telle quelle
function Start-AllUpdateSearch {
    if ($Sync.Running) { return }
    if (-not $Sync.WuSearching) { [void](Start-WuOnlineSearch) }
    if (-not $Sync.OemRunning -and -not $Sync.OemInstalling) { Start-OemScan; Show-OemResult }
    Update-AllSearchButton
}
function Update-AllSearchButton {
    if ($InfoUI.AllSearchBtn) {
        $InfoUI.AllSearchBtn.IsEnabled = -not $Sync.Running -and -not ($Sync.WuSearching -and ($Sync.OemRunning -or $Sync.OemInstalling))
    }
}
function Update-WuButton {
    if (-not $InfoUI.WuSearchBtn) { return }
    $busy = [bool]$Sync.WuSearching
    $InfoUI.WuCancelBtn.Visibility = $(if ($busy -and -not $Sync.WuCancel) { 'Visible' } else { 'Collapsed' })
    $InfoUI.WuSearchBtn.Visibility = $(if ($busy -and -not $Sync.WuCancel) { 'Collapsed' } else { 'Visible' })
    $InfoUI.WuSearchBtn.IsEnabled = -not $busy -and -not $Sync.Running
    Update-AllSearchButton
}
$WuScanFile = Join-Path (Get-LogPath 'Etat') 'wu-recherche.txt'
$Sync.WuOwnLast = $null
try {
    if (Test-Path -LiteralPath $WuScanFile) {
        $Sync.WuOwnLast = [DateTime]::Parse([IO.File]::ReadAllText($WuScanFile).Trim(), [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
    }
} catch {
    Write-Ignored 'Lecture de la dernière recherche Windows Update' $_
}
# Ligne d'état pleine largeur dans une carte (« Aucune mise à jour disponible »...) ; même vocabulaire pour Windows Update
# et le constructeur : « disponible » = proposée, pas encore installée
function Add-StateLine($Panel, [string]$Text, [string]$Brush) {
    $t = New-Text $Text; $t.FontWeight = [Windows.FontWeights]::SemiBold; $t.Margin = New-Thickness 46 4 10 4
    $t.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, $Brush); [void]$Panel.Children.Add($t)
}
# Installation : rien de coché = tout installer ; au moins 1 case cochée = la sélection seule
function Get-WuChecked { @($Sync.WuPending.Items | Where-Object { $_ -and $_.Id -and $InfoUI.WuSel -and $InfoUI.WuSel[$_.Id] }) }
function Get-WuSelection {
    $chk = @(Get-WuChecked)
    if ($chk.Count) { return $chk }
    @($Sync.WuPending.Items | Where-Object { $_ })
}
# libellé commun aux 2 cartes : 1 élément / tout / sélection
# même libellé partout, quel que soit le nombre de mises à jour : rien de coché = tout, sinon la sélection
function Get-InstallLabel([int]$Total, [int]$Checked) {
    if ($Checked) { "Installer la sélection ($Checked)" } else { "Installer tout ($Total)" }
}
function Update-WuInstallButton {
    if (-not $InfoUI.WuBtn) { return }
    $all = @($Sync.WuPending.Items | Where-Object { $_ })
    $InfoUI.WuBtn.Content = Get-InstallLabel $all.Count @(Get-WuChecked).Count
    $InfoUI.WuBtn.IsEnabled = ($all.Count -gt 0) -and -not $Sync.Running
}
# Libellé court d'une mise à jour Windows (titre complet en info-bulle) : produit et version.
# Retirés : n° KB (« KB2267602 », « 2267602 Ko » des titres français), « (version ...) » repris à part, canal de diffusion
# (« - Canal actuel (large) »), architecture (« pour les systèmes x64 »). Antivirus Microsoft Defender : « Mise à jour de
# la sélection disjointe pour Microsoft Defender Antivirus » (traduction de Security Intelligence Update) > « Microsoft
# Defender Antivirus (définitions) ». Pas de taille : MaxDownloadSize n'est qu'un maximum (1,5 Go pour un delta de quelques Mo).
function Get-WuShortTitle($X) {
    $t = "$($X.Title)"; $ver = ''
    if ($t -match '\((?i:version)\s+([\d.]+)\)') { $ver = $Matches[1] }
    if ($t -match '(?i)Microsoft Defender Antivirus' -and $t -match '(?i)s.lection disjointe|renseignements de s.curit.|security intelligence|d.finitions?') { $t = 'Microsoft Defender Antivirus (définitions)' }
    else {
        $t = $t -replace '\s*\((?i:version)[^)]*\)', '' -replace '\s*\(?\bKB\d{6,8}\)?', '' -replace '\s*[-\u2013]?\s*\b\d{6,8}\s*Ko\b', ''
        $t = $t -replace '\s*[-\u2013]\s*(Canal|Current Channel|Channel)\b.*$', '' -replace '(?i)\s+(pour les systèmes|for)\s+(x64|x86|arm64)(-based systems)?\b', ''
        $t = $t.Trim(' ', '-', [char]0x2013)
    }
    $parts = @($t)
    if ($ver) { $parts += "version $ver" }
    $parts -join '  ·  '
}
function Show-WuPending {
    $w = $Sync.WuPending
    $InfoUI.WuPanel.Children.Clear()
    $InfoUI.WuBtn.Visibility = 'Collapsed'; Update-WuButton
    $hasRb = $w -and -not $w.Error -and @($w.Reboot | Where-Object { $_ }).Count
    $planned = $Sync.RebootAt -and $Sync.RebootAt -gt [DateTime]::Now
    $InfoUI.WuRebootBtn.Visibility = $(if ($hasRb -and -not $planned) { 'Visible' } else { 'Collapsed' })
    $InfoUI.WuUnRebootBtn.Visibility = $(if ($hasRb -and $planned) { 'Visible' } else { 'Collapsed' })
    $InfoUI.WuProg = $null
    if (-not $w) {
        if ($Sync.WuCancel -or -not $Sync.WuSearching) { Add-StateLine $InfoUI.WuPanel $(if ($Sync.WuCancel) { 'Recherche annulée' } else { 'Lecture de Windows Update...' }) 'MutedBrush' }
        else { $InfoUI.WuProg = Add-ProgressLine $InfoUI.WuPanel ''; Update-WuProgress }
        $InfoUI.WuBtn.IsEnabled = $false; $InfoUI.WuAge.Text = ''; return
    }
    foreach ($it in @($InfoUI.WuHist)) { if ($it) { $hv = Add-KV $InfoUI.WuPanel ("$($it.K)" -replace '^Dernière mise à jour ', 'Dernière ') $it.V $it.B; if ($it.T) { $hv.ToolTip = $it.T } } }
    if ($w.Error) { Add-StateLine $InfoUI.WuPanel ('Lecture impossible : ' + $w.Error) 'ErrFgBrush'; $InfoUI.WuBtn.IsEnabled = $false; return }
    $rb = @($w.Reboot | Where-Object { $_ })
    if ($rb.Count) {
        Add-StateLine $InfoUI.WuPanel ('{0} {1}, redémarrage du poste requis' -f $rb.Count, (Get-Plural $rb.Count 'mise à jour installée' 'mises à jour installées')) 'WarnFgBrush'
        if ($Sync.RebootAt -and $Sync.RebootAt -gt [DateTime]::Now) {
            [void](Add-KV $InfoUI.WuPanel 'Redémarrage' ('programmé {0}' -f $(if ($Sync.RebootAt.Date -eq [DateTime]::Today) { 'à {0:HH:mm}' -f $Sync.RebootAt } else { 'le {0:dd/MM} à {0:HH:mm}' -f $Sync.RebootAt })) 'AccentBrush')
        } elseif (($wa = (Get-RebootState).WuAt)) {
            [void](Add-KV $InfoUI.WuPanel 'Redémarrage' ('programmé par Windows Update {0}' -f $(if ($wa.Date -eq [DateTime]::Today) { 'à {0:HH:mm}' -f $wa } else { 'le {0:dd/MM} à {0:HH:mm}' -f $wa })) 'AccentBrush')
        }
        foreach ($x in $rb) {
            $v = Add-KV $InfoUI.WuPanel $(if ($x.KB) { $x.KB } else { 'Mise à jour' }) (Get-WuShortTitle $x)
            $v.ToolTip = "{0}`ninstallée, finalisée au prochain redémarrage" -f $x.Title
        }
    }
    $n = @($w.Items).Count
    if ($n -eq 0) { if (-not $rb.Count) { Add-StateLine $InfoUI.WuPanel 'Aucune mise à jour disponible' 'OkFgBrush' } }
    else {
        Add-StateLine $InfoUI.WuPanel ('{0} {1}{2}' -f $n, (Get-Plural $n 'mise à jour disponible' 'mises à jour disponibles'), '') 'WarnFgBrush'
        $all = @($w.Items)
        # tout décoché par défaut ; cases cochées conservées d'une recherche à l'autre tant que la mise à jour est proposée
        if (-not $InfoUI.WuSel) { $InfoUI.WuSel = @{} }
        foreach ($k in @($InfoUI.WuSel.Keys)) { if (-not ($all | Where-Object { $_.Id -eq $k })) { $InfoUI.WuSel.Remove($k) } }
        $list = [Windows.Controls.StackPanel]::new(); $list.Margin = New-Thickness 38 0 10 0; [void]$InfoUI.WuPanel.Children.Add($list)
        $more = [Windows.Controls.StackPanel]::new(); $more.Margin = New-Thickness 38 0 10 0
        $InfoUI.WuChecks = [Collections.ArrayList]::new(); $idx = 0
        foreach ($x in $all) {
            $dst = $(if ($idx -lt $ListMax) { $list } else { $more }); $idx++
            $tip = "{0}`n{1}" -f $x.Title, $(if ($x.Done) { 'déjà téléchargée sur ce poste' } else { 'taille réelle sur ce poste : déterminée par Windows au téléchargement' })
            if ($x.Id) {
                $cb = New-HoverCheck $dst (Get-WuShortTitle $x) $tip {
                    foreach ($c in $InfoUI.WuChecks) { $InfoUI.WuSel[$c.Tag] = [bool]$c.IsChecked }
                    Update-WuInstallButton
                }
                $cb.Tag = $x.Id; $cb.IsChecked = [bool]$InfoUI.WuSel[$x.Id]; [void]$InfoUI.WuChecks.Add($cb)
            } else {
                $v = Add-KV $dst $(if ($x.KB) { $x.KB } else { 'Mise à jour' }) (Get-WuShortTitle $x)
                $v.ToolTip = $tip
                $v.Parent.Parent.Margin = New-Thickness 0 0 0 0
            }
        }
        Add-FoldMore $InfoUI.WuPanel $more $all.Count 'Wu'
    }
    $InfoUI.WuBtn.Visibility = $(if ($n -gt 0) { 'Visible' } else { 'Collapsed' })
    Update-WuInstallButton
    Update-WuAge
}
