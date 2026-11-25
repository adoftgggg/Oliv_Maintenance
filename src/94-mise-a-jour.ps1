# ---------- Mises à jour de l'application : dernière version publiée sur GitHub (Releases du dépôt public)
# Recherche au lancement (Paramètres > Mises à jour de l'application, activée par défaut) puis bandeau « Version X
# disponible » : Mettre à jour = téléchargement de l'exe publié (pièce jointe de la version, sinon branche « binaires »
# du dépôt) dans le dossier de l'exe en cours, contrôle de la taille et de l'empreinte SHA-256 publiées, puis relance sur la nouvelle version (ancien exe supprimé après fermeture).
# Choix enregistré dans HKCU\Software\Oliv_Maintenance\Affichage\MajAuLancement (conservé d'une version à l'autre).
$UpdRepo = 'adoftgggg/Oliv_Maintenance'
$UpdUI = @{ Info = $null; Dismissed = $false; Checked = $null }
function Get-UpdAuto { $v = Get-RegValue $CardRegKey 'MajAuLancement'; $null -eq $v -or [int]$v -eq 1 }
# recherche des mises à jour des logiciels installés (winget, Microsoft Store) en arrière-plan 30 s après le lancement ;
# choix dans HKCU\Software\Oliv_Maintenance\Affichage\MajLogicielsAuLancement (activé par défaut)
function Get-SoftAuto { $v = Get-RegValue $CardRegKey 'MajLogicielsAuLancement'; $null -eq $v -or [int]$v -eq 1 }
function Set-SoftAuto([bool]$On) { try { $k = Open-RegKey $CardRegKey $true $true; try { $k.SetValue('MajLogicielsAuLancement', [int]$On, [Microsoft.Win32.RegistryValueKind]::DWord) } finally { $k.Close() } } catch { Write-Ignored 'Recherche des mises à jour des logiciels au lancement' $_ } }
function Set-UpdAuto([bool]$On) { try { $k = Open-RegKey $CardRegKey $true $true; try { $k.SetValue('MajAuLancement', [int]$On, [Microsoft.Win32.RegistryValueKind]::DWord) } finally { $k.Close() } } catch { Write-Ignored 'Mises à jour au lancement' $_ } }
function Get-UpdVersion([string]$Tag) { $t = $Tag -replace '^[vV]', ''; try { [version]$t } catch { $null } }

