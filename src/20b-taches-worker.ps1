# Tâches du worker, partie 2 : réparation (SFC, DISM, CHKDSK), réseau, dépannage
$WorkerScript += "`n" + @'
function Invoke-Task_SfcVerify   { Invoke-SfcRun '/verifyonly' }
function Invoke-Task_Sfc         { Invoke-SfcRun '/scannow' }
function Invoke-Task_ChkBoot {
    [void](Invoke-Native "$env:windir\System32\fsutil.exe" @('dirty', 'set', $SysDrive))
    [void](Invoke-Native "$env:windir\System32\fsutil.exe" @('dirty', 'query', $SysDrive))
    Write-TaskLog 'CHKDSK /F (autochk) s''exécutera au prochain redémarrage.' 'OK'
}
function Invoke-Task_ChkState {
    $dirty = $null
    $h = [_OlivM.VolDirty]::CreateFile("\\.\$SysDrive", 0, 3, [IntPtr]::Zero, 3, 0, [IntPtr]::Zero)
    try {
        $o = [uint32]0; $r = [uint32]0
        if (-not $h.IsInvalid -and [_OlivM.VolDirty]::DeviceIoControl($h, 0x90078, [IntPtr]::Zero, 0, [ref]$o, 4, [ref]$r, [IntPtr]::Zero)) { $dirty = [bool]($o -band 1) }
    } finally { $h.Dispose() }
    if ($null -eq $dirty) { Write-TaskLog "Bit dirty de $SysDrive : lecture impossible (FSCTL_IS_VOLUME_DIRTY)." 'WARN' }
    elseif ($dirty) { Write-TaskLog "Bit dirty de $SysDrive : positionné, CHKDSK /F s'exécutera au prochain démarrage." 'WARN' }
    else { Write-TaskLog "Bit dirty de $SysDrive : non positionné." 'OK' }
    $since = (Get-Date).AddDays(-30)
    $ms = [long]([DateTime]::Now - $since).TotalMilliseconds
    $ntfs = @(Get-WinEvent -LogName System -FilterXPath "*[System[Provider[@Name='Ntfs' or @Name='Microsoft-Windows-Ntfs'] and (EventID=55 or EventID=98) and TimeCreated[timediff(@SystemTime) <= $ms]]]" -ErrorAction SilentlyContinue)
    if ($ntfs.Count) {
        Write-TaskLog ('Événements NTFS 55 / 98 (corruption, CHKDSK hors ligne requis) sur 30 jours : {0}, dernier le {1:dd/MM/yyyy HH:mm}.' -f $ntfs.Count, $ntfs[0].TimeCreated) 'WARN'
        Write-TaskLog ('  ' + ("$($ntfs[0].Message)" -split "`r?`n")[0])
    } else { Write-TaskLog 'Événements NTFS 55 / 98 sur 30 jours : aucun.' 'OK' }
    $last = Get-WinEvent -LogName Application -FilterXPath "*[System[Provider[@Name='Wininit' or @Name='Chkdsk'] and EventID=1001]]" -MaxEvents 1 -ErrorAction SilentlyContinue
    if ($last) { Write-TaskLog ('Dernier résultat CHKDSK : {0:dd/MM/yyyy HH:mm} ({1}, Application, ID 1001).' -f $last.TimeCreated, $last.ProviderName) }
    else { Write-TaskLog 'Dernier résultat CHKDSK : aucun dans le journal Application.' }
    if ($dirty -or $ntfs.Count) { Write-TaskLog 'Réparation recommandée : CHKDSK > Réparer (programmé au prochain démarrage).' 'WARN' }
    else { Write-TaskLog 'Volume système sain d''après NTFS, aucune réparation nécessaire.' 'OK' }
}
function Invoke-Task_WindowsOld {
    if (-not (Test-Path -LiteralPath "$SysDrive\Windows.old")) { Write-TaskLog 'Aucun dossier Windows.old.' 'OK'; return }
    Start-CleanMgr -Id 778 -Include @('Previous Installations')
    if (Test-Path -LiteralPath "$SysDrive\Windows.old") { Write-TaskLog 'Windows.old toujours présent après cleanmgr.' 'WARN' } else { Write-TaskLog 'Windows.old supprimé.' 'OK' }
}
function Stop-ServiceWait([string[]]$Names) {
    foreach ($n in $Names) {
        $s = Get-Service -Name $n -ErrorAction SilentlyContinue
        if (-not $s -or $s.Status -eq 'Stopped') { continue }
        try { $s.Stop() } catch {}
        try { $s.WaitForStatus('Stopped', [TimeSpan]::FromSeconds(60)); Write-TaskLog "Service $n arrêté." }
        catch { Write-TaskLog "Service $n : arrêt non confirmé après 60 s." 'WARN' }
    }
}
function Invoke-Task_WuReset {
    Stop-ServiceWait 'bits', 'wuauserv', 'cryptsvc'
    foreach ($f in @(Get-ChildItem -LiteralPath "$env:ProgramData\Microsoft\Network\Downloader" -Filter 'qmgr*.dat' -File -Force -ErrorAction SilentlyContinue)) {
        try {
            Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop
            Write-TaskLog "Supprimé : $($f.FullName)"
        } catch { Write-TaskLog "$($f.Name) : $($_.Exception.Message)" 'WARN' }
    }
    $stamp = '{0:yyyyMMdd-HHmmss}' -f (Get-Date)
    foreach ($p in "$env:windir\SoftwareDistribution\DataStore", "$env:windir\SoftwareDistribution\Download", "$env:windir\System32\catroot2") {
        if (-not (Test-Path -LiteralPath $p)) { continue }
        $new = '{0}.bak_{1}' -f (Split-Path $p -Leaf), $stamp
        try { Rename-Item -LiteralPath $p -NewName $new -ErrorAction Stop; Write-TaskLog "Renommé : $p -> $new" }
        catch { Write-TaskLog "$p non renommé (service relancé par Windows ?) : $($_.Exception.Message)" 'WARN' }
    }
    foreach ($n in 'cryptsvc', 'bits', 'wuauserv') {
        try {
            Start-Service -Name $n -ErrorAction Stop
            Write-TaskLog "Service $n démarré."
        } catch { Write-TaskLog "Service $n : $($_.Exception.Message)" 'WARN' }
    }
    Write-TaskLog 'Composants Windows Update réinitialisés. L''historique affiché dans Paramètres repart de zéro ; lancer une recherche de mises à jour.' 'OK'
}
function Invoke-Task_WuInstall {
    Write-TaskLog 'Mises à jour disponibles dans Windows Update (hors facultatives et préversions)...'
    $p = Get-PendingUpdate $false
    $s = $p.Session; $list = @($p.Updates)
    if (-not $list.Count) { Write-TaskLog 'Aucune mise à jour disponible.' 'OK'; return }
    # sélection faite dans l'Accueil (identifiants Windows Update) : les autres restent en attente
    $want = @($Sync.WuSel | Where-Object { $_ })
    if ($want.Count) {
        $skip = @($list | Where-Object { $want -notcontains "$($_.Identity.UpdateID)" })
        $list = @($list | Where-Object { $want -contains "$($_.Identity.UpdateID)" })
        foreach ($u in $skip) { Write-TaskLog "Non sélectionnée, non installée : $($u.Title)" }
        if (-not $list.Count) {
            Write-TaskLog 'Les mises à jour sélectionnées ne sont plus disponibles (déjà installées ou retirées par Windows Update).' 'WARN'
            return
        }
    }
    Write-TaskLog ('{0} {1} à installer.' -f $list.Count, (Get-Plural $list.Count 'mise à jour' 'mises à jour'))
    $n = $list.Count; $i = 0; $ok = 0; $ko = 0; $reboot = $false
    foreach ($u in $list) {
        if ($Sync.Cancel) { Write-TaskLog 'Arrêt demandé : mises à jour suivantes non installées.' 'WARN'; break }
        $i++
        $kb = Get-KB $u.Title
        $Sync.Status = 'Mise à jour {0}/{1}  {2}' -f $i, $n, $(if ($kb) { $kb } else { $u.Title })
        $Sync.TaskPct = 100 * ($i - 1) / $n
        Write-TaskLog ('[{0}/{1}] {2}' -f $i, $n, $u.Title)
        try {
            if ($u.InstallationBehavior.CanRequestUserInput) {
                Write-TaskLog '   Ignorée : demande une interaction utilisateur.' 'WARN'
                $ko++
                continue
            }
            if (-not $u.EulaAccepted) { $u.AcceptEula() }
            $c = New-Object -ComObject Microsoft.Update.UpdateColl; [void]$c.Add($u)
            if (-not $u.IsDownloaded) {
                $d = $s.CreateUpdateDownloader(); $d.Updates = $c
                $job = $null
                try { $job = $d.BeginDownload($null, $null, $null) } catch {}
                if ($job) {
                    # taille réelle pour ce poste = TotalBytesToDownload calculé par Windows (fichiers express / différentiels)
                    $tot = [double]0
                    while (-not $job.IsCompleted) {
                        if ($Sync.Cancel) { $job.RequestAbort() }
                        try {
                            $pg = $job.GetProgress()
                            $tot = [double]$pg.TotalBytesToDownload
                            $done = [double]$pg.TotalBytesDownloaded
                        } catch { $done = 0 }
                        if ($tot -gt 0) {
                            $Sync.Status = 'Mise à jour {0}/{1}  {2}  -  téléchargement {3:N1} / {4:N1} Mo' -f $i, $n, $(if ($kb) { $kb } else { 'en cours' }), ($done / 1MB), ($tot / 1MB)
                            $Sync.TaskPct = 100 * ($i - 1 + 0.5 * $done / $tot) / $n
                        }
                        Start-Sleep -Milliseconds 500
                    }
                    $dr = $d.EndDownload($job)
                    if ($tot -gt 0) { Write-TaskLog ('   Taille réelle téléchargée sur ce poste : {0:N1} Mo' -f ($tot / 1MB)) }
                } else { $dr = $d.Download() }
                if ($dr.ResultCode -notin 2, 3) {
                    Write-TaskLog ('   Téléchargement en échec (code {0}, 0x{1:X8}).' -f $dr.ResultCode, $dr.HResult) 'ERROR'
                    $ko++
                    continue
                }
            } else { Write-TaskLog '   Déjà téléchargée sur ce poste.' }
            $Sync.Status = 'Mise à jour {0}/{1}  {2}  -  installation' -f $i, $n, $(if ($kb) { $kb } else { '' })
            $Sync.TaskPct = 100 * ($i - 0.5) / $n
            $ins = $s.CreateUpdateInstaller(); $ins.Updates = $c
            $ir = $ins.Install()
            if ($ir.ResultCode -in 2, 3) {
                $ok++
                Write-TaskLog '   Installée.' 'OK'
            } else {
                $ko++
                Write-TaskLog ('   Installation en échec (code {0}, 0x{1:X8}).' -f $ir.ResultCode, $ir.HResult) 'ERROR'
            }
            [void]$Sync.WuInstalled.Add(@{ Title = "$($u.Title)"; Kb = $kb; Ok = ($ir.ResultCode -in 2, 3); Code = ('0x{0:X8}' -f $ir.HResult) })
            if ($ir.RebootRequired) { $reboot = $true }
        } catch { $ko++; Write-TaskLog ('   ' + $_.Exception.Message) 'ERROR' }
    }
    $Sync.TaskPct = 100
    $Sync.WuReboot = $reboot; $Sync.WuOkCount = $ok
    Write-TaskLog ('Mises à jour : {0} {1}, {2} {3}{4}.' -f $ok, (Get-Plural $ok 'installée' 'installées'), $ko, (Get-Plural $ko 'en échec ou ignorée' 'en échec ou ignorées'), $(if ($reboot) { ' - redémarrage requis' } else { '' })) $(if ($ko) { 'WARN' } else { 'OK' })
}
function Invoke-Task_NetReset {
    [void](Invoke-Native "$env:windir\System32\ipconfig.exe" @('/flushdns'))
    [void](Invoke-Native "$env:windir\System32\netsh.exe" @('winsock', 'reset'))
    Write-TaskLog 'Cache DNS vidé et catalogue Winsock réinitialisé : redémarrage nécessaire pour terminer.' 'WARN'
}
function Invoke-Task_SpoolReset {
    $dir = "$((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Print\Printers' -ErrorAction SilentlyContinue).DefaultSpoolDirectory)"
    if (-not $dir) { $dir = "$env:windir\System32\spool\PRINTERS" }
    Stop-ServiceWait 'Spooler'
    $n = 0
    foreach ($f in @(Get-ChildItem -LiteralPath $dir -File -Force -ErrorAction SilentlyContinue)) {
        try {
            Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop
            $n++
        } catch { Write-TaskLog "$($f.Name) : $($_.Exception.Message)" 'WARN' }
    }
    Write-TaskLog ("$n $(Get-Plural $n 'fichier' 'fichiers') de file d'attente $(Get-Plural $n 'supprimé' 'supprimés') dans $dir.")
    try {
        Start-Service -Name Spooler -ErrorAction Stop
        Write-TaskLog 'Spouleur d''impression redémarré.' 'OK'
    } catch { Write-TaskLog "Spouleur : $($_.Exception.Message)" 'ERROR' }
}
# Heure du poste : service de temps démarré (désactivé = repassé en manuel), puis resynchronisation. Poste du domaine :
# hiérarchie du domaine (contrôleur de domaine), source jamais modifiée. Hors domaine : source configurée gardée ; aucune
# source réseau (horloge CMOS locale) = time.windows.com, serveur par défaut de Windows. Écart restant mesuré ensuite.
function Invoke-Task_TimeSync {
    $w32 = "$env:windir\System32\w32tm.exe"
    $svc = Get-CimInstance Win32_Service -Filter "Name='W32Time'" -ErrorAction SilentlyContinue
    if (-not $svc) { Write-TaskLog 'Service de temps Windows (W32Time) absent du poste.' 'ERROR'; return }
    if ("$($svc.StartMode)" -eq 'Disabled') { Set-Service -Name W32Time -StartupType Manual; Write-TaskLog 'Service de temps Windows réactivé (démarrage manuel).' }
    if ("$($svc.State)" -ne 'Running') {
        try { Start-Service -Name W32Time -ErrorAction Stop; Write-TaskLog 'Service de temps Windows démarré.' } catch { Write-TaskLog "Service de temps Windows : $($_.Exception.Message)" 'ERROR'; return }
    }
    $domain = [bool](Get-CimInstance Win32_ComputerSystem).PartOfDomain
    $src = "$(& $w32 /query /source 2>&1 | Select-Object -First 1)".Trim()
    Write-TaskLog ('Source de temps : {0}' -f $(if ($src) { $src } else { 'aucune' }))
    if ($domain) { Write-TaskLog 'Poste du domaine : synchronisation sur la hiérarchie du domaine, source inchangée.' }
    elseif (-not $src -or $src -match '(?i)CMOS|Free-running') {
        Write-TaskLog 'Aucune source réseau : time.windows.com configuré (serveur de temps par défaut de Windows).'
        [void](Invoke-Native $w32 @('/config', '/manualpeerlist:"time.windows.com,0x9"', '/syncfromflags:manual', '/update'))
        $src = 'time.windows.com'
    }
    $rc = Invoke-Native $w32 @('/resync', '/rediscover')
    if ($rc -ne 0 -and -not $Sync.Aborted) {
        # source pas encore jointe juste après le démarrage du service ou un changement de configuration : nouvel essai
        Start-Sleep -Seconds 3
        $rc = Invoke-Native $w32 @('/resync')
    }
    if ($rc -ne 0) { Write-TaskLog 'Heure non synchronisée : source de temps injoignable (réseau, pare-feu UDP 123 ou serveur de temps).' 'ERROR'; return }
    # écart restant avec la source (1 mesure) ; source locale ou illisible : pas de mesure
    $peer = ($src -replace ',0x[0-9a-f]+$', '').Trim()
    if ($peer -and $peer -notmatch '(?i)CMOS|Free-running|VM IC') {
        $line = "$(& $w32 /stripchart "/computer:$peer" /samples:1 /dataonly 2>&1 | Select-Object -Last 1)"
        $m = [regex]::Match($line, '([+-]\d+[.,]\d+)s')
        if ($m.Success) { Write-TaskLog ('Heure synchronisée sur {0} : écart restant {1} s.' -f $peer, ($m.Groups[1].Value -replace '\.', ',')) 'OK'; return }
    }
    Write-TaskLog 'Heure synchronisée.' 'OK'
}
function Invoke-Task_GpForce {
    # gpupdate peut demander une déconnexion ou un redémarrage (O/N) : réponse « N » envoyée d'office, l'outil ne redémarre rien
    $psi = [Diagnostics.ProcessStartInfo]::new("$env:windir\System32\gpupdate.exe", '/force /wait:600')
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardInput = $true
    Write-TaskLog "> $($psi.FileName) $($psi.Arguments)" 'CMD'
    $p = [Diagnostics.Process]::Start($psi)
    $Sync.ChildPid = $p.Id; $Sync.ChildName = 'GPUPDATE'
    try {
        try { $p.StandardInput.WriteLine('N'); $p.StandardInput.WriteLine('N'); $p.StandardInput.Close() } catch {}
        Read-NativeLine $p.StandardOutput.BaseStream { param($l) if ($l.Trim()) { Write-TaskLog $l.Trim() } }
        $p.WaitForExit()
    } finally { $Sync.ChildPid = $null; $Sync.ChildName = $null }
    Write-TaskLog "Code retour : $($p.ExitCode)" $(if ($p.ExitCode -eq 0) { 'OK' } else { 'WARN' })
}
function Invoke-Task_NetCheck {
    $fail = @(); $warn = @()
    $cfg = @(Get-NetIPConfiguration -ErrorAction SilentlyContinue | Where-Object { $_.IPv4DefaultGateway -and "$($_.NetAdapter.Status)" -eq 'Up' })
    if (-not $cfg) {
        Write-TaskLog 'Carte réseau : aucune carte connectée avec une passerelle IPv4.' 'ERROR'
        Write-TaskLog 'Résultat : échec dès la connexion locale (câble, Wi-Fi, DHCP).' 'ERROR'
        return
    }
    foreach ($c in $cfg) {
        $ip = @($c.IPv4Address)[0]
        Write-TaskLog ('Carte {0} : {1}/{2}  ·  passerelle {3}  ·  DNS {4}' -f $c.InterfaceAlias, $ip.IPAddress, $ip.PrefixLength, $c.IPv4DefaultGateway[0].NextHop, ((@($c.DNSServer | Where-Object { $_.AddressFamily -eq 2 } | ForEach-Object { $_.ServerAddresses }) -join ' / ')))
        if ("$($ip.IPAddress)" -like '169.254.*') { $fail += 'adresse APIPA (DHCP injoignable)' }
    }
    $c = $cfg[0]; $gw = $c.IPv4DefaultGateway[0].NextHop
    if (Test-Connection -ComputerName $gw -Count 2 -Quiet -ErrorAction SilentlyContinue) { Write-TaskLog "Passerelle $gw : répond au ping." 'OK' }
    else {
        Write-TaskLog "Passerelle $gw : pas de réponse au ping (ICMP parfois filtré, à confirmer par les tests suivants)." 'WARN'
        $warn += 'passerelle'
    }
    $dns = @($c.DNSServer | Where-Object { $_.AddressFamily -eq 2 } | ForEach-Object { $_.ServerAddresses })
    $dnsOk = 0
    foreach ($d in $dns) {
        try {
            $r = Resolve-DnsName -Name 'www.microsoft.com' -Server $d -DnsOnly -QuickTimeout -ErrorAction Stop | Where-Object { $_.Type -eq 'A' } | Select-Object -First 1
            Write-TaskLog "DNS $d : résolution externe OK (www.microsoft.com -> $($r.IPAddress))." 'OK'
            $dnsOk++
        }
        catch { Write-TaskLog "DNS $d : échec de résolution ($($_.Exception.Message))." 'ERROR' }
    }
    if ($dns.Count -and -not $dnsOk) { $fail += 'résolution DNS' } elseif ($dnsOk -lt $dns.Count) { $warn += 'un serveur DNS' }
    $cs = Get-CimInstance Win32_ComputerSystem -Property PartOfDomain, Domain -ErrorAction SilentlyContinue
    if ($cs.PartOfDomain) {
        try {
            $srv = @(Resolve-DnsName -Name "_ldap._tcp.dc._msdcs.$($cs.Domain)" -Type SRV -DnsOnly -ErrorAction Stop | Where-Object { $_.Type -eq 'SRV' })
            Write-TaskLog ('Domaine {0} : {1} contrôleur(s) annoncé(s) ({2}).' -f $cs.Domain, $srv.Count, (($srv | Select-Object -First 3 | ForEach-Object { $_.NameTarget }) -join ', ')) 'OK'
            $dc = "$(@($srv)[0].NameTarget)"
            $t = [Net.Sockets.TcpClient]::new(); $ok = $false
            try { $ok = $t.ConnectAsync($dc, 389).Wait(3000) -and $t.Connected } catch {} finally { $t.Dispose() }
            if ($ok) { Write-TaskLog "Contrôleur $dc : port LDAP 389 joignable." 'OK' } else {
                Write-TaskLog "Contrôleur $dc : port LDAP 389 injoignable." 'ERROR'
                $fail += 'contrôleur de domaine'
            }
        } catch {
            Write-TaskLog "Domaine $($cs.Domain) : enregistrements SRV des contrôleurs introuvables ($($_.Exception.Message))." 'ERROR'
            $fail += 'domaine'
        }
    } else { Write-TaskLog 'Domaine : poste hors domaine, test ignoré.' }
    $t = [Net.Sockets.TcpClient]::new(); $ok = $false
    try { $ok = $t.ConnectAsync('www.microsoft.com', 443).Wait(4000) -and $t.Connected } catch {} finally { $t.Dispose() }
    if ($ok) { Write-TaskLog 'Internet : connexion HTTPS (www.microsoft.com:443) OK.' 'OK' } else {
        Write-TaskLog 'Internet : connexion HTTPS (www.microsoft.com:443) impossible.' 'ERROR'
        $fail += 'accès Internet HTTPS'
    }
    try {
        $w = Invoke-WebRequest -Uri 'http://www.msftconnecttest.com/connecttest.txt' -UseBasicParsing -TimeoutSec 6 -ErrorAction Stop
        if ("$($w.Content)".Trim() -eq 'Microsoft Connect Test') { Write-TaskLog 'Test de connectivité Windows (msftconnecttest.com) : OK.' 'OK' }
        else {
            Write-TaskLog 'Test de connectivité Windows : réponse inattendue (portail captif ou proxy filtrant).' 'WARN'
            $warn += 'portail captif ou proxy'
        }
    } catch { Write-TaskLog "Test de connectivité Windows : échec ($($_.Exception.Message))." 'ERROR'; $fail += 'accès HTTP' }
    $px = @(Invoke-Capture "$env:windir\System32\netsh.exe" 'winhttp show proxy' | ForEach-Object { "$_".Trim() } | Where-Object { $_ })
    if ($px) { Write-TaskLog ('Proxy WinHTTP : ' + ($px[-1])) }
    if ($fail.Count) { Write-TaskLog ('Résultat : échec - ' + ($fail -join ', ') + '.') 'ERROR' }
    elseif ($warn.Count) { Write-TaskLog ('Résultat : réseau fonctionnel, à surveiller - ' + ($warn -join ', ') + '.') 'WARN' }
    else { Write-TaskLog 'Résultat : réseau local, DNS et Internet fonctionnels.' 'OK' }
}
function Invoke-Task_StoreReset {
    $pkg = Join-Path $Sync.UserProfile 'AppData\Local\Packages\Microsoft.WindowsStore_8wekyb3d8bbwe'
    if (-not (Test-Path -LiteralPath $pkg)) { Write-TaskLog "Microsoft Store absent du profil ciblé ($pkg)." 'WARN'; return }
    $procs = @(Get-Process -Name 'WinStore.App' -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $Sync.UserSession })
    if ($procs) { $procs | Stop-Process -Force -ErrorAction SilentlyContinue; Start-Sleep -Seconds 1; Write-TaskLog 'Microsoft Store fermé.' }
    $freed = Clear-Folder (Join-Path $pkg 'LocalCache')
    Write-TaskLog ('Cache du Microsoft Store vidé ({0}) : {1}\LocalCache.' -f (Format-Size $freed 'déjà vide'), $pkg) 'OK'
}
function Invoke-Task_GpuReset {
    if ([Environment]::OSVersion.Version.Build -lt 19041) {
        Write-TaskLog 'pnputil /restart-device nécessite Windows 10 2004 (build 19041) ou plus récent.' 'ERROR'
        return
    }
    $devs = @(Get-PnpDevice -Class Display -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -like 'PCI\*' })
    if (-not $devs) { Write-TaskLog 'Aucune carte graphique PCI détectée (machine virtuelle ou affichage de base).' 'WARN'; return }
    foreach ($d in $devs) {
        Write-TaskLog ('{0} - état {1} - {2}' -f $d.FriendlyName, $d.Status, $d.InstanceId)
        $rc = Invoke-Native "$env:windir\System32\pnputil.exe" @('/restart-device', ('"{0}"' -f $d.InstanceId))
        if ($rc -eq 3010) { Write-TaskLog "$($d.FriendlyName) : redémarrage du poste nécessaire pour terminer." 'WARN' }
        elseif ($rc -eq 0) { Write-TaskLog "$($d.FriendlyName) : pilote redémarré." 'OK' }
    }
}
function Invoke-Task_Optimize {
    try {
        $n  = (Get-Partition -DriveLetter $SysLetter | Get-Disk).Number
        $pd = Get-PhysicalDisk | Where-Object { $_.DeviceId -eq "$n" }
        Write-TaskLog "Disque $n - type de support : $(V $pd.MediaType)"
    } catch {}
    Optimize-Volume -DriveLetter $SysLetter -Verbose 4>&1 | ForEach-Object { Write-TaskLog "$_" 'OUT' }
    Write-TaskLog 'Optimisation terminée.' 'OK'
}
'@
