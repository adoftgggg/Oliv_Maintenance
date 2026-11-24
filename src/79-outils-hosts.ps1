# ================= Fichier hosts : blocage pubs / traqueurs (liste StevenBlack, entre 2 repères), édition, sauvegarde
function Read-HostsFile { try { [IO.File]::ReadAllText($HostsFile) } catch { '' } }
# contenu hors bloc de blocage, et bloc (lignes) séparés
function Split-HostsContent([string]$Text) {
    $own = [Collections.Generic.List[string]]::new(); $blk = [Collections.Generic.List[string]]::new(); $in = $false
    foreach ($l in ($Text -split "`r?`n")) {
        if ($l.StartsWith($HostsMarkA)) { $in = $true; [void]$blk.Add($l); continue }
        if ($in) { [void]$blk.Add($l); if ($l.StartsWith($HostsMarkB)) { $in = $false }; continue }
        [void]$own.Add($l)
    }
    @{ Own = (($own -join "`r`n").TrimEnd()); Block = @($blk) }
}
function Write-HostsFile([string]$Own, [string[]]$Block) {
    if (-not (Test-Path -LiteralPath $HostsBackup)) { try { [void][IO.Directory]::CreateDirectory((Split-Path $HostsBackup)); Copy-Item -LiteralPath $HostsFile -Destination $HostsBackup -Force } catch { Write-Ignored 'Sauvegarde du fichier hosts' $_ } }
    $fi = [IO.FileInfo]::new($HostsFile); if ($fi.Exists -and $fi.IsReadOnly) { $fi.IsReadOnly = $false }
    $txt = $Own.TrimEnd() + "`r`n" + $(if ($Block -and $Block.Count) { "`r`n" + ($Block -join "`r`n").TrimEnd() + "`r`n" } else { '' })
    # fichier momentanément ouvert par le service Client DNS (relecture après modification) ou l'antivirus : nouvel essai
    # toutes les 250 ms, 15 s au plus, avant de signaler l'échec
    for ($k = 0; ; $k++) {
        try { [IO.File]::WriteAllText($HostsFile, $txt, [Text.Encoding]::ASCII); break }
        catch [IO.IOException] { if ($k -ge 60) { throw 'fichier hosts occupé par un autre programme depuis 15 s (service Client DNS ou antivirus) : réessayer dans un instant.' }; Start-Sleep -Milliseconds 250 }
    }
    # vidage du cache DNS sans attendre (Clear-DnsClientCache bloquait l'interface pendant la relecture du fichier par le service)
    try { Start-Process -FilePath (Join-Path $env:windir 'System32\ipconfig.exe') -ArgumentList '/flushdns' -WindowStyle Hidden } catch { Write-Ignored 'Vidage du cache DNS' $_ }
}
# entrées personnelles : « IP nom [nom...] [# commentaire] » ; une paire (IP, nom) par nom
function Get-HostsEntry([string]$Own) {
    $i = 0
    foreach ($l in ($Own -split "`r?`n")) {
        $t = $l.Trim()
        if ($t -and -not $t.StartsWith('#') -and $t -match '^(\S+)\s+([^#]+?)\s*(?:#\s*(.*))?$') { [pscustomobject]@{ Ip = $Matches[1]; Names = @($Matches[2].Trim() -split '\s+'); Comment = "$($Matches[3])".Trim(); Line = $i } }
        $i++
    }
}
function Get-HostsPair([string]$Own) { @(foreach ($e in (Get-HostsEntry $Own)) { foreach ($n in $e.Names) { '{0} {1}' -f $e.Ip, $n.ToLower() } }) }
function Get-HostsMeaning([string]$Ip) { $(if ($Ip -in '0.0.0.0', '127.0.0.1', '::', '::1', '0:0:0:0:0:0:0:0') { "bloqué ($Ip)" } else { "redirigé vers $Ip" }) }
# récapitulatif avant écriture : noms ajoutés, retirés, redirigés ailleurs ; $true si confirmé
function Confirm-HostsChange([string]$Before, [string]$After, [string]$Head) {
    $a = @{}; foreach ($x in (Get-HostsPair $Before)) { $p = $x -split ' ', 2; $a[$p[1]] = $p[0] }
    $b = @{}; foreach ($x in (Get-HostsPair $After)) { $p = $x -split ' ', 2; $b[$p[1]] = $p[0] }
    $lines = @()
    foreach ($n in ($b.Keys | Sort-Object)) {
        if (-not $a.ContainsKey($n)) { $lines += '+ ajouté : {0}  ->  {1}' -f $n, (Get-HostsMeaning $b[$n]) }
        elseif ($a[$n] -ne $b[$n]) { $lines += '~ modifié : {0}  ->  {1} (avant : {2})' -f $n, (Get-HostsMeaning $b[$n]), (Get-HostsMeaning $a[$n]) }
    }
    foreach ($n in ($a.Keys | Sort-Object)) { if (-not $b.ContainsKey($n)) { $lines += '- retiré : {0}  (était {1})' -f $n, (Get-HostsMeaning $a[$n]) } }
    if (-not $lines.Count) {
        if ($Before.Trim() -ceq $After.Trim()) { return $false }
        $lines = @('Aucune entrée modifiée : seuls les commentaires ou la mise en forme changent.')
    }
    $ToolsUI.HostsLast = $lines
    (Show-Dialog "$Head`n`nModifications du fichier hosts :" 'Question' @(@{ T = 'Annuler'; V = $false; C = $true }, @{ T = 'Enregistrer'; V = $true; S = 'PrimaryBtn' }) $lines) -eq $true
}
function Save-HostsOwn([string]$Own, $Block, [string]$What) {
    try {
        Write-HostsFile $Own $Block
        Write-UiLog ("Fichier hosts modifié ($What) : " + (@($ToolsUI.HostsLast) -join ' ; ')) 'OK'; Add-SessionEvent 'Réglages' 'Fichier hosts' $What 'ok'
    } catch { Show-Info "Écriture du fichier hosts impossible (antivirus ?).`n`n$($_.Exception.Message)" 'Error' }
    Update-HostsCard
}
function Update-HostsCard {
    $b = $ToolsUI.HostsBody; $b.Children.Clear()
    $p = Split-HostsContent (Read-HostsFile)
    $nb = 0; foreach ($x in $p.Block) { if ($x.StartsWith('0.0.0.0 ') -or $x.StartsWith("0.0.0.0`t")) { $nb += @($x.Trim() -split '\s+').Count - 1 } }
    $date = $(if ($p.Block.Count -and $p.Block[0] -match '\((\d{2}/\d{2}/\d{4})\)') { $Matches[1] } else { '' })
    [void](Add-KV $b 'Blocage pubs et traqueurs' $(if ($nb) { '{0:N0} domaines bloqués (liste du {1})' -f $nb, $date } else { 'désactivé' }) $(if ($nb) { 'OkFgBrush' } else { '' }))
    if ($nb) {
        # mise à jour de la liste : automatique (tâche hebdomadaire) ou manuelle (bouton Mettre à jour la liste)
        $auto = [bool](Get-HostsAutoTask); $last = Get-HostsAutoLast
        $nx = $(if ($auto) { Get-HostsAutoNext } else { '' })
        [void](Add-KV $b 'Mise à jour de la liste' $(if ($auto) { 'automatique, chaque semaine' + $(if ($nx) { "  ·  prochaine mise à jour programmée $nx" } else { '' }) + $(if ($last) { "`ndernier passage : $last" } else { '' }) } else { 'manuelle (bouton Mettre à jour la liste)' }) $(if ($auto) { '' } else { 'WarnFgBrush' }))
        $ToolsUI.HostsAuto = Add-SettingsChoice $b 'Actualisation de la liste' 'La liste StevenBlack évolue chaque semaine (nouveaux domaines de pub et de pistage). Automatique : tâche planifiée hebdomadaire, rattrapée au démarrage si le PC était éteint.' ([ordered]@{ On = 'Automatique'; Off = 'Manuelle' }) $(if ($auto) { 'On' } else { 'Off' }) {
            param($s, $e)
            $on = "$($s.DataContext)" -eq 'On'
            try { Set-HostsAuto $on; Write-UiLog $(if ($on) { "Fichier hosts : mise à jour automatique hebdomadaire de la liste activée (tâche \Oliv_Maintenance\$HostsTaskName)." } else { 'Fichier hosts : mise à jour automatique de la liste désactivée.' }) 'APP' }
            catch { Show-Info "Réglage impossible.`n`n$($_.Exception.Message)" 'Error' }
            Update-HostsCard
        }
    }
    try { $fi = [IO.FileInfo]::new($HostsFile); [void](Add-KV $b 'Fichier hosts' ('{0}  ·  modifié le {1:dd/MM/yyyy HH:mm}' -f (Format-SizeUi $fi.Length), $fi.LastWriteTime)) } catch { Write-Ignored 'Date du fichier hosts' $_ }
    # entrées personnelles : une ligne par entrée (nom, effet, commentaire), suppression à l'unité
    $ents = @(Get-HostsEntry $p.Own)
    $h = New-Text $(if ($ents.Count) { 'Mes entrées ({0})' -f $ents.Count } else { 'Mes entrées : aucune' }); $h.FontWeight = [Windows.FontWeights]::SemiBold; $h.Margin = New-Thickness 46 10 10 4
    [void]$b.Children.Add($h)
    foreach ($e in ($ents | Select-Object -First 12)) {
        $del = New-ToolIconButton 0xE74D 'Retirer cette entrée' $e { param($s, $e2) Remove-HostsEntry $s.Tag }
        $sub = (Get-HostsMeaning $e.Ip) + $(if ($e.Comment) { '  ·  ' + $e.Comment } else { '' })
        $r = New-ToolRow ($e.Names -join ', ') $sub @($del) $null; [void]$b.Children.Add($r.Row)
    }
    if ($ents.Count -gt 12) { $t = New-Text ('+ {0} autres entrées (Modifier le texte)' -f ($ents.Count - 12)) 'Muted'; $t.Margin = New-Thickness 46 2 10 0; [void]$b.Children.Add($t) }
    $btns = @()
    $btns += $(if ($nb) { New-ToolButton 'Mettre à jour la liste' $null { Start-HostsBlock $true } 'PrimaryBtn' } else { New-ToolButton 'Bloquer pubs et traqueurs' $null { Start-HostsBlock $true } 'PrimaryBtn' })
    if ($nb) { $btns += New-ToolButton 'Retirer le blocage' $null { Start-HostsBlock $false } }
    $btns += New-ToolButton 'Ajouter une entrée' $null { Add-HostsEntry }
    $btns += New-ToolButton 'Modifier le texte' $null { Edit-HostsFile }
    if (Test-Path -LiteralPath $HostsBackup) { $btns += New-ToolButton 'Restaurer l''original' $null { Restore-HostsFile } }
    [void]$b.Children.Add((New-ToolBar $btns))
}
function Add-HostsEntry {
    $v = Read-ToolInput "Ajouter une entrée au fichier hosts`n`nBloquer un site : adresse 0.0.0.0. Nom local (NAS, serveur) : son adresse IP, ex. 192.168.1.20." @(@{ L = 'Nom (ex. nas.maison ou publicite.exemple.com)'; V = '' }, @{ L = 'Adresse IP'; V = '0.0.0.0' }, @{ L = 'Commentaire (facultatif)'; V = '' }) 'Suivant' 600
    if (-not $v) { return }
    $n = "$($v[0])".Trim().ToLower(); $ip = "$($v[1])".Trim(); $cm = "$($v[2])".Trim()
    $ipo = $null
    if ($n -notmatch '^[a-z0-9]([a-z0-9\-\.]*[a-z0-9])?$') { Show-Info 'Nom invalide : lettres, chiffres, tirets et points uniquement.' 'Warn'; return }
    if (-not [Net.IPAddress]::TryParse($ip, [ref]$ipo)) { Show-Info 'Adresse IP invalide.' 'Warn'; return }
    $p = Split-HostsContent (Read-HostsFile)
    $new = $p.Own.TrimEnd() + "`r`n" + ("{0}`t{1}{2}" -f $ip, $n, $(if ($cm) { "`t# $cm" } else { '' }))
    if (Confirm-HostsChange $p.Own $new 'Ajouter cette entrée ?') { Save-HostsOwn $new $p.Block "ajout de $n" }
}
function Remove-HostsEntry($E) {
    $p = Split-HostsContent (Read-HostsFile)
    $ls = [Collections.Generic.List[string]]::new([string[]]($p.Own -split "`r?`n"))
    if ($E.Line -ge $ls.Count) { Update-HostsCard; return }
    $ls.RemoveAt($E.Line); $new = $ls -join "`r`n"
    if (Confirm-HostsChange $p.Own $new 'Retirer cette entrée ?') { Save-HostsOwn $new $p.Block ('retrait de ' + ($E.Names -join ', ')) }
}
$HostsScript = @'
# tout le travail en arrière-plan, avancement réel en 3 étapes : téléchargement 0-70 % (octets reçus / taille annoncée),
# analyse 70-90 % (lignes traitées, dédoublonnage par HashSet : l'ancien Select-Object -Unique, quadratique, prenait plusieurs
# minutes sur 80 000 lignes), écriture 90-100 % (fusion avec les entrées personnelles, écriture, vidage du cache DNS)
$r = @{}
$P = $Sync.HostsProg = @{ Done = 0; Total = 0; Step = 'dl'; Pct = 0.0; N = 0; Of = 0 }; $t0j = [DateTime]::Now
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $rq = [Net.HttpWebRequest]::Create($Sync.HostsUrl); $rq.UserAgent = 'Oliv_Maintenance'; $rq.Timeout = 30000; $rq.ReadWriteTimeout = 30000
    $rq.AutomaticDecompression = [Net.DecompressionMethods]::None
    $rs = $rq.GetResponse()
    try {
        $P.Total = [long]$rs.ContentLength
        $st = $rs.GetResponseStream(); $ms = New-Object IO.MemoryStream; $buf = New-Object byte[] 262144
        while (($n = $st.Read($buf, 0, $buf.Length)) -gt 0) { $ms.Write($buf, 0, $n); $P.Done = $ms.Length; if ($P.Total -gt 0) { $P.Pct = 70.0 * $ms.Length / $P.Total } }
        $t = [Text.Encoding]::UTF8.GetString($ms.ToArray())
    } finally { $rs.Close() }
    $P.Step = 'parse'; $P.Pct = 70.0
    $lines = $t.Split([char]10); $P.Of = $lines.Length
    $set = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase); $l = [Collections.Generic.List[string]]::new()
    $re = [regex]'^0\.0\.0\.0\s+([^\s#]+)'
    for ($i = 0; $i -lt $lines.Length; $i++) {
        $m = $re.Match($lines[$i])
        if ($m.Success) { $d = $m.Groups[1].Value; if ($d -ne '0.0.0.0' -and $set.Add($d)) { $l.Add($d) } }
        if (($i -band 4095) -eq 0) { $P.N = $i; $P.Pct = 70.0 + 20.0 * $i / $lines.Length }
    }
    if ($l.Count -lt 1000) { throw "liste inattendue ($($l.Count) entrées)" }
    $P.Step = 'write'; $P.Pct = 90.0
    # fichier actuel : entrées personnelles gardées, ancien bloc comparé (ajouts / retraits)
    $txt = try { [IO.File]::ReadAllText($Sync.HostsPath) } catch { '' }
    $own = [Collections.Generic.List[string]]::new(); $old = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase); $in = $false
    foreach ($x in $txt.Split([char]10)) {
        $x = $x.TrimEnd([char]13)
        if ($x.StartsWith($Sync.HostsA)) { $in = $true; continue }
        if ($in) { if ($x.StartsWith($Sync.HostsB)) { $in = $false } elseif ($x.StartsWith('0.0.0.0')) { foreach ($d in @($x -split '\s+' | Select-Object -Skip 1)) { if ($d) { [void]$old.Add($d) } } }; continue }
        $own.Add($x)
    }
    $plus = 0; foreach ($d in $set) { if (-not $old.Contains($d)) { $plus++ } }
    $moins = 0; foreach ($d in $old) { if (-not $set.Contains($d)) { $moins++ } }
    if (-not [IO.File]::Exists($Sync.HostsBak)) { try { [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Sync.HostsBak)); [IO.File]::Copy($Sync.HostsPath, $Sync.HostsBak, $true) } catch { $null = $_ } }
    $fi = [IO.FileInfo]::new($Sync.HostsPath); if ($fi.Exists -and $fi.IsReadOnly) { $fi.IsReadOnly = $false }
    $sb = [Text.StringBuilder]::new(($own -join "`r`n").TrimEnd()); [void]$sb.Append("`r`n`r`n")
    [void]$sb.Append($Sync.HostsA + ' (' + (Get-Date).ToString('dd/MM/yyyy') + ') - source : ' + $Sync.HostsUrl + " - ne pas modifier`r`n")
    # 9 domaines par ligne (format « compressé » de StevenBlack) : 9 fois moins de lignes à relire par le service Client DNS
    # de Windows, qui ralentissait fortement avec une entrée par ligne
    for ($i = 0; $i -lt $l.Count; $i += 9) { [void]$sb.Append('0.0.0.0 ').Append(($l.GetRange($i, [math]::Min(9, $l.Count - $i)) -join ' ')).Append("`r`n") }
    [void]$sb.Append($Sync.HostsB + "`r`n")
    # écriture par blocs de 256 Ko : avancement réel 90 > 99 %
    $bytes = [Text.Encoding]::ASCII.GetBytes($sb.ToString()); $tw = [DateTime]::Now
    # fichier momentanément ouvert par le service Client DNS ou l'antivirus : nouvel essai toutes les 250 ms, 30 s au plus
    $fs = $null
    for ($k = 0; -not $fs; $k++) {
        try { $fs = [IO.FileStream]::new($Sync.HostsPath, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::Read) }
        catch [IO.IOException] { if ($k -ge 120) { throw 'fichier hosts occupé par un autre programme depuis 30 s (service Client DNS ou antivirus).' }; $P.Step = 'busy'; Start-Sleep -Milliseconds 250 }
    }
    $P.Step = 'write'
    try { for ($o = 0; $o -lt $bytes.Length; $o += 262144) { $fs.Write($bytes, $o, [math]::Min(262144, $bytes.Length - $o)); $P.Pct = 90.0 + 9.0 * ($o / $bytes.Length) } } finally { $fs.Dispose() }
    $r.WriteS = ([DateTime]::Now - $tw).TotalSeconds
    # cache DNS : vidage lancé sans attendre (Clear-DnsClientCache attendait que le service Client DNS ait relu tout le
    # fichier, plusieurs minutes) ; le service relit de lui-même le fichier hosts modifié
    try { Start-Process -FilePath (Join-Path $env:windir 'System32\ipconfig.exe') -ArgumentList '/flushdns' -WindowStyle Hidden } catch { $null = $_ }
    $P.Pct = 100.0
    $r.Count = $l.Count; $r.Plus = $plus; $r.Moins = $moins; $r.OldCount = $old.Count; $r.TotalS = ([DateTime]::Now - $t0j).TotalSeconds
} catch { $r.Error = $_.Exception.Message }
$Sync.HostsDl = $r
'@
# ---- mise à jour automatique de la liste de blocage : tâche planifiée hebdomadaire (compte SYSTEM, rattrapée au
# démarrage si le PC était éteint, seulement avec un réseau) ; script dans ProgramData\Oliv_Maintenance\Outils (écriture
# réservée aux administrateurs), journal hosts-maj.log à côté. Sans effet si le blocage a été retiré.
$HostsTaskName = 'Mise à jour du blocage pubs et traqueurs (hosts)'
$HostsAutoDir = Join-Path $env:ProgramData 'Oliv_Maintenance\Outils'
$HostsAutoScript = Join-Path $HostsAutoDir 'hosts-maj.ps1'
$HostsAutoCode = @'
$h = Join-Path $env:windir 'System32\drivers\etc\hosts'; $log = Join-Path $PSScriptRoot 'hosts-maj.log'
$A = '# >>> Oliv_Maintenance : blocage pubs et traqueurs'; $B = '# <<< Oliv_Maintenance'; $url = 'https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts'
function Write-Line([string]$M) { Add-Content -LiteralPath $log -Value ('{0:yyyy-MM-dd HH:mm} {1}' -f (Get-Date), $M) -Encoding UTF8 }
try {
    $txt = [IO.File]::ReadAllText($h)
    if (-not $txt.Contains($A)) { Write-Line 'blocage non actif : rien à faire'; exit 0 }
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $t = (New-Object Net.WebClient).DownloadString($url)
    $set = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase); $l = [Collections.Generic.List[string]]::new(); $re = [regex]'^0\.0\.0\.0\s+([^\s#]+)'
    foreach ($x in $t.Split([char]10)) { $m = $re.Match($x); if ($m.Success) { $d = $m.Groups[1].Value; if ($d -ne '0.0.0.0' -and $set.Add($d)) { $l.Add($d) } } }
    if ($l.Count -lt 1000) { throw "liste inattendue ($($l.Count) entrées)" }
    $own = [Collections.Generic.List[string]]::new(); $in = $false
    foreach ($x in ($txt -split "`r?`n")) { if ($x.StartsWith($A)) { $in = $true; continue }; if ($in) { if ($x.StartsWith($B)) { $in = $false }; continue }; [void]$own.Add($x) }
    $g9 = for ($i = 0; $i -lt $l.Count; $i += 9) { '0.0.0.0 ' + ($l.GetRange($i, [math]::Min(9, $l.Count - $i)) -join ' ') }
    $blk = @("$A ($((Get-Date).ToString('dd/MM/yyyy'))) - source : $url - ne pas modifier") + @($g9) + @($B)
    $fi = [IO.FileInfo]::new($h); if ($fi.IsReadOnly) { $fi.IsReadOnly = $false }
    $txt2 = (($own -join "`r`n").TrimEnd() + "`r`n`r`n" + ($blk -join "`r`n") + "`r`n")
    for ($k = 0; ; $k++) { try { [IO.File]::WriteAllText($h, $txt2, [Text.Encoding]::ASCII); break } catch [IO.IOException] { if ($k -ge 120) { throw }; Start-Sleep -Milliseconds 250 } }
    try { Start-Process -FilePath (Join-Path $env:windir 'System32\ipconfig.exe') -ArgumentList '/flushdns' -WindowStyle Hidden } catch { $null = $_ }
    Write-Line ('liste mise à jour : {0} domaines bloqués' -f $l.Count)
} catch { Write-Line ('échec : ' + $_.Exception.Message); exit 1 }
'@
function Get-HostsAutoTask { try { $svc = New-Object -ComObject Schedule.Service; $svc.Connect(); $svc.GetFolder('\Oliv_Maintenance').GetTask($HostsTaskName) } catch { $null } }
function Set-HostsAuto([bool]$On) {
    $svc = New-Object -ComObject Schedule.Service; $svc.Connect()
    $f = $null; try { $f = $svc.GetFolder('\Oliv_Maintenance') } catch { if ($On) { $f = $svc.GetFolder('\').CreateFolder('Oliv_Maintenance') } }
    if (-not $On) { if ($f) { try { $f.DeleteTask($HostsTaskName, 0) } catch { $null = $_ } }; return }
    [void][IO.Directory]::CreateDirectory($HostsAutoDir); [IO.File]::WriteAllText($HostsAutoScript, $HostsAutoCode, [Text.UTF8Encoding]::new($true))
    $td = $svc.NewTask(0)
    $td.RegistrationInfo.Description = 'Met à jour chaque semaine la liste StevenBlack/hosts ajoutée au fichier hosts par Oliv_Maintenance (Outils > Fichier hosts).'
    $td.Settings.StartWhenAvailable = $true; $td.Settings.RunOnlyIfNetworkAvailable = $true; $td.Settings.ExecutionTimeLimit = 'PT30M'
    $td.Settings.DisallowStartIfOnBatteries = $false; $td.Settings.StopIfGoingOnBatteries = $false
    $tr = $td.Triggers.Create(2); $tr.DaysInterval = 7; $tr.StartBoundary = (Get-Date).Date.AddDays(1).AddHours(12).ToString('yyyy-MM-ddTHH:mm:ss')
    $td.Principal.UserId = 'S-1-5-18'; $td.Principal.LogonType = 5; $td.Principal.RunLevel = 1
    $ac = $td.Actions.Create(0); $ac.Path = Join-Path $env:windir 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $ac.Arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $HostsAutoScript
    [void]$f.RegisterTaskDefinition($HostsTaskName, $td, 6, 'SYSTEM', $null, 5)
}
function Get-HostsAutoLast { try { $l = @(Get-Content -LiteralPath (Join-Path $HostsAutoDir 'hosts-maj.log') -Encoding UTF8 -Tail 1); "$($l[-1])" } catch { '' } }
function Start-HostsBlock([bool]$On) {
    if (-not $On) {
        if (-not (Confirm-Action 'Retirer le blocage des pubs et traqueurs du fichier hosts ?')) { return }
        try { $p = Split-HostsContent (Read-HostsFile); Write-HostsFile $p.Own @(); Write-UiLog 'Fichier hosts : blocage des pubs et traqueurs retiré.' 'OK' } catch { Show-Info "Écriture du fichier hosts impossible.`n`n$($_.Exception.Message)" 'Error' }
        try { Set-HostsAuto $false } catch { Write-Ignored 'Tâche de mise à jour du fichier hosts' $_ }
        Update-HostsCard; return
    }
    if ($BgJobs.ContainsKey('Hosts')) { return }
    if (-not (Test-Path -LiteralPath $HostsBackup) -and -not (Confirm-Action "Bloquer les pubs, traqueurs et sites malveillants connus dans le fichier hosts ?`n`nListe StevenBlack/hosts (environ 80 000 domaines, mise à jour régulièrement), ajoutée à la fin du fichier sans toucher à vos entrées ; sauvegarde du fichier d'origine dans le dossier d'état. Un site qui ne s'affiche plus se débloque en retirant le blocage.")) { return }
    $Sync.HostsUrl = $HostsListUrl; $Sync.HostsDl = $null; $Sync.HostsProg = $null
    $Sync.HostsPath = $HostsFile; $Sync.HostsBak = $HostsBackup; $Sync.HostsA = $HostsMarkA; $Sync.HostsB = $HostsMarkB
    # avancement réel : octets reçus sur la taille annoncée par le serveur, temps écoulé ; barre indéterminée sans taille annoncée
    $ToolsUI.HostsBody.Children.Clear()
    $sp = [Windows.Controls.StackPanel]::new(); $sp.Margin = New-Thickness 38 0 10 12
    $t = New-Text 'Téléchargement de la liste de blocage : connexion...' 'Muted'
    $pb = [Windows.Controls.ProgressBar]::new(); $pb.Height = 6; $pb.Margin = New-Thickness 0 6 0 0; $pb.Maximum = 100; $pb.IsIndeterminate = $true
    [void]$sp.Children.Add($t); [void]$sp.Children.Add($pb); [void]$ToolsUI.HostsBody.Children.Add($sp)
    $t0 = [DateTime]::Now
    if ($ToolsUI.HostsTimer) { $ToolsUI.HostsTimer.Stop() }
    $tm = [Windows.Threading.DispatcherTimer]::new(); $tm.Interval = [TimeSpan]::FromMilliseconds(250)
    $tm.Add_Tick({
        $g = $Sync.HostsProg; $el = [int]([DateTime]::Now - $t0).TotalSeconds
        if (-not $g) { return }
        $pc = [math]::Min([double]100, [double]$g.Pct)
        $what = $(switch ($g.Step) {
                'dl' { $(if ($g.Total -gt 0) { 'téléchargement {0} / {1}' -f (Format-SizeUi $g.Done '0 Ko'), (Format-SizeUi $g.Total) } else { 'téléchargement {0} reçus (taille non annoncée)' -f (Format-SizeUi $g.Done '0 Ko') }) }
                'parse' { 'analyse de la liste ({0:N0} / {1:N0} lignes)' -f $g.N, $g.Of }
                'busy' { 'fichier hosts occupé (service Client DNS ou antivirus), nouvel essai...' }
                default { 'écriture du fichier hosts' } })
        $pb.IsIndeterminate = ($g.Step -eq 'dl' -and $g.Total -le 0); $pb.Value = $pc
        $t.Text = 'Blocage pubs et traqueurs : {0:N0} %  ·  {1}  ·  {2} s' -f $pc, $what, $el
    }.GetNewClosure())
    $ToolsUI.HostsTimer = $tm; $tm.Start()
    Start-BgJob 'Hosts' $HostsScript
}
# prochaine exécution de la tâche hebdomadaire : « le 24/11 à 12h » (minutes affichées si non nulles)
function Get-HostsAutoNext {
    $tk = Get-HostsAutoTask; if (-not $tk -or -not $tk.Enabled) { return '' }
    try { $d = [DateTime]$tk.NextRunTime } catch { return '' }
    if ($d.Year -lt 2000) { return '' }
    'le {0:dd/MM} à {0:HH}h{1}' -f $d, $(if ($d.Minute) { '{0:mm}' -f $d } else { '' })
}
$BgJobDone['Hosts'] = {
    if ($ToolsUI.HostsTimer) { $ToolsUI.HostsTimer.Stop(); $ToolsUI.HostsTimer = $null }
    $r = $Sync.HostsDl
    if (-not $r -or $r.Error) { $m = $(if ($r) { $r.Error } else { 'tâche interrompue' }); Write-UiLog "Fichier hosts : liste de blocage non appliquée - $m" 'ERROR'; Show-Info "Mise à jour de la liste de blocage impossible.`n`n$m" 'Error'; Update-HostsCard; return }
    $chg = $(if ($r.OldCount) { '{0:N0} domaines ajoutés, {1:N0} retirés depuis la liste précédente' -f $r.Plus, $r.Moins } else { 'blocage activé' })
    Write-UiLog ('Fichier hosts : {0:N0} domaines de pubs et traqueurs bloqués ({1}) en {2:N0} s (écriture du fichier : {3:N1} s).' -f $r.Count, $chg, $r.TotalS, $r.WriteS) 'OK'
    # 1re activation : mise à jour automatique hebdomadaire mise en place d'office (désactivable dans la carte)
    if (-not $r.OldCount -and -not (Get-HostsAutoTask)) { try { Set-HostsAuto $true; Write-UiLog 'Fichier hosts : mise à jour automatique hebdomadaire de la liste activée.' 'APP' } catch { Write-Ignored 'Tâche de mise à jour du fichier hosts' $_ } }
    $nx = Get-HostsAutoNext
    $sz = try { Format-SizeUi ([IO.FileInfo]::new($HostsFile).Length) } catch { '?' }
    Show-Info ("Liste de blocage à jour : {0:N0} domaines bloqués (fichier hosts : {3}).`n`n{1}. Vos entrées personnelles ne sont pas modifiées.`n`n{2}" -f $r.Count, ($chg.Substring(0, 1).ToUpper() + $chg.Substring(1)), $(if ($nx) { "Prochaine mise à jour programmée $nx." } else { 'Mise à jour automatique désactivée : prochaine mise à jour manuelle (bouton Mettre à jour la liste).' }), $sz) 'Ok'
    Add-SessionEvent 'Réglages' 'Blocage pubs et traqueurs (hosts)' ('{0:N0} domaines' -f $r.Count) 'ok'
    Update-HostsCard
}
function Edit-HostsFile {
    $p = Split-HostsContent (Read-HostsFile)
    $v = Read-ToolInput "Fichier hosts : mes entrées (texte)`n`nUne entrée par ligne : adresse IP, espace, nom (ex. 192.168.1.20 nas.maison ; 0.0.0.0 site-a-bloquer.com). Lignes commençant par # = commentaires. La liste de blocage, si elle est active, est conservée à part. Récapitulatif des changements avant enregistrement." @(@{ V = $p.Own; M = $true; H = 380 }) 'Suivant' 860
    if (-not $v) { return }
    $new = "$($v[0])"
    if (Confirm-HostsChange $p.Own $new 'Enregistrer ces changements ?') { Save-HostsOwn $new $p.Block 'édition du texte' }
}
function Restore-HostsFile {
    if (-not (Confirm-Action "Remettre le fichier hosts d'origine (sauvegardé avant la 1re modification par l'application) ?`n`nVos entrées et le blocage ajoutés depuis sont retirés.")) { return }
    try {
        $fi = [IO.FileInfo]::new($HostsFile); if ($fi.Exists -and $fi.IsReadOnly) { $fi.IsReadOnly = $false }
        Copy-Item -LiteralPath $HostsBackup -Destination $HostsFile -Force; try { Start-Process -FilePath (Join-Path $env:windir 'System32\ipconfig.exe') -ArgumentList '/flushdns' -WindowStyle Hidden } catch { Write-Ignored 'Vidage du cache DNS' $_ }
        Write-UiLog 'Fichier hosts d''origine restauré.' 'OK'
    } catch { Show-Info "Restauration impossible.`n`n$($_.Exception.Message)" 'Error' }
    Update-HostsCard
}

