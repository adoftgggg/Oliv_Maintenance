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
    foreach ($pk in @(Get-WinGetPackage -ErrorAction Stop)) {
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
$SoftExclFile = Join-Path (Get-LogPath 'Etat') 'logiciels-exclus.json'
$SoftExcl = @{}
try {
    if (Test-Path -LiteralPath $SoftExclFile) {
        foreach ($k in @(Get-Content -LiteralPath $SoftExclFile -Raw -Encoding UTF8 | ConvertFrom-Json)) { $SoftExcl["$k"] = $true }
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
            try {
                $o = @{} + $r
                $o.Stamp = ([DateTime]$r.Stamp).ToString('o')
                ConvertTo-Json -InputObject $o -Depth 4 | Set-Content -LiteralPath $SoftFile -Encoding UTF8
            } catch {
                Write-Ignored 'Enregistrement de l''inventaire des logiciels' $_
            }
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
function Initialize-SoftView {
    $w = [Windows.Markup.XamlReader]::Load([System.Xml.XmlNodeReader]::new([xml]$SoftXaml))
    foreach ($n in 'Stop', 'Go', 'Head', 'FUpd', 'FAll', 'FExcl', 'FHist', 'H0', 'H1', 'H2', 'H3', 'FindBox', 'SumBox', 'SumTot', 'SumWg', 'SumMs', 'SumNo', 'PWg', 'PMs', 'PNo', 'Find', 'FindHint', 'Scroll', 'List', 'Hint', 'Empty', 'HintIcon', 'HintLink', 'Prog', 'HistClear', 'RunStop', 'Run', 'Reinst', 'Status') {
        $SoftUI[$n] = $w.FindName($n)
    }
    $SoftUI.Win = $w
    # contenu déplacé dans l'onglet Applications (marges de la page)
    $root = $w.Content; $w.Content = $null; $root.Margin = New-Thickness 0 0 0 0
    [void]$Ui.AppsUpdHost.Children.Add($root)
    # en-tête aligné sur les lignes : marge droite = largeur réelle de la barre de défilement (style de l'application) + marges des lignes
    $SoftUI.Head = $w.FindName('Head')
    $SoftUI.Scroll.Add_SizeChanged({
        $sb = [math]::Max([double]0, $SoftUI.Scroll.ActualWidth - $SoftUI.Scroll.ViewportWidth)
        $SoftUI.Head.Margin = New-Thickness 13 8 (10 + $sb) 6
    })
    $SoftUI.Scroll.Add_ScrollChanged({
        $sb = [math]::Max([double]0, $SoftUI.Scroll.ActualWidth - $SoftUI.Scroll.ViewportWidth)
        $SoftUI.Head.Margin = New-Thickness 13 8 (10 + $sb) 6
    })
    foreach ($f in @(@{ B = $SoftUI.FUpd; K = 'Upd' }, @{ B = $SoftUI.FAll; K = 'All' }, @{ B = $SoftUI.FExcl; K = 'Excl' }, @{ B = $SoftUI.FHist; K = 'Hist' })) {
        $f.B.DataContext = $f.K; $f.B.Add_Click({ param($s, $e) $SoftUI.Filter = $s.DataContext; Update-SoftView })
    }
    # recherche : vue recalculée 200 ms après la dernière frappe (pas à chaque caractère)
    $SoftUI.FindTimer = [Windows.Threading.DispatcherTimer]::new(); $SoftUI.FindTimer.Interval = [TimeSpan]::FromMilliseconds(200)
    $SoftUI.FindTimer.Add_Tick({ $SoftUI.FindTimer.Stop(); Update-SoftView })
    $SoftUI.Find.Add_TextChanged({
        $SoftUI.FindHint.Visibility = $(if ($SoftUI.Find.Text) { 'Collapsed' } else { 'Visible' })
        $SoftUI.FindTimer.Stop()
        $SoftUI.FindTimer.Start()
    })
    $SoftUI.Find.Add_GotKeyboardFocus({ $SoftUI.FindBox.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, 'AccentBrush') })
    $SoftUI.Find.Add_LostKeyboardFocus({ $SoftUI.FindBox.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, 'LineBrush') })
    $SoftUI.FindBox.Add_MouseLeftButtonDown({ [void]$SoftUI.Find.Focus() })
    $root.Add_PreviewMouseLeftButtonDown($ClearTextFocus)
    $SoftUI.Go.Add_Click({ Start-SoftSearch })
    # pastilles de l'encart : filtre par gestionnaire (appui et relâchement sur la même pastille), nouveau clic : sans filtre
    foreach ($pb in $SoftUI.PWg, $SoftUI.PMs, $SoftUI.PNo) {
        $pb.Add_MouseEnter({ param($s, $e)
            if ($SoftUI.Filter -eq 'All' -and $SoftUI.SrcFilter -ne "$($s.Tag)") { $s.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, 'HoverBrush') }
        })
        $pb.Add_MouseLeave({ param($s, $e) if ($SoftUI.SrcFilter -ne "$($s.Tag)") { $s.Background = [Windows.Media.Brushes]::Transparent } })
        $pb.Add_MouseLeftButtonDown({ param($s, $e) $SoftUI.PPress = $s })
        $pb.Add_MouseLeftButtonUp({ param($s, $e) if ($SoftUI.Filter -ne 'All' -or -not [object]::ReferenceEquals($SoftUI.PPress, $s)) { return }; $SoftUI.PPress = $null
            $SoftUI.SrcFilter = $(if ($SoftUI.SrcFilter -eq "$($s.Tag)") { $null } else { "$($s.Tag)" }); Update-SoftView })
    }
    $SoftUI.HintLink.Add_Click({ param($s, $e)
        switch ("$($s.Tag)") { 'q' { $SoftUI.Find.Text = '' } 'src' {
            $SoftUI.SrcFilter = $null
            Update-SoftView
        } 'search' { if ($SoftUI.Filter -eq 'All') { Start-SoftSearch -ListOnly } else { Start-SoftSearch } } default { Set-AppsMode 'Mine' } }
    })
    $SoftUI.Stop.Add_Click({ Stop-SoftSearch })
    $SoftUI.RunStop.Add_Click({ Stop-SoftUpgrade })
    $SoftUI.HistClear.Add_Click({ Clear-SoftHistory })
    # un seul bouton : sélection si des lignes sont en surbrillance, sinon toutes les mises à jour non exclues
    # Mes applications (filtre All) : désinstallation de la sélection ; Mettre à jour : mises à jour
    $SoftUI.Run.Add_Click({ if ($SoftUI.Filter -eq 'All') { Invoke-SoftRemove @(Get-SoftRemoveTarget) 'uninstall' } else { Invoke-SoftUpgrade @(Get-SoftRunTarget) } })
    $SoftUI.Reinst.Add_Click({ Invoke-SoftRemove @(Get-SoftRemoveTarget) 'reinstall' })
    # clic hors d'une ligne (zone vide de la liste, en-têtes, bas de fenêtre) : sélection vidée ;
    # boutons, barre de défilement et champ de filtre ignorés (le bouton Mettre à jour agit sur la sélection)
    $root.Add_PreviewMouseLeftButtonDown({
        param($s, $e)
        if (-not $SoftUI.SelSet -or -not $SoftUI.SelSet.Count) { return }
        $el = $e.OriginalSource
        while ($el) {
            if ($el -is [Windows.Controls.Primitives.ButtonBase] -or $el -is [Windows.Controls.Primitives.ScrollBar] -or $el -is [Windows.Controls.TextBox]) {
                return
            }
            $par = $(if ($el -is [Windows.Media.Visual] -or $el -is [Windows.Media.Media3D.Visual3D]) { [Windows.Media.VisualTreeHelper]::GetParent($el) } else { [Windows.LogicalTreeHelper]::GetParent($el) })
            if ($par -eq $SoftUI.List) { return }
            $el = $par
        }
        $SoftUI.SelSet.Clear(); Update-SoftSelection
    })
    # Ctrl+A : tout sélectionner dans la vue ; Échap : vider la sélection
    $root.Add_PreviewKeyDown({
        param($s, $e)
        if ($SoftUI.Find.IsKeyboardFocusWithin) { return }
        if ($e.Key -eq 'A' -and ([Windows.Input.Keyboard]::Modifiers -band [Windows.Input.ModifierKeys]::Control)) {
            foreach ($k in $SoftUI.Order) { [void]$SoftUI.SelSet.Add($k) }
            Update-SoftSelection
            $e.Handled = $true
        }
        elseif ($e.Key -eq 'Escape') { $SoftUI.SelSet.Clear(); Update-SoftSelection; $e.Handled = $true }
    })
    Update-SoftView
}
# sélection multiple (lignes en surbrillance) : ensemble de clés, ordre d'affichage pour Maj+clic
# nom court pour les boutons et titres : sans numéro de version ni architecture (« Microsoft Visual C++ v14 Redistributable (x86) »
# -> « Microsoft Visual C++ Redistributable »)
function Get-SoftShortName([string]$N) {
    $t = $N -replace '\((x64|x86|amd64|arm64|64[- ]?bits?|32[- ]?bits?)[^)]*\)', '' -replace '\b(x64|x86|amd64|arm64|64[- ]?bits?|32[- ]?bits?)\b', ''
    # retirés : « v14 », numéros à points (23.01, 14.40.33810), nombres de 3 chiffres et plus et plages d'années (401, 2015-2022)
    $t = $t -replace '\s+v\d+([._]\d+)*\b', '' -replace '\s+-?\s*\d+([._]\d+)+\S*', '' -replace '\s+\d{3,}(-\d{3,})?\b', ''
    $t = $t -replace '\s+\(\s*\)', '' -replace '\s{2,}', ' ' -replace '[\s\-_,]+$', ''
    $(if ($t.Trim()) { $t.Trim() } else { $N })
}
# cibles du bouton : lignes sélectionnées ayant une mise à jour (version inconnue seulement si choisie seule), sinon toutes les non exclues
# Applications : « Mes applications » (liste complète, sans onglets de filtre) ou « Mettre à jour » (mises à jour,
# exclus, historique ; dernier onglet conservé). Sélection vidée au changement.
function Set-SoftScope([string]$Mode) {
    if ($Mode -eq 'Mine') { if ($SoftUI.Filter -ne 'All') { $SoftUI.UpdFilter = $SoftUI.Filter }; $SoftUI.Filter = 'All' }
    elseif ($SoftUI.Filter -eq 'All') { $SoftUI.Filter = $(if ($SoftUI.UpdFilter) { $SoftUI.UpdFilter } else { 'Upd' }); $SoftUI.SrcFilter = $null }
    $v = $(if ($Mode -eq 'Mine') { 'Collapsed' } else { 'Visible' })
    foreach ($b in $SoftUI.FUpd, $SoftUI.FExcl, $SoftUI.FHist) { $b.Visibility = $v }
    # Mes applications : affichage du dernier inventaire, aucune recherche (simple lecture s'il n'y en a pas) ;
    # Mettre à jour : recherche complète à la 1re ouverture de la session
    if (-not $Sync.WgRunning -and -not (Test-SoftUpgrading)) {
        if ($Mode -eq 'Upd' -and -not $SoftUI.Searched) { Start-SoftSearch }
        elseif ($Mode -eq 'Mine' -and (-not $Sync.WgResult -or -not $SoftUI.ListRead -or ([DateTime]::Now - $SoftUI.ListRead).TotalMinutes -ge 2)) { Start-SoftSearch -ListOnly }
    }
    if ($SoftUI.SelSet -and $SoftUI.SelSet.Count) { $SoftUI.SelSet.Clear(); Update-SoftSelection }
    Update-SoftView
    Update-SoftStatus
}
# désinstallation / réinstallation : lignes sélectionnées connues de winget (identifiant local)
function Get-SoftRemoveTarget { @(Get-SoftSelectedApp | Where-Object { Get-SoftLocalId $_ }) }
function Get-SoftRunTarget {
    $sel = @(Get-SoftSelectedApp)
    if ($sel.Count) { return @($sel | Where-Object { $_.To -and $_.Src -and ($sel.Count -eq 1 -or -not $_.Unknown) }) }
    @(Get-SoftUpdate | Where-Object { -not $SoftExcl[(Get-SoftKey $_)] })
}
function Get-SoftSelectedApp { if (-not $SoftUI.SelSet -or -not $SoftUI.Rows) { return @() }; @($SoftUI.Order | Where-Object { $SoftUI.SelSet.Contains($_) } | Where-Object { $SoftUI.Rows.ContainsKey($_) } | ForEach-Object { $SoftUI.Rows[$_].DataContext }) }
function Select-SoftOnly($Key) { $SoftUI.SelSet.Clear(); if ($Key) { [void]$SoftUI.SelSet.Add($Key) }; $SoftUI.Anchor = $Key; Update-SoftSelection }
function Select-SoftToggle($Key) { if (-not $SoftUI.SelSet.Remove($Key)) { [void]$SoftUI.SelSet.Add($Key) }; $SoftUI.Anchor = $Key; Update-SoftSelection }
function Select-SoftRange($Key) {
    $a = $SoftUI.Order.IndexOf("$($SoftUI.Anchor)"); $b = $SoftUI.Order.IndexOf($Key)
    if ($a -lt 0) { Select-SoftOnly $Key; return }
    $SoftUI.SelSet.Clear()
    foreach ($i in ([math]::Min($a, $b))..([math]::Max($a, $b))) { [void]$SoftUI.SelSet.Add($SoftUI.Order[$i]) }
    Update-SoftSelection
}
function Update-SoftSelection {
    if ($SoftUI.Rows) {
        foreach ($k in @($SoftUI.Rows.Keys)) {
            $r = $SoftUI.Rows[$k]
            if ($SoftUI.SelSet.Contains($k)) {
                $r.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, 'BtnBrush')
                $r.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, 'AccentBrush')
            }
            else { $r.Background = [Windows.Media.Brushes]::Transparent; $r.BorderBrush = [Windows.Media.Brushes]::Transparent }
        }
    }
    Update-SoftStatus
}
function Set-SoftExcluded($Apps, [bool]$On) {
    foreach ($a in @($Apps | Where-Object { $_.Src })) {
        $k = Get-SoftKey $a
        if ($On) {
            $SoftExcl[$k] = $true
            Write-UiLog "Logiciel exclu des mises à jour : $($a.Name)."
        } elseif ($SoftExcl.ContainsKey($k)) {
            $SoftExcl.Remove($k)
            Write-UiLog "Logiciel réintégré aux mises à jour : $($a.Name)."
        }
    }
    Save-SoftExcl; Update-SoftView; Update-SoftCard
}
function Show-SoftMenu($Row) {
    $sel = @(Get-SoftSelectedApp); if (-not $sel.Count) { $sel = @($Row.DataContext) }
    $one = $sel.Count -eq 1; $busy = $Sync.Running -or $Sync.WgRunning
    $up = @($sel | Where-Object { $_.To -and $_.Src -and ($one -or -not $_.Unknown) })
    $exIn = @($sel | Where-Object { $_.Src -and -not $SoftExcl[(Get-SoftKey $_)] })
    $exOut = @($sel | Where-Object { $_.Src -and $SoftExcl[(Get-SoftKey $_)] })
    $m = [Windows.Controls.ContextMenu]::new(); $m.PlacementTarget = $Row
    $add = {
        param([string]$Head, [scriptblock]$Act, $Data, [bool]$On = $true)
        $mi = [Windows.Controls.MenuItem]::new(); $mi.Header = $Head; $mi.IsEnabled = $On; $mi.Tag = $Data
        if ($Act) { $mi.Add_Click($Act) }
        [void]$m.Items.Add($mi)
    }
    if ($up.Count) {
        $h = $(if ($one -and $up[0].Unknown) { 'Réinstaller la dernière version' } elseif ($one) { 'Mettre à jour ce logiciel' } else { "Mettre à jour les $($up.Count) logiciels sélectionnés" })
        & $add $h { param($s, $e) Invoke-SoftUpgrade $s.Tag } $up (-not $busy)
    }
    if ($exIn.Count) {
        & $add $(if ($exIn.Count -eq 1) { 'Exclure des mises à jour' } else { "Exclure les $($exIn.Count) logiciels des mises à jour" }) { param($s, $e) Set-SoftExcluded $s.Tag $true } $exIn
    }
    if ($exOut.Count) {
        & $add $(if ($exOut.Count -eq 1) { 'Réintégrer aux mises à jour' } else { "Réintégrer les $($exOut.Count) logiciels aux mises à jour" }) { param($s, $e) Set-SoftExcluded $s.Tag $false } $exOut
    }
    # désinstaller (tout logiciel de l'inventaire) / réinstaller (paquet winget ou application du Store) / retirer une
    # entrée orpheline (logiciel déjà absent du poste)
    $orph = @($sel | Where-Object { $_.Orphan -and $_.RegKey })
    $uni = @($sel | Where-Object { -not $_.Orphan -and (Get-SoftLocalId $_) })
    $rei = @($uni | Where-Object { $_.Src -eq 'winget' -or $_.Pfn })
    if ($m.Items.Count -and ($uni.Count -or $orph.Count)) { [void]$m.Items.Add([Windows.Controls.Separator]::new()) }
    if ($rei.Count) {
        & $add $(if ($rei.Count -eq 1) { 'Réinstaller (désinstaller puis installer la dernière version)' } else { "Réinstaller les $($rei.Count) logiciels" }) { param($s, $e) Invoke-SoftRemove $s.Tag 'reinstall' } $rei (-not $busy)
    }
    if ($uni.Count) {
        & $add $(if ($uni.Count -eq 1) { 'Désinstaller' } else { "Désinstaller les $($uni.Count) logiciels" }) { param($s, $e) Invoke-SoftRemove $s.Tag 'uninstall' } $uni (-not $busy)
    }
    if ($orph.Count) {
        & $add $(if ($orph.Count -eq 1) { 'Retirer l''entrée (reste d''installation)' } else { "Retirer les $($orph.Count) entrées (restes d'installation)" }) { param($s, $e) Remove-SoftOrphan $s.Tag } $orph (-not $busy)
    }
    if ($m.Items.Count) { [void]$m.Items.Add([Windows.Controls.Separator]::new()) }
    # logiciels en échec lors de la dernière mise à jour : détail de l'erreur copiable
    $failed = @($sel | Where-Object { $Sync.SoftRun -and $Sync.SoftRun.Items["$($_.Id)"] -and $Sync.SoftRun.Items["$($_.Id)"].State -eq 'fail' })
    if ($failed.Count) {
        & $add $(if ($failed.Count -eq 1) { 'Copier l''erreur' } else { "Copier les $($failed.Count) erreurs" }) { param($s, $e) Set-ClipText ((@($s.Tag | ForEach-Object { Get-SoftErrorText "$($_.Id)" }) -join "`r`n`r`n")) } $failed
    }
    & $add 'Copier la version installée' { param($s, $e) Set-ClipText ((@($s.Tag | ForEach-Object { "$($_.From)" }) -join "`r`n")) } $sel
    & $add $(if ($one) { 'Copier la ligne' } else { 'Copier les lignes' }) { param($s, $e) Set-ClipText ((@($s.Tag | ForEach-Object { Format-SoftAppLine $_ }) -join "`r`n")) } $sel
    & $add $(if ($one) { 'Copier le nom' } else { 'Copier les noms' }) { param($s, $e) Set-ClipText ((@($s.Tag | ForEach-Object { "$($_.Name)" }) -join "`r`n")) } $sel
    & $add $(if ($one) { 'Copier l''identifiant' } else { 'Copier les identifiants' }) { param($s, $e) Set-ClipText ((@($s.Tag | Where-Object { $_.Id } | ForEach-Object { "$($_.Id)" }) -join "`r`n")) } $sel
    $m.IsOpen = $true
}
# codes de retour de winget (APPINSTALLER_CLI_ERROR_*, documentation winget-cli) : signification et conduite à tenir
$WingetErr = @{
    '0x8A150101' = @('INSTALL_PACKAGE_IN_USE', 'le logiciel est ouvert : le fermer puis relancer la mise à jour')
    '0x8A150102' = @('INSTALL_INSTALL_IN_PROGRESS', 'une autre installation est déjà en cours : réessayer plus tard')
    '0x8A150103' = @('INSTALL_FILE_IN_USE', 'des fichiers du logiciel sont utilisés : le fermer puis relancer la mise à jour')
    '0x8A150104' = @('INSTALL_MISSING_DEPENDENCY', 'un composant requis par le logiciel est absent du poste')
    '0x8A150105' = @('INSTALL_DISK_FULL', 'espace disque insuffisant')
    '0x8A150106' = @('INSTALL_INSUFFICIENT_MEMORY', 'mémoire insuffisante : fermer des applications puis réessayer')
    '0x8A150107' = @('INSTALL_NO_NETWORK', 'connexion Internet requise')
    '0x8A150108' = @('INSTALL_CONTACT_SUPPORT', 'erreur de l''installeur : voir la sortie ci-dessous ou l''éditeur')
    '0x8A150109' = @('INSTALL_REBOOT_REQUIRED_TO_FINISH', 'redémarrage du poste nécessaire pour terminer l''installation')
    '0x8A15010A' = @('INSTALL_REBOOT_REQUIRED_TO_INSTALL', 'redémarrer le poste puis relancer la mise à jour')
    '0x8A15010B' = @('INSTALL_REBOOT_INITIATED', 'le poste va redémarrer pour terminer l''installation')
    '0x8A15010C' = @('INSTALL_CANCELLED_BY_USER', 'installation annulée')
    '0x8A15010D' = @('INSTALL_ALREADY_INSTALLED', 'une autre version du logiciel est déjà installée')
    '0x8A15010E' = @('INSTALL_DOWNGRADE', 'une version plus récente est déjà installée')
    '0x8A15002B' = @('UPDATE_NOT_APPLICABLE', 'aucune mise à jour applicable selon winget')
    '0x8A150011' = @('INSTALLER_HASH_MISMATCH', 'le fichier téléchargé ne correspond pas au catalogue (hachage) : réessayer plus tard')
    '0x8A150014' = @('NO_APPLICATIONS_FOUND', 'paquet introuvable dans le catalogue winget')
    '0x8A150056' = @('INSTALLER_PROHIBITS_ELEVATION', 'l''installeur refuse de s''exécuter en administrateur')
    '0x8A150061' = @('PACKAGE_ALREADY_INSTALLED', 'au moins une version du paquet est déjà installée')
}
function Format-WingetCode($Code) { $c = [int64]$Code; if ($c -lt 0) { $c += 4294967296 }; '0x{0:X8}' -f $c }
# texte d'erreur complet (clic droit > Copier l'erreur) depuis un enregistrement : Name, Id, From, To, Date, Code, Out, User, Computer
function Format-SoftError($R) {
    $c = Format-WingetCode $R.Code; $m = $WingetErr[$c]
    $d = try { '{0:dd/MM/yyyy HH:mm}' -f [DateTime]$R.Date } catch { "$($R.Date)" }
    $l = @(
        ('{0} ({1})' -f $R.Name, $R.Id),
        ('Mise à jour {0} > {1} : échec le {2} (winget, poste {3}{4})' -f $R.From, $R.To, $d, $(if ($R.Computer) { $R.Computer } else { $env:COMPUTERNAME }), $(if ($R.User) { ", utilisateur $($R.User)" } else { '' })),
        ('Code de retour : {0}{1}' -f $c, $(if ($m) { " (APPINSTALLER_CLI_ERROR_$($m[0])) - $($m[1])" } elseif ([int64]$R.Code -gt 0 -and [int64]$R.Code -lt 65536) { ' (code de sortie de l''installeur du logiciel)' } else { '' }))
    )
    if (@($R.Out).Count) { $l += 'Sortie de winget :'; $l += @($R.Out | ForEach-Object { '  ' + $_ }) }
    $l -join "`r`n"
}
# erreur de la mise à jour en cours / dernière mise à jour (fenêtre ouverte)
function Get-SoftErrorText([string]$Id) {
    $it = $Sync.SoftRun.Items[$Id]; if (-not $it -or $it.State -ne 'fail') { return '' }
    Format-SoftError @{ Name = $it.Name; Id = $Id; From = $it.From; To = $it.To; Date = $it.End; Code = $it.Code; Out = $it.Out }
}
# ligne copiée : historique « date · logiciel (id) · avant > après · résultat · utilisateur » ; liste « logiciel (id) · versions · source »
function Format-SoftHistLine($H) {
    $d = try { '{0:dd/MM/yyyy HH:mm}' -f [DateTime]$H.Date } catch { "$($H.Date)" }
    '{0}  ·  {1} ({2})  ·  {3} > {4}  ·  {5}{6}' -f $d, $H.Name, $H.Id, $H.From, $H.To, $(if ($H.Ok) { 'mis à jour' } else { 'échec ({0})' -f (Format-WingetCode $H.Code) }), $(if ($H.User) { "  ·  $($H.User)" } else { '' })
}
function Format-SoftAppLine($A) {
    '{0} ({1})  ·  installée {2}{3}  ·  {4}' -f $A.Name, $A.Id, $A.From, $(if ($A.To) { "  ·  disponible $($A.To)" } else { '' }), $A.SrcLabel
}
# purge de l'historique des mises à jour de logiciels (fichier _etat\logiciels-historique.jsonl supprimé après confirmation)
function Clear-SoftHistory {
    if ($Sync.WgRunning -or $Sync.Running) { return }
    $n = @(Get-SoftHistory).Count; if (-not $n) { return }
    $msg = "Vider l'historique des mises à jour ?`n`n{0} {1} supprimée(s) définitivement : dates, versions, résultats et détails des erreurs." -f $n, (Get-Plural $n 'entrée' 'entrées')
    if ((Show-Dialog $msg 'Warn' @(@{ T = 'Vider'; V = $true; S = 'WarnBtn' }, @{ T = 'Annuler'; V = $false; S = 'PrimaryBtn'; D = $true; C = $true })) -ne $true) {
        return
    }
    try {
        Remove-Item -LiteralPath $SoftHistFile -Force -ErrorAction Stop
        Write-UiLog "Historique des mises à jour de logiciels vidé ($n $(Get-Plural $n 'entrée' 'entrées'))."
    }
    catch {
        Write-UiLog "Historique des logiciels : $($_.Exception.Message)" 'ERROR'
        Show-Info "Impossible de vider l'historique : $($_.Exception.Message)" 'Error'
    }
    Update-SoftView
}
function Show-SoftHistMenu($Row) {
    $h = $Row.DataContext
    $Row.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, 'BtnBrush')
    $Row.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, 'AccentBrush')
    $m = [Windows.Controls.ContextMenu]::new(); $m.PlacementTarget = $Row; $m.Tag = $Row
    $m.Add_Closed({ param($s, $e)
        $r = $s.Tag
        $r.ClearValue([Windows.Controls.Border]::BackgroundProperty)
        $r.BorderBrush = [Windows.Media.Brushes]::Transparent
    })
    $add = { param([string]$Head, [string]$Text)
        $mi = [Windows.Controls.MenuItem]::new()
        $mi.Header = $Head
        $mi.Tag = $Text
        $mi.Add_Click({ param($s, $e) Set-ClipText ("$($s.Tag)") })
        [void]$m.Items.Add($mi)
    }
    if (-not $h.Ok) { & $add 'Copier l''erreur' (Format-SoftError $h) }
    # mise à jour réussie : nouvelle version installée ; échec : rien n'a changé, version installée sans objet ici
    if ($h.Ok) { & $add 'Copier la version installée' "$($h.To)" }
    & $add 'Copier la ligne' (Format-SoftHistLine $h)
    [void]$m.Items.Add([Windows.Controls.Separator]::new())
    & $add 'Copier le nom' "$($h.Name)"
    & $add 'Copier l''identifiant' "$($h.Id)"
    $m.IsOpen = $true
}
function Test-SoftUpgrading { [bool]($Sync.Running -and $Sync.Selected -contains 'SoftUpgrade') }
# texte et couleur d'état d'un logiciel pendant / après une mise à jour (colonne SOURCE)
# octets du téléchargement en cours (fichier le plus gros modifié depuis le début de l'étape dans les dossiers temporaires
# de winget : compte administrateur, et compte de l'utilisateur pour les logiciels installés dans son profil) ; relu au plus
# une fois par seconde
function Get-SoftDownloadByte($It) {
    if ($It.DlAt -and ([DateTime]::Now - $It.DlAt).TotalMilliseconds -lt 1000) { return [double]$It.DlBytes }
    $It.DlAt = [DateTime]::Now; $max = [double]0; $since = $It.PhaseT.AddSeconds(-5)
    foreach ($d in @("$env:TEMP\WinGet", $(if ($Sync.UserProfile) { "$($Sync.UserProfile)\AppData\Local\Temp\WinGet" })) | Select-Object -Unique) {
        if (-not $d -or -not [IO.Directory]::Exists($d)) { continue }
        try { foreach ($f in [IO.DirectoryInfo]::new($d).EnumerateFiles('*', 'AllDirectories')) { if ($f.LastWriteTime -ge $since -and $f.Length -gt $max) { $max = [double]$f.Length } } } catch { Write-Ignored 'Progression du téléchargement' $_ }
    }
    $It.DlBytes = $max; $max
}
function Get-SoftItemText($It) {
    switch ("$($It.State)") {
        'wait' { @{ Text = 'en attente'; Brush = 'MutedBrush' } }
        'run'  {
            $ph = $(if ($It.Phase) { "$($It.Phase)" } else { 'préparation' })
            if ($It.PhaseK -ne $ph) { $It.PhaseK = $ph; $It.PhaseT = [DateTime]::Now }
            $el = [DateTime]::Now - $It.PhaseT
            $t = "$ph..."
            if ($ph -eq 'téléchargement') {
                # winget n'affiche pas sa progression quand sa sortie est redirigée : taille du fichier en cours de
                # téléchargement (dossier temporaire de winget) rapportée à la taille de l'installeur (en-tête HTTP)
                $b = Get-SoftDownloadByte $It
                if ($It.Pct -gt 0) { $t = "téléchargement $($It.Pct) %" }
                elseif ($b -gt 0 -and $It.Total -gt 0) { $t = 'téléchargement {0} %  ({1} / {2})' -f [int][math]::Min([double]99, [math]::Floor(100 * $b / $It.Total)), (Format-SizeUi $b), (Format-SizeUi $It.Total) }
                elseif ($b -gt 0) { $t = 'téléchargement  {0}' -f (Format-SizeUi $b) }
            }
            elseif ($ph -eq 'installation') {
                # installeur silencieux : aucune progression publiée, durée écoulée (réelle) pour montrer qu'il travaille
                $t = $(if ($It.Pct -gt 0 -and $It.Pct -lt 100) { "installation $($It.Pct) %" } else { 'installation  {0:m\:ss}' -f $el })
            }
            elseif ($el.TotalSeconds -ge 5) { $t = '{0}  {1:m\:ss}' -f $ph, $el }
            @{ Text = $t; Brush = 'AccentBrush' }
        }
        'ok'   { @{ Text = $(if ($It.Note) { "$($It.Note)" } else { 'mis à jour' }); Brush = $(if ($It.NoteBrush) { "$($It.NoteBrush)" } else { 'OkFgBrush' }) } }
        'pend' { @{ Text = $(if ($It.Note) { "$($It.Note)" } else { 'version inchangée' }); Brush = 'WarnFgBrush' } }
        'fail' { @{ Text = 'échec ({0})' -f (Format-WingetCode $It.Code); Brush = 'ErrFgBrush' } }
        'skip' { @{ Text = $(if ($It.Phase -eq 'interrompu') { 'interrompu' } else { 'annulé' }); Brush = 'WarnFgBrush' } }
        default { $null }
    }
}
# ligne d'état : en cours « Mise à jour 3/7 · Google Chrome · téléchargement 42 % · 2 mis à jour » ; après : bilan
function Get-SoftRunSummary([bool]$Running) {
    $r = $Sync.SoftRun; if (-not $r) { return '' }
    $its = @($r.Items.Values)
    $nOk = @($its | Where-Object { $_.State -eq 'ok' }).Count
    $nKo = @($its | Where-Object { $_.State -eq 'fail' }).Count
    $nSk = @($its | Where-Object { $_.State -eq 'skip' }).Count
    $tot = @()
    if ($nOk) { $tot += '{0} {1}' -f $nOk, (Get-Plural $nOk 'mis à jour' 'mis à jour') }
    if ($nKo) { $tot += '{0} en échec' -f $nKo }
    if ($nSk) { $tot += '{0} {1}' -f $nSk, (Get-Plural $nSk 'annulé' 'annulés') }
    if ($Running) {
        $cur = $r.Items["$($r.Cur)"]
        $t = 'Mise à jour {0}/{1}' -f $r.Index, $r.Count
        if ($cur) { $t += '  ·  {0}  ·  {1}' -f (Get-SoftShortName $cur.Name), (Get-SoftItemText $cur).Text }
        if ($Sync.Cancel) { $t += '  ·  arrêt demandé' }
        if ($tot.Count) { $t += '  ·  ' + ($tot -join ', ') }
        return $t
    }
    'Dernière mise à jour : ' + $(if ($tot.Count) { $tot -join ', ' } else { 'aucun logiciel traité' })
}
# états appliqués aux lignes affichées (sans reconstruire la liste)
# intitulé de la 4e colonne : ÉTAT dès qu'une ligne affichée porte l'état d'une mise à jour (en cours ou dernière), sinon SOURCE
function Get-SoftColTitle([bool]$Hist, [bool]$Shown) { if ($Hist) { 'RÉSULTAT' } elseif ($Shown) { 'ÉTAT' } elseif ($SoftUI.Filter -eq 'All') { '' } else { 'SOURCE' } }
function Update-SoftRunRow {
    if (-not $SoftUI.SrcCells) { return }
    $shown = $false
    if ($Sync.SoftRun) { foreach ($id in @($Sync.SoftRun.Items.Keys)) { if ($SoftUI.SrcCells[$id]) { $shown = $true; break } } }
    if ($SoftUI.H3 -and $SoftUI.Filter -ne 'Hist') { $t = Get-SoftColTitle $false $shown; if ($SoftUI.H3.Text -ne $t) { $SoftUI.H3.Text = $t } }
    if (-not $shown) { return }
    foreach ($id in @($Sync.SoftRun.Items.Keys)) {
        $c = $SoftUI.SrcCells[$id]; if (-not $c) { continue }
        $x = Get-SoftItemText $Sync.SoftRun.Items[$id]; if (-not $x) { continue }
        if ($c.Text -ne $x.Text) {
            $c.Text = $x.Text
            $c.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, $x.Brush)
            $c.FontWeight = [Windows.FontWeights]::SemiBold
            $m = $(if ($Sync.SoftRun.Items[$id].State -eq 'fail') { $WingetErr[(Format-WingetCode $Sync.SoftRun.Items[$id].Code)] } else { $null })
            $c.ToolTip = $(if ($m) { "$($m[1])`nClic droit > Copier l'erreur pour le détail" } elseif ($Sync.SoftRun.Items[$id].State -eq 'fail') { "Clic droit > Copier l'erreur pour le détail" } else { $null })
        }
    }
}
# arrêt : après le logiciel en cours (sûr) ou tout de suite (winget et l'installeur arrêtés : installation possiblement incomplète)
function Stop-SoftUpgrade {
    if (-not (Test-SoftUpgrading) -or $Sync.Cancel) { return }
    $cur = $Sync.SoftRun.Items["$($Sync.SoftRun.Cur)"]; $nm = $(if ($cur) { Get-SoftShortName $cur.Name } else { 'le logiciel en cours' })
    $rest = @($Sync.SoftRun.Items.Values | Where-Object { $_.State -eq 'wait' }).Count
    $msg = "Interrompre les mises à jour ?`n`n{0} : mise à jour en cours. {1}" -f $nm, $(if ($rest) { "$rest $(Get-Plural $rest 'autre logiciel reste' 'autres logiciels restent') à mettre à jour." } else { 'C''est le dernier logiciel de la liste.' })
    $r = Show-Dialog $msg 'Warn' @(
        @{ T = "Interrompre après $nm"; V = 'after' },
        @{ T = 'Interrompre maintenant'; V = 'now'; S = 'WarnBtn' },
        @{ T = 'Continuer'; V = $null; S = 'PrimaryBtn'; D = $true; C = $true }) $null 'Interrompre maintenant arrête winget et l''installeur en cours : le logiciel peut rester partiellement installé et devra être réinstallé.'
    if ($r -eq 'after') { $Sync.Cancel = $true; Write-UiLog "Mises à jour des logiciels : arrêt demandé après $nm." 'WARN' }
    elseif ($r -eq 'now') {
        $Sync.Cancel = $true; $Sync.Aborted = $true
        if ($Sync.ChildPid) { & "$env:windir\System32\taskkill.exe" /PID $Sync.ChildPid /T /F 2>&1 | Out-Null }
        Write-UiLog "Mises à jour des logiciels interrompues pendant $nm." 'WARN'
    }
    Update-SoftStatus
}
function Update-SoftStatus {
    if (-not $SoftUI.Win) { return }
    $run = [bool]$Sync.WgRunning -and -not $Sync.WgCancel
    $mineV = $SoftUI.Filter -eq 'All'
    $SoftUI.Go.Visibility = $(if ($run -or $mineV) { 'Collapsed' } else { 'Visible' }); $SoftUI.Stop.Visibility = $(if ($run -and -not $mineV) { 'Visible' } else { 'Collapsed' })
    $SoftUI.Go.IsEnabled = -not $Sync.WgRunning
    $SoftUI.Go.Content = $(if ($SoftUI.Done) { 'Nouvelle recherche' } else { 'Rechercher' })
    $upg = Test-SoftUpgrading
    # mise à jour en cours : avancement et bouton Interrompre du panneau d'exécution global (bas de la fenêtre), pas de doublon ici
    $SoftUI.Prog.Visibility = $(if ($Sync.WgRunning) { 'Visible' } else { 'Collapsed' })
    # mise à jour : avancement réel (logiciels terminés + étape du logiciel en cours), bouton d'arrêt à la place du bouton principal
    $SoftUI.Prog.IsIndeterminate = -not $upg; if ($upg) { $SoftUI.Prog.Value = [math]::Max([double]0, [double]$Sync.TaskPct) }
    $SoftUI.RunStop.Visibility = 'Collapsed'
    $SoftUI.Run.Visibility = $(if ($upg -or $SoftUI.Filter -eq 'Hist') { 'Collapsed' } else { 'Visible' })
    # onglet Historique : bouton de purge à la place du bouton de mise à jour (grisé si l'historique est vide)
    $SoftUI.HistClear.Visibility = $(if ($SoftUI.Filter -eq 'Hist' -and -not $upg) { 'Visible' } else { 'Collapsed' })
    # grisé si l'historique est vide, pendant une recherche ou pendant une tâche (une mise à jour ajoute des entrées)
    $SoftUI.HistClear.IsEnabled = (Test-Path -LiteralPath $SoftHistFile) -and -not $Sync.WgRunning -and -not $Sync.Running
    $SoftUI.HistClear.ToolTip = $(if (-not (Test-Path -LiteralPath $SoftHistFile)) { 'Historique vide' } elseif (-not $SoftUI.HistClear.IsEnabled) { 'Indisponible pendant une recherche ou une mise à jour' } else { $null })
    $r = $Sync.WgResult
    # bouton principal : logiciel en surbrillance ; secondaire : toutes les mises à jour non exclues
    # même logique que les cartes de mises à jour : rien de sélectionné = tout, sinon la sélection
    $busy = $Sync.Running -or $Sync.WgRunning
    $sel = @(Get-SoftSelectedApp); $tg = @(Get-SoftRunTarget)
    # rien à installer (aucune mise à jour, ou sélection sans mise à jour) : bouton masqué plutôt que grisé à « (0) »
    if (-not $tg.Count -and $SoftUI.Run.Visibility -eq 'Visible') { $SoftUI.Run.Visibility = 'Collapsed' }
    # même libellé que les cartes de mises à jour de l'Accueil
    $SoftUI.Run.Content = $(if ($sel.Count) { "Installer la sélection ($($tg.Count))" } else { Get-InstallLabel $tg.Count 0 })
    $SoftUI.Run.ToolTip = $(if ($tg.Count) { (@($tg | Select-Object -First 15 | ForEach-Object { Get-SoftShortName $_.Name }) -join "`n") + $(if ($tg.Count -gt 15) { "`n..." } else { '' }) } else { $null })
    $SoftUI.Run.IsEnabled = $tg.Count -gt 0 -and -not $busy
    if (-not $SoftUI.Run.IsEnabled) {
        $SoftUI.Run.ToolTip = $(if ($Sync.Running) { 'Une exécution est déjà en cours' } elseif ($Sync.WgRunning) { 'Recherche des mises à jour en cours' } else { 'Aucune mise à jour à installer' })
    }
    $mine = $SoftUI.Filter -eq 'All'
    # Mes applications : actions sur chaque ligne (et clic droit pour la sélection multiple), pas de boutons en bas
    $SoftUI.Reinst.Visibility = 'Collapsed'
    foreach ($e in @($SoftUI.RowCache.Values)) { if ($e -and $e.Acts) { foreach ($b in $e.Acts.Children) { $b.IsEnabled = -not ($Sync.Running -or ($Sync.WgRunning -and -not $Sync.WgListOnly)) } } }
    if ($mine) {
        # Mes applications : actions sur la sélection (clic, Ctrl + clic, Maj + clic) ; boutons grisés sans sélection
        $rm = @(Get-SoftRemoveTarget)
        $SoftUI.Run.Visibility = $(if ($upg) { 'Collapsed' } else { 'Visible' })
        $SoftUI.Run.Content = $(if ($rm.Count) { 'Désinstaller ({0})' -f $rm.Count } else { 'Désinstaller' })
        $SoftUI.Reinst.Content = $(if ($rm.Count) { 'Réinstaller ({0})' -f $rm.Count } else { 'Réinstaller' })
        $tip = $(if ($Sync.Running) { 'Une exécution est déjà en cours' } elseif ($Sync.WgRunning) { 'Inventaire en cours' }
            elseif (-not $sel.Count) { 'Sélectionner une ou plusieurs applications (Ctrl + clic, Maj + clic)' }
            elseif (-not $rm.Count) { 'Sélection inconnue de winget : désinstallation depuis Paramètres > Applications' }
            else { (@($rm | Select-Object -First 15 | ForEach-Object { Get-SoftShortName $_.Name }) -join "`n") + $(if ($rm.Count -gt 15) { "`n..." } else { '' }) })
        foreach ($b in $SoftUI.Run, $SoftUI.Reinst) { $b.IsEnabled = $rm.Count -gt 0 -and -not $busy; $b.ToolTip = $tip }
        $SoftUI.Run.Visibility = 'Collapsed'
    }
    $rs = $(if ($mine) { 'WarnBtn' } else { 'PrimaryBtn' })
    if ($SoftUI.RunStyle -ne $rs) { $SoftUI.RunStyle = $rs; $SoftUI.Run.SetResourceReference([Windows.FrameworkElement]::StyleProperty, $rs) }
    $st = $(if ($Sync.WgRunning) { $(if ($Sync.WgCancel) { 'Arrêt de la recherche...' } else { 'Recherche en cours  ·  {0:mm\:ss}  ·  {1}' -f ([DateTime]::Now - $Sync.WgStart), $Sync.WgStatus }) }
        elseif ($upg) { Get-SoftRunSummary $true }
        elseif (-not $r) { 'Aucun inventaire.' }
        elseif ($r.Error) { 'Recherche impossible : ' + $r.Error }
        else {
            $age = try { Format-Age ([DateTime](Get-SoftSearchStamp $r)) } catch { '' }
            $(if ($Sync.SoftRun) { (Get-SoftRunSummary $false) + '  ·  ' } else { '' }) + ('Dernière recherche : {0}  ·  winget {1}' -f $age, $(if ($r.WingetVer) { $r.WingetVer } else { '?' }))
        })
    if ($SoftUI.Status.Text -ne $st) { $SoftUI.Status.Text = $st }
}
# Ligne de la liste des logiciels : construite une fois par inventaire et conservée (filtres, recherche, exclusions ne
# recréent que les lignes qui changent). Signature = inventaire, exclusion, versions, source.
# Mes applications : source non affichée (seul « reste d'installation » est signalé), actions sur la ligne à la place
function Get-SoftSrcText($App) {
    if ($SoftUI.Filter -eq 'All') { return $(if ($App.Orphan) { 'reste d''installation' } else { '' }) }
    "$($App.SrcLabel)" + $(if ($App.Orphan) { '  ·  reste d''installation' } else { '' })
}
# colonne 3 selon la vue : Mes applications = 250 px (boutons Modifier / réparer et Désinstaller), sinon 170 px (source / état)
function Set-SoftRowMode($E) {
    $mine = $SoftUI.Filter -eq 'All'
    $E.Grid.ColumnDefinitions[3].Width = [Windows.GridLength]::new($(if ($mine) { 250 } else { 170 }))
    $E.Acts.Visibility = $(if ($mine -and -not $E.Row.DataContext.Orphan) { 'Visible' } else { 'Collapsed' })
    # actions de ligne indisponibles seulement pendant une tâche (une actualisation de la liste en arrière-plan ne bloque rien)
    $busy = $Sync.Running -or ($Sync.WgRunning -and -not $Sync.WgListOnly)
    foreach ($b in $E.Acts.Children) { $b.IsEnabled = -not $busy }
    $E.BRm.ToolTip = $(if (-not (Get-SoftLocalId $E.Row.DataContext)) { 'Inconnu de winget : ouvre le désinstalleur du logiciel (Paramètres > Applications)' } else { $null })
}
# Modifier / réparer : commande de modification de l'éditeur (clé de désinstallation : ModifyPath), sinon réparation
# Windows Installer (msiexec /fa), application du Store : Paramètres > Applications installées (Options avancées > Réparer)
function Get-SoftArpKey($App) {
    $id = "$(Get-SoftLocalId $App)"
    $cand = [Collections.Generic.List[object]]::new()
    if ($id -match '^ARP\\(Machine|User)\\(X64|X86)\\(.+)$') {
        $root = $(if ($Matches[1] -eq 'User') { 'HKCU\Software' } elseif ($Matches[2] -eq 'X86' -and [Environment]::Is64BitOperatingSystem) { 'HKLM\SOFTWARE\WOW6432Node' } else { 'HKLM\SOFTWARE' })
        $cand.Add(@{ R = $root + '\Microsoft\Windows\CurrentVersion\Uninstall'; N = $Matches[3] })
    }
    foreach ($c in $cand) { $k = Open-RegKey ($c.R + '\' + $c.N); if ($k) { return @{ Key = $k; Name = $c.N } } }
    foreach ($root in 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall', 'HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall') {
        $k = Open-RegKey $root; if (-not $k) { continue }
        try {
            foreach ($n in $k.GetSubKeyNames()) {
                $sk = $k.OpenSubKey($n); if (-not $sk) { continue }
                if ("$($sk.GetValue('DisplayName'))" -eq "$($App.Name)") { return @{ Key = $sk; Name = $n } }
                $sk.Close()
            }
        } finally { $k.Close() }
    }
    $null
}
function Split-SoftCommand([string]$Cmd) {
    $c = [Environment]::ExpandEnvironmentVariables($Cmd.Trim())
    if ($c -match '^"([^"]+)"\s*(.*)$') { return @($Matches[1], $Matches[2]) }
    if ($c -match '^(.+?\.exe)\s*(.*)$') { return @($Matches[1], $Matches[2]) }
    @($c, '')
}
function Invoke-SoftModify($App) {
    $nm = Get-SoftShortName "$($App.Name)"
    if ($App.Pfn) {
        Start-Process 'ms-settings:appsfeatures'
        Show-Info "$nm est une application du Microsoft Store : dans Paramètres > Applications installées, menu ... de $nm > Options avancées > Réparer (ou Réinitialiser)."
        return
    }
    $a = Get-SoftArpKey $App
    if (-not $a) { Start-Process 'ms-settings:appsfeatures'; Show-Info "Entrée de désinstallation de $nm introuvable : modification depuis Paramètres > Applications installées."; return }
    try {
        $mp = "$($a.Key.GetValue('ModifyPath'))".Trim(); $msi = [int]('0' + $a.Key.GetValue('WindowsInstaller')) -eq 1
        $noMod = [int]('0' + $a.Key.GetValue('NoModify')) -eq 1; $noRep = [int]('0' + $a.Key.GetValue('NoRepair')) -eq 1
        $guid = $(if ($a.Name -match '^\{[0-9A-Fa-f\-]{36}\}$') { $a.Name } else { $null })
    } finally { $a.Key.Close() }
    try {
        if ($msi -and $guid -and ($mp -match '(?i)msiexec' -or -not $mp)) {
            # MSI : interface de maintenance de l'éditeur (Modifier / Réparer / Supprimer), réparation directe si l'éditeur la masque
            $arg = $(if ($noMod -and -not $noRep) { "/fa $guid" } else { "/i $guid" })
            Start-Process "$env:windir\System32\msiexec.exe" $arg
            Write-UiLog ('{0} : {1} (msiexec {2}).' -f $nm, $(if ($arg -like '/fa*') { 'réparation lancée' } else { 'maintenance lancée' }), $arg) 'INFO'
        }
        elseif ($mp -and -not $noMod) {
            $x = Split-SoftCommand $mp
            if ($x[1]) { Start-Process $x[0] $x[1] } else { Start-Process $x[0] }
            Write-UiLog "$nm : modification lancée ($mp)." 'INFO'
        }
        else { Show-Info "$nm ne propose ni modification ni réparation : pour repartir d'une installation propre, utiliser Réinstaller (clic droit sur la ligne)." }
    } catch { Write-UiLog "$nm : modification impossible : $($_.Exception.Message)" 'ERROR'; Show-Info "Modification de $nm impossible : $($_.Exception.Message)" }
}
# Désinstaller : winget si le logiciel lui est connu, sinon page Applications installées de Windows
function Invoke-SoftRowRemove($App) {
    if (Get-SoftLocalId $App) { Invoke-SoftRemove @($App) 'uninstall'; return }
    Start-Process 'ms-settings:appsfeatures'
    Show-Info ('{0} est inconnu de winget : désinstallation depuis Paramètres > Applications installées.' -f (Get-SoftShortName "$($App.Name)"))
}
function Get-SoftRowEntry($App, [bool]$Avail) {
    $k = Get-SoftKey $App; $ex = [bool]$SoftExcl[$k]
    $sig = '{0}|{1}|{2}|{3}|{4}|{5}|{6}|{7}' -f $App.Name, $ex, $App.From, $App.To, $App.SrcLabel, $App.Unknown, $App.Orphan, $App.Id
    $e = $SoftUI.RowCache[$k]
    if ($e -and $e.Sig -eq $sig) {
        # réutilisation : colonne DISPONIBLE selon l'onglet, cellule SOURCE / ÉTAT remise à l'état de l'inventaire
        $e.Grid.ColumnDefinitions[2].Width = [Windows.GridLength]::new($(if ($Avail) { 150 } else { 0 }))
        $c4 = $e.C4
        $c4.Text = Get-SoftSrcText $App
        $c4.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, $(if ($App.Orphan) { 'WarnFgBrush' } else { 'MutedBrush' }))
        $c4.FontWeight = [Windows.FontWeights]::Normal
        $c4.ToolTip = $(if ($App.Match) { "Rattaché par le nom au paquet winget $($App.Id)" } else { $null })
        # données de la ligne remplacées par celles de l'inventaire actualisé (actions, double clic, menu)
        $e.Row.DataContext = $App; foreach ($b in $e.Acts.Children) { $b.DataContext = $App }
        Set-SoftRowMode $e
        return $e
    }
    $k = Get-SoftKey $App; $ex = [bool]$SoftExcl[$k]; $hasUp = [bool]($App.To -and $App.Src)
    $row = [Windows.Controls.Border]::new()
    $row.CornerRadius = [Windows.CornerRadius]::new(4)
    $row.Padding = New-Thickness 6 5 6 5
    $row.Margin = New-Thickness 0 0 0 1
    $row.BorderThickness = New-Thickness 3 0 0 0; $row.BorderBrush = [Windows.Media.Brushes]::Transparent
    $row.Background = [Windows.Media.Brushes]::Transparent; $row.Cursor = [Windows.Input.Cursors]::Hand; $row.DataContext = $App; $row.Tag = $k
    $g = [Windows.Controls.Grid]::new()
    foreach ($wd in 0, 150, $(if ($Avail) { 150 } else { -1 }), 170, 80) {
        $cd = [Windows.Controls.ColumnDefinition]::new()
        if ($wd -gt 0) { $cd.Width = [Windows.GridLength]::new($wd) } elseif ($wd -lt 0) { $cd.Width = [Windows.GridLength]::new(0) }
        [void]$g.ColumnDefinitions.Add($cd)
    }
    $nm = [Windows.Controls.StackPanel]::new()
    $t1 = New-Text "$($App.Name)"; $t1.TextWrapping = 'NoWrap'; $t1.TextTrimming = 'CharacterEllipsis'; $t1.ToolTip = "$($App.Name)"
    [void]$nm.Children.Add($t1)
    if ($App.Id -and $App.Id -ne $App.Name) {
        $t2 = New-Text "$($App.Id)" 'Muted'
        $t2.FontSize = 11
        $t2.TextWrapping = 'NoWrap'
        $t2.TextTrimming = 'CharacterEllipsis'
        [void]$nm.Children.Add($t2)
    }
    $c2 = New-Text "$($App.From)"; [Windows.Controls.Grid]::SetColumn($c2, 1)
    $c3 = New-Text $(if ($hasUp) { "$($App.To)" } else { '' }); [Windows.Controls.Grid]::SetColumn($c3, 2)
    # mise à jour du Store sans numéro dans le catalogue public : libellé court, explication en info-bulle
    if ("$($App.To)" -eq 'non publiée') { $c3.ToolTip = 'Le Microsoft Store propose une mise à jour pour ce poste mais ne publie pas son numéro de version (catalogue public). Version réelle affichée après installation.' }
    if ($hasUp -and -not $App.Unknown) {
        $c3.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, $(if ($ex) { 'MutedBrush' } else { 'WarnFgBrush' }))
        $c3.FontWeight = [Windows.FontWeights]::SemiBold
    }
    elseif ($App.Unknown) {
        $c3.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'MutedBrush')
        $c3.ToolTip = 'Version installée non détectable : mise à jour possible à la demande (réinstallation de la dernière version)'
    }
    $c4 = New-Text (Get-SoftSrcText $App) 'Muted'; [Windows.Controls.Grid]::SetColumn($c4, 3); $SoftUI.SrcCells["$($App.Id)"] = $c4
    if ($App.Orphan) { $c4.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'WarnFgBrush'); $c4.ToolTip = 'Logiciel absent du poste : entrée de désinstallation restée dans le registre (clic droit > Retirer l''entrée)' }
    if ($App.Match) { $c4.ToolTip = "Rattaché par le nom au paquet winget $($App.Id)" }
    $c5 = New-Text $(if ($ex) { 'exclu' } else { '' }) 'Muted'; [Windows.Controls.Grid]::SetColumn($c5, 4)
    foreach ($x in $c2, $c3, $c4, $c5) { $x.VerticalAlignment = 'Center'; $x.TextWrapping = 'NoWrap'; $x.TextTrimming = 'CharacterEllipsis' }
    # actions de la ligne (Mes applications) : clic sur un bouton sans changer la sélection
    $acts = [Windows.Controls.StackPanel]::new(); $acts.Orientation = 'Horizontal'; $acts.HorizontalAlignment = 'Right'; $acts.VerticalAlignment = 'Center'
    $bMod = New-Button 'Modifier / réparer'; $bRm = New-Button 'Désinstaller' 'WarnBtn'
    foreach ($x in $bMod, $bRm) { $x.MinWidth = 0; $x.Height = 26; $x.Padding = New-Thickness 8 0 8 0; $x.Margin = New-Thickness 4 0 0 0; $x.DataContext = $App; [void]$acts.Children.Add($x) }
    $bMod.Add_Click({ param($s, $e) $e.Handled = $true; try { Invoke-SoftModify $s.DataContext } catch { Write-UiLog "Modifier / réparer : $($_.Exception.Message)" 'ERROR' } })
    $bRm.Add_Click({ param($s, $e) $e.Handled = $true; try { Invoke-SoftRowRemove $s.DataContext } catch { Write-UiLog "Désinstaller : $($_.Exception.Message)" 'ERROR' } })
    $cc = [Windows.Controls.Grid]::new(); [void]$cc.Children.Add($c4); [void]$cc.Children.Add($acts); [Windows.Controls.Grid]::SetColumn($cc, 3)
    foreach ($x in $nm, $c2, $c3, $cc, $c5) { [void]$g.Children.Add($x) }
    if ($ex) { $g.Opacity = 0.6 }
    $row.Child = $g
    # survol, sélection maintenue (surbrillance), double clic = mettre à jour, clic droit = menu
    $row.Add_MouseEnter({ param($s, $e)
        if (-not $SoftUI.SelSet.Contains($s.Tag)) { $s.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, 'HoverBrush') }
    })
    $row.Add_MouseLeave({ param($s, $e) if (-not $SoftUI.SelSet.Contains($s.Tag)) { $s.Background = [Windows.Media.Brushes]::Transparent } })
    # clic : sélection seule ; Ctrl+clic : ajout / retrait ; Maj+clic : plage depuis la dernière ligne cliquée ; double clic : mise à jour
    $row.Add_MouseLeftButtonDown({
        param($s, $e)
        $mod = [Windows.Input.Keyboard]::Modifiers
        if ($mod -band [Windows.Input.ModifierKeys]::Shift) { Select-SoftRange $s.Tag }
        elseif ($mod -band [Windows.Input.ModifierKeys]::Control) { Select-SoftToggle $s.Tag }
        else { Select-SoftOnly $s.Tag }
        if ($e.ClickCount -eq 2) { $App = $s.DataContext; if ($App.To -and $App.Src) { Invoke-SoftUpgrade @($App) } }
    })
    $row.Add_MouseRightButtonUp({ param($s, $e)
        if (-not $SoftUI.SelSet.Contains($s.Tag)) { Select-SoftOnly $s.Tag }
        Show-SoftMenu $s
        $e.Handled = $true
    })
    $e = @{ Row = $row; Grid = $g; C4 = $c4; Sig = $sig; Key = $k; Acts = $acts; BRm = $bRm }
    Set-SoftRowMode $e
    $SoftUI.RowCache[$k] = $e
    $e
}
# ajout de lignes à la liste (au plus $Max), depuis la file de la vue courante
function Add-SoftRow($Todo, [bool]$Avail, [int]$Max) {
    $n = 0
    while ($Todo.Count -and $n -lt $Max) {
        $a = $Todo.Dequeue(); $e = Get-SoftRowEntry $a $Avail
        [void]$SoftUI.List.Children.Add($e.Row); $SoftUI.Rows[$e.Key] = $e.Row; $SoftUI.SrcCells["$($a.Id)"] = $e.C4; $n++
        Update-WinTextZoom $SoftUI.Win $e.Row
    }
}
# état de liste vide : icône (à jour, recherche, historique, erreur, recherche en cours), message et action utile
# gestionnaire des mises à jour d'un logiciel (pastilles de l'encart) : wg = winget, ms = Microsoft Store, no = non géré
function Get-SoftSrcKind($A) { $l = "$($A.SrcLabel)"; if ($l -eq 'Microsoft Store') { 'ms' } elseif ($l -like 'winget*') { 'wg' } else { 'no' } }
function Update-SoftEmpty {
    $c = $SoftUI.EmptyCtx; $t = "$($SoftUI.Hint.Text)"
    $SoftUI.Empty.Visibility = $(if ($t) { 'Visible' } else { 'Collapsed' }); if (-not $t) { return }
    $ic, $br = $(if ($c.Run) { 0xE895, 'AccentBrush' } elseif ($c.Err) { 0xE7BA, 'ErrFgBrush' } elseif ($c.Q) { 0xE721, 'MutedBrush' } elseif ($c.Hist) { 0xE81C, 'MutedBrush' }
        elseif ($SoftUI.Filter -eq 'Upd' -and -not $c.NoInv) { 0xE73E, 'OkFgBrush' } else { 0xE71D, 'MutedBrush' })
    $SoftUI.HintIcon.Text = [string][char]$ic; $SoftUI.HintIcon.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, $br)
    $lk = $(if ($c.Run) { $null } elseif ($c.Q) { 'Effacer la recherche' } elseif ($c.Src) { 'Retirer le filtre' } elseif ($c.Err -or $c.NoInv) { $(if ($SoftUI.Filter -eq 'All') { 'Lire les applications installées' } else { 'Lancer la recherche' }) }
        elseif ($SoftUI.Filter -in 'Upd', 'Excl' -and $c.All) { 'Voir les {0} logiciels' -f $c.All } else { $null })
    $SoftUI.HintLink.Content = $lk; $SoftUI.HintLink.Visibility = $(if ($lk) { 'Visible' } else { 'Collapsed' })
    $SoftUI.HintLink.Tag = $(if ($c.Q) { 'q' } elseif ($c.Src) { 'src' } elseif ($c.Err -or $c.NoInv) { 'search' } else { 'all' })
}
function Update-SoftView {
    if (-not $SoftUI.Win) { return }
    $r = $Sync.WgResult
    $apps = @(); if ($r -and -not $r.Error) { $apps = @($r.Apps | Where-Object { $_ }) }
    # sécurité (inventaire enregistré par une version précédente) : correspondance en double d'un paquet déjà géré par winget écartée
    $own = @{}; foreach ($x in $apps) { if (-not $x.Match -and $x.Src) { $own["$($x.Id)"] = 1 } }
    $apps = @($apps | Where-Object { -not ($_.Match -and $own.ContainsKey("$($_.Id)")) })
    $upd = @($apps | Where-Object { $_.To -and $_.Src -and -not $SoftExcl[(Get-SoftKey $_)] })
    $exc = @($apps | Where-Object { $SoftExcl[(Get-SoftKey $_)] })
    $hist = @(Get-SoftHistory)
    $SoftUI.FUpd.Content = 'Mises à jour ({0})' -f $upd.Count
    $SoftUI.FAll.Content = 'Tous ({0})' -f $apps.Count
    $mt = $(if ($apps.Count) { 'Mes applications ({0})' -f $apps.Count } else { 'Mes applications' }); if ($Ui.AppsModeMineTxt.Text -ne $mt) { $Ui.AppsModeMineTxt.Text = $mt }
    $SoftUI.FExcl.Content = 'Exclus ({0})' -f $exc.Count
    $SoftUI.FHist.Content = 'Historique ({0})' -f $hist.Count
    foreach ($b in $SoftUI.FUpd, $SoftUI.FAll, $SoftUI.FExcl, $SoftUI.FHist) { $b.Tag = $(if ($b.DataContext -eq $SoftUI.Filter) { 'on' } else { '' }) }
    $isHist = $SoftUI.Filter -eq 'Hist'
    # recherche en cours : aucune interaction tant que le résultat n'est pas là (onglets, filtre, encart et liste masqués ou
    # grisés, ancien résultat non affiché), seul état visible : recherche en cours
    # recherche en cours : liste précédente gardée à l'écran (actualisée à l'arrivée du résultat) ; écran d'attente seulement
    # sans aucun inventaire
    $busy = [bool]$Sync.WgRunning -and -not $Sync.WgCancel -and $SoftUI.Filter -ne 'All' -and -not $apps.Count
    # onglets non désactivés (le style désactivé effaçait le bleu de l'onglet actif et rendait son texte illisible) : clics et
    # clavier bloqués, onglets inactifs et filtre estompés, onglet actif inchangé
    foreach ($c in $SoftUI.FUpd, $SoftUI.FAll, $SoftUI.FExcl, $SoftUI.FHist, $SoftUI.FindBox) {
        $c.IsHitTestVisible = -not $busy; if ($c -ne $SoftUI.FindBox) { $c.Focusable = -not $busy }
        $c.Opacity = $(if ($busy -and "$($c.Tag)" -ne 'on') { 0.5 } else { 1 })
    }
    if ($busy -and $SoftUI.Find.IsKeyboardFocusWithin) { [void]$SoftUI.Win.Focus() }
    $SoftUI.Find.IsEnabled = -not $busy
    if ($busy) {
        $SoftUI.Gen = 1 + [int]$SoftUI.Gen
        $SoftUI.List.Children.Clear()
        $SoftUI.Rows = @{}
        $SoftUI.Order = [Collections.ArrayList]::new()
        $SoftUI.SrcCells = @{}
        if ($SoftUI.SelSet -and $SoftUI.SelSet.Count) { $SoftUI.SelSet.Clear(); Update-SoftSelection }
        $SoftUI.SumBox.Visibility = 'Collapsed'; $SoftUI.Head.Visibility = 'Hidden'
        $SoftUI.EmptyCtx = @{ Run = $true }; $SoftUI.Hint.Text = 'Recherche des mises à jour en cours...'
        Update-SoftEmpty; Update-SoftStatus; return
    }
    $SoftUI.Head.Visibility = 'Visible'
    # encart de répartition : SrcLabel (winget, winget (correspondance), Microsoft Store, non géré) calculé à l'inventaire
    # gestionnaire de chaque logiciel calculé une fois par affichage (compteurs, filtre)
    $kind = @{}; foreach ($x in $apps) { $kind[(Get-SoftKey $x)] = Get-SoftSrcKind $x }
    $nMs = @($apps | Where-Object { $kind[(Get-SoftKey $_)] -eq 'ms' }).Count
    $nWg = @($apps | Where-Object { $kind[(Get-SoftKey $_)] -eq 'wg' }).Count
    $nNo = $apps.Count - $nMs - $nWg
    foreach ($pb in $SoftUI.PWg, $SoftUI.PMs, $SoftUI.PNo) {
        if ($SoftUI.Filter -eq 'All' -and $SoftUI.SrcFilter -eq "$($pb.Tag)") {
            $pb.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, 'AccentBrush')
            $pb.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, 'HoverBrush')
        }
        else { $pb.BorderBrush = [Windows.Media.Brushes]::Transparent; $pb.Background = [Windows.Media.Brushes]::Transparent }
    }
    # Tous : répartition de l'inventaire, pastilles cliquables (filtre) ; Mises à jour : répartition des mises à jour
    # disponibles, simple information ; Exclus / Historique : pas d'encart
    $isAll = $SoftUI.Filter -eq 'All'; $isUpd = $SoftUI.Filter -eq 'Upd'
    # bilan de la dernière installation (jusqu'à la prochaine recherche) à la place de la répartition
    $done = $(if ($isUpd -and $SoftUI.Done -and -not $Sync.Running) { $SoftUI.Done } else { $null })
    foreach ($pb in $SoftUI.PWg, $SoftUI.PMs) { $pb.Visibility = $(if ($done) { 'Collapsed' } else { 'Visible' }) }
    if ($done) {
        $parts = @('{0} {1}' -f $done.Ok, (Get-Plural $done.Ok 'installée' 'installées'))
        if ($done.Fail) { $parts += '{0} en échec' -f $done.Fail }
        if ($done.Skip) { $parts += '{0} non {1}' -f $done.Skip, (Get-Plural $done.Skip 'installée' 'installées') }
        $SoftUI.SumTot.Text = $(if (-not $done.Fail -and -not $done.Skip) { 'Toutes les mises à jour disponibles ont été installées.' } else { ($parts -join ', ') + '.' }) + '  Nouvelle recherche : bouton en haut à droite.'
        $SoftUI.SumTot.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, $(if ($done.Fail) { 'WarnFgBrush' } else { 'OkFgBrush' }))
    } else { $SoftUI.SumTot.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'FgBrush') }
    if ($isUpd -and -not $done) {
        $uMs = @($upd | Where-Object { $kind[(Get-SoftKey $_)] -eq 'ms' }).Count; $uWg = $upd.Count - $uMs
        $SoftUI.SumTot.Text = '{0} {1}' -f $upd.Count, (Get-Plural $upd.Count 'mise à jour disponible' 'mises à jour disponibles')
        $SoftUI.SumWg.Text = '{0} par winget' -f $uWg; $SoftUI.SumMs.Text = '{0} par le Microsoft Store' -f $uMs
    } elseif (-not $done) {
        $SoftUI.SumTot.Text = '{0} sur {1} {2}' -f ($nWg + $nMs), $apps.Count, (Get-Plural ($nWg + $nMs) 'logiciel géré' 'logiciels gérés')
        $SoftUI.SumWg.Text = '{0} par winget' -f $nWg
        $SoftUI.SumMs.Text = '{0} par le Microsoft Store' -f $nMs
        $SoftUI.SumNo.Text = '{0} non {1}' -f $nNo, (Get-Plural $nNo 'géré' 'gérés')
    }
    $SoftUI.PNo.Visibility = $(if ($isAll) { 'Visible' } else { 'Collapsed' })
    foreach ($pb in $SoftUI.PWg, $SoftUI.PMs, $SoftUI.PNo) {
        $pb.Cursor = $(if ($isAll) { [Windows.Input.Cursors]::Hand } else { [Windows.Input.Cursors]::Arrow })
        if (-not $pb.Uid) { $pb.Uid = "$($pb.ToolTip)" }
        $pb.ToolTip = $(if ($isAll) { "$($pb.Uid)" } else { $null })
    }
    # Mes applications : pas d'encart de répartition (winget / Store / non géré)
    $SoftUI.SumBox.Visibility = $(if ($done -or ($apps.Count -and $isUpd -and $upd.Count)) { 'Visible' } else { 'Collapsed' })
    if ($isAll -and $SoftUI.SrcFilter) { $SoftUI.SrcFilter = $null }
    $SoftUI.H3.Parent.ColumnDefinitions[3].Width = [Windows.GridLength]::new($(if ($isAll) { 250 } else { 170 }))
    $SoftUI.H1.Text = $(if ($isHist) { 'VERSION AVANT' } else { 'VERSION INSTALLÉE' })
    $SoftUI.H2.Text = $(if ($isHist) { 'VERSION APRÈS' } else { 'DISPONIBLE' })
    $SoftUI.H3.Text = Get-SoftColTitle $isHist $false
    if ($isHist) { $SoftUI.H2.Parent.ColumnDefinitions[2].Width = [Windows.GridLength]::new(150); Show-SoftHistory $hist; return }
    $show = $(switch ($SoftUI.Filter) { 'Upd' { $upd } 'Excl' { $exc } default { $apps } })
    # colonne DISPONIBLE seulement dans l'onglet Mises à jour (Tous / Exclus : simple inventaire)
    $avail = $SoftUI.Filter -eq 'Upd'
    $SoftUI.H2.Parent.ColumnDefinitions[2].Width = [Windows.GridLength]::new($(if ($avail) { 150 } else { 0 }))
    $q = "$($SoftUI.Find.Text)".Trim()
    if ($q) { $show = @($show | Where-Object { "$($_.Name)" -like "*$q*" -or "$($_.Id)" -like "*$q*" }) }
    $sf = $(if ($SoftUI.Filter -eq 'All') { $SoftUI.SrcFilter } else { $null })
    if ($sf) { $show = @($show | Where-Object { $kind[(Get-SoftKey $_)] -eq $sf }) }
    $SoftUI.List.Children.Clear(); $SoftUI.Rows = @{}; $SoftUI.Order = [Collections.ArrayList]::new(); $SoftUI.SrcCells = @{}
    if (-not $SoftUI.SelSet) { $SoftUI.SelSet = [Collections.Generic.HashSet[string]]::new() }
    # nouvel inventaire : lignes conservées de l'inventaire précédent libérées
    # lignes gardées d'un inventaire à l'autre (signature : nom, versions, source...) ; lignes des logiciels disparus libérées
    if (-not $SoftUI.RowCache) { $SoftUI.RowCache = @{} }
    $stamp = "$($r.Stamp)"
    if ($SoftUI.CacheStamp -ne $stamp) {
        $SoftUI.CacheStamp = $stamp; $live = @{}; foreach ($a in $apps) { $live[(Get-SoftKey $a)] = 1 }
        foreach ($k in @($SoftUI.RowCache.Keys)) { if (-not $live.ContainsKey($k)) { $SoftUI.RowCache.Remove($k) } }
    }
    foreach ($a in $show) { [void]$SoftUI.Order.Add((Get-SoftKey $a)) }
    # affichage progressif : 40 premières lignes tout de suite, la suite par lots de 60 quand l'interface est libre
    # (une vue plus récente, filtre ou recherche, annule les lots restants)
    $SoftUI.Gen = 1 + [int]$SoftUI.Gen; $gen = $SoftUI.Gen
    $todo = [Collections.Generic.Queue[object]]::new(); foreach ($a in $show) { $todo.Enqueue($a) }
    Add-SoftRow $todo $avail 40
    if ($todo.Count) {
        $SoftUI.Next = {
            if ($SoftUI.Gen -ne $gen -or -not $SoftUI.Win) { return }
            Add-SoftRow $todo $avail 60
            if ($todo.Count) { [void]$SoftUI.Win.Dispatcher.BeginInvoke([Action]$SoftUI.Next, [Windows.Threading.DispatcherPriority]::Background) }
            else { Update-SoftRunRow; Update-SoftSelection }
        }.GetNewClosure()
        [void]$SoftUI.Win.Dispatcher.BeginInvoke([Action]$SoftUI.Next, [Windows.Threading.DispatcherPriority]::Background)
    }
    foreach ($k in @($SoftUI.SelSet)) { if (-not $SoftUI.Order.Contains($k)) { [void]$SoftUI.SelSet.Remove($k) } }
    Update-SoftRunRow
    Update-SoftSelection
    $SoftUI.EmptyCtx = @{ Src = [bool]$sf; Q = $q; Upd = $upd.Count; All = $apps.Count; Hist = $false; Err = [bool]($r -and $r.Error); NoInv = -not $r; Run = [bool]($Sync.WgRunning -and -not $apps.Count) }
    $SoftUI.Hint.Text = $(if ($Sync.WgRunning -and -not $apps.Count) { $(if ($Sync.WgListOnly) { 'Lecture des applications installées...' } else { 'Recherche en cours...' }) } elseif ($r -and $r.Error) { 'Recherche impossible : ' + $r.Error } elseif (-not $r) { 'Aucun inventaire.' } elseif (-not $show.Count -and $sf -and -not $q) { 'Aucun logiciel {0} dans cet onglet.' -f $(switch ($sf) { 'wg' { 'géré par winget' } 'ms' { 'géré par le Microsoft Store' } default { 'non géré' } }) } elseif (-not $show.Count) { $(switch ($SoftUI.Filter) { 'Upd' { $(if ($q) { 'Aucune mise à jour pour cette recherche.' } else { 'Tous les logiciels sont à jour.' }) } 'Excl' { 'Aucun logiciel exclu.' } default { 'Aucun logiciel pour cette recherche.' } }) } else { '' })
    Update-SoftEmpty
    Update-SoftStatus
}
# historique : date et utilisateur sous le nom, versions avant / après, résultat (mis à jour / échec avec code winget)
function Show-SoftHistory($Hist) {
    $q = "$($SoftUI.Find.Text)".Trim()
    $show = @($Hist | Where-Object { -not $q -or "$($_.Name)" -like "*$q*" -or "$($_.Id)" -like "*$q*" })
    $SoftUI.List.Children.Clear(); $SoftUI.Rows = @{}; $SoftUI.Order = [Collections.ArrayList]::new(); if ($SoftUI.SelSet) { $SoftUI.SelSet.Clear() }
    foreach ($h in $show) {
        $row = [Windows.Controls.Border]::new()
        $row.CornerRadius = [Windows.CornerRadius]::new(4)
        $row.Padding = New-Thickness 6 5 6 5
        $row.Margin = New-Thickness 0 0 0 1
        $row.BorderThickness = New-Thickness 3 0 0 0
        $row.BorderBrush = [Windows.Media.Brushes]::Transparent
        $row.Style = $Window.FindResource('HoverLine')
        $row.DataContext = $h
        $row.Add_MouseRightButtonUp({ param($s, $e) Show-SoftHistMenu $s; $e.Handled = $true })
        $g = [Windows.Controls.Grid]::new()
        foreach ($wd in 0, 150, 150, 170, 80) {
            $cd = [Windows.Controls.ColumnDefinition]::new()
            if ($wd) { $cd.Width = [Windows.GridLength]::new($wd) }
            [void]$g.ColumnDefinitions.Add($cd)
        }
        $nm = [Windows.Controls.StackPanel]::new()
        $t1 = New-Text "$($h.Name)"; $t1.TextWrapping = 'NoWrap'; $t1.TextTrimming = 'CharacterEllipsis'; [void]$nm.Children.Add($t1)
        $dt = try { '{0:dd/MM/yyyy HH:mm}' -f [DateTime]$h.Date } catch { "$($h.Date)" }
        $t2 = New-Text ('{0}  ·  {1}{2}' -f $dt, $h.Id, $(if ($h.User) { "  ·  $($h.User)" } else { '' })) 'Muted'
        $t2.FontSize = 11
        $t2.TextWrapping = 'NoWrap'
        $t2.TextTrimming = 'CharacterEllipsis'
        [void]$nm.Children.Add($t2)
        $c2 = New-Text "$($h.From)"; [Windows.Controls.Grid]::SetColumn($c2, 1)
        $c3 = New-Text "$($h.To)"; [Windows.Controls.Grid]::SetColumn($c3, 2)
        $c4 = New-Text $(if ($h.Ok) { 'mis à jour' } else { 'échec ({0})' -f (Format-WingetCode $h.Code) }); [Windows.Controls.Grid]::SetColumn($c4, 3)
        if (-not $h.Ok) {
            $em = $WingetErr[(Format-WingetCode $h.Code)]
            $c4.ToolTip = $(if ($em) { "$($em[1])`n" } else { '' }) + 'Clic droit > Copier l''erreur pour le détail'
        }
        $c4.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, $(if ($h.Ok) { 'OkFgBrush' } else { 'ErrFgBrush' }))
        $c4.FontWeight = [Windows.FontWeights]::SemiBold
        foreach ($x in $c2, $c3, $c4) { $x.VerticalAlignment = 'Center'; $x.TextWrapping = 'NoWrap'; $x.TextTrimming = 'CharacterEllipsis' }
        foreach ($x in $nm, $c2, $c3, $c4) { [void]$g.Children.Add($x) }
        $row.Child = $g; [void]$SoftUI.List.Children.Add($row)
    }
    Update-WinTextZoom $SoftUI.Win $SoftUI.List
    $SoftUI.EmptyCtx = @{ Q = $q; Upd = 0; All = 0; Hist = $true; Err = $false; NoInv = $false; Run = $false }
    $SoftUI.Hint.Text = $(if (-not $Hist.Count) { 'Aucune mise à jour effectuée par l''application sur ce poste.' } elseif (-not $show.Count) { 'Aucune entrée pour cette recherche.' } else { '' })
    Update-SoftEmpty
    Update-SoftStatus
}
# Logiciel ouvert pendant sa mise à jour : certains installeurs (Discord, Slack... installeur Squirrel dans le profil)
# échouent au lieu de le fermer (« accès refusé » en déplaçant leur dossier). Bloquent ce dossier : le logiciel lui-même,
# mais aussi tout processus qui a chargé une de ses DLL (superposition Discord injectée dans les jeux, extension de
# l'Explorateur...). Repérés avant la confirmation : exécutable portant le nom du logiciel, exécutable ou DLL chargée
# dans son dossier d'installation (clé de désinstallation : InstallLocation, sinon dossier du désinstalleur).
function Get-SoftInstallDir($App) {
    $dirs = [Collections.Generic.List[string]]::new()
    foreach ($root in 'HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall') {
        $k = Open-RegKey $root; if (-not $k) { continue }
        try {
            foreach ($n in $k.GetSubKeyNames()) {
                $sk = $k.OpenSubKey($n); if (-not $sk) { continue }
                try {
                    if ("$($sk.GetValue('DisplayName'))" -ne "$($App.Name)") { continue }
                    $d = "$($sk.GetValue('InstallLocation'))".Trim().Trim('"')
                    if (-not $d) { $us = "$($sk.GetValue('UninstallString'))"; if ($us -match '^\s*"([^"]+\.exe)"' -or $us -match '^\s*(\S+\.exe)') { $d = Split-Path $Matches[1] } }
                    $d = [Environment]::ExpandEnvironmentVariables($d).TrimEnd('\')
                    # dossiers trop généraux (racine, Program Files, Windows) écartés
                    if ($d.Length -gt 12 -and $d -notmatch '(?i)^[a-z]:\\(program files( \(x86\))?|windows|programdata)?$' -and (Test-Path -LiteralPath $d)) { $dirs.Add($d + '\') }
                } finally { $sk.Close() }
            }
        } finally { $k.Close() }
    }
    @($dirs | Select-Object -Unique)
}
# Programmes qui bloquent le logiciel : recherche complète (processus du même nom + fichiers du dossier ouverts, gestionnaire
# de redémarrage de Windows) faite par la tâche juste avant l'installeur (Find-SoftLocker), jamais par l'interface :
# l'énumération des processus et de leurs fichiers prend plusieurs secondes et figeait la fenêtre (« Ne répond pas »).
# Ici : nom court et dossiers d'installation (registre, quelques ms) transmis à la tâche, et programmes ouverts du même
# nom (liste des processus seule, sans ouvrir chaque processus) pour les nommer dans la confirmation.
function Get-SoftLockInfo($App) {
    @{ Base = ((Get-SoftShortName "$($App.Name)") -replace '[^\p{L}\p{N}]', ''); Dirs = @(Get-SoftInstallDir $App) }
}
function Get-SoftOpenName($Items) {
    $run = @{}
    foreach ($p in [Diagnostics.Process]::GetProcesses()) { try { $run[$p.ProcessName] = 1 } finally { $p.Dispose() } }
    $out = @{}
    foreach ($a in $Items) { $b = (Get-SoftLockInfo $a).Base; if ($b.Length -ge 3 -and $run.ContainsKey($b)) { $out["$($a.Id)"] = "$b.exe" } }
    $out
}
# logiciel installé dans le profil de l'utilisateur (identifiant « ARP\User\... » ou entrée de désinstallation de son
# registre) : winget lancé sous son compte, sans élévation (Invoke-SoftToolAsUser)
function Test-SoftUserScope($App) {
    if ($App.Pfn) { return $false }
    if ("$(Get-SoftLocalId $App)" -match '^ARP\\User\\') { return $true }
    $k = Open-RegKey 'HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall'; if (-not $k) { return $false }
    try {
        foreach ($n in $k.GetSubKeyNames()) {
            $sk = $k.OpenSubKey($n); if (-not $sk) { continue }
            try { if ("$($sk.GetValue('DisplayName'))" -eq "$($App.Name)") { return $true } } finally { $sk.Close() }
        }
    } finally { $k.Close() }
    $false
}
function Get-SoftLocalId($App) { $(if ($App.LocalId) { "$($App.LocalId)" } elseif (-not $App.Match) { "$($App.Id)" } else { '' }) }
# Désinstallation ou réinstallation (désinstallation puis installation de la dernière version) via winget, mêmes suivi,
# historique et rapport que les mises à jour ; logiciel ouvert fermé avant.
function Invoke-SoftRemove($Items, [string]$Mode) {
    $sel = @($Items | Where-Object { $_ -and (Get-SoftLocalId $_) })
    if (-not $sel.Count) { return }
    if ($Sync.Running) { Show-Info 'Une tâche est déjà en cours. Relancer une fois terminée.'; return }
    $re = $Mode -eq 'reinstall'; $one = $sel.Count -eq 1
    $head = $(if ($re) { $(if ($one) { 'Réinstaller {0} ?' -f (Get-SoftShortName $sel[0].Name) } else { "Réinstaller ces $($sel.Count) logiciels ?" }) } else { $(if ($one) { 'Désinstaller {0} ?' -f (Get-SoftShortName $sel[0].Name) } else { "Désinstaller ces $($sel.Count) logiciels ?" }) })
    $lines = @($sel | ForEach-Object { '{0}  ·  {1}  ·  {2}' -f $_.Name, $_.From, $_.SrcLabel })
    $foot = $(if ($re) { 'Chaque logiciel est désinstallé puis réinstallé dans sa dernière version ; si la désinstallation échoue, il n''est pas réinstallé.' } else { 'Désinstallation silencieuse quand l''éditeur la prévoit, sinon le désinstalleur du logiciel s''affiche.' })
    $open = Get-SoftOpenName $sel
    $foot += ' Les programmes qui bloquent le dossier du logiciel sont fermés juste avant (travail non enregistré perdu)' + $(if ($open.Count) { ', dont ' + (@($open.Values | Select-Object -Unique) -join ', ') + '.' } else { '.' })
    if (-not (Confirm-List $head $lines $foot $(if ($re) { 'Réinstaller' } else { 'Désinstaller' }) 'WarnBtn')) { return }
    $Sync.Params = @{ Soft = @($sel | ForEach-Object { @{ Mode = $Mode; Name = "$($_.Name)"; Id = "$($_.Id)"; LocalId = (Get-SoftLocalId $_); Src = "$($_.Src)"; Pfn = "$($_.Pfn)"; From = "$($_.From)"; To = ''; Match = [bool]$_.Match; Unknown = $false; User = (Test-SoftUserScope $_); Lock = (Get-SoftLockInfo $_) } }) }
    [void](Start-Worker @('SoftUpgrade'))
    Update-SoftStatus
}
# entrées orphelines : sauvegardées (.reg, dossier d'état) puis supprimées du registre ; lignes retirées de l'inventaire
function Remove-SoftOrphan($Items) {
    $sel = @($Items | Where-Object { $_.Orphan -and $_.RegKey })
    if (-not $sel.Count) { return }
    $lines = @($sel | ForEach-Object { '{0}  ·  {1}' -f $_.Name, $_.RegKey })
    if (-not (Confirm-List $(if ($sel.Count -eq 1) { 'Retirer l''entrée de {0} ?' -f (Get-SoftShortName $sel[0].Name) } else { "Retirer ces $($sel.Count) entrées ?" }) $lines 'Logiciel déjà absent du poste : seule son entrée de désinstallation est supprimée du registre, après sauvegarde (.reg) dans le dossier d''état de l''application.' 'Retirer' 'WarnBtn')) { return }
    $dir = Join-Path (Get-LogPath 'Etat') 'entrees-retirees'
    try { [void][IO.Directory]::CreateDirectory($dir) } catch { Write-Ignored 'Dossier de sauvegarde des entrées' $_ }
    $done = [Collections.Generic.List[string]]::new()
    foreach ($a in $sel) {
        $file = Join-Path $dir ('{0:yyyyMMdd-HHmmss}_{1}.reg' -f (Get-Date), (("$($a.Name)" -replace '[^\w\-]+', '_').Trim('_')))
        try {
            $out = & "$env:windir\System32\reg.exe" export $a.RegKey $file /y 2>&1
            if ($LASTEXITCODE -ne 0) { throw "sauvegarde impossible : $((@($out) -join ' ').Trim())" }
            $root = $(if ($a.RegKey -like 'HKCU\*') { [Microsoft.Win32.Registry]::CurrentUser } else { [Microsoft.Win32.Registry]::LocalMachine })
            $root.DeleteSubKeyTree($a.RegKey.Substring(5), $false)
            $done.Add("$($a.Id)")
            Write-UiLog ('Entrée orpheline retirée : {0} ({1}), sauvegarde {2}' -f $a.Name, $a.RegKey, $file) 'OK'
            Add-SessionEvent 'Logiciels' $a.Name 'entrée orpheline retirée' 'ok'
        } catch { Write-UiLog ('Entrée de {0} non retirée : {1}' -f $a.Name, $_.Exception.Message) 'WARN' }
    }
    if ($done.Count -and $Sync.WgResult) {
        $Sync.WgResult.Apps = @($Sync.WgResult.Apps | Where-Object { $done -notcontains "$($_.Id)" })
        try { $o = @{} + $Sync.WgResult; $o.Stamp = ([DateTime]$Sync.WgResult.Stamp).ToString('o'); ConvertTo-Json -InputObject $o -Depth 4 | Set-Content -LiteralPath $SoftFile -Encoding UTF8 } catch { Write-Ignored 'Enregistrement de l''inventaire des logiciels' $_ }
        $SoftUI.CacheStamp = $null; Update-SoftView
    }
}
function Invoke-SoftUpgrade($Items) {
    $sel = @($Items | Where-Object { $_ -and $_.To -and $_.Src })
    if (-not $sel.Count) { return }
    if ($Sync.Running) { Show-Info 'Une tâche est déjà en cours. Relancer la mise à jour une fois terminée.'; return }
    $one = $sel.Count -eq 1
    $head = $(if ($one) { 'Installer la mise à jour de {0} ?' -f (Get-SoftShortName $sel[0].Name) } else { "Installer ces $($sel.Count) mises à jour ?" })
    $lines = @($sel | ForEach-Object { '{0}  ·  {1} > {2}  ·  {3}' -f $_.Name, $_.From, $_.To, $_.SrcLabel })
    $foot = 'Installation silencieuse' + $(if ($one) { '' } else { ', un logiciel après l''autre' }) + '. Les logiciels ouverts peuvent être fermés par leur installeur.'
    if (@($sel | Where-Object { $_.Match }).Count) { $foot += ' Logiciel rattaché par son nom : la nouvelle version est installée par-dessus l''existante.' }
    $open = Get-SoftOpenName $sel
    if ($open.Count) { $foot += ' Programmes ouverts qui bloquent la mise à jour, fermés juste avant (travail non enregistré perdu) : ' + (@($open.Values | Select-Object -Unique) -join ', ') + '.' }
    if (-not (Confirm-List $head $lines $foot 'Installer' 'ActionBtn')) { return }
    $Sync.Params = @{ Soft = @($sel | ForEach-Object { @{ Name = "$($_.Name)"; Id = "$($_.Id)"; Src = "$($_.Src)"; Pfn = "$($_.Pfn)"; From = "$($_.From)"; To = "$($_.To)"; Match = [bool]$_.Match; Unknown = [bool]$_.Unknown; User = (Test-SoftUserScope $_); Lock = (Get-SoftLockInfo $_) } }) }
    [void](Start-Worker @('SoftUpgrade'))
    Update-SoftStatus
}
# carte Logiciels de Maintenance retirée (mises à jour dans l'onglet Applications) : texte de résumé gardé hors écran,
# il porte l'état affiché sur le bouton « Mettre à jour (N) » et le journal des inventaires (Update-SoftCard)
$SoftUI.CardText = [Windows.Controls.TextBlock]::new()
# barre de progression du pied de page cliquable pendant une tâche : fenêtre Logiciels pendant leur mise à jour,
# onglet Journal (avancement détaillé) pour les autres tâches
$Ui.FooterStatus.Add_MouseLeftButtonUp({
    if (-not $Sync.Running) { return }
    if (Test-SoftUpgrading) { try { Show-SoftWindow } catch { Write-UiLog "Fenêtre Logiciels : $($_.Exception.Message)" 'ERROR' } }
    else { Show-Page 'Log' }
})
