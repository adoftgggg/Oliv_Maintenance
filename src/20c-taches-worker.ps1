# Tâches du worker, partie 3 : winget, Microsoft Store, logiciels, applications, exécution des tâches
$WorkerScript += "`n" + @'
# winget : alias du compte, sinon exécutable du paquet App Installer (contexte administrateur où l'alias manque). Plus de
# recherche par le PATH : un dossier du PATH modifiable sans élévation, placé avant WindowsApps, faisait lancer un autre
# winget.exe en administrateur
function Find-Winget {
    $c = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'; if (Test-Path -LiteralPath $c) { return $c }
    $pk = Get-AppxPackage -AllUsers -Name Microsoft.DesktopAppInstaller -ErrorAction SilentlyContinue | Sort-Object Version -Descending | Select-Object -First 1
    if ($pk) { $c = Join-Path $pk.InstallLocation 'winget.exe'; if (Test-Path -LiteralPath $c) { return $c } }
    $null
}
# Mise à jour des logiciels cochés dans la fenêtre Logiciels : winget upgrade silencieux, un à la fois
# Ligne de sortie de winget -> étape et pourcentage de l'installation en cours (sortie en anglais ou en français selon Windows) :
# « 12.0 MB / 85.3 MB » = téléchargement (octets reçus / taille) ; « 42% » = avancement ; vérification du hachage ; installation.
# Renvoie $null pour une ligne sans information d'avancement.
# Taille de l'installeur de la dernière version : URL lue dans « winget show » (« Installer Url » / « URL du programme
# d'installation »), puis en-tête Content-Length (requête HEAD, 8 s au plus). 0 si inconnue.
function Get-WingetInstallerSize([string]$Id) {
    try {
        $wg = Find-Winget; if (-not $wg) { return [double]0 }
        $out = & $wg show -e --id $Id --accept-source-agreements --disable-interactivity 2>$null
        $u = @($out | Where-Object { $_ -match '(?i)(installer url|url.{0,30}install\S*)\s*:\s*(https?://\S+)' } | ForEach-Object { $Matches[2] } | Select-Object -First 1)
        if (-not $u.Count) { return [double]0 }
        $r = Invoke-WebRequest -Uri $u[0] -Method Head -UseBasicParsing -TimeoutSec 8 -MaximumRedirection 5 -ErrorAction Stop
        $len = "$($r.Headers['Content-Length'])"; if ($len) { [double]$len } else { [double]0 }
    } catch { [double]0 }
}
function ConvertFrom-WingetLine([string]$Line) {
    $t = "$Line".Trim(); if (-not $t) { return $null }
    $u = @{ KB = 1KB; MB = 1MB; GB = 1GB; Ko = 1KB; Mo = 1MB; Go = 1GB }
    if ($t -match '(\d+(?:[.,]\d+)?)\s*(KB|MB|GB|Ko|Mo|Go)\s*/\s*(\d+(?:[.,]\d+)?)\s*(KB|MB|GB|Ko|Mo|Go)') {
        $a = [double]::Parse(($Matches[1] -replace ',', '.'), [Globalization.CultureInfo]::InvariantCulture) * $u[$Matches[2]]
        $b = [double]::Parse(($Matches[3] -replace ',', '.'), [Globalization.CultureInfo]::InvariantCulture) * $u[$Matches[4]]
        return @{ Phase = 'téléchargement'; Pct = $(if ($b -gt 0) { [int][math]::Min([double]100, [math]::Floor(100 * $a / $b)) } else { 0 }) }
    }
    # barre de progression seule (« 42% », reste de la barre retiré) : pourcentage de l'étape en cours (téléchargement, ou
    # déploiement d'un paquet MSIX pendant l'installation)
    if ($t.Length -le 12 -and $t -match '(\d{1,3})\s*%') { return @{ Phase = $null; Pct = [int][math]::Min(100, [int]$Matches[1]) } }
    if ($t -match '(?i)hash|hachage') { return @{ Phase = 'vérification'; Pct = -1 } }
    # « Successfully installed » / « Installé correctement » : installation terminée
    if ($t -match '(?i)success\w*\s+install|install\S*\s+(correctement|avec succ)') { return @{ Phase = 'installation'; Pct = 100 } }
    if ($t -match '(?i)^downloading|^t\S{1,3}l\S{1,3}chargement') { return @{ Phase = 'téléchargement'; Pct = 0 } }
    # « Starting package install... » / « Démarrage de l'installation du package... » / « Installing... » : accents et
    # apostrophe typographique ignorés (sortie lue en UTF-8 ou en page de codes selon la version de winget)
    if ($t -match '(?i)install') { return @{ Phase = 'installation'; Pct = -1 } }
    $null
}
# ligne de commande : argument vide ou contenant une espace entre guillemets (« --override "--quiet --force" » était
# passé en 3 arguments, override faux) ; guillemet intérieur retiré, comme pour le lancement sans élévation
function Join-ProcessArg([string[]]$A) { @($A | ForEach-Object { $x = "$_" -replace '"', ''; if ($x -eq '' -or $x -match '\s') { '"' + $x + '"' } else { $x } }) -join ' ' }
function Invoke-SoftTool([string]$Exe, [string[]]$A, [string]$Name, [scriptblock]$OnLine) {
    $line = Join-ProcessArg $A
    Write-TaskLog ('> {0} {1}' -f $Name, $line) 'CMD'
    $psi = [Diagnostics.ProcessStartInfo]::new($Exe, $line); $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true; $psi.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
    $p = [Diagnostics.Process]::Start($psi)
    $Sync.ChildPid = $p.Id; $Sync.ChildName = $Name.ToUpper()
    try {
        while ($null -ne ($l = $p.StandardOutput.ReadLine())) {
            $t = ($l -replace '[\u2580-\u259F\u2500-\u257F]', '').Trim()
            if ($OnLine -and $t) { & $OnLine $t }
            if ($t -and $t -notmatch '^[-\\|/]$' -and $t -notmatch '^\d+([.,]\d+)?\s*(KB|MB|GB|Ko|Mo|Go)\s*/' -and $t -notmatch '^Progress:') { Write-TaskLog $t 'OUT' }
        }
        $p.WaitForExit()
    } finally { $Sync.ChildPid = $null; $Sync.ChildName = $null }
    $p.ExitCode
}
# winget lancé dans le contexte de l'utilisateur de la session, sans élévation : obligatoire pour les logiciels installés
# dans le profil (winget refuse de les désinstaller en administrateur, 0x8A15007D, et leurs installeurs - Squirrel de
# Discord... - doivent tourner sous le compte propriétaire du dossier). Tâche planifiée à usage unique (principal
# interactif, RunLevel Limited, console masquée par conhost --headless), sortie lue en direct dans un fichier du dossier
# temporaire de l'utilisateur, code de retour écrit par le script. Tâche et fichiers supprimés à la fin.
function Invoke-SoftToolAsUser([string[]]$A, [string]$Name, [scriptblock]$OnLine) {
    Write-TaskLog ('> {0} {1}  (compte {2}, sans élévation)' -f $Name, ($A -join ' '), $Sync.UserName) 'CMD'
    $tn = 'Oliv_Maintenance-winget-' + [guid]::NewGuid().ToString('N').Substring(0, 12)
    $dir = Join-Path $Sync.UserProfile ('AppData\Local\Temp\' + $tn)
    $out = Join-Path $dir 'out.txt'; $rcf = Join-Path $dir 'rc.txt'
    $rc = -1
    try {
        [void][IO.Directory]::CreateDirectory($dir)
        $q = @($A | ForEach-Object { '"' + ("$_" -replace '%', '%%' -replace '"', '') + '"' }) -join ' '
        $cmd = "@echo off`r`nwinget $q >`"$out`" 2>&1`r`n>`"$rcf.tmp`" echo %ERRORLEVEL%`r`nmove /y `"$rcf.tmp`" `"$rcf`" >nul`r`n"
        # page de code OEM (850 en France) : cmd lit les .cmd ainsi ; en ASCII un profil accentué (C:\Users\Frédéric) devenait « Fr?d?ric »
        [IO.File]::WriteAllText((Join-Path $dir 'run.cmd'), $cmd, [Text.Encoding]::GetEncoding([Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage))
        $act = New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\conhost.exe" -Argument ('--headless "{0}\System32\cmd.exe" /d /c "{1}"' -f $env:SystemRoot, (Join-Path $dir 'run.cmd'))
        $pr = New-ScheduledTaskPrincipal -UserId $Sync.UserName -LogonType Interactive -RunLevel Limited
        $set = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Hours 2) -Hidden
        [void](Register-ScheduledTask -TaskName $tn -TaskPath '\Oliv_Maintenance\' -Action $act -Principal $pr -Settings $set -Force -ErrorAction Stop)
        Start-ScheduledTask -TaskName $tn -TaskPath '\Oliv_Maintenance\' -ErrorAction Stop
        $Sync.ChildName = $Name.ToUpper()
        $pos = 0L; $rest = ''; $t0 = [DateTime]::Now; $k = 0
        $read = {
            if (-not [IO.File]::Exists($out)) { return }
            $fs = [IO.FileStream]::new($out, 'Open', 'Read', 'ReadWrite, Delete')
            try {
                if ($fs.Length -le $pos) { return }
                [void]$fs.Seek($pos, 'Begin'); $buf = [byte[]]::new($fs.Length - $pos); $nb = $fs.Read($buf, 0, $buf.Length); $pos += $nb
                $txt = $rest + [Text.Encoding]::UTF8.GetString($buf, 0, $nb)
                $parts = $txt -split '[\r\n]'; $rest = $parts[-1]
                foreach ($l in $parts[0..($parts.Count - 2)]) {
                    $t = ($l -replace '[\u2580-\u259F\u2500-\u257F]', '').Trim()
                    if ($OnLine -and $t) { & $OnLine $t }
                    if ($t -and $t -notmatch '^[-\\|/]$' -and $t -notmatch '^\d+([.,]\d+)?\s*(KB|MB|GB|Ko|Mo|Go)\s*/' -and $t -notmatch '^Progress:') { Write-TaskLog $t 'OUT' }
                }
            } finally { $fs.Dispose() }
        }
        while (-not [IO.File]::Exists($rcf)) {
            if ($Sync.Cancel) { Stop-ScheduledTask -TaskName $tn -TaskPath '\Oliv_Maintenance\' -ErrorAction SilentlyContinue; break }
            # état de la tâche relu toutes les 2 s seulement (requête CIM), sortie lue toutes les 300 ms
            $k++; if ($k % 7) { . $read; Start-Sleep -Milliseconds 300; continue }
            $st = "$((Get-ScheduledTask -TaskName $tn -TaskPath '\Oliv_Maintenance\' -ErrorAction SilentlyContinue).State)"
            if ($st -ne 'Running' -and ([DateTime]::Now - $t0).TotalSeconds -gt 15 -and -not [IO.File]::Exists($rcf)) {
                Start-Sleep -Milliseconds 500
                if (-not [IO.File]::Exists($rcf)) { Write-TaskLog ('winget sans élévation : tâche terminée sans code de retour (état {0}, dernier résultat 0x{1:X8}). Session de {2} ouverte ?' -f $st, [int64]((Get-ScheduledTaskInfo -TaskName $tn -TaskPath '\Oliv_Maintenance\' -ErrorAction SilentlyContinue).LastTaskResult), $Sync.UserName) 'ERROR' }
                break
            }
            . $read; Start-Sleep -Milliseconds 300
        }
        . $read
        $t = ($rest -replace '[\u2580-\u259F\u2500-\u257F]', '').Trim()
        if ($t) { if ($OnLine) { & $OnLine $t }; Write-TaskLog $t 'OUT' }
        if ([IO.File]::Exists($rcf)) { $v = 0; if ([int]::TryParse(([IO.File]::ReadAllText($rcf)).Trim(), [ref]$v)) { $rc = $v } }
    } catch {
        Write-TaskLog ('winget sans élévation impossible : {0}' -f $_.Exception.Message) 'ERROR'
    } finally {
        $Sync.ChildName = $null
        try { Unregister-ScheduledTask -TaskName $tn -TaskPath '\Oliv_Maintenance\' -Confirm:$false -ErrorAction Stop } catch { Write-Ignored 'Suppression de la tâche winget' $_ }
        try { [IO.Directory]::Delete($dir, $true) } catch { Write-Ignored 'Dossier temporaire winget' $_ }
    }
    $rc
}
# winget pour un logiciel : contexte de l'utilisateur si installé dans son profil (User), sinon administrateur
function Invoke-SoftWinget($X, [string]$Wg, [string[]]$A, [scriptblock]$OnLine) {
    if ($X.User) { Invoke-SoftToolAsUser $A 'winget' $OnLine } else { Invoke-SoftTool $Wg $A 'winget' $OnLine }
}
# État par logiciel publié pour la fenêtre Logiciels ($Sync.SoftRun.Items[Id]) :
# State = wait | run | ok | fail | skip ; Phase / Pct pendant l'installation ; Code = code de retour winget
function Set-SoftItem([string]$Id, [hashtable]$Values) { $it = $Sync.SoftRun.Items[$Id]; if ($it) {
    foreach ($k in $Values.Keys) { $it[$k] = $Values[$k] }
} }
# Applications du Microsoft Store : mise à jour demandée au Store pour chaque application, par son nom de famille de paquet
# (AppInstallManager.UpdateAppByPackageFamilyNameAsync). Le Store ne publie pas la version disponible sans lancer la mise à
# jour : résultat nul = déjà à jour, application inconnue du Store = hors Store, sinon installation suivie jusqu'à la fin
# puis version relue (Get-AppxPackage). Demandes envoyées ensemble (réponses en parallèle), état de chaque ligne en direct.
# Compte de l'utilisateur qui exécute l'application (le Store installe pour ce compte).
function Get-StoreAppVersion([string]$Pfn) {
    try {
        $nm = ($Pfn -split '_')[0]
        "$(@(Get-AppxPackage -Name $nm -ErrorAction Stop | Sort-Object Version -Descending)[0].Version)"
    } catch {
        Write-Ignored 'Version d''une application du Store' $_
        ''
    }
}
function Add-StoreHistory($X, [string]$Now) {
    try { $rec = @{ Date = (Get-Date).ToString('o'); Name = "$($X.Name)"; Id = "$($X.Pfn)"; From = "$($X.From)"; To = $Now; Ok = $true; Code = 0; User = "$env:USERNAME"; Computer = "$env:COMPUTERNAME" }
          [IO.File]::AppendAllText((Join-Path $Sync.LogRoot '_etat\logiciels-historique.jsonl'), (ConvertTo-Json -Compress -InputObject $rec) + [Environment]::NewLine, [Text.UTF8Encoding]::new($false)) } catch { Write-Ignored 'Historique des mises à jour de logiciels' $_ }
}
# Désinstallation (winget uninstall de l'identifiant installé : « ARP\... » = désinstalleur déclaré par l'éditeur,
# « MSIX\... » = paquet) ou réinstallation : désinstallation puis installation de la dernière version (paquet winget, ou
# application du Store retrouvée par le catalogue du Store), arrêtée si la désinstallation échoue.
function Invoke-SoftRemoveItem($X, $Wg) {
    $id = "$($X.Id)"; $re = $X.Mode -eq 'reinstall'
    $common = @('--silent', '--accept-source-agreements', '--disable-interactivity')
    $run = {
        param([string[]]$A, [string]$Phase)
        Set-SoftItem $id @{ Phase = $Phase; Pct = -1 }
        Invoke-SoftWinget $X $Wg $A {
            param($t)
            $it = $Sync.SoftRun.Items[$id]
            if ($t -notmatch '^[-\\|/]$') { [void]$it.Out.Add($t); if ($it.Out.Count -gt 40) { $it.Out.RemoveAt(0) } }
        }
    }
    $rc = & $run (@('uninstall', '-e', '--id', "$($X.LocalId)") + $common) 'désinstallation'
    # désinstalleur de l'éditeur qui refuse le mode silencieux (Battle.net : code de sortie 4...) : relancé en mode
    # interactif, sa fenêtre s'affiche pour que l'utilisateur confirme
    if ($rc -ne 0 -and -not $Sync.Cancel) {
        Write-TaskLog ('Désinstallation silencieuse refusée (code {0}, 0x{0:X8}) : désinstalleur de l''éditeur relancé en mode interactif, confirmer dans sa fenêtre.' -f $rc) 'WARN'
        $rc = & $run @('uninstall', '-e', '--id', "$($X.LocalId)", '--interactive', '--accept-source-agreements') 'désinstallation (fenêtre de l''éditeur)'
    }
    # réinstallation impossible par désinstallation : dernière version installée par-dessus l'existante (install --force)
    $over = $false
    if ($rc -ne 0 -and $re -and "$($X.Src)" -eq 'winget' -and -not $Sync.Cancel) {
        Write-TaskLog 'Désinstallation en échec : dernière version installée par-dessus l''existante (winget install --force).' 'WARN'
        $rc = & $run @('install', '-e', '--id', $id, '--force', '--silent', '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity') 'installation par-dessus'
        $over = $rc -eq 0
    }
    $note = ''; $state = 'ok'
    # réussite par-dessus : suite commune (état de la ligne et historique des logiciels, que le « return » d'avant sautait)
    if ($over) { $note = 'réinstallé (par-dessus)'; Write-TaskLog 'Réinstallé par-dessus l''installation existante.' 'OK' }
    elseif ($rc -ne 0) {
        $state = 'fail'
        Write-TaskLog ('Désinstallation en échec : code {0} (0x{0:X8}){1}.' -f $rc, $(if ($re) { ', logiciel non réinstallé' } else { '' })) 'WARN'
    } elseif (-not $re) {
        # contrôle : logiciel encore inventorié par winget (désinstalleur de l'éditeur ouvert à part, installation pour un
        # autre compte...) = signalé, ligne gardée ; absent = ligne retirée de la liste dès la fin de la tâche
        $still = $false
        try { Import-Module Microsoft.WinGet.Client -ErrorAction Stop; $still = @(Get-WinGetPackage -Id "$($X.LocalId)" -MatchOption Equals -ErrorAction Stop).Count -gt 0 } catch { Write-Ignored 'Contrôle après désinstallation' $_ }
        if ($still) { $note = 'encore présent'; Write-TaskLog 'Désinstallation lancée (code 0), mais le logiciel est toujours inventorié : terminer son désinstalleur s''il est ouvert, ou le désinstaller depuis Paramètres > Applications.' 'WARN' }
        else { $note = 'désinstallé'; Set-SoftItem $id @{ Removed = $true }; Write-TaskLog 'Désinstallé (absent de l''inventaire).' 'OK' }
    } else {
        Write-TaskLog 'Désinstallé, réinstallation...'
        $pkg = "$id"; $src = @()
        if ($X.Pfn) {
            $pkg = ''
            try {
                $u = 'https://displaycatalog.mp.microsoft.com/v7.0/products/lookup?alternateId=PackageFamilyName&value={0}&market=FR&languages=fr-FR&fieldsTemplate=Details' -f [uri]::EscapeDataString("$($X.Pfn)")
                $pkg = "$(@((Invoke-RestMethod -Uri $u -TimeoutSec 10 -UseBasicParsing -ErrorAction Stop).Products)[0].ProductId)"
            } catch { Write-Ignored 'Microsoft Store (identifiant du produit)' $_ }
            $src = @('-s', 'msstore')
        }
        if (-not $pkg) { $rc = -1; $state = 'fail'; Write-TaskLog 'Désinstallé, mais réinstallation impossible : application introuvable dans le catalogue du Microsoft Store.' 'ERROR' }
        else {
            $rc = & $run (@('install', '-e', '--id', $pkg) + $src + @('--accept-package-agreements') + $common) 'réinstallation'
            if ($rc -eq 0) {
                $now = ''
                if (-not $X.Pfn) { try { Import-Module Microsoft.WinGet.Client -ErrorAction Stop; $now = "$(@(Get-WinGetPackage -Id $pkg -MatchOption Equals -ErrorAction Stop)[0].InstalledVersion)" } catch { Write-Ignored 'Version réinstallée' $_ } }
                $note = $(if ($now) { "réinstallé ($now)" } else { 'réinstallé' }); Write-TaskLog ('Réinstallé{0}.' -f $(if ($now) { " (version $now)" } else { '' })) 'OK'
            } else {
                $state = 'fail'
                Write-TaskLog ('Désinstallé, mais réinstallation en échec : code {0} (0x{0:X8}). Logiciel absent du poste : le réinstaller manuellement.' -f $rc) 'ERROR'
            }
        }
    }
    if ($state -eq 'ok') { $Sync.SoftRun.Ok++; Set-SoftItem $id @{ State = 'ok'; Note = $note; NoteBrush = $(if ($note -eq 'encore présent') { 'WarnFgBrush' } else { 'OkFgBrush' }); Phase = ''; Pct = 100; End = [DateTime]::Now } }
    else { $Sync.SoftRun.Fail++; Set-SoftItem $id @{ State = 'fail'; Code = $rc; End = [DateTime]::Now } }
    try {
        $rec = @{ Date = (Get-Date).ToString('o'); Name = "$($X.Name)"; Id = $id; From = "$($X.From)"; To = $(if ($note) { $note } elseif ($re) { 'réinstallation' } else { 'désinstallation' }); Ok = ($state -eq 'ok'); Code = [int64]$rc; User = "$env:USERNAME"; Computer = "$env:COMPUTERNAME" }
        if ($state -ne 'ok') { $rec.Out = @($Sync.SoftRun.Items[$id].Out) }
        [IO.File]::AppendAllText((Join-Path $Sync.LogRoot '_etat\logiciels-historique.jsonl'), (ConvertTo-Json -Compress -InputObject $rec) + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
    } catch { Write-Ignored 'Historique des logiciels' $_ }
}
# programmes qui bloquent le logiciel, juste avant son installeur : processus du même nom que le logiciel, puis tout
# processus qui a un fichier du dossier d'installation ouvert ou chargé (exe, DLL) d'après le gestionnaire de redémarrage
# de Windows (3 000 fichiers au plus)
function Find-SoftLocker($Lock) {
    $it = $Sync.SoftRun.Items["$($Sync.SoftRun.Cur)"]; $it.Phase = 'recherche des programmes ouverts'
    $found = @{}; $base = "$($Lock.Base)"
    $dirs = @($Lock.Dirs | Where-Object { $_ } | ForEach-Object { "$_".TrimEnd('\') + '\' })
    # 1) processus du même nom que le logiciel, ou dont l'exécutable est dans son dossier d'installation (Git : git-bash,
    #    mintty, bash, git... aucun ne s'appelle « Git ») : chemin de l'image, rapide (pas d'ouverture des fichiers du dossier)
    foreach ($p in [Diagnostics.Process]::GetProcesses()) {
        try {
            if ($p.Id -eq $PID -or $p.Id -le 4) { continue }
            $hit = $base.Length -ge 3 -and $p.ProcessName -eq $base
            if (-not $hit -and $dirs.Count) { $img = $null; try { $img = $p.MainModule.FileName } catch { $null = $_ }; if ($img) { foreach ($d in $dirs) { if ($img.StartsWith($d, [StringComparison]::OrdinalIgnoreCase)) { $hit = $true; break } } } }
            if ($hit) { $found[$p.Id] = @{ Pid = $p.Id; Name = "$($p.ProcessName).exe" } }
        } finally { $p.Dispose() }
    }
    # 2) DLL du logiciel chargées par un autre programme (extension de l'Explorateur, superposition injectée) : gestionnaire de
    #    redémarrage de Windows limité aux exe / dll des 2 premiers niveaux (400 fichiers au plus : au-delà il pouvait
    #    tourner plusieurs minutes sans rien fermer)
    if ($dirs.Count) {
        try {
            $files = @(foreach ($d in $dirs) { Get-ChildItem -LiteralPath $d -Depth 1 -File -Force -Include '*.exe', '*.dll' -ErrorAction SilentlyContinue | Select-Object -First 400 | ForEach-Object { $_.FullName } })
            if ($files.Count) {
                foreach ($lp in @([_OlivM.FileLock]::Lockers([string[]]$files))) {
                    if ($lp -eq $PID -or $found.ContainsKey($lp)) { continue }
                    $pr = Get-Process -Id $lp -ErrorAction SilentlyContinue
                    if ($pr) { $found[$lp] = @{ Pid = $lp; Name = "$($pr.ProcessName).exe" } }
                }
            }
        } catch { Write-Ignored 'Programmes qui bloquent le dossier du logiciel' $_ }
    }
    $it.Phase = $(if ($found.Count) { 'fermeture de ' + ((@($found.Values | ForEach-Object { $_.Name }) | Select-Object -Unique) -join ', ') } else { '' })
    @($found.Values)
}
# processus du logiciel fermés avant son installeur : fermeture normale demandée (fenêtre), puis forcée au bout de 8 s
function Close-SoftProc($List) {
    $Sync.SoftRun.Items["$($Sync.SoftRun.Cur)"].Phase = 'fermeture du logiciel'
    # jamais de processus du système ou de la session Windows (fermés de force = déconnexion, écran noir ou arrêt du poste),
    # ni hors de la session de l'utilisateur
    $crit = 'System', 'Idle', 'Registry', 'smss', 'csrss', 'wininit', 'winlogon', 'services', 'lsass', 'lsaiso', 'svchost', 'dwm', 'explorer', 'sihost', 'fontdrvhost', 'ctfmon', 'taskhostw', 'RuntimeBroker', 'StartMenuExperienceHost', 'ShellExperienceHost', 'SearchHost', 'TextInputHost', 'MsMpEng', 'NisSrv', 'SecurityHealthService', 'audiodg', 'spoolsv', 'conhost', 'powershell'
    $live = @(foreach ($c in $List) { if ($c) { Get-Process -Id $c.Pid -ErrorAction SilentlyContinue | Where-Object { $_.Id -ne $PID -and $crit -notcontains $_.ProcessName -and $_.SessionId -eq $Sync.UserSession } } })
    if (-not $live.Count) { return }
    foreach ($p in $live) { try { [void]$p.CloseMainWindow() } catch { Write-Ignored 'Fermeture du logiciel' $_ } }
    $t0 = [DateTime]::Now
    while (([DateTime]::Now - $t0).TotalSeconds -lt 8 -and @($live | Where-Object { -not $_.HasExited }).Count) { Start-Sleep -Milliseconds 300; foreach ($p in $live) { $p.Refresh() } }
    $left = @($live | Where-Object { -not $_.HasExited })
    foreach ($p in $left) { try { Stop-Process -Id $p.Id -Force -ErrorAction Stop } catch { Write-Ignored 'Fermeture forcée du logiciel' $_ } }
    Write-TaskLog ('Fermés avant l''opération (bloquaient le dossier du logiciel) : {0}{1}.' -f ((@($live | ForEach-Object { $_.ProcessName }) | Select-Object -Unique) -join ', '), $(if ($left.Count) { " - $($left.Count) fermé(s) de force" } else { '' }))
    Start-Sleep -Milliseconds 800
}
function Invoke-StoreUpdate($List, [double]$P0 = 0, [double]$P1 = 100) {
    [void][Reflection.Assembly]::LoadWithPartialName('System.Runtime.WindowsRuntime')
    $mt = $null; $itT = $null
    try {
        $mt = [Windows.ApplicationModel.Store.Preview.InstallControl.AppInstallManager, Windows.ApplicationModel.Store.Preview.InstallControl, ContentType = WindowsRuntime]
        $itT = [Windows.ApplicationModel.Store.Preview.InstallControl.AppInstallItem, Windows.ApplicationModel.Store.Preview.InstallControl, ContentType = WindowsRuntime]
    } catch { Write-Ignored 'Microsoft Store (types WinRT)' $_ }
    if (-not $mt -or -not $itT) {
        Write-TaskLog 'Microsoft Store : interface de mise à jour (AppInstallManager) indisponible sur ce poste.' 'ERROR'
        foreach ($x in $List) { Set-SoftItem "$($x.Id)" @{ State = 'fail'; Code = 0; End = [DateTime]::Now } }
        return
    }
    $asTask = @([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0].MakeGenericMethod($itT)
    $mgr = [Activator]::CreateInstance($mt)
    $req = @{}
    foreach ($x in $List) {
        Set-SoftItem "$($x.Id)" @{ State = 'run'; Phase = 'vérification'; Pct = -1 }
        try { $req["$($x.Id)"] = $asTask.Invoke($null, @($mgr.UpdateAppByPackageFamilyNameAsync("$($x.Pfn)"))) } catch { $req["$($x.Id)"] = $_.Exception }
    }
    $pending = @{}; $nUp = 0; $nOk = 0; $nNo = 0; $nKo = 0; $done = 0
    # réponses attendues 2 min en tout (pas 2 min par application) ; Task.Result après un délai dépassé bloquait sans fin
    $limit = [DateTime]::Now.AddMinutes(2)
    foreach ($x in $List) {
        $id = "$($x.Id)"; $t = $req[$id]; $item = $null; $err = $null
        if ($t -is [Exception]) { $err = $t }
        else {
            try {
                $ms = [int][math]::Max([double]0, ($limit - [DateTime]::Now).TotalMilliseconds)
                if ($t.Wait($ms)) { $item = $t.Result } else { $err = [TimeoutException]::new('pas de réponse du Store en 2 minutes') }
            }
            catch { $err = $_.Exception }
        }
        if ($err) { while ($err.InnerException) { $err = $err.InnerException } }
        $done++; $Sync.TaskPct = [int]($P0 + ($P1 - $P0) * 0.5 * $done / [math]::Max([double]1, $List.Count))
        if ($err -is [IO.FileNotFoundException]) {
            $nNo++
            Set-SoftItem $id @{ State = 'ok'; Note = 'hors Store'; NoteBrush = 'MutedBrush'; Phase = ''; End = [DateTime]::Now }
        }
        elseif ($err) {
            $nKo++
            Set-SoftItem $id @{ State = 'fail'; Code = $err.HResult; End = [DateTime]::Now }
            Write-TaskLog ('{0} : {1}' -f $x.Name, $err.Message) 'WARN'
        }
        elseif ($null -eq $item) {
            # rien à installer : version relue, la mise à jour a pu être posée entre-temps par Windows (mises à jour
            # automatiques du Store, déclenchées parfois dès la recherche)
            $now = Get-StoreAppVersion $x.Pfn
            if ($now -and $x.From -and $now -ne "$($x.From)") {
                $nUp++
                Set-SoftItem $id @{ State = 'ok'; Note = ('mis à jour ({0} > {1})' -f $x.From, $now); NoteBrush = 'OkFgBrush'; Phase = ''; Pct = 100; To = $now; End = [DateTime]::Now }
                Write-TaskLog ('{0} : mis à jour par le Store ({1} > {2}).' -f $x.Name, $x.From, $now) 'OK'
                Add-StoreHistory $x $now
            }
            else { $nOk++; Set-SoftItem $id @{ State = 'ok'; Note = 'à jour'; NoteBrush = 'MutedBrush'; Phase = ''; End = [DateTime]::Now } }
        }
        else {
            $pending[$id] = @{ Item = $item; X = $x }
            Set-SoftItem $id @{ Phase = 'mise à jour trouvée' }
            Write-TaskLog ('{0} : mise à jour trouvée par le Store, installation...' -f $x.Name)
        }
    }
    # installations en cours : avancement réel de chacune (téléchargement / installation, pourcentage), 30 min au plus
    $t0 = [DateTime]::Now; $tot = $pending.Count
    while ($pending.Count -and ([DateTime]::Now - $t0).TotalMinutes -lt 30 -and -not $Sync.Cancel) {
        foreach ($id in @($pending.Keys)) {
            $a = $pending[$id]; $s = $null; try { $s = $a.Item.GetCurrentStatus() } catch { Write-Ignored 'Microsoft Store (état de l''installation)' $_ }
            if (-not $s) { continue }
            $st = "$($s.InstallState)"
            Set-SoftItem $id @{ Phase = $(switch ($st) { 'Downloading' { 'téléchargement' } 'Installing' { 'installation' } 'Pending' { 'en file d''attente' } 'Starting' { 'démarrage' } 'AcquiringLicense' { 'licence' } default { "Store : $st" } }); Pct = [int]$s.PercentComplete }
            if ($st -notin 'Completed', 'Canceled', 'Error') { continue }
            $pending.Remove($id)
            if ($st -eq 'Completed') {
                $now = Get-StoreAppVersion $a.X.Pfn
                $nUp++; Set-SoftItem $id @{ State = 'ok'; Note = $(if ($now) { 'mis à jour ({0} > {1})' -f $a.X.From, $now } else { 'mis à jour' }); NoteBrush = 'OkFgBrush'; Phase = ''; Pct = 100; To = $now; End = [DateTime]::Now }
                Write-TaskLog ('{0} : mis à jour{1}.' -f $a.X.Name, $(if ($now) { " ($($a.X.From) > $now)" } else { '' })) 'OK'
                Add-StoreHistory $a.X $now
            } else {
                $nKo++; $hr = 0; try {
                    if ($s.ErrorCode) { $hr = [int]$s.ErrorCode.HResult }
                } catch { Write-Ignored 'Microsoft Store (code d''erreur)' $_ }
                Set-SoftItem $id @{ State = 'fail'; Code = $hr; End = [DateTime]::Now }; Write-TaskLog ('{0} : {1} (0x{2:X8}).' -f $a.X.Name, $st, $hr) 'WARN'
            }
        }
        $Sync.TaskPct = [int]($P0 + ($P1 - $P0) * (0.5 + 0.5 * ($tot - $pending.Count) / [math]::Max([double]1, $tot)))
        Start-Sleep -Milliseconds 500
    }
    foreach ($id in @($pending.Keys)) { Set-SoftItem $id @{ State = 'skip'; Phase = $(if ($Sync.Cancel) { 'interrompu' } else { 'délai dépassé' }); End = [DateTime]::Now } }
    $Sync.SoftRun.Ok += $nUp + $nOk + $nNo; $Sync.SoftRun.Fail += $nKo
    Write-TaskLog ('Microsoft Store : {0} {1}, {2} {3}, {4} à jour{5}{6}.' -f $List.Count, (Get-Plural $List.Count 'application vérifiée' 'applications vérifiées'), $nUp, (Get-Plural $nUp 'mise à jour installée' 'mises à jour installées'), $nOk, $(if ($nNo) { ", $nNo hors Store" } else { '' }), $(if ($nKo) { ", $nKo en échec" } else { '' })) $(if ($nKo) { 'WARN' } else { 'OK' })
}
# Installation d'applications du catalogue (onglet Applications) : même moteur que les mises à jour (winget install)
function Invoke-Task_AppInstall { Invoke-Task_SoftUpgrade }
function Invoke-Task_SoftUpgrade {
    $list = @($Sync.Params.Soft); $ok = 0; $i = 0; $reboot = $false
    $Sync.SoftRun = [hashtable]::Synchronized(@{ Count = $list.Count; Index = 0; Cur = ''; Ok = 0; Fail = 0; Items = [hashtable]::Synchronized(@{}) })
    foreach ($x in $list) { $Sync.SoftRun.Items["$($x.Id)"] = [hashtable]::Synchronized(@{ State = 'wait'; Phase = ''; Pct = -1; Code = 0; Name = "$($x.Name)"; From = "$($x.From)"; To = "$($x.To)"; End = $null; Out = [Collections.ArrayList]::Synchronized([Collections.ArrayList]::new()) }) }
    # winget d'abord (un logiciel après l'autre), puis les applications du Microsoft Store (demandes au Store en parallèle) ;
    # avancement global réparti au prorata du nombre de logiciels de chaque groupe
    # mises à jour Store par le Store ; désinstallations / réinstallations (Mode) toujours par winget
    $isStoreUp = { param($X) "$($X.Src)" -eq 'store' -and $X.Pfn -and -not $X.Mode }
    $stl = @($list | Where-Object { & $isStoreUp $_ }); $list = @($list | Where-Object { -not (& $isStoreUp $_) })
    $nAll = [math]::Max([double]1, $list.Count + $stl.Count); $Sync.SoftRun.Store = $stl.Count -gt 0
    $wg = $(if ($list.Count) { Find-Winget } else { $null })
    foreach ($x in $list) {
        if ($Sync.Cancel) {
            Write-TaskLog 'Interrompu : logiciels suivants non mis à jour.' 'WARN'
            foreach ($y in $list) { if ($Sync.SoftRun.Items["$($y.Id)"].State -eq 'wait') { Set-SoftItem "$($y.Id)" @{ State = 'skip' } } }
            break
        }
        $i++; $Sync.TaskPct = [int](100 * ($i - 1) / $nAll)
        $Sync.SoftRun.Index = $i; $Sync.SoftRun.Cur = "$($x.Id)"; Set-SoftItem "$($x.Id)" @{ State = 'run'; Phase = 'préparation'; Pct = -1 }
        Write-TaskLog $(if ($x.Install) { 'Installation de {0} ({1})' -f $x.Name, $x.Id } else { '{0} ({1}) : {2} > {3}' -f $x.Name, $x.Src, $x.From, $x.To }) 'STEP'
        # winget testé avant toute fermeture de programme : sans lui, rien n'est installé et les programmes de l'utilisateur
        # (travail non enregistré) restent ouverts
        if (-not $wg) {
            Write-TaskLog 'winget introuvable : logiciel non mis à jour.' 'ERROR'
            $Sync.SoftRun.Fail++; Set-SoftItem "$($x.Id)" @{ State = 'fail'; Phase = 'winget introuvable'; Pct = -1; End = [DateTime]::Now }
            continue
        }
        if ($x.Lock) { $cl = @(Find-SoftLocker $x.Lock); if ($cl.Count) { Close-SoftProc $cl } }
        if ($x.Mode) { Invoke-SoftRemoveItem $x $wg; continue }
        # rattaché par correspondance de nom : winget ne le connaît pas comme installé, « install » pose la nouvelle version par-dessus ;
        # version installée illisible (Battle.net...) : « upgrade » ne peut pas comparer, dernière version posée par-dessus (--force)
        $verb = $(if ($x.Match -or $x.Unknown) { 'install' } else { 'upgrade' })
        # taille de l'installeur (progression du téléchargement calculée par l'interface)
        $Sync.SoftRun.Items["$($x.Id)"].Total = Get-WingetInstallerSize "$($x.Id)"
        $args2 = @($verb, '-e', '--id', $x.Id, '--silent', '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity')
        if ($x.Unknown) { $args2 += '--force'; Write-TaskLog 'Version installée illisible : dernière version installée par-dessus l''existante (winget install --force).' }
        # catalogue d'applications : source imposée (msstore pour les applications du Microsoft Store)
        if ($x.Source) { $args2 += @('--source', "$($x.Source)") }
        # avancement réel lu dans la sortie de winget : étape + pourcentage du logiciel, report sur l'avancement global
        $id = "$($x.Id)"; $n = $nAll; $base = $i - 1
        $onLine = {
            param($t)
            $p = ConvertFrom-WingetLine $t; $it = $Sync.SoftRun.Items[$id]
            # sortie texte de winget gardée par logiciel (40 dernières lignes) : copiée avec l'erreur en cas d'échec
            if (-not $p) { if ($t -notmatch '^[-\\|/]$') { [void]$it.Out.Add($t); if ($it.Out.Count -gt 40) { $it.Out.RemoveAt(0) } }; return }
            if ($p.Phase) { $it.Phase = $p.Phase }
            $it.Pct = $p.Pct
            # téléchargement = 1re moitié du logiciel, installation = 2de moitié (durée inconnue : début de moitié)
            $frac = $(if ($it.Phase -eq 'téléchargement') { 0.5 * [math]::Max([double]0, $it.Pct) / 100 } elseif ($it.Phase -eq 'installation') { 0.5 + 0.5 * [math]::Max([double]0, $it.Pct) / 100 } elseif ($it.Phase -eq 'vérification') { 0.5 } else { 0 })
            $Sync.TaskPct = [int](100 * ($base + $frac) / $n)
        }
        $rc = Invoke-SoftWinget $x $wg $args2 $onLine   # $onLine appelé depuis Invoke-SoftTool : $id, $n et $base lus par portée dynamique (pas de GetNewClosure dans les runspaces)
        # 0x8A15002B « aucune mise à jour applicable » : manifeste winget incohérent avec l'installation (type d'installeur,
        # portée...) ; nouvelle version installée par-dessus l'existante (install --force), sans désinstallation
        if ($rc -eq -1978335189 -and -not $Sync.Cancel) {
            Write-TaskLog 'winget : aucune mise à jour applicable (0x8A15002B), installation de la nouvelle version par-dessus l''existante (--force).' 'WARN'
            $rc = Invoke-SoftWinget $x $wg @('install', '-e', '--id', $x.Id, '--force', '--silent', '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity') $onLine
        }
        # Windows App Runtime (Microsoft.WindowsAppRuntime.x.y) : son installeur échoue (0x8A150006) quand des applications
        # utilisent le composant ; nouvel essai avec ses options documentées --quiet --force (ferme ces applications)
        if ($rc -eq -1978335226 -and "$($x.Id)" -like 'Microsoft.WindowsAppRuntime*' -and -not $Sync.Cancel) {
            Write-TaskLog 'Windows App Runtime : installeur en échec (0x8A150006, composant utilisé par des applications ouvertes) : nouvel essai en forçant la fermeture de ces applications (--quiet --force).' 'WARN'
            $rc = Invoke-SoftWinget $x $wg @('install', '-e', '--id', $x.Id, '--force', '--override', '--quiet --force', '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity') $onLine
        }
        # codes winget de réussite à redémarrage (0x8A150109 : redémarrer pour terminer, 0x8A15010B : redémarrage lancé par
        # l'installeur) et d'application déjà installée (0x8A150061, installation depuis le catalogue) : comptés en échec avant
        if ($rc -in -1978334967, -1978334965) { $reboot = $true; Write-TaskLog ('Installé : redémarrage du poste nécessaire pour terminer (code winget 0x{0:X8}).' -f $rc) 'WARN'; $rc = 0 }
        elseif ($rc -eq -1978335135 -and $x.Install) { Write-TaskLog 'Déjà installé sur ce poste (0x8A150061) : rien à faire.' 'OK'; $rc = 0 }
        $good = $rc -eq 0
        # installeur terminé sans erreur : version réellement installée relue (certains logiciels, Discord, EA app...,
        # ne changent de version qu'au prochain lancement, ou s'installent pour un autre compte que celui de l'utilisateur)
        $now = $null
        if ($good -and -not $x.Match) {
            try {
                Import-Module Microsoft.WinGet.Client -ErrorAction Stop
                $now = "$(@(Get-WinGetPackage -Id $id -MatchOption Equals -ErrorAction Stop)[0].InstalledVersion)"
            } catch { Write-Ignored 'Vérification de la version installée' $_ }
        }
        if ($good -and $now -and $now -eq "$($x.From)") {
            $ok++
            $Sync.SoftRun.Ok++
            Set-SoftItem $id @{ State = 'pend'; Phase = ''; Pct = 100; End = [DateTime]::Now }
            Write-TaskLog ("Installeur terminé sans erreur, mais version toujours {0} : mise à jour finalisée au prochain lancement du logiciel, ou installée pour un autre compte que l'utilisateur." -f $now) 'WARN'
        }
        elseif ($good) {
            $ok++
            $Sync.SoftRun.Ok++
            Set-SoftItem $id @{ State = 'ok'; Phase = ''; Pct = 100; End = [DateTime]::Now }
            Write-TaskLog $(if ($now) { "Mis à jour (version installée : $now)." } else { 'Mis à jour.' }) 'OK'
        }
        elseif ($Sync.Cancel) {
            Set-SoftItem $id @{ State = 'skip'; Phase = 'interrompu'; End = [DateTime]::Now }
            Write-TaskLog 'Interrompu pendant l''installation.' 'WARN'
        }
        else {
            $Sync.SoftRun.Fail++
            Set-SoftItem $id @{ State = 'fail'; Code = $rc; End = [DateTime]::Now }
            Write-TaskLog ('Échec : code de retour {0} (0x{0:X8}).' -f $rc) 'WARN'
        }
        # historique des mises à jour faites par l'application (une ligne JSON par logiciel), affiché dans la fenêtre Logiciels
        try {
            # échec : sortie de winget conservée (40 dernières lignes) pour « Copier l'erreur » depuis l'onglet Historique
            $rec = @{ Date = (Get-Date).ToString('o'); Name = "$($x.Name)"; Id = "$($x.Id)"; From = "$($x.From)"; To = "$($x.To)"; Ok = [bool]$good; Code = [int64]$rc; User = "$env:USERNAME"; Computer = "$env:COMPUTERNAME" }
            if (-not $good) { $rec.Out = @($Sync.SoftRun.Items["$($x.Id)"].Out) }
            $hl = ConvertTo-Json -Compress -InputObject $rec
            [IO.File]::AppendAllText((Join-Path $Sync.LogRoot '_etat\logiciels-historique.jsonl'), $hl + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
        } catch { Write-Ignored 'Historique des mises à jour de logiciels' $_ }
    }
    if ($list.Count) { Write-TaskLog ('winget : {0}/{1} {2}.' -f $ok, $list.Count, (Get-Plural $list.Count 'logiciel mis à jour' 'logiciels mis à jour')) $(if ($ok -eq $list.Count) { 'OK' } else { 'WARN' }) }
    if ($stl.Count -and -not $Sync.Cancel) { $Sync.SoftRun.Cur = ''; Invoke-StoreUpdate $stl (100 * $list.Count / $nAll) 100 }
    elseif ($stl.Count) { foreach ($y in $stl) { Set-SoftItem "$($y.Id)" @{ State = 'skip' } } }
    $Sync.TaskPct = 100; $Sync.SoftRun.Cur = ''
    if ($reboot) { Write-TaskLog 'Redémarrage du poste demandé par au moins un installeur.' 'WARN' }
}
function Invoke-Task_AppxRemove {
    foreach ($n in $Sync.Params.Appx) {
        Write-TaskLog "AppX : $n" 'STEP'
        $found = $false
        foreach ($p in @(Get-AppxPackage -AllUsers -Name $n -ErrorAction SilentlyContinue)) {
            $found = $true
            try {
                Remove-AppxPackage -Package $p.PackageFullName -AllUsers -ErrorAction Stop
                Write-TaskLog "  supprimé : $($p.PackageFullName)" 'OK'
            }
            catch { Write-TaskLog "  échec : $($p.PackageFullName) - $($_.Exception.Message)" 'WARN' }
        }
        foreach ($p in @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -eq $n })) {
            $found = $true
            try {
                Remove-AppxProvisionedPackage -Online -PackageName $p.PackageName -ErrorAction Stop | Out-Null
                Write-TaskLog "  provisionnement retiré : $($p.PackageName)" 'OK'
            }
            catch { Write-TaskLog "  échec provisionnement : $($_.Exception.Message)" 'WARN' }
        }
        if (-not $found) { Write-TaskLog '  non présent.' }
    }
}

function Invoke-Task_Clean {
    $ids = @($Sync.Params.Clean)
    $total = [double]0
    foreach ($id in $ids) {
        $it = $CleanItems | Where-Object { $_.Id -eq $id } | Select-Object -First 1
        if (-not $it) { continue }
        Write-TaskLog ('--- {0} / {1}' -f $it.Group, $it.Label) 'STEP'
        try {
            if ($it.Pre) { & $it.Pre }
            if ($it.Clean) { & $it.Clean }
            else {
                $g = [double]0; $script:ClearLeft = 0
                foreach ($t in @(Resolve-CleanTarget $it)) {
                    if ($t.Kind -eq 'D') { $g += Clear-Folder $t.Path }
                    else { try { Remove-Item -LiteralPath $t.Path -Force -ErrorAction Stop; $g += $t.Len } catch { $script:ClearLeft++ } }
                }
                Write-TaskLog $(if ($g -gt 0) { 'Libéré : {0}' -f (Format-Size $g) } else { 'Déjà vide : rien à libérer.' }) 'OK'
                if ($script:ClearLeft) { Write-TaskLog ('{0} {1} (fichier ouvert par une application ou accès refusé).' -f $script:ClearLeft, (Get-Plural $script:ClearLeft 'élément conservé' 'éléments conservés')) }
                $total += $g
            }
        } catch { Write-TaskLog $_.Exception.Message 'ERROR' }
        finally { if ($it.Post) { try { & $it.Post } catch { Write-Ignored 'Remise en route après nettoyage' $_ } } }
    }
    Write-TaskLog $(if ($total -gt 0) { 'Total libéré (hors composants Windows) : {0}' -f (Format-Size $total) } else { 'Total libéré (hors composants Windows) : rien, éléments déjà vides.' }) 'BILAN'
}

try {
    $Sync.FreeBefore = Get-FreeSpace
    $os = Get-CimInstance Win32_OperatingSystem
    Write-TaskLog ('Oliv_Maintenance {0} - {1} - {2} build {3} - PS {4}' -f $Sync.Version, $env:COMPUTERNAME, $os.Caption, $os.BuildNumber, $PSVersionTable.PSVersion)
    # espace libre avant / après : seulement pour les tâches qui libèrent ou consomment de l'espace disque
    $space = @($Sync.Selected | Where-Object { $_ -in 'Clean', 'WindowsOld', 'AppxRemove', 'DismRestore', 'WuInstall' }).Count -gt 0
    if ($space) { Write-TaskLog ('Espace libre {0} avant : {1}' -f $SysDrive, (Format-Size $Sync.FreeBefore)) }
    $n = $Sync.Selected.Count; $i = 0
    foreach ($id in $Sync.Selected) {
        if ($Sync.Cancel) { Write-TaskLog 'Arrêt demandé par l''utilisateur : tâches suivantes annulées.' 'WARN'; break }
        $i++
        $label = $Sync.Labels[$id]
        $Sync.Status = "[$i/$n] $label"
        $Sync.TaskIdx = $i; $Sync.TaskCount = $n; $Sync.TaskPct = -1; $Sync.TaskStart = [DateTime]::Now
        Write-TaskLog ''
        Write-TaskLog "===== [$i/$n] $label =====" 'STEP'
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $Sync.TaskRes = [hashtable]::Synchronized(@{ Id = $id; Label = $label; Start = [DateTime]::Now; Err = 0; Warn = 0; Last = ''; Dur = $null; Cancel = $false })
        try { [void](& "Invoke-Task_$id") } catch { Write-TaskLog $_.Exception.Message 'ERROR' }
        $Sync.TaskRes.Dur = $sw.Elapsed; $Sync.TaskRes.Cancel = [bool]$Sync.Cancel; [void]$Sync.TaskResults.Add($Sync.TaskRes); $Sync.TaskRes = $null
        Write-TaskLog ('Durée : {0:hh\:mm\:ss}' -f $sw.Elapsed) 'BILAN'
    }
    Write-TaskLog ''
    if ($space) {
        # écart mesuré sur le volume entier : peut différer du total libéré (autres programmes, fichier d'échange, mises à jour)
        $after = Get-FreeSpace; $g = $after - $Sync.FreeBefore; $Sync.SpaceGain = $g
        Write-TaskLog ('Espace libre {0} après : {1} ({2})' -f $SysDrive, (Format-Size $after), $(if ($g -gt 0) { 'gain : ' + (Format-Size $g) } elseif ($g -lt 0) { 'consommé : ' + (Format-Size (-$g)) } else { 'inchangé' })) 'BILAN'
    }
    Write-TaskLog "Journal : $($Sync.LogFile)"
    $Sync.Status = if ($Sync.Cancel) { 'Interrompu' } else { 'Terminé' }
} catch {
    Write-TaskLog "Erreur fatale : $($_.Exception.Message)" 'ERROR'
    $Sync.Status = 'Erreur'
} finally {
    $Sync.Done = $true
}
'@

