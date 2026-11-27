# ================= Fichier hosts : entrées personnelles (noms locaux, sites bloqués à la main), édition, sauvegarde ; ancien
# blocage par liste (versions précédentes, entre 2 repères) détecté et retiré sur demande, remplacé par le DNS AdGuard
# hosts lu et réécrit en ANSI (page de code du système, lecture de Windows) : octets des lignes de l'utilisateur gardés à
# l'identique (avant : lecture UTF-8 puis écriture ASCII, tout caractère accentué d'un commentaire devenait « ? »)
# fichier absent : contenu vide ; illisible (verrouillé par l'antivirus ou le service Client DNS, droits) : erreur levée,
# jamais un contenu vide (une modification réécrivait alors le fichier avec la seule nouvelle entrée, toutes les autres perdues)
function Read-HostsFile { if (-not [IO.File]::Exists($HostsFile)) { return '' }; [IO.File]::ReadAllText($HostsFile, [Text.Encoding]::Default) }
# contenu découpé pour une modification ; lecture impossible : message, Journal, $null (aucune modification)
function Read-HostsPart {
    try { Split-HostsContent (Read-HostsFile) }
    catch {
        Write-UiLog "Fichier hosts illisible : $($_.Exception.Message)" 'ERROR'
        Show-Info "Lecture du fichier hosts impossible (fichier ouvert par l'antivirus ou le service Client DNS ?) : aucune modification faite. Réessayer dans un instant.`n`n$($_.Exception.Message)" 'Error'
        $null
    }
}
# contenu hors bloc de blocage, et bloc (lignes) séparés
# Repère de fin absent (retiré à la main) : avant, tout ce qui suivait le repère de début était classé dans le bloc, et les
# entrées personnelles placées après étaient effacées par « Retirer l'ancien blocage ». Bloc limité alors au repère et aux
# lignes qui suivent jusqu'à la dernière ligne « 0.0.0.0 ... » (commentaires et lignes vides du milieu de la liste compris),
# avant la première entrée qui n'est pas un blocage ; le reste est gardé.
function Split-HostsContent([string]$Text) {
    $own = [Collections.Generic.List[string]]::new(); $blk = [Collections.Generic.List[string]]::new()
    $ls = @($Text -split "`r?`n"); $i = 0
    while ($i -lt $ls.Count) {
        $l = $ls[$i]
        if (-not $l.StartsWith($HostsMarkA)) { [void]$own.Add($l); $i++; continue }
        $end = -1; for ($j = $i + 1; $j -lt $ls.Count; $j++) { if ($ls[$j].StartsWith($HostsMarkB)) { $end = $j; break } }
        if ($end -lt 0) {
            $last = $i
            for ($j = $i + 1; $j -lt $ls.Count; $j++) {
                $t = $ls[$j].Trim()
                # en-tête de la liste (localhost, broadcasthost, ip6-...) : traversé sans fin du bloc
                if ($t -match '^0\.0\.0\.0\s') { $last = $j }
                elseif ($t -and -not $t.StartsWith('#') -and $t -notmatch '^\S+\s+(localhost(\.localdomain)?|local|broadcasthost|ip6-\S+)\s*$') { break }
            }
            $end = $last
        }
        for ($j = $i; $j -le $end; $j++) { [void]$blk.Add($ls[$j]) }
        $i = $end + 1
    }
    @{ Own = (($own -join "`r`n").TrimEnd()); Block = @($blk) }
}
function Write-HostsFile([string]$Own, [string[]]$Block) {
    if (-not (Test-Path -LiteralPath $HostsBackup)) { try { [void][IO.Directory]::CreateDirectory((Split-Path $HostsBackup)); Copy-Item -LiteralPath $HostsFile -Destination $HostsBackup -Force } catch { Write-Ignored 'Sauvegarde du fichier hosts' $_ } }
    $fi = [IO.FileInfo]::new($HostsFile); if ($fi.Exists -and $fi.IsReadOnly) { $fi.IsReadOnly = $false }
    $txt = $Own.TrimEnd() + "`r`n" + $(if ($Block -and $Block.Count) { "`r`n" + ($Block -join "`r`n").TrimEnd() + "`r`n" } else { '' })
    # fichier momentanément ouvert par le service Client DNS (relecture après modification) ou l'antivirus : nouvel essai
    # toutes les 250 ms, 15 s au plus, avant de signaler l'échec
    # écriture atomique (fichier temporaire substitué, droits du fichier conservés) : une coupure ne laisse jamais un hosts tronqué
    for ($k = 0; ; $k++) {
        try { Write-FileAtomic $HostsFile $txt ([Text.Encoding]::Default) -NoBackup; break }
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
# DNS AdGuard (94.140.14.14 : blocage des pubs et traqueurs côté serveur) réglé sur toutes les cartes réseau actives ; ancien
# blocage par liste encore présent dans le fichier hosts retiré au passage
function Switch-HostsToAdGuard {
    if ($BgJobs.ContainsKey('Dns')) { Show-Info 'Un changement de DNS est déjà en cours.'; return }
    $dom = try { [bool](Get-CimInstance Win32_ComputerSystem -Property PartOfDomain -ErrorAction Stop).PartOfDomain } catch { $false }
    if ($dom) { Show-Info 'Poste joint à un domaine : ses serveurs DNS doivent rester ceux du domaine (DNS AdGuard refusé).' 'Warn'; return }
    $p = Read-HostsPart; if (-not $p) { return }; $old = $p.Block.Count -gt 0
    $msg = "Régler le DNS AdGuard ?`n`nLes serveurs DNS de toutes les cartes réseau actives passent sur AdGuard (94.140.14.14), qui bloque les pubs, traqueurs et sites malveillants connus pour tout le PC. Retour possible dans Sécurité > Réseau > Serveurs DNS (Automatique)." +
        $(if ($old) { "`n`nL'ancien blocage par liste est aussi retiré du fichier hosts (vos entrées personnelles sont gardées) : coupure réseau possible une dernière fois (environ 5 minutes), le service Client DNS de Windows relit le fichier." } else { '' }) +
        "`n`nUn navigateur réglé sur son propre DNS sécurisé (DoH) contourne AdGuard : le laisser sur « Automatique » ou le désactiver."
    if (-not (Confirm-Action $msg)) { return }
    if ($old) {
        try { Write-HostsFile $p.Own @(); Write-UiLog 'Fichier hosts : ancien blocage des pubs et traqueurs retiré (passage au DNS AdGuard).' 'OK' }
        catch { Write-UiLog "Fichier hosts : $($_.Exception.Message)" 'ERROR'; Show-Info "Écriture du fichier hosts impossible.`n`n$($_.Exception.Message)" 'Error'; Update-HostsCard; return }
    }
    # DNS : ligne du réglage « Serveurs DNS » utilisée si elle existe (état « en cours », relecture à la fin), sinon application directe
    try {
        if (-not $Lazy.Done) { New-DeferredPage }
        $row = @($TweakRows | Where-Object { $_.Tweak -and $_.Tweak.Id -eq 'DnsProvider' })[0]
        if ($row) { Invoke-TweakChange $row 'AdGuard' } else { Set-DnsProvider 'AdGuard' }
        Write-UiLog 'DNS : passage sur AdGuard lancé (toutes les cartes réseau actives).' 'APP'
        Add-SessionEvent 'Outils' 'Blocage des pubs' 'DNS AdGuard' 'ok'
        Show-Toast 'DNS AdGuard en cours d''application'
    } catch { Write-UiLog "DNS AdGuard : $($_.Exception.Message)" 'ERROR'; Show-Info "Réglage du DNS AdGuard impossible.`n`n$($_.Exception.Message)" 'Error' }
    Update-HostsCard
}
function Update-HostsCard {
    $b = $ToolsUI.HostsBody; $b.Children.Clear()
    $p = try { Split-HostsContent (Read-HostsFile) } catch {
        # illisible : rien d'affiché comme « aucune entrée » (trompeur), aucun bouton de modification ; relecture sur demande
        $w = New-Text ("Fichier hosts illisible pour l'instant (ouvert par l'antivirus ou le service Client DNS ?) : $($_.Exception.Message)")
        $w.TextWrapping = 'Wrap'; $w.Margin = New-Thickness 46 6 18 6; $w.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'WarnFgBrush'); [void]$b.Children.Add($w)
        [void]$b.Children.Add((New-ToolBar @(New-ToolButton 'Relire' $null { Update-HostsCard })))
        return
    }
    $nb = 0; foreach ($x in $p.Block) { if ($x.StartsWith('0.0.0.0 ') -or $x.StartsWith("0.0.0.0`t")) { $nb += @($x.Trim() -split '\s+').Count - 1 } }
    # blocage des pubs et traqueurs : par le DNS AdGuard (Sécurité > Réseau > Serveurs DNS), plus par le fichier hosts
    $dns = try { Get-DnsProvider } catch { '' }
    [void](Add-KV $b 'Blocage pubs et traqueurs' $(if ($dns -eq 'AdGuard') { 'actif : DNS AdGuard' } else { 'inactif (DNS AdGuard non réglé)' }) $(if ($dns -eq 'AdGuard') { 'OkFgBrush' } else { '' }))
    if ($nb) {
        # ancien blocage par liste (versions précédentes) : relu à chaque démarrage par le service Client DNS (mesuré sur un poste :
        # 140 s de processeur, session inutilisable et sans réseau ~3 min)
        $w = New-Text ('Ancien blocage par liste encore présent dans le fichier ({0:N0} domaines) : à chaque démarrage, le service Client DNS de Windows doit le relire en entier, le PC rame et reste sans réseau plusieurs minutes. À retirer : le DNS AdGuard bloque les pubs et traqueurs sans ce coût.' -f $nb)
        $w.TextWrapping = 'Wrap'; $w.Margin = New-Thickness 46 6 18 6; $w.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'WarnFgBrush'); [void]$b.Children.Add($w)
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
    if ($nb) { $btns += New-ToolButton 'Retirer l''ancien blocage et passer au DNS AdGuard' $null { Switch-HostsToAdGuard } 'PrimaryBtn'; $btns += New-ToolButton 'Retirer l''ancien blocage' $null { Remove-HostsLegacyBlock } }
    elseif ($dns -ne 'AdGuard') { $btns += New-ToolButton 'Régler le DNS AdGuard' $null { Switch-HostsToAdGuard } 'PrimaryBtn' }
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
    $p = Read-HostsPart; if (-not $p) { return }
    $new = $p.Own.TrimEnd() + "`r`n" + ("{0}`t{1}{2}" -f $ip, $n, $(if ($cm) { "`t# $cm" } else { '' }))
    if (Confirm-HostsChange $p.Own $new 'Ajouter cette entrée ?') { Save-HostsOwn $new $p.Block "ajout de $n" }
}
function Remove-HostsEntry($E) {
    $p = Read-HostsPart; if (-not $p) { return }
    $ls = [Collections.Generic.List[string]]::new([string[]]($p.Own -split "`r?`n"))
    if ($E.Line -ge $ls.Count) { Update-HostsCard; return }
    $ls.RemoveAt($E.Line); $new = $ls -join "`r`n"
    if (Confirm-HostsChange $p.Own $new 'Retirer cette entrée ?') { Save-HostsOwn $new $p.Block ('retrait de ' + ($E.Names -join ', ')) }
}
# ---- ancien blocage par liste StevenBlack (versions précédentes) : retiré de l'application. Le DNS AdGuard le remplace (le fichier
# hosts de plusieurs dizaines de milliers de domaines était relu à chaque démarrage par le service Client DNS : PC bloqué et
# sans réseau plusieurs minutes). Bloc encore présent dans le fichier : signalé dans la carte, retiré sur demande ; tâche
# planifiée de mise à jour hebdomadaire et son script supprimés au lancement.
$HostsTaskName = 'Mise à jour du blocage pubs et traqueurs (hosts)'
function Remove-HostsLegacyTask {
    try {
        $svc = New-Object -ComObject Schedule.Service; $svc.Connect()
        $f = $null; try { $f = $svc.GetFolder('\Oliv_Maintenance') } catch { $f = $null }
        if ($f) { $t = $null; try { $t = $f.GetTask($HostsTaskName) } catch { $t = $null }; if ($t) { $f.DeleteTask($HostsTaskName, 0); Write-UiLog 'Ancienne tâche de mise à jour de la liste hosts supprimée.' 'APP' } }
    } catch { Write-Ignored 'Ancienne tâche de mise à jour du fichier hosts' $_ }
    foreach ($x in 'hosts-maj.ps1', 'hosts-maj.log') { try { $fp = Join-Path $env:ProgramData "Oliv_Maintenance\Outils\$x"; if (Test-Path -LiteralPath $fp) { Remove-Item -LiteralPath $fp -Force } } catch { Write-Ignored 'Ancien script de mise à jour du fichier hosts' $_ } }
}
[void]$Window.Dispatcher.BeginInvoke([Action]{ Remove-HostsLegacyTask }, [Windows.Threading.DispatcherPriority]::ApplicationIdle)
function Remove-HostsLegacyBlock {
    if (-not (Confirm-Action "Retirer l'ancien blocage des pubs et traqueurs du fichier hosts ?`n`nVos entrées personnelles sont gardées.`n`nCoupure réseau possible une dernière fois (environ 5 minutes) : le service Client DNS de Windows doit relire le fichier.")) { return }
    $p = Read-HostsPart; if (-not $p) { return }
    try { Write-HostsFile $p.Own @(); Write-UiLog 'Fichier hosts : ancien blocage des pubs et traqueurs retiré.' 'OK'; Show-Toast 'Ancien blocage retiré du fichier hosts' }
    catch { Write-UiLog "Fichier hosts : $($_.Exception.Message)" 'ERROR'; Show-Info "Écriture du fichier hosts impossible.`n`n$($_.Exception.Message)" 'Error' }
    Update-HostsCard
}
function Edit-HostsFile {
    $p = Read-HostsPart; if (-not $p) { return }
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

