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
    $part = $p.Dest + '.part'
    $rq = [Net.HttpWebRequest]::Create($p.Url); $rq.UserAgent = 'Oliv_Maintenance'; $rq.Timeout = 20000
    $rs = $rq.GetResponse(); $tot = [long]$rs.ContentLength; $in = $rs.GetResponseStream()
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
        $UpdUI.Info = $r; $UpdUI.Dismissed = $false
        Write-UiLog ('Nouvelle version disponible : {0} (installée : {1}).' -f $new, $AppVersion) 'APP'
        Show-UpdBar; Update-UpdStatus ('Version {0} disponible.' -f $new)
    } else {
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
    $Sync.UpdDl = @{ Url = $r.Url; Size = $r.Size; Digest = $r.Digest; Dest = (Join-Path $dir $r.Name); Old = $exe }
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
    Write-UiLog ('Mise à jour téléchargée : {0}{1}.' -f $p.Dest, $(if ($st.Hash) { ' (empreinte SHA-256 vérifiée)' } else { ' (empreinte non publiée : taille vérifiée)' })) 'OK'
    # lancé par l'exe : relance sur la nouvelle version, ancien exe supprimé après la fermeture ; sinon dossier ouvert
    if (-not $p.Old) { Start-Process explorer.exe -ArgumentList ('/select,"{0}"' -f $p.Dest); $Ui.UpdBar.Visibility = 'Collapsed'; return }
    if (-not (Confirm-Action "Mise à jour prête.`n`nL'application se ferme puis s'ouvre dans sa nouvelle version (quelques secondes).")) { $Ui.UpdBar.Visibility = 'Collapsed'; return }
    $same = [string]::Equals($p.Old, $p.Dest, [StringComparison]::OrdinalIgnoreCase)
    $stable = [string]::Equals($p.Old, $StableExe, [StringComparison]::OrdinalIgnoreCase)
    # lancé par l'exe stable (raccourci, ouverture de session) : nouvelle version copiée à sa place, raccourcis inchangés
    $cmd = $(if ($stable) { 'timeout /t 3 /nobreak >nul & copy /y "{0}" "{1}" >nul & del /f /q "{0}" & start "" "{1}"' -f $p.Dest, $StableExe }
        else { 'timeout /t 3 /nobreak >nul' + $(if (-not $same) { ' & del /f /q "{0}"' -f $p.Old } else { '' }) + (' & start "" "{0}"' -f $p.Dest) })
    Start-Process -FilePath (Join-Path $env:windir 'System32\cmd.exe') -ArgumentList @('/c', $cmd) -WindowStyle Hidden
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
if ((Get-SoftAuto) -and -not $SelfTest) {
    $SoftAutoTimer = [Windows.Threading.DispatcherTimer]::new(); $SoftAutoTimer.Interval = [TimeSpan]::FromSeconds(30)
    $SoftAutoTimer.Add_Tick({
        $SoftAutoTimer.Stop()
        try {
            if ($Sync.WgRunning -or $Sync.Running -or (Test-SoftUpgrading)) { Write-UiLog 'Recherche des mises à jour des logiciels au lancement : reportée (tâche déjà en cours).' 'APP'; return }
            Write-UiLog 'Recherche des mises à jour des logiciels installés en arrière-plan (lancement de l''application).' 'APP'
            Start-SoftSearch
        } catch { Write-Ignored 'Recherche des mises à jour des logiciels au lancement' $_ }
    })
    $SoftAutoTimer.Start()
}
if ((Get-UpdAuto) -and -not $SelfTest) { [void]$Window.Dispatcher.BeginInvoke([Action]{ try { Start-UpdCheck $false } catch { Write-Ignored 'Recherche de mise à jour' $_ } }, [Windows.Threading.DispatcherPriority]::ApplicationIdle) }
