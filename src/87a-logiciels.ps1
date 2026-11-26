# Logiciels : carte compacte en Maintenance (sous Espace disque) qui ouvre une fenêtre d'inventaire. Inventaire et mises à jour
# par winget (module Microsoft.WinGet.Client, installés au besoin) ; une mise à jour n'est
# proposée que si la version disponible est réellement supérieure. Exclusions mémorisées par logiciel.
$SoftScript = @'
$ProgressPreference = 'SilentlyContinue'
# comparaison de versions par segments numériques (1.2 = 1.2.0.0) ; -1 / 0 / 1
function Compare-Ver([string]$A, [string]$B) {
    $x = @([regex]::Matches($A, '\d+') | ForEach-Object { [decimal]$_.Value }); $y = @([regex]::Matches($B, '\d+') | ForEach-Object { [decimal]$_.Value })
    if (-not $x.Count -or -not $y.Count) { return [math]::Sign([string]::Compare($A, $B, $true)) }
    for ($i = 0; $i -lt [math]::Max($x.Count, $y.Count); $i++) {
        # noms distincts de $A / $B : les variables PowerShell ne sont pas sensibles à la casse
        $va = $(if ($i -lt $x.Count) { $x[$i] } else { 0 }); $vb = $(if ($i -lt $y.Count) { $y[$i] } else { 0 })
        if ($va -gt $vb) { return 1 }; if ($va -lt $vb) { return -1 }
    }
    0
}
function Get-NormName([string]$N) { ($N.ToLower() -replace '[^a-z0-9]', '') }
# nom sans version, architecture ni édition (« 7-Zip 23.01 (x64) » -> « 7-Zip ») pour la recherche dans le catalogue
function Get-BaseName([string]$N) {
    $t = $N -replace '\((x64|x86|amd64|arm64|64[- ]?bits?|32[- ]?bits?)[^)]*\)', '' -replace '\b(x64|x86|amd64|arm64|64[- ]?bit|32[- ]?bit)\b', ''
    $t = $t -replace '\s+v?\d+([._]\d+)+\S*.*$', '' -replace '\s+\(\s*\)', '' -replace '\s+-\s+[\p{L}]{2,}(-[\p{L}]{2,})?$', '' -replace '\s+(release|version)$', '' -replace '[\s\-_,]+$', ''
    $t.Trim()
}
$r = @{ Apps = @(); Error = $null; Stamp = $null; Installed = @(); WingetVer = $null }
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    if (-not (Get-Module -ListAvailable -Name Microsoft.WinGet.Client)) {
        $Sync.WgStatus = 'installation du module PowerShell Microsoft.WinGet.Client'
        if (-not (Get-PackageProvider -ListAvailable -Name NuGet -ErrorAction SilentlyContinue | Where-Object { $_.Version -ge [version]'2.8.5.201' })) { Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers | Out-Null }
        Install-Module -Name Microsoft.WinGet.Client -Repository PSGallery -Scope AllUsers -Force -AllowClobber -ErrorAction Stop
        $r.Installed += 'module Microsoft.WinGet.Client'
    }
    Import-Module Microsoft.WinGet.Client -ErrorAction Stop
    $wg = Find-Winget
    if (-not $wg) {
        $Sync.WgStatus = 'enregistrement de winget'
        try { Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe -ErrorAction Stop } catch { Write-Ignored 'Enregistrement de winget' $_ }
        $wg = Find-Winget
    }
    if (-not $wg) {
        $Sync.WgStatus = 'installation de winget'
        Repair-WinGetPackageManager -AllUsers -ErrorAction Stop | Out-Null
        $wg = Find-Winget
        if (-not $wg) { throw 'winget toujours introuvable après installation.' }
        $r.Installed += 'winget'
    }
    try { $r.WingetVer = "$(& $wg --version 2>$null | Select-Object -First 1)".Trim() } catch {}
    $Sync.WgStatus = 'inventaire des logiciels (winget)'
    $apps = [Collections.ArrayList]::new()
    # « Failed to create instance: -2147023174 » (0x800706BA, serveur RPC indisponible) : le module ne joint pas le service
    # de winget (Programme d'installation d'application absent, abîmé ou trop ancien) ; réparation automatique
    # (Repair-WinGetPackageManager -Latest, recommandé par Microsoft) puis un nouvel essai, sinon message explicite
    $pkList = $null
    try { $pkList = @(Get-WinGetPackage -ErrorAction Stop) }
    catch {
        if ("$($_.Exception.Message)" -notmatch '2147023174|800706BA|create instance') { throw }
        $Sync.WgStatus = 'réparation de winget (service indisponible)'
        try { Repair-WinGetPackageManager -Latest -Force -ErrorAction Stop | Out-Null; $r.Installed += 'réparation de winget' } catch { $null = $_ }
        try { $pkList = @(Get-WinGetPackage -ErrorAction Stop) }
        catch { throw 'le service winget ne répond pas (0x800706BA) malgré une réparation automatique : mettre à jour « Programme d''installation d''application » (App Installer) dans le Microsoft Store, puis relancer la recherche.' }
    }
    foreach ($pk in $pkList) {
        $from = "$($pk.InstalledVersion)"; $to = $null; $unk = $false; $last = "$(@($pk.AvailableVersions)[0])"
        $src = "$($pk.Source)"
        if ($from -match '^(Unknown|Inconnu)') {
            # version installée illisible : dernière version affichée, mise à jour proposée seulement à la demande (réinstallation)
            $unk = $true; $from = 'inconnue'; if ($last) { $to = $last }
        } elseif ($pk.IsUpdateAvailable) { $to = $last; if (-not $to -or (Compare-Ver $to $from) -le 0) { $to = $null } }
        # paquet MSIX que winget n'a pas rattaché à un catalogue (« MSIX\<nom complet du paquet> ») : application du Microsoft
        # Store reconnue par son nom de famille de paquet (nom_éditeur), indépendant de la langue du nom affiché
        $pfn = $null
        if (-not $src -and "$($pk.Id)" -like 'MSIX\*') {
            $pp = "$($pk.Id)".Substring(5) -split '_'
            if ($pp.Count -ge 5) { $pfn = '{0}_{1}' -f $pp[0], $pp[-1] }
        }
        [void]$apps.Add(@{ LocalId = "$($pk.Id)"; Name = "$($pk.Name)"; Id = "$($pk.Id)"; Src = $(if ($src) { 'winget' } elseif ($pfn) { 'store' } else { '' }); SrcLabel = $(if ($src -eq 'msstore' -or $pfn) { 'Microsoft Store' } elseif ($src) { 'winget' } else { 'non géré' }); From = $from; To = $to; Unknown = $unk; Pfn = $pfn; Match = $false })
    }
    # logiciels que winget n'a pas rattachés à son catalogue (« non géré ») : recherche par nom normalisé dans le catalogue winget,
    # retenue seulement si un seul paquet correspond exactement ; mise à jour ensuite par « winget install » de ce paquet
    # simple lecture (onglet Mes applications sans inventaire) : ni correspondance avec le catalogue ni Microsoft Store
    $todo = @($apps | Where-Object { -not $Sync.WgListOnly -and -not $_.Src -and $_.From -and $_.From -ne 'inconnue' -and $_.Name -and $_.Name -notmatch '\bKB\d{6,}' })
    $n = 0
    foreach ($a in $todo) {
        if ($Sync.WgCancel) { break }
        $n++; $Sync.WgStatus = 'correspondance avec le catalogue winget ({0}/{1})' -f $n, $todo.Count
        $base = Get-BaseName $a.Name; $nb = Get-NormName $base
        if ($nb.Length -lt 3 -or $a.Name -match '^(Microsoft Visual C\+\+|Microsoft \.NET|Windows SDK|Microsoft Update Health|Update for )') { continue }
        # 1) nom exact (insensible à la casse) : « Git » ne ramène plus GitHub Desktop, Git LFS... qui repoussaient Git.Git
        #    hors des 15 premiers résultats ; 2) à défaut, nom contenant le texte (40 résultats au plus)
        $cands = @(); try { $cands = @(Find-WinGetPackage -Name $base -Source winget -MatchOption EqualsCaseInsensitive -ErrorAction Stop) } catch {}
        if (-not $cands.Count) { try { $cands = @(Find-WinGetPackage -Name $base -Source winget -Count 40 -ErrorAction Stop) } catch {} }
        $hit = @($cands | Where-Object { (Get-NormName (Get-BaseName "$($_.Name)")) -eq $nb })
        # plusieurs paquets du même nom : celui dont l'identifiant se termine par ce nom (Git.Git, Kitware.CMake)
        if ($hit.Count -gt 1) { $hit = @($hit | Where-Object { (Get-NormName ("$($_.Id)" -split '\.')[-1]) -eq $nb }) }
        if ($hit.Count -ne 1) { continue }
        $m = $hit[0]; $lv = "$($m.Version)"
        # paquet déjà rattaché par winget lui-même (entrée d'installation en double, ancienne trace) : la correspondance est écartée
        if (@($apps | Where-Object { -not $_.Match -and $_.Src -and $_.Id -eq "$($m.Id)" }).Count) { $a.Drop = $true; continue }
        # deux entrées rattachées au même paquet : seule la version installée la plus récente est gardée
        $prev = @($apps | Where-Object { $_.Match -and $_.Id -eq "$($m.Id)" -and -not $_.Drop } | Select-Object -First 1)
        if ($prev.Count) { if ((Compare-Ver $a.From $prev[0].From) -gt 0) { $prev[0].Drop = $true } else { $a.Drop = $true; continue } }
        $a.Id = "$($m.Id)"; $a.Src = 'winget'; $a.SrcLabel = 'winget (correspondance)'; $a.Match = $true
        if ($lv -and (Compare-Ver $lv $a.From) -gt 0) { $a.To = $lv }
    }
    # entrées de désinstallation orphelines (« ARP\Machine|User\X64|X86\<clé> ») : logiciel disparu dont l'entrée est restée
    # dans le registre. Orpheline si le désinstalleur déclaré (hors msiexec) est absent et que le dossier d'installation
    # déclaré, s'il y en a un, n'existe plus ; MSI : seulement si son dossier d'installation déclaré n'existe plus.
    foreach ($a in @($apps | Where-Object { "$($_.LocalId)" -like 'ARP\*' })) {
        try {
            $pp = "$($a.LocalId)" -split '\\', 4
            if ($pp.Count -lt 4) { continue }
            $hive = $(if ($pp[1] -eq 'User') { [Microsoft.Win32.Registry]::CurrentUser } else { [Microsoft.Win32.Registry]::LocalMachine })
            $sub = $(if ($pp[2] -eq 'X86' -and $pp[1] -ne 'User') { 'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\' } else { 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\' }) + $pp[3]
            $k = $hive.OpenSubKey($sub); if (-not $k) { continue }
            try { $us = "$($k.GetValue('UninstallString'))"; $loc = "$($k.GetValue('InstallLocation'))".Trim().Trim('"') } finally { $k.Close() }
            $exe = $(if ($us -match '^\s*"([^"]+)"') { $Matches[1] } elseif ($us -match '^\s*(\S+\.exe)') { $Matches[1] } else { '' })
            $exe = [Environment]::ExpandEnvironmentVariables($exe); $loc = [Environment]::ExpandEnvironmentVariables($loc)
            $locGone = $loc -and -not (Test-Path -LiteralPath $loc)
            $orphan = $(if ($us -match '(?i)msiexec') { $locGone } elseif ($exe) { -not (Test-Path -LiteralPath $exe) -and ($locGone -or -not $loc) } else { $locGone })
            if ($orphan) { $a.Orphan = $true; $a.RegKey = '{0}\{1}' -f $(if ($pp[1] -eq 'User') { 'HKCU' } else { 'HKLM' }), $sub }
        } catch { Write-Ignored 'Entrées de désinstallation (contrôle des restes)' $_ }
    }
    # applications du Microsoft Store que winget ne suit pas : mises à jour demandées au Store lui-même
    # (AppInstallManager.SearchForAllUpdatesAsync, options sans téléchargement ni installation automatiques, Windows 10 1809
    # et plus). Le Store ne donne pas le numéro de la nouvelle version : catalogue en ligne interrogé ensuite, à défaut
    # « nouvelle version » ; numéro réel relu après installation.
    $stApps = @($apps | Where-Object { -not $Sync.WgListOnly -and $_.Src -eq 'store' -and -not $_.Drop })
    if ($stApps.Count -and -not $Sync.WgCancel) {
        $Sync.WgStatus = 'recherche des mises à jour du Microsoft Store'
        try {
            [void][Reflection.Assembly]::LoadWithPartialName('System.Runtime.WindowsRuntime')
            $mt = [Windows.ApplicationModel.Store.Preview.InstallControl.AppInstallManager, Windows.ApplicationModel.Store.Preview.InstallControl, ContentType = WindowsRuntime]
            $ot = [Windows.ApplicationModel.Store.Preview.InstallControl.AppUpdateOptions, Windows.ApplicationModel.Store.Preview.InstallControl, ContentType = WindowsRuntime]
            $itT = [Windows.ApplicationModel.Store.Preview.InstallControl.AppInstallItem, Windows.ApplicationModel.Store.Preview.InstallControl, ContentType = WindowsRuntime]
            $lt = [Collections.Generic.IReadOnlyList`1].MakeGenericType($itT)
            $asTask = @([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0].MakeGenericMethod($lt)
            $mgr = [Activator]::CreateInstance($mt); $opt = [Activator]::CreateInstance($ot)
            $opt.AutomaticallyDownloadAndInstallUpdateIfFound = $false; $opt.AllowForcedAppRestart = $false
            $t = $asTask.Invoke($null, @($mgr.SearchForAllUpdatesAsync('', 'Oliv_Maintenance', $opt)))
            if (-not $t.Wait(120000)) { throw 'pas de réponse du Store en 2 minutes' }
            $found = @{}; foreach ($it in @($t.Result)) { if ($it) { $found["$($it.PackageFamilyName)"] = "$($it.ProductId)" } }
            foreach ($a in $stApps) { if ($found.ContainsKey("$($a.Pfn)")) { $a.To = 'non publiée'; $a.StoreId = $found["$($a.Pfn)"] } }
            # numéro de version : catalogue en ligne du Store (displaycatalog, non documenté, recherche par nom de famille de
            # paquet), plus haute version des paquets publiés, retenue seulement si elle dépasse la version installée.
            # Mise à jour réservée à certains postes (version constructeur, déploiement progressif) : absente du catalogue
            # public, le libellé « nouvelle version » est gardé.
            $Sync.WgStatus = 'versions disponibles (catalogue du Microsoft Store)'; $r.StoreNotes = @()
            foreach ($a in @($stApps | Where-Object { $_.To })) {
                if ($Sync.WgCancel) { break }
                # 2 recherches : par nom de famille de paquet, puis par identifiant de produit renvoyé par le Store (produit
                # publié sous un autre nom de famille, ou plusieurs produits pour la même application) ; paquets de la même
                # application seulement (nom avant le 1er « _ »)
                $nm = ("$($a.Pfn)" -split '_')[0]; $best = $null
                foreach ($u in @(
                    ('https://displaycatalog.mp.microsoft.com/v7.0/products/lookup?alternateId=PackageFamilyName&value={0}&market=FR&languages=fr-FR&fieldsTemplate=Details' -f [uri]::EscapeDataString("$($a.Pfn)")),
                    $(if ($a.StoreId) { 'https://displaycatalog.mp.microsoft.com/v7.0/products?bigIds={0}&market=FR&languages=fr-FR&fieldsTemplate=Details' -f [uri]::EscapeDataString("$($a.StoreId)") }))) {
                    if (-not $u -or ($best -and (Compare-Ver $best $a.From) -gt 0)) { continue }
                    try {
                        $cat = Invoke-RestMethod -Uri $u -TimeoutSec 8 -UseBasicParsing -ErrorAction Stop
                        foreach ($pk in @($cat.Products.DisplaySkuAvailabilities.Sku.Properties.Packages)) {
                            $pp = "$($pk.PackageFullName)" -split '_'
                            if ($pp[0] -ne $nm) { continue }
                            $v = $pp[1]
                            if ($v -match '^\d+(\.\d+){1,3}$' -and (-not $best -or (Compare-Ver $v $best) -gt 0)) { $best = $v }
                        }
                    } catch { Write-Ignored 'Microsoft Store (catalogue des versions)' $_ }
                }
                if ($best -and (Compare-Ver $best $a.From) -gt 0) { $a.To = $best }
                else {
                    # mise à jour proposée par le Store à ce poste, absente du catalogue public (déploiement progressif, version
                    # constructeur, composant de l'application) : rien d'inventé, détail dans le journal
                    $r.StoreNotes += '{0} : mise à jour proposée par le Store, version non publiée dans le catalogue (catalogue : {1}, installée : {2}).' -f $a.Name, $(if ($best) { $best } else { 'aucune version' }), $a.From
                }
            }
            $r.StoreUpd = @($stApps | Where-Object { $_.To }).Count
        } catch { $e = $_.Exception; while ($e.InnerException) { $e = $e.InnerException }; $r.StoreError = $e.Message }
    }
    $r.Apps = @($apps | Where-Object { -not $_.Drop } | Sort-Object { $_.Name })
    # entrées écartées (doublons d'un paquet déjà géré) : mémorisées pour que l'actualisation de la liste ne les fasse pas réapparaître
    $r.Dropped = @($apps | Where-Object { $_.Drop } | ForEach-Object { "$($_.LocalId)" })
    $r.SearchStamp = $(if ($Sync.WgListOnly) { $null } else { [DateTime]::Now.ToString('o') })
    # simple lecture (Mes applications) avec un inventaire précédent : liste installée actualisée, informations de la dernière
    # recherche complète conservées pour les logiciels toujours présents (rattachement au catalogue, mise à jour Store / winget
    # disponible si toujours supérieure à la version installée) ; logiciels désinstallés entre-temps retirés
    $prev = $Sync.WgPrev
    if ($Sync.WgListOnly -and $prev -and -not $prev.Error -and @($prev.Apps).Count) {
        $old = @{}; foreach ($o in @($prev.Apps)) { if ($o -and $o.LocalId) { $old["$($o.LocalId)"] = $o } }
        $drop = @{}; foreach ($d in @($prev.Dropped)) { if ($d) { $drop["$d"] = 1 } }
        $gone = $Sync.SoftGone
        $keep = [Collections.ArrayList]::new()
        foreach ($n in @($r.Apps)) {
            $lid = "$($n.LocalId)"
            if ($drop.ContainsKey($lid)) { continue }
            $o = $old[$lid]
            if ($o) {
                if ($o.Match) { $n.Id = "$($o.Id)"; $n.Src = "$($o.Src)"; $n.SrcLabel = "$($o.SrcLabel)"; $n.Match = $true }
                if (-not $n.To -and $o.To -and ("$($o.To)" -eq 'non publiée' -or (Compare-Ver "$($o.To)" "$($n.From)") -gt 0)) { $n.To = "$($o.To)"; if ($o.StoreId) { $n.StoreId = "$($o.StoreId)" } }
            }
            if ($gone -and ($gone.ContainsKey("$($n.Id)") -or $gone.ContainsKey($lid))) { continue }
            [void]$keep.Add($n)
        }
        $r.Apps = @($keep); $r.Dropped = @($prev.Dropped); $r.SearchStamp = $(if ($prev.SearchStamp) { "$($prev.SearchStamp)" } elseif ($prev.Stamp) { ([DateTime]$prev.Stamp).ToString('o') } else { $null })
        $r.ListMerge = $true
        foreach ($k in 'StoreUpd', 'StoreNotes') { if ($null -ne $prev.$k) { $r[$k] = $prev.$k } }
    }
} catch { $r.Error = $_.Exception.Message }
$r.Stamp = [DateTime]::Now
if (-not $Sync.WgCancel) { $Sync.WgResult = $r }
$Sync.WgRunning = $false
'@
$SoftUI = @{ Sel = @{}; Filter = 'Upd' }
$SoftFile = Join-Path (Get-LogPath 'Etat') 'logiciels.json'
# inventaire enregistré (logiciels.json, écriture atomique) : $Sync.WgResult est une table après une recherche, un objet
# relu du fichier sinon. « @{} + objet » échouait sur ce dernier : après une mise à jour, une désinstallation ou le retrait
# d'une entrée lancés depuis la liste en cache, le fichier n'était plus réécrit et les logiciels réapparaissaient.
function Save-SoftInventory([string]$What = 'Enregistrement de l''inventaire des logiciels') {
    $r = $Sync.WgResult; if (-not $r) { return }
    try {
        $o = ConvertTo-StateTable $r
        $o.Stamp = ([DateTime]$r.Stamp).ToString('o')
        Write-FileAtomic $SoftFile (ConvertTo-Json -InputObject $o -Depth 4)
    } catch { Write-Ignored $What $_ }
}
$SoftExclFile = Join-Path (Get-LogPath 'Etat') 'logiciels-exclus.json'
$SoftExcl = @{}
try {
    if (Test-Path -LiteralPath $SoftExclFile) {
        # parenthèses : sous Windows PowerShell 5.1, ConvertFrom-Json renvoie le tableau en un seul objet ; sans elles, dès 2
        # logiciels exclus, une seule clé « A B » était lue et plus aucune exclusion ne s'appliquait au lancement suivant.
        # Clés ainsi fusionnées enregistrées par les versions précédentes : séparées de nouveau (« source|id »)
        foreach ($k in @((Get-Content -LiteralPath $SoftExclFile -Raw -Encoding UTF8 | ConvertFrom-Json))) {
            foreach ($x in @("$k" -split '\s+(?=[^\s|]+\|)')) { if ($x) { $SoftExcl[$x] = $true } }
        }
    }
} catch {
    Write-Ignored 'Lecture des logiciels exclus' $_
}
function Save-SoftExcl { try { ConvertTo-Json -InputObject @($SoftExcl.Keys | Sort-Object) | Set-Content -LiteralPath $SoftExclFile -Encoding UTF8 } catch { Write-Ignored 'Enregistrement des logiciels exclus' $_ } }
function Get-SoftKey($A) { '{0}|{1}' -f $A.Src, $A.Id }
$SoftHistFile = Join-Path (Get-LogPath 'Etat') 'logiciels-historique.jsonl'
function Get-SoftHistory {
    if (-not (Test-Path -LiteralPath $SoftHistFile)) { return @() }
    $l = @()
    foreach ($ln in [IO.File]::ReadAllLines($SoftHistFile, [Text.Encoding]::UTF8)) {
        if ($ln.Trim()) { try { $l += ($ln | ConvertFrom-Json) } catch { Write-Ignored 'Historique des logiciels : ligne illisible ignorée' $_ } }
    }
    @($l | Sort-Object { [DateTime]$_.Date } -Descending)
}
function Get-SoftUpdate {
    $r = $Sync.WgResult; if (-not $r -or $r.Error) { return @() }
    $own = @{}; foreach ($x in @($r.Apps)) { if ($x -and -not $x.Match -and $x.Src) { $own["$($x.Id)"] = 1 } }
    @($r.Apps | Where-Object { $_ -and $_.To -and $_.Src -and -not $_.Unknown -and -not ($_.Match -and $own.ContainsKey("$($_.Id)")) })
}
# date de la dernière recherche complète des mises à jour (une actualisation de la liste ne la change pas)
function Get-SoftSearchStamp($R) { $(if ($R.SearchStamp) { $R.SearchStamp } else { $R.Stamp }) }
function Start-SoftSearch([switch]$ListOnly) {
    Close-BgJob
    if ($Sync.WgRunning -or $BgJobs.ContainsKey('Soft')) { return }
    $SoftUI.Done = $null
    $Sync.WgListOnly = [bool]$ListOnly; if (-not $ListOnly) { $SoftUI.Searched = $true }
    $Sync.WgPrev = $Sync.WgResult; if (-not $Sync.SoftGone) { $Sync.SoftGone = @{} }
    if ($ListOnly) { $SoftUI.ListRead = [DateTime]::Now }
    $Sync.WgCancel = $false; $Sync.WgRunning = $true; $Sync.WgStart = [DateTime]::Now; $Sync.WgStatus = 'préparation'
    Write-UiLog $(if ($ListOnly -and $Sync.WgPrev) { 'Actualisation de la liste des applications installées (winget), liste enregistrée affichée en attendant.' } elseif ($ListOnly) { 'Lecture des applications installées (winget).' } else { 'Recherche des logiciels et de leurs mises à jour (winget).' })
    Start-BgJob 'Soft' $SoftScript
    Update-SoftCard; Update-SoftView
}
function Stop-SoftSearch {
    if (-not $Sync.WgRunning -or $Sync.WgCancel) { return }
    $Sync.WgCancel = $true
    $j = $BgJobs['Soft']; if ($j) { try { [void]$j.PS.BeginStop($null, $null) } catch {} }
    Write-UiLog 'Recherche des logiciels annulée : dernier résultat conservé.' 'WARN'
    Add-SessionEvent 'Logiciels' 'Recherche des mises à jour des logiciels' 'annulée' 'warn'
    Update-SoftView
}
# carte de Maintenance : résumé du dernier inventaire
function Update-SoftCard {
    if (-not $SoftUI.CardText) { return }
    $r = $Sync.WgResult
    # nouveau résultat : enregistrement, journal, rafraîchissement de la fenêtre
    if (-not $Sync.WgRunning -and $r -and $r.Stamp -and "$($r.Stamp)" -ne "$($SoftUI.Shown)") {
        $SoftUI.Shown = $r.Stamp
        if ($SoftUI.Fresh) {
            Save-SoftInventory
            # actualisation de la liste (Mes applications) : enregistrée, sans nouveau bilan d'inventaire dans le journal
            if (-not $r.ListMerge) {
                $up = @(Get-SoftUpdate)
                $sum = $(if ($r.Error) { "Inventaire des logiciels impossible : $($r.Error)" } else { 'Inventaire des logiciels : {0} {1}, {2} {3}{4}{5}.' -f @($r.Apps).Count, (Get-Plural @($r.Apps).Count 'logiciel' 'logiciels'), $up.Count, (Get-Plural $up.Count 'mise à jour disponible' 'mises à jour disponibles'),  '', $(if (@($r.Installed).Count) { ' (installé au préalable : ' + (@($r.Installed) -join ', ') + ')' } else { '' }) })
                Write-UiLog $sum $(if ($r.Error) { 'WARN' } else { 'INFO' })
                if ($r.StoreError) { Write-UiLog "Microsoft Store : recherche des mises à jour impossible ($($r.StoreError))." 'WARN' }
                foreach ($n in @($r.StoreNotes)) { if ($n) { Write-UiLog "Microsoft Store - $n" 'INFO' } }
                Add-SessionEvent 'Logiciels' 'Recherche des mises à jour des logiciels' $(if ($r.Error) { "impossible : $($r.Error)" } else { '{0} {1}, {2} {3}' -f @($r.Apps).Count, (Get-Plural @($r.Apps).Count 'logiciel' 'logiciels'), $up.Count, (Get-Plural $up.Count 'mise à jour disponible' 'mises à jour disponibles') }) $(if ($r.Error) { 'error' } elseif ($up.Count) { 'warn' } else { 'ok' })
                $lines = @($sum) + @($up | ForEach-Object { '   {0} [{1} {2}] : {3} > {4}{5}' -f $_.Name, $_.SrcLabel, $_.Id, $_.From, $_.To, $(if ($SoftExcl[(Get-SoftKey $_)]) { '  (exclu)' } else { '' }) })
                $cf = Join-Path (Get-LogPath 'Logiciels') ('{0}_inventaires_{1:yyyy-MM}.log' -f $env:COMPUTERNAME, (Get-Date))
                try {
                    [void][IO.Directory]::CreateDirectory((Split-Path $cf))
                    [IO.File]::AppendAllText($cf, (($lines | ForEach-Object { '{0:yyyy-MM-dd HH:mm:ss} {1}' -f (Get-Date), $_ }) -join [Environment]::NewLine) + [Environment]::NewLine, [Text.Encoding]::UTF8)
                } catch {
                    Write-Ignored 'Journal des inventaires de logiciels' $_
                }
            }
        }
        $SoftUI.Fresh = $true
        Update-SoftView
        # bandeau dans la fenêtre + notification Windows dès la fin de la recherche (sans attendre la ronde des alertes)
        try { Update-SoftUpdBanner; if (-not $r.ListMerge) { Watch-PcAlert } } catch { Write-Ignored 'Bandeau des mises à jour des logiciels' $_ }
        try { Update-AppsInstalledFromInv } catch { Write-Ignored 'Catalogue Applications (badges Installé)' $_ }
    }
    if ($SoftUI.Win -and ($Sync.WgRunning -or $SoftUI.WasRunning -or $Sync.Running -or [bool]$Sync.Running -ne [bool]$SoftUI.WasBusy)) {
        $SoftUI.WasRunning = [bool]$Sync.WgRunning; $SoftUI.WasBusy = [bool]$Sync.Running; Update-SoftStatus
    }
    $up = @(Get-SoftUpdate | Where-Object { -not $SoftExcl[(Get-SoftKey $_)] })
    $txt = $(if ($Sync.WgRunning) { 'Recherche en cours...' } elseif (-not $r) { 'Aucun inventaire : ouvrir pour lancer la recherche.' } elseif ($r.Error) { 'Dernière recherche impossible : ' + $r.Error } else {
        $age = try { Format-Age ([DateTime](Get-SoftSearchStamp $r)) } catch { '' }
        '{0} {1}, {2}  ·  dernière recherche : {3}' -f @($r.Apps).Count, (Get-Plural @($r.Apps).Count 'logiciel' 'logiciels'), $(if ($up.Count) { '{0} {1}' -f $up.Count, (Get-Plural $up.Count 'mise à jour disponible' 'mises à jour disponibles') } else { 'tous à jour' }), $age })
    if ($SoftUI.CardText.Text -ne $txt) { $SoftUI.CardText.Text = $txt }
    $mt = $(if ($up.Count) { "Mettre à jour ($($up.Count))" } else { 'Mettre à jour' }); if ($Ui.AppsModeUpdTxt.Text -ne $mt) { $Ui.AppsModeUpdTxt.Text = $mt }
    # couleurs d'état communes aux 3 cartes de mises à jour : à faire = orange, à jour = vert, en cours / inconnu = gris
    $SoftUI.CardText.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, $(if ($Sync.WgRunning -or -not $r -or $r.Error) { 'MutedBrush' } elseif ($up.Count) { 'WarnFgBrush' } else { 'OkFgBrush' }))
    if (-not $Sync.WgRunning -and $up.Count -ne [int]$UpdBanner.N) { try { Update-SoftUpdBanner } catch { Write-Ignored 'Bandeau des mises à jour des logiciels' $_ } }
}
function New-SoftCard {
    $b = [Windows.Controls.Border]::new(); $b.Style = $Window.FindResource('Panel'); $b.Padding = New-Thickness 16 14 16 14; $b.Margin = New-Thickness 0 12 0 0
    [Windows.Controls.DockPanel]::SetDock($b, 'Bottom')
    $g = [Windows.Controls.Grid]::new(); $b.Child = $g
    $sp = [Windows.Controls.StackPanel]::new(); $sp.VerticalAlignment = 'Center'; $sp.Margin = New-Thickness 0 0 130 0
    $dp = [Windows.Controls.DockPanel]::new()
    $ic = New-Text ([string][char]0xE7B8); $ic.Style = $Window.FindResource('CardIcon'); [Windows.Controls.DockPanel]::SetDock($ic, 'Left')
    $tt = New-Text 'Logiciels'; $tt.Style = $Window.FindResource('Section')
    [void]$dp.Children.Add($ic); [void]$dp.Children.Add($tt); [void]$sp.Children.Add($dp)
    $d = New-Text 'Inventaire des logiciels installés et mises à jour disponibles (winget)' 'Muted'
    $d.Margin = New-Thickness 30 4 0 0
    [void]$sp.Children.Add($d)
    $SoftUI.CardText = New-Text '' 'Muted'; $SoftUI.CardText.Margin = New-Thickness 30 4 0 0; [void]$sp.Children.Add($SoftUI.CardText)
    # bord droit des boutons des cartes de Maintenance : marge de carte 16 + retrait des lignes 8 + marge du bouton 6 = 30
    $btn = New-Button 'Ouvrir'
    $btn.MinWidth = 110
    $btn.HorizontalAlignment = 'Right'
    $btn.VerticalAlignment = 'Center'
    $btn.Margin = New-Thickness 0 0 14 0
    $btn.Add_Click({
        try { Show-SoftWindow } catch {
            Write-UiLog "Fenêtre Logiciels : $($_.Exception.Message)" 'ERROR'
            Show-Info "Ouverture de la fenêtre Logiciels impossible.`n`n$($_.Exception.Message)" 'Error'
        }
    })
    [void]$g.Children.Add($sp); [void]$g.Children.Add($btn)
    # premier enfant ancré en bas = tout en bas : la carte passe sous Espace disque
    $Ui.MaintLeft.Children.Insert(0, $b)
    try {
        if (Test-Path -LiteralPath $SoftFile) {
            $Sync.WgResult = Get-Content -LiteralPath $SoftFile -Raw -Encoding UTF8 | ConvertFrom-Json
            $SoftUI.Shown = $Sync.WgResult.Stamp
        }
    } catch {
        Write-Ignored 'Lecture du dernier inventaire des logiciels' $_
    }
    $SoftUI.Fresh = $true
    Update-SoftCard
}
$SoftXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Oliv_Maintenance - Logiciels" Width="1100" Height="760" MinWidth="760" MinHeight="480" WindowStartupLocation="Manual"
        Background="{DynamicResource BgBrush}" Foreground="{DynamicResource FgBrush}" FontFamily="Segoe UI" FontSize="13">
  <Grid Margin="16,14,16,12">
    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
    <DockPanel Margin="0,0,0,10">
      <StackPanel DockPanel.Dock="Right" Orientation="Horizontal">
        <!-- même champ que la recherche globale : pastille arrondie, loupe, contour bleu au focus -->
        <Border x:Name="FindBox" Width="240" Height="30" CornerRadius="15" Background="{DynamicResource BgBrush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="1.5" VerticalAlignment="Center" Cursor="IBeam">
          <Grid>
            <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
            <TextBlock Text="&#xE721;" FontFamily="Segoe MDL2 Assets" FontSize="12" Foreground="{DynamicResource AccentBrush}" Margin="12,0,8,0" VerticalAlignment="Center"/>
            <TextBox x:Name="Find" Grid.Column="1" BorderThickness="0" Background="Transparent" Foreground="{DynamicResource FgBrush}" CaretBrush="{DynamicResource FgBrush}" VerticalAlignment="Center" Margin="0,0,12,0" FontSize="13">
              <TextBox.Template><ControlTemplate TargetType="TextBox"><ScrollViewer x:Name="PART_ContentHost" Focusable="False" HorizontalScrollBarVisibility="Hidden" VerticalScrollBarVisibility="Hidden" Background="Transparent"/></ControlTemplate></TextBox.Template>
            </TextBox>
            <TextBlock x:Name="FindHint" Grid.Column="1" Text="Filtrer la liste" Foreground="{DynamicResource MutedBrush}" VerticalAlignment="Center" IsHitTestVisible="False"/>
          </Grid>
        </Border>
        <Button x:Name="Stop" Content="Annuler la recherche" Style="{DynamicResource WarnBtn}" Height="30" Margin="6,0,0,0" Visibility="Collapsed"/>
        <Button x:Name="Go" Content="Rechercher" Style="{DynamicResource PrimaryBtn}" Height="30" MinWidth="110" Margin="6,0,0,0"/>
      </StackPanel>
      <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
        <Button x:Name="FUpd" Style="{DynamicResource ActionBtn}" Height="30" Padding="12,0" Margin="0,0,6,0"/>
        <Button x:Name="FAll" Style="{DynamicResource ActionBtn}" Height="30" Padding="12,0" Margin="0,0,6,0" Visibility="Collapsed"/>
        <Button x:Name="FExcl" Style="{DynamicResource ActionBtn}" Height="30" Padding="12,0" Margin="0,0,6,0"/>
        <Button x:Name="FHist" Style="{DynamicResource ActionBtn}" Height="30" Padding="12,0" Margin="0,0,6,0"/>
      </StackPanel>
    </DockPanel>
    <!-- encart : répartition des logiciels par gestionnaire de mises à jour -->
    <Border x:Name="SumBox" Grid.Row="1" Margin="0,0,0,8" Padding="14,8" CornerRadius="6" Background="{DynamicResource PanelBrush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="1" Visibility="Collapsed">
      <WrapPanel VerticalAlignment="Center">
        <TextBlock x:Name="SumTot" FontWeight="SemiBold" VerticalAlignment="Center" Margin="0,0,14,0"/>
        <Border x:Name="PWg" Tag="wg" CornerRadius="12" Padding="9,3" Margin="0,0,8,0" BorderThickness="1" BorderBrush="Transparent" Background="Transparent" Cursor="Hand" VerticalAlignment="Center"
                ToolTip="Mis à jour par winget : paquet du dépôt winget, ou correspondance trouvée par nom. Clic : filtrer la liste, nouveau clic : tout afficher">
          <StackPanel Orientation="Horizontal"><Ellipse Width="8" Height="8" Fill="{DynamicResource AccentBrush}" VerticalAlignment="Center" Margin="0,0,7,0"/><TextBlock x:Name="SumWg" VerticalAlignment="Center"/></StackPanel>
        </Border>
        <Border x:Name="PMs" Tag="ms" CornerRadius="12" Padding="9,3" Margin="0,0,8,0" BorderThickness="1" BorderBrush="Transparent" Background="Transparent" Cursor="Hand" VerticalAlignment="Center"
                ToolTip="Mis à jour par le Microsoft Store : recherche des mises à jour auprès du Store avec celle de winget. Clic : filtrer la liste, nouveau clic : tout afficher">
          <StackPanel Orientation="Horizontal"><Ellipse Width="8" Height="8" Fill="#8B6CF0" VerticalAlignment="Center" Margin="0,0,7,0"/><TextBlock x:Name="SumMs" VerticalAlignment="Center"/></StackPanel>
        </Border>
        <Border x:Name="PNo" Tag="no" CornerRadius="12" Padding="9,3" Margin="0,0,8,0" BorderThickness="1" BorderBrush="Transparent" Background="Transparent" Cursor="Hand" VerticalAlignment="Center"
                ToolTip="Inconnus de winget et du Microsoft Store : mise à jour par le logiciel lui-même ou manuelle. Clic : filtrer la liste, nouveau clic : tout afficher">
          <StackPanel Orientation="Horizontal"><Ellipse Width="8" Height="8" Fill="{DynamicResource MutedBrush}" VerticalAlignment="Center" Margin="0,0,7,0"/><TextBlock x:Name="SumNo" VerticalAlignment="Center" Foreground="{DynamicResource MutedBrush}"/></StackPanel>
        </Border>
      </WrapPanel>
    </Border>
    <Border Grid.Row="2" Background="{DynamicResource PanelBrush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="1" CornerRadius="6">
      <Grid>
        <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
        <!-- en-tête : mêmes marges que les lignes (liste 4 + liseré 3 + marge 6) et place de la barre de défilement réservée -->
        <Grid x:Name="Head" Margin="13,8,27,6">
          <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="150"/><ColumnDefinition Width="150"/><ColumnDefinition Width="170"/><ColumnDefinition Width="80"/></Grid.ColumnDefinitions>
          <TextBlock x:Name="H0" Text="NOM" Foreground="{DynamicResource MutedBrush}" FontSize="11" FontWeight="SemiBold"/>
          <TextBlock x:Name="H1" Grid.Column="1" Text="VERSION INSTALLÉE" Foreground="{DynamicResource MutedBrush}" FontSize="11" FontWeight="SemiBold"/>
          <TextBlock x:Name="H2" Grid.Column="2" Text="DISPONIBLE" Foreground="{DynamicResource MutedBrush}" FontSize="11" FontWeight="SemiBold"/>
          <TextBlock x:Name="H3" Grid.Column="3" Text="SOURCE" Foreground="{DynamicResource MutedBrush}" FontSize="11" FontWeight="SemiBold"/>
        </Grid>
        <Border Grid.Row="1" Height="1" VerticalAlignment="Top" Background="{DynamicResource LineBrush}"/>
        <ScrollViewer x:Name="Scroll" Grid.Row="1" VerticalScrollBarVisibility="Visible" Focusable="False"><StackPanel x:Name="List" Margin="4"/></ScrollViewer>
        <!-- liste vide : icône d'état, message, action utile (voir tous les logiciels, effacer la recherche, relancer) -->
        <StackPanel x:Name="Empty" Grid.Row="1" HorizontalAlignment="Center" VerticalAlignment="Center" Margin="20" Visibility="Collapsed">
          <TextBlock x:Name="HintIcon" FontFamily="Segoe MDL2 Assets" FontSize="34" HorizontalAlignment="Center" Margin="0,0,0,12" Foreground="{DynamicResource MutedBrush}"/>
          <TextBlock x:Name="Hint" Foreground="{DynamicResource FgBrush}" FontSize="14" HorizontalAlignment="Center" TextAlignment="Center" TextWrapping="Wrap" MaxWidth="460"/>
          <Button x:Name="HintLink" Style="{DynamicResource ActionBtn}" Height="30" Margin="0,14,0,0" HorizontalAlignment="Center" Visibility="Collapsed"/>
        </StackPanel>
      </Grid>
    </Border>
    <DockPanel Grid.Row="3" Margin="0,10,0,0">
      <ProgressBar x:Name="Prog" DockPanel.Dock="Bottom" Height="4" Margin="0,6,0,0" IsIndeterminate="True" Visibility="Collapsed" Foreground="{DynamicResource AccentBrush}" Background="Transparent" BorderThickness="0"/>
      <StackPanel DockPanel.Dock="Right" Orientation="Horizontal">
        <Button x:Name="HistClear" Content="Vider l'historique" Style="{DynamicResource WarnBtn}" Height="30" Margin="6,0,0,0" Visibility="Collapsed"/>
        <Button x:Name="RunStop" Content="Interrompre" Style="{DynamicResource WarnBtn}" Height="30" Margin="6,0,0,0" Visibility="Collapsed"/>
        <Button x:Name="Reinst" Style="{DynamicResource ActionBtn}" Height="30" Margin="6,0,0,0" Padding="12,0" IsEnabled="False" Visibility="Collapsed" MaxWidth="300"/>
        <Button x:Name="Run" Style="{DynamicResource PrimaryBtn}" Height="30" Margin="6,0,0,0" IsEnabled="False" MaxWidth="440"/>
      </StackPanel>
      <!-- zoom propre à la fenêtre (Ctrl + molette, Ctrl + / Ctrl -, Ctrl + 0, clic sur le pourcentage : 100 %) -->
      <Border DockPanel.Dock="Left" Height="30" Padding="2,0" Margin="0,0,12,0" CornerRadius="6" Background="{DynamicResource BgBrush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="1" VerticalAlignment="Center"
              ToolTip="Taille du texte de la liste (80 à 150 %) : Ctrl + molette ou Ctrl + / Ctrl -, clic sur le pourcentage ou Ctrl + 0 pour revenir à 100 %">
        <StackPanel Orientation="Horizontal">
          <Button x:Name="ZoomOut" Style="{DynamicResource IconBtn}" Width="28" Height="26" FontSize="12" Content="&#xE71F;"/>
          <TextBlock x:Name="ZoomTxt" Foreground="{DynamicResource MutedBrush}" FontSize="12" Width="44" TextAlignment="Center" VerticalAlignment="Center" Cursor="Hand" Text="100 %"/>
          <Button x:Name="ZoomIn" Style="{DynamicResource IconBtn}" Width="28" Height="26" FontSize="12" Content="&#xE8A3;"/>
        </StackPanel>
      </Border>
      <TextBlock x:Name="Status" Foreground="{DynamicResource MutedBrush}" VerticalAlignment="Center" TextWrapping="NoWrap" TextTrimming="CharacterEllipsis"/>
    </DockPanel>
  </Grid>
</Window>
'@
# Mises à jour des logiciels intégrées à l'onglet Applications (mode « Mettre à jour ») : contenu de l'ancienne fenêtre
# Logiciels construit une fois depuis son XAML puis déplacé dans l'onglet ($Ui.AppsUpdHost) ; la fenêtre, jamais
# affichée, reste l'objet de référence ($SoftUI.Win : « vue construite », répartiteur). Show-SoftWindow : ouvre l'onglet.
function Show-SoftWindow {
    # 1re ouverture de la session : recherche lancée par Set-SoftScope (pas pendant une mise à jour)
    Set-AppsMode 'Upd'; Show-Page 'Apps'
}