$UpdScript = @'
$r = @{}
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $h = @{ 'User-Agent' = 'Oliv_Maintenance'; 'Accept' = 'application/vnd.github+json' }
    $j = Invoke-RestMethod -Uri ('https://api.github.com/repos/{0}/releases/latest' -f $Sync.UpdRepo) -Headers $h -TimeoutSec 12 -UseBasicParsing -ErrorAction Stop
    $r.Tag = "$($j.tag_name)"; $r.Notes = "$($j.body)"; $r.Page = "$($j.html_url)"; $r.Date = "$($j.published_at)"
    $a = @($j.assets | Where-Object { "$($_.name)" -like '*.exe' })[0]
    if ($a) { $r.Url = "$($a.browser_download_url)"; $r.Name = "$($a.name)"; $r.Size = [long]$a.size; $r.Digest = "$($a.digest)" }
    else {
        # exe hors des pièces jointes de la version : branche « binaires » du dépôt, empreinte SHA-256 dans les notes
        $v = "$($j.tag_name)" -replace '^[vV]', ''; $r.Name = "Oliv_Maintenance_$v.exe"
        $r.Url = 'https://raw.githubusercontent.com/{0}/binaires/{1}' -f $Sync.UpdRepo, $r.Name
        if ("$($j.body)" -match '(?i)SHA-?256\W+([0-9a-f]{64})') { $r.Digest = 'sha256:' + $Matches[1].ToLower() }
        if ("$($j.body)" -match '(?i)taille\W+(\d+)\s*octets') { $r.Size = [long]$Matches[1] }
    }
} catch {
    $m = $_.Exception.Message
    $r.Error = $(if ($m -match '404') { 'aucune version publiée sur le dépôt' } else { $m })
}
$Sync.Upd = $r
'@
$UpdDlScript = @'
$p = $Sync.UpdDl; $st = $Sync.UpdDlState
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $rq = [Net.HttpWebRequest]::Create($p.Url); $rq.UserAgent = 'Oliv_Maintenance'; $rq.Timeout = 20000
    try { $rs = $rq.GetResponse() }
    catch [Net.WebException] {
        # 404 : version annoncée retirée du dépôt entre la recherche et le clic (nouvelle publication) -> dernière version relue puis téléchargée
        if (-not ($_.Exception.Response -and [int]$_.Exception.Response.StatusCode -eq 404)) { throw }
        $h = @{ 'User-Agent' = 'Oliv_Maintenance'; 'Accept' = 'application/vnd.github+json' }
        $j = Invoke-RestMethod -Uri ('https://api.github.com/repos/{0}/releases/latest' -f $p.Repo) -Headers $h -TimeoutSec 12 -UseBasicParsing -ErrorAction Stop
        $v = "$($j.tag_name)" -replace '^[vV]', ''; $name = "Oliv_Maintenance_$v.exe"
        if ($p.Url -like "*/$name") { throw }
        $p.Url = 'https://raw.githubusercontent.com/{0}/binaires/{1}' -f $p.Repo, $name; $p.Tag = "$($j.tag_name)"
        $p.Size = $null; $p.Digest = $null
        if ("$($j.body)" -match '(?i)SHA-?256\W+([0-9a-f]{64})') { $p.Digest = 'sha256:' + $Matches[1].ToLower() }
        if ("$($j.body)" -match '(?i)taille\W+(\d+)\s*octets') { $p.Size = [long]$Matches[1] }
        $st.Retarget = $v
        $rq = [Net.HttpWebRequest]::Create($p.Url); $rq.UserAgent = 'Oliv_Maintenance'; $rq.Timeout = 20000
        $rs = $rq.GetResponse()
    }
    $part = $p.Dest + '.part'
    $tot = [long]$rs.ContentLength; $in = $rs.GetResponseStream()
    $out = [IO.File]::Create($part); $buf = New-Object byte[] 65536; $done = 0L
    try { while (($n = $in.Read($buf, 0, $buf.Length)) -gt 0) { $out.Write($buf, 0, $n); $done += $n; if ($tot -gt 0) { $st.Pct = [int](100 * $done / $tot) } } }
    finally { $out.Close(); $in.Close(); $rs.Close() }
    if ($p.Size -and $done -ne $p.Size) { throw "taille reçue $done octets, attendue $($p.Size)" }
    if ($p.Digest -match '^sha256:([0-9a-fA-F]{64})$') {
        $want = $Matches[1].ToLower(); $got = (Get-FileHash -LiteralPath $part -Algorithm SHA256).Hash.ToLower()
        if ($got -ne $want) { throw 'empreinte SHA-256 différente de celle publiée : fichier rejeté' }
        $st.Hash = $true
    }
    if (Test-Path -LiteralPath $p.Dest) { Remove-Item -LiteralPath $p.Dest -Force }
    Move-Item -LiteralPath $part -Destination $p.Dest
    $st.Ok = $true
} catch { $st.Msg = $_.Exception.Message; try { Remove-Item -LiteralPath ($p.Dest + '.part') -Force -ErrorAction SilentlyContinue } catch { $null = $_ } }
'@
function Start-UpdCheck([bool]$Manual = $false) {
    if ($BgJobs.ContainsKey('Upd')) { return }
    $UpdUI.Manual = $Manual; $Sync.UpdRepo = $UpdRepo; $Sync.Upd = $null
    if ($SetUI.UpdStatus) { $SetUI.UpdStatus.Text = 'Recherche de mise à jour...' }
    Start-BgJob 'Upd' $UpdScript
}
$BgJobDone['Upd'] = {
    $r = $Sync.Upd; $UpdUI.Checked = [DateTime]::Now
    if (-not $r -or $r.Error) {
        $m = 'Recherche de mise à jour impossible : ' + $(if ($r) { $r.Error } else { 'tâche interrompue' })
        if ($UpdUI.Manual) { Write-UiLog $m 'WARN' }
        Update-UpdStatus $m; return
    }
    $new = Get-UpdVersion $r.Tag; $cur = Get-UpdVersion $AppVersion
    if ($new -and $cur -and $new -gt $cur -and $r.Url) {
        $chg = -not $UpdUI.Info -or "$($UpdUI.Info.Tag)" -ne "$($r.Tag)"; if ($chg) { $UpdUI.Dismissed = $false }
        $UpdUI.Info = $r
        if ($chg -or $UpdUI.Manual) { Write-UiLog ('Nouvelle version disponible : {0} (installée : {1}).' -f $new, $AppVersion) 'APP' }
        Show-UpdBar; Update-UpdStatus ('Version {0} disponible.' -f $new)
    } else {
        $UpdUI.Info = $null; if (-not $BgJobs.ContainsKey('UpdDl')) { $Ui.UpdBar.Visibility = 'Collapsed' }
        if ($UpdUI.Manual) { Write-UiLog "Oliv_Maintenance $AppVersion est à jour." 'APP' }
        Update-UpdStatus ("Oliv_Maintenance $AppVersion est à jour" + $(if ($new) { " (dernière publiée : $new)" } else { '' }) + '.')
    }
}
function Update-UpdStatus([string]$Text) {
    $t = $Text + $(if ($UpdUI.Checked) { '  ·  vérifié {0:HH:mm}' -f $UpdUI.Checked } else { '' })
    if ($SetUI.UpdStatus) { $SetUI.UpdStatus.Text = $t }
    if ($SetUI.HeroStatus) { $SetUI.HeroStatus.Text = $t; $SetUI.HeroStatus.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, $(if ($UpdUI.Info) { 'WarnFgBrush' } elseif ($UpdUI.Checked) { 'OkFgBrush' } else { 'MutedBrush' })) }
}
function Show-UpdBar {
    $r = $UpdUI.Info; if (-not $r -or $UpdUI.Dismissed) { return }
    $Ui.UpdText.Text = 'Oliv_Maintenance {0} est disponible (installée : {1}){2}' -f (Get-UpdVersion $r.Tag), $AppVersion, $(if ($r.Size) { '  ·  {0:N1} Mo' -f ($r.Size / 1MB) } else { '' })
    $Ui.UpdGo.IsEnabled = $true; $Ui.UpdProg.Visibility = 'Collapsed'; $Ui.UpdBar.Visibility = 'Visible'
}
# téléchargement à côté de l'exe en cours (sinon dans Téléchargements), puis bascule
function Start-UpdInstall {
    $r = $UpdUI.Info; if (-not $r -or $BgJobs.ContainsKey('UpdDl')) { return }
    if ($Sync.Running) { Show-Info 'Une tâche est en cours. Mettre à jour une fois terminée.'; return }
    $exe = "$env:_OLIVM_EXE"
    $dir = $(if ($exe -and (Test-Path -LiteralPath $exe)) { Split-Path -Parent $exe } else { Join-Path $UserProfilePath 'Downloads' })
    # nom fixe sur le poste (Oliv_Maintenance.exe), sans numéro de version : version et logo portés par le fichier lui-même.
    # Téléchargé à côté (.new), substitué après la fermeture (l'exe en cours ne peut pas être remplacé)
    $Sync.UpdDl = [hashtable]::Synchronized(@{ Url = $r.Url; Size = $r.Size; Digest = $r.Digest; Dest = (Join-Path $dir 'Oliv_Maintenance.exe.new'); Target = (Join-Path $dir 'Oliv_Maintenance.exe'); Old = $exe; Repo = $UpdRepo })
    $Sync.UpdDlState = [hashtable]::Synchronized(@{ Pct = 0; Ok = $false; Msg = ''; Hash = $false })
    $Ui.UpdGo.IsEnabled = $false; $Ui.UpdProg.Value = 0; $Ui.UpdProg.Visibility = 'Visible'; $Ui.UpdText.Text = 'Téléchargement de la version {0}...' -f (Get-UpdVersion $r.Tag)
    Write-UiLog ('Mise à jour : téléchargement de {0}.' -f $r.Url) 'APP'
    Start-BgJob 'UpdDl' $UpdDlScript
    if (-not $UpdUI.Timer) { $UpdUI.Timer = [Windows.Threading.DispatcherTimer]::new(); $UpdUI.Timer.Interval = [TimeSpan]::FromMilliseconds(300); $UpdUI.Timer.Add_Tick({ if ($Sync.UpdDlState) { $Ui.UpdProg.Value = $Sync.UpdDlState.Pct } }) }
    $UpdUI.Timer.Start()
}
$BgJobDone['UpdDl'] = {
    if ($UpdUI.Timer) { $UpdUI.Timer.Stop() }
    $st = $Sync.UpdDlState; $p = $Sync.UpdDl
    if (-not $st -or -not $st.Ok) {
        $m = $(if ($st -and $st.Msg) { $st.Msg } else { 'tâche interrompue' })
        Write-UiLog "Mise à jour : échec du téléchargement - $m" 'ERROR'; Show-Info "Téléchargement de la mise à jour impossible.`n`n$m" 'Error'
        Show-UpdBar; return
    }
    if ($st.Retarget) { Write-UiLog ('Mise à jour : la version annoncée a été remplacée sur le dépôt, version {0} téléchargée à la place.' -f $st.Retarget) 'APP' }
    Write-UiLog ('Mise à jour téléchargée : {0}{1}.' -f $p.Target, $(if ($st.Hash) { ' (empreinte SHA-256 vérifiée)' } else { ' (empreinte non publiée : taille vérifiée)' })) 'OK'
    # lancé par l'exe : remplacé par la nouvelle version sous le nom Oliv_Maintenance.exe puis relancé ; sinon fichier
    # renommé et dossier ouvert
    if (-not $p.Old) {
        try { Move-Item -LiteralPath $p.Dest -Destination $p.Target -Force -ErrorAction Stop } catch { Write-UiLog "Mise à jour : renommage impossible ($($_.Exception.Message))." 'WARN'; $p.Target = $p.Dest }
        Start-Process explorer.exe -ArgumentList ('/select,"{0}"' -f $p.Target); $Ui.UpdBar.Visibility = 'Collapsed'; return
    }
    if (-not (Confirm-Action "Mise à jour prête.`n`nL'application se ferme puis s'ouvre dans sa nouvelle version (quelques secondes).")) { $Ui.UpdBar.Visibility = 'Collapsed'; return }
    $stable = [string]::Equals($p.Old, $StableExe, [StringComparison]::OrdinalIgnoreCase)
    # lancé par l'exe stable (raccourci, ouverture de session) : copie à jour aussi dans le dossier d'origine du téléchargement
    # et exe stable remplacé, raccourcis inchangés ; sinon ancien exe (Oliv_Maintenance_1.x.y.exe) supprimé, nouveau sous
    # le nom fixe. Substitution répétée jusqu'à 30 s (exe encore verrouillé le temps de la fermeture)
    $q = { param($s) "'" + ($s -replace "'", "''") + "'" }
    $ps = "`$n = $(& $q $p.Dest); `$t = $(& $q $p.Target); `$o = $(& $q $p.Old); `$s = $(& $q $StableExe); `$st = `$$stable" + @'

for ($i = 0; $i -lt 60; $i++) {
    try {
        if ($st) { Copy-Item -LiteralPath $n -Destination $s -Force -ErrorAction Stop }
        Move-Item -LiteralPath $n -Destination $t -Force -ErrorAction Stop
        if (-not $st -and $o -ne $t -and (Test-Path -LiteralPath $o)) { Remove-Item -LiteralPath $o -Force -ErrorAction SilentlyContinue }
        break
    } catch { Start-Sleep -Milliseconds 500 }
}
Start-Process -FilePath $(if ($st) { $s } elseif (Test-Path -LiteralPath $t) { $t } else { $o })
'@
    $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($ps))
    Start-Process -FilePath (Join-Path $env:windir 'System32\WindowsPowerShell\v1.0\powershell.exe') -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-EncodedCommand', $enc) -WindowStyle Hidden
    Write-UiLog 'Fermeture pour mise à jour.' 'APP'
    $Tray.Quit = $true; $Window.Close()
}
function Show-UpdNote {
    $r = $UpdUI.Info; if (-not $r) { return }
    # pied technique de la publication (nom de l'exe, taille, SHA-256, lien) : lu par la vérification du téléchargement, non affiché
    $t = ("$($r.Notes)" -replace '(?m)^\s*(Exe|T.l.chargement)\s*:.*$', '').Trim()
    $n = $(if ($t) { $t -replace '(?m)^#+\s*', '' -replace '\*\*', '' } else { 'Pas de notes pour cette version.' })
    $v = Show-Dialog ("Nouveautés de la version {0}`n`n{1}" -f (Get-UpdVersion $r.Tag), $n) 'Info' @(@{ T = 'Voir sur GitHub'; V = 'web' }, @{ T = 'Mettre à jour'; V = 'go'; S = 'PrimaryBtn' }, @{ T = 'Fermer'; V = 'no'; C = $true }) $null $null 640
    if ($v -eq 'web') { Start-Process $r.Page } elseif ($v -eq 'go') { Start-UpdInstall }
}
$Ui.UpdGo.Add_Click({ Start-UpdInstall })
$Ui.UpdNotes.Add_Click({ Show-UpdNote })
$Ui.UpdLater.Add_Click({ $UpdUI.Dismissed = $true; $Ui.UpdBar.Visibility = 'Collapsed' })
# recherche au lancement, une fois l'interface prête (réseau en tâche de fond, sans effet sur l'ouverture)
if (Get-SoftAuto) {
    $SoftAutoTimer = [Windows.Threading.DispatcherTimer]::new(); $SoftAutoTimer.Interval = [TimeSpan]::FromSeconds(30)
    # 30 s après l'ouverture puis toutes les 12 h (application gardée ouverte dans la zone de notification)
    $SoftAutoTimer.Add_Tick({
        $SoftAutoTimer.Interval = [TimeSpan]::FromHours(12)
        if (-not (Get-SoftAuto)) { return }
        try {
            if ($Sync.WgRunning -or $Sync.Running -or (Test-SoftUpgrading)) { $SoftAutoTimer.Interval = [TimeSpan]::FromMinutes(5); Write-UiLog 'Recherche automatique des mises à jour des logiciels : reportée de 5 minutes (tâche déjà en cours).' 'APP'; return }
            Write-UiLog 'Recherche des mises à jour des logiciels installés en arrière-plan (automatique).' 'APP'
            Start-SoftSearch
        } catch { Write-Ignored 'Recherche des mises à jour des logiciels au lancement' $_ }
    })
    $SoftAutoTimer.Start()
}
# application restée ouverte (zone de notification, lancement à l'ouverture de session) : nouvelle vérification toutes les 6 h,
# sinon la version annoncée au lancement peut avoir été remplacée sur le dépôt
$UpdUI.Recheck = [Windows.Threading.DispatcherTimer]::new(); $UpdUI.Recheck.Interval = [TimeSpan]::FromHours(6)
$UpdUI.Recheck.Add_Tick({ if ((Get-UpdAuto) -and -not $BgJobs.ContainsKey('UpdDl')) { try { Start-UpdCheck $false } catch { Write-Ignored 'Recherche de mise à jour' $_ } } })
$UpdUI.Recheck.Start()
if (Get-UpdAuto) { [void]$Window.Dispatcher.BeginInvoke([Action]{ try { Start-UpdCheck $false } catch { Write-Ignored 'Recherche de mise à jour' $_ } }, [Windows.Threading.DispatcherPriority]::ApplicationIdle) }
