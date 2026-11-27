# ---------- Mises à jour de l'application : dernière version publiée sur GitHub (Releases du dépôt public)
# Recherche au lancement (Paramètres > Mises à jour de l'application, activée par défaut) puis bandeau « Version X
# disponible » : Mettre à jour = téléchargement de l'exe publié (pièce jointe de la version, sinon branche « binaires »
# du dépôt) dans le dossier protégé C:\ProgramData\Oliv_Maintenance\MiseAJour, contrôle de la taille et de l'empreinte
# SHA-256 publiées, puis relance sur la nouvelle version par l'exe stable (copie pour l'utilisateur à côté de l'exe en
# cours, ancien exe supprimé après fermeture).
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
        # version relue pas plus récente que celle installée (publication retirée, retour en arrière) : rien n'est installé
        $nv = $null; $cv = $null; [void][version]::TryParse($v, [ref]$nv); [void][version]::TryParse("$($p.Cur)", [ref]$cv)
        if (-not $nv -or ($cv -and $nv -le $cv)) { throw "la dernière version publiée ($v) n'est pas plus récente que celle installée ($($p.Cur)) : rien à installer" }
        $p.Url = 'https://raw.githubusercontent.com/{0}/binaires/{1}' -f $p.Repo, $name; $p.Tag = "$($j.tag_name)"
        $p.Size = $null; $p.Digest = $null
        if ("$($j.body)" -match '(?i)SHA-?256\W+([0-9a-f]{64})') { $p.Digest = 'sha256:' + $Matches[1].ToLower() }
        if ("$($j.body)" -match '(?i)taille\W+(\d+)\s*octets') { $p.Size = [long]$Matches[1] }
        $st.Retarget = $v
        $rq = [Net.HttpWebRequest]::Create($p.Url); $rq.UserAgent = 'Oliv_Maintenance'; $rq.Timeout = 20000
        $rs = $rq.GetResponse()
    }
    [void][IO.Directory]::CreateDirectory((Split-Path $p.Dest))
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
    # empreinte publiée obligatoire (comme lancer.ps1) : sans elle, rien ne garantit que le fichier reçu est celui publié
    if (-not $st.Hash) { throw 'empreinte SHA-256 non publiée avec cette version : fichier rejeté' }
    # empreinte du fichier reçu : recontrôlée par le script de remplacement juste avant la copie et le lancement
    $st.Sha = (Get-FileHash -LiteralPath $part -Algorithm SHA256).Hash
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
    # dernière version publiée mémorisée : affichée dès l'ouverture des Paramètres, sans nouvelle vérification
    $UpdUI.Latest = $new
    if ($new -and $cur -and $new -gt $cur -and $r.Url) {
        $chg = -not $UpdUI.Info -or "$($UpdUI.Info.Tag)" -ne "$($r.Tag)"; if ($chg) { $UpdUI.Dismissed = $false }
        $UpdUI.Info = $r
        if ($chg -or $UpdUI.Manual) { Write-UiLog ('Nouvelle version disponible : {0} (installée : {1}).' -f $new, $AppVersion) 'APP' }
        Show-UpdBar; Update-UpdStatus ('Version {0} disponible.' -f $new)
    } else {
        $UpdUI.Info = $null; if (-not $BgJobs.ContainsKey('UpdDl')) { $Ui.UpdBar.Visibility = 'Collapsed' }
        if ($UpdUI.Manual) { Write-UiLog "Oliv_Maintenance $AppVersion est à jour." 'APP' }
        Update-UpdStatus (Get-UpdUpToDate)
    }
}
function Get-UpdUpToDate { 'À jour' + $(if ($UpdUI.Latest) { '  ·  dernière version publiée : {0}' -f $UpdUI.Latest } else { '' }) }
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
# téléchargement dans le dossier protégé de l'application (C:\ProgramData\Oliv_Maintenance\MiseAJour, écriture réservée
# aux administrateurs : le fichier vérifié ne peut pas être remplacé avant son lancement en administrateur), puis bascule ;
# copie pour l'utilisateur à côté de l'exe en cours (sinon dans Téléchargements), jamais lancée par l'application
$UpdDlDir = Join-Path $env:ProgramData 'Oliv_Maintenance\MiseAJour'
function Start-UpdInstall {
    $r = $UpdUI.Info; if (-not $r -or $BgJobs.ContainsKey('UpdDl')) { return }
    if ($Sync.Running) { Show-Info 'Une tâche est en cours. Mettre à jour une fois terminée.'; return }
    if ("$($r.Digest)" -notmatch '^sha256:[0-9a-fA-F]{64}$') {
        Write-UiLog ('Mise à jour {0} refusée : empreinte SHA-256 non publiée avec la version.' -f (Get-UpdVersion $r.Tag)) 'WARN'
        Show-Info "Mise à jour refusée : l'empreinte SHA-256 du fichier n'est pas publiée avec cette version, son intégrité ne peut pas être vérifiée.`n`nTélécharger la version depuis sa page GitHub (bouton Voir sur GitHub)." 'Warn'; return
    }
    if (-not $AppDirSafe) {
        Write-UiLog 'Mise à jour impossible : dossier de l''application non sécurisé (C:\ProgramData\Oliv_Maintenance).' 'ERROR'
        Show-Info "Mise à jour impossible : les droits du dossier C:\ProgramData\Oliv_Maintenance n'ont pas pu être sécurisés.`n`nFermer puis relancer l'application pour les remettre en conformité." 'Error'; return
    }
    $exe = "$env:_OLIVM_EXE"
    $dir = $(if ($exe -and (Test-Path -LiteralPath $exe)) { Split-Path -Parent $exe } else { Join-Path $UserProfilePath 'Downloads' })
    # nom fixe sur le poste (Oliv_Maintenance.exe), sans numéro de version : version et logo portés par le fichier lui-même.
    # Téléchargé dans le dossier protégé (.new), substitué après la fermeture
    $Sync.UpdDl = [hashtable]::Synchronized(@{ Url = $r.Url; Size = $r.Size; Digest = $r.Digest; Dest = (Join-Path $UpdDlDir 'Oliv_Maintenance.exe.new'); Target = (Join-Path $dir 'Oliv_Maintenance.exe'); Old = $exe; Repo = $UpdRepo; Cur = $AppVersion })
    $Sync.UpdDlState = [hashtable]::Synchronized(@{ Pct = 0; Ok = $false; Msg = ''; Hash = $false; Sha = '' })
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
    Write-UiLog ('Mise à jour téléchargée et vérifiée (empreinte SHA-256 publiée) : version {0}.' -f $(if ($st.Retarget) { $st.Retarget } else { Get-UpdVersion $UpdUI.Info.Tag })) 'OK'
    # lancé par le fichier .cmd : nouvel exe copié pour l'utilisateur (Téléchargements) et dossier ouvert, lancement par
    # l'utilisateur (invite UAC)
    if (-not $p.Old) {
        try { Copy-Item -LiteralPath $p.Dest -Destination $p.Target -Force -ErrorAction Stop; Remove-Item -LiteralPath $p.Dest -Force -ErrorAction SilentlyContinue }
        catch { Write-UiLog "Mise à jour : copie dans $(Split-Path $p.Target) impossible ($($_.Exception.Message))." 'WARN'; $p.Target = $p.Dest }
        Start-Process explorer.exe -ArgumentList ('/select,"{0}"' -f $p.Target); $Ui.UpdBar.Visibility = 'Collapsed'; return
    }
    if (-not (Confirm-Action "Mise à jour prête.`n`nL'application se ferme puis s'ouvre dans sa nouvelle version (quelques secondes).")) { $Ui.UpdBar.Visibility = 'Collapsed'; return }
    # script de remplacement (administrateur) : empreinte du fichier du dossier protégé recontrôlée, exe stable
    # (C:\ProgramData\Oliv_Maintenance\Oliv_Maintenance.exe, raccourcis et ouverture de session) remplacé puis lancé ;
    # copie pour l'utilisateur sous le nom fixe à côté de l'ancien exe (Oliv_Maintenance_1.x.y.exe supprimé), jamais
    # lancée : un fichier d'un dossier modifiable sans élévation n'est pas exécuté en administrateur. Empreinte différente :
    # rien n'est remplacé, exe stable (ancienne version) relancé. Substitution répétée jusqu'à 30 s (exe stable encore
    # verrouillé le temps de la fermeture)
    $q = { param($s) "'" + ($s -replace "'", "''") + "'" }
    $ps = "`$n = $(& $q $p.Dest); `$t = $(& $q $p.Target); `$o = $(& $q $p.Old); `$s = $(& $q $StableExe); `$h = $(& $q $Sync.UpdDlState.Sha)" + @'

$ok = $h -and (Test-Path -LiteralPath $n) -and ((Get-FileHash -LiteralPath $n -Algorithm SHA256).Hash -eq $h)
if ($ok) {
    for ($i = 0; $i -lt 60; $i++) {
        try { Copy-Item -LiteralPath $n -Destination $s -Force -ErrorAction Stop; break } catch { Start-Sleep -Milliseconds 500 }
    }
    if ($t -ne $s) {
        try {
            Copy-Item -LiteralPath $n -Destination $t -Force -ErrorAction Stop
            if ($o -ne $t -and $o -ne $s -and (Test-Path -LiteralPath $o)) { Remove-Item -LiteralPath $o -Force -ErrorAction SilentlyContinue }
        } catch { $null = $_ }
    }
}
Remove-Item -LiteralPath $n -Force -ErrorAction SilentlyContinue
if (Test-Path -LiteralPath $s) { Start-Process -FilePath $s }
'@
    # script lancé par Exit-App, une fois la fenêtre réellement fermée (Start-UpdHelper) : lancé ici, il remplaçait l'exe et
    # ouvrait une 2e instance même si la fermeture était annulée ; son PID est gardé par Exit-App (arrêt des processus enfants)
    $Sync.UpdHelper = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($ps))
    Write-UiLog 'Fermeture pour mise à jour.' 'APP'
    $Tray.Quit = $true; $Window.Close()
    # fermeture annulée (tâche en cours, réponse Non) : rien n'est remplacé, la croix réduit de nouveau la fenêtre
    if ($Window.IsVisible) {
        $Tray.Quit = $false; $Sync.UpdHelper = $null
        Write-UiLog 'Mise à jour reportée : fermeture annulée. Bouton Mettre à jour pour la relancer.' 'WARN'
        Show-UpdBar
    }
}
# script de remplacement de la mise à jour prête ; PID renvoyé (gardé par Exit-App), $null si rien à lancer
function Start-UpdHelper {
    if (-not $Sync.UpdHelper) { return $null }
    $enc = $Sync.UpdHelper; $Sync.UpdHelper = $null
    $p = Start-Process -FilePath (Join-Path $env:windir 'System32\WindowsPowerShell\v1.0\powershell.exe') -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-EncodedCommand', $enc) -WindowStyle Hidden -PassThru
    $p.Id
}
function Show-UpdNote {
    $r = $UpdUI.Info; if (-not $r) { return }
    # pied technique de la publication (nom de l'exe, taille, SHA-256, lien) : lu par la vérification du téléchargement, non affiché
    $t = ("$($r.Notes)" -replace '(?m)^\s*(Exe|T.l.chargement)\s*:.*$', '').Trim()
    $n = $(if ($t) { $t -replace '(?m)^#+\s*', '' -replace '\*\*', '' } else { 'Pas de notes pour cette version.' })
    $v = Show-Dialog ("Nouveautés de la version {0}`n`n{1}" -f (Get-UpdVersion $r.Tag), $n) 'Info' @(@{ T = 'Voir sur GitHub'; V = 'web' }, @{ T = 'Mettre à jour'; V = 'go'; S = 'PrimaryBtn' }, @{ T = 'Fermer'; V = 'no'; C = $true }) $null $null 640
    if ($v -eq 'web') { try { Open-WebPage $r.Page } catch { Write-UiLog "Ouverture de la page GitHub : $($_.Exception.Message)" 'ERROR'; Show-Info "Ouverture de la page GitHub impossible.`n`n$($_.Exception.Message)" 'Error' } } elseif ($v -eq 'go') { Start-UpdInstall }
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
            if ($Sync.WgRunning -or $Sync.Running -or (Test-SoftUpgrading)) { $SoftAutoTimer.Interval = [TimeSpan]::FromMinutes(5); Write-FileLog 'Recherche automatique des mises à jour des logiciels : reportée de 5 minutes (tâche déjà en cours).' 'APP'; return }
            Write-FileLog 'Recherche des mises à jour des logiciels installés en arrière-plan (automatique).' 'APP'
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
