$CleanLib = @'
$CleanProfiles = @(Get-ChildItem -LiteralPath "$env:SystemDrive\Users" -Directory -Force -ErrorAction SilentlyContinue |
                   Where-Object { -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) } | ForEach-Object { $_.FullName })
# lecteurs fixes : lus à la première utilisation seulement (IsReady réveille un disque dur en veille : plusieurs secondes),
# donc dans les runspaces de mesure et de nettoyage, jamais pendant la préparation de la fenêtre
function Get-CleanDrive {
    if ($null -eq $script:CleanDrivesCache) { $script:CleanDrivesCache = @([IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq 'Fixed' -and $_.IsReady } | ForEach-Object { $_.Name.TrimEnd('\') }) }
    $script:CleanDrivesCache
}
function UP([string]$Kind, [string[]]$Rel) { foreach ($p in $CleanProfiles) { foreach ($r in $Rel) { '{0}:{1}\{2}' -f $Kind, $p, $r } } }
function Get-FastSize([string]$Path) {
    $total = [double]0
    $stack = [System.Collections.Stack]::new()
    $stack.Push($Path)
    while ($stack.Count) {
        $d = $stack.Pop()
        try {
            $di = [IO.DirectoryInfo]::new($d)
            foreach ($f in $di.EnumerateFiles()) { $total += $f.Length }
            foreach ($s in $di.EnumerateDirectories()) {
                if (-not ($s.Attributes -band [IO.FileAttributes]::ReparsePoint)) { $stack.Push($s.FullName) }
            }
        } catch {}
    }
    $total
}
$CleanItems = @(
    [pscustomobject]@{ Id='Temp'; Group='Système'; Label='Fichiers temporaires'
        Tip='%LOCALAPPDATA%\Temp (tous profils), %windir%\Temp. Fichiers verrouillés ignorés.'
        Targets={ @(UP 'D' 'AppData\Local\Temp') + "D:$env:windir\Temp" } }
    [pscustomobject]@{ Id='WinUpdate'; Group='Système'; Label='Mises à jour Windows (téléchargements)'
        Tip='%windir%\SoftwareDistribution\Download. Arrêt / relance de wuauserv et BITS.'
        Targets={ "D:$env:windir\SoftwareDistribution\Download" }
        Pre={
            $Sync.WasRunning = @(Get-Service -Name wuauserv, bits -ErrorAction SilentlyContinue | Where-Object Status -EQ 'Running' | ForEach-Object Name)
            Stop-Service -Name wuauserv, bits -Force -ErrorAction SilentlyContinue
        }
        Post={ foreach ($s in @($Sync.WasRunning)) { Start-Service -Name $s -ErrorAction SilentlyContinue } } }
    [pscustomobject]@{ Id='DOCache'; Group='Système'; Label='Cache de partage des mises à jour'
        Tip='Delete-DeliveryOptimizationCache -Force.'
        Targets={ "D:$env:windir\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache" }
        Clean={
            if (Get-Command Delete-DeliveryOptimizationCache -ErrorAction SilentlyContinue) {
                Delete-DeliveryOptimizationCache -Force -ErrorAction Stop
                Write-TaskLog 'Cache vidé.' 'OK'
            } else { Write-TaskLog 'Delete-DeliveryOptimizationCache indisponible sur cette version.' 'WARN' }
        } }
    [pscustomobject]@{ Id='Logs'; Group='Système'; Label='Journaux'
        Tip='%windir%\Logs\CBS, DISM, WindowsUpdate, SoftwareDistribution\DataStore\Logs.'
        Targets={
            "D:$env:windir\Logs\CBS"
            "D:$env:windir\Logs\DISM"
            "D:$env:windir\Logs\WindowsUpdate"
            "D:$env:windir\SoftwareDistribution\DataStore\Logs"
        } }
    [pscustomobject]@{ Id='Dumps'; Group='Système'; Label='Fichiers de vidage mémoire'
        Tip='%windir%\MEMORY.DMP, Minidump, LiveKernelReports, %LOCALAPPDATA%\CrashDumps.'
        Targets={ @("F:$env:windir\MEMORY.DMP", "D:$env:windir\Minidump", "D:$env:windir\LiveKernelReports") + @(UP 'D' 'AppData\Local\CrashDumps') } }
    [pscustomobject]@{ Id='WER'; Group='Système'; Label='Rapports d''erreurs'
        Tip='%ProgramData%\Microsoft\Windows\WER\ReportArchive, ReportQueue, Temp + WER des profils.'
        Targets={ @("D:$env:ProgramData\Microsoft\Windows\WER\ReportArchive", "D:$env:ProgramData\Microsoft\Windows\WER\ReportQueue", "D:$env:ProgramData\Microsoft\Windows\WER\Temp") + @(UP 'D' 'AppData\Local\Microsoft\Windows\WER') } }
    [pscustomobject]@{ Id='DirectX'; Group='Système'; Label='Cache DirectX'
        Tip='%LOCALAPPDATA%\D3DSCache (tous profils).'
        Targets={ UP 'D' 'AppData\Local\D3DSCache' } }
    [pscustomobject]@{ Id='Thumbs'; Group='Système'; Label='Miniatures'
        Tip='%LOCALAPPDATA%\Microsoft\Windows\Explorer\thumbcache_*.db (tous profils).'
        Targets={ UP 'F' 'AppData\Local\Microsoft\Windows\Explorer\thumbcache_*.db' } }
    [pscustomobject]@{ Id='Prefetch'; Group='Système'; Label='Préchargement (Prefetch)'
        Tip='%windir%\Prefetch.'
        Targets={ "D:$env:windir\Prefetch" } }
    [pscustomobject]@{ Id='Recycle'; Group='Système'; Label='Corbeilles (tous les utilisateurs)'
        Tip='<lecteur>\$Recycle.Bin (disques fixes, tous SID).'
        Targets={ foreach ($d in (Get-CleanDrive)) { "D:$d\`$Recycle.Bin\*" } } }
    [pscustomobject]@{ Id='RestorePoints'; Present={
        try {
            $v = Get-SysVolumeId
            @(Get-CimInstance Win32_ShadowStorage -ErrorAction Stop | Where-Object { "$($_.Volume.DeviceID)" -eq $v }).Count -gt 0
        } catch { $true }
    }; Group='Composants Windows'; Label='Anciens points de restauration (le plus récent est conservé)'
        Tip='Win32_ShadowCopy (ClientAccessible) du volume système créés avec un point de restauration (Get-ComputerRestorePoint), sauf le plus récent ; autres clichés jamais supprimés. Taille affichée : Win32_ShadowStorage.UsedSpace, espace occupé par tous les points.'
        Targets={ }
        Size={ Get-RestoreUsed }
        Clean={
            $vol = Get-SysVolumeId
            # clichés des seuls points de restauration (date de création d'un point de restauration à 5 min près) : les autres
            # clichés accessibles du volume (logiciel de sauvegarde, versions précédentes) ne sont jamais supprimés.
            # Liste des points illisible : rien n'est supprimé
            $pts = @(Get-ComputerRestorePoint -ErrorAction Stop | ForEach-Object { [Management.ManagementDateTimeConverter]::ToDateTime("$($_.CreationTime)") })
            $sc = @(Select-RestoreShadow @(Get-CimInstance Win32_ShadowCopy -ErrorAction Stop | Where-Object { $_.VolumeName -eq $vol -and $_.ClientAccessible }) $pts | Sort-Object InstallDate)
            if ($sc.Count -le 1) { Write-TaskLog ('{0} point de restauration : rien à supprimer.' -f $sc.Count) 'OK'; return }
            $before = Get-RestoreUsed
            $old = @($sc | Select-Object -First ($sc.Count - 1))
            foreach ($x in $old) {
                try { Remove-CimInstance -InputObject $x -ErrorAction Stop } catch { Write-TaskLog ('Cliché {0} : {1}' -f $x.ID, $_.Exception.Message) 'WARN' }
            }
            $after = Get-RestoreUsed
            Write-TaskLog ('{0} {1}, le plus récent conservé. Libéré : {2}.' -f $old.Count, (Get-Plural $old.Count 'point supprimé' 'points supprimés'), (Format-Size ([math]::Max([double]0, $before - $after)) 'rien')) 'OK'
        } }

    [pscustomobject]@{ Id='WindowsOld'; Present={ Test-Path -LiteralPath "$env:SystemDrive\Windows.old" }; Group='Composants Windows'; Label='Ancienne version de Windows (Windows.old)'
        Tip='cleanmgr /sagerun (Previous Installations). Rollback impossible ensuite.'
        Targets={ "D:$env:SystemDrive\Windows.old" }
        Clean={ Invoke-Task_WindowsOld } }
)
# Navigateurs : détection générique dans chaque profil (AppData classique + paquets MSIX\LocalCache)
#  - Chromium : <Local>\...\User Data contenant "Local State" (2 niveaux max) -> User Data\*\Cache, Code Cache, GPUCache
#  - Opera    : <Roaming>\Opera Software\<canal> contenant "Local State" -> cache dans Local et Roaming, profil racine et sous-profils
#  - Gecko    : <Roaming>\...\profiles.ini (2 niveaux max) -> <Local>\<même chemin>\Profiles\*\cache2 (clients mail exclus)
$BrowserNames = @{
    'C|Microsoft\Edge' = 'Microsoft Edge'; 'C|Microsoft\Edge Beta' = 'Microsoft Edge Beta'; 'C|Microsoft\Edge Dev' = 'Microsoft Edge Dev'; 'C|Microsoft\Edge SxS' = 'Microsoft Edge Canary'
    'C|Google\Chrome' = 'Google Chrome'; 'C|Google\Chrome Beta' = 'Google Chrome Beta'; 'C|Google\Chrome Dev' = 'Google Chrome Dev'; 'C|Google\Chrome SxS' = 'Google Chrome Canary'
    'C|BraveSoftware\Brave-Browser' = 'Brave'; 'C|BraveSoftware\Brave-Browser-Beta' = 'Brave Beta'; 'C|BraveSoftware\Brave-Browser-Nightly' = 'Brave Nightly'
    'C|Vivaldi' = 'Vivaldi'; 'C|Chromium' = 'Chromium'; 'C|Thorium' = 'Thorium'; 'C|Yandex\YandexBrowser' = 'Yandex Browser'; 'C|Arc' = 'Arc'
    'C|Comodo\Dragon' = 'Comodo Dragon'; 'C|CentBrowser' = 'Cent Browser'; 'C|Naver\Naver Whale' = 'Naver Whale'; 'C|Epic Privacy Browser' = 'Epic Privacy Browser'
    'C|Ecosia\EcosiaBrowser' = 'Ecosia'; 'C|Avast Software\Browser' = 'Avast Secure Browser'; 'C|AVG\Browser' = 'AVG Secure Browser'; 'C|CCleaner Browser' = 'CCleaner Browser'
    'O|Opera Stable' = 'Opera'; 'O|Opera GX Stable' = 'Opera GX'; 'O|Opera Air Stable' = 'Opera Air'; 'O|Opera Beta' = 'Opera Beta'; 'O|Opera Developer' = 'Opera Developer'
    'G|Mozilla\Firefox' = 'Mozilla Firefox'; 'G|Waterfox' = 'Waterfox'; 'G|librewolf' = 'LibreWolf'; 'G|Floorp' = 'Floorp'; 'G|zen' = 'Zen Browser'
    'G|Moonchild Productions\Pale Moon' = 'Pale Moon'; 'G|Mozilla\SeaMonkey' = 'SeaMonkey'; 'G|Mullvad\MullvadBrowser' = 'Mullvad Browser'
}
function Get-SubDirectory([string]$Path) { try { @([IO.Directory]::EnumerateDirectories($Path)) } catch { @() } }
function Get-BrowserItem {
    $found = [ordered]@{}
    $add = { param($Key, [string[]]$Paths)
        if (-not $found.Contains($Key)) { $found[$Key] = [System.Collections.ArrayList]::new() }
        foreach ($x in $Paths) { [void]$found[$Key].Add("D:$x") }
    }
    foreach ($p in $CleanProfiles) {
        $l0 = "$p\AppData\Local"; $r0 = "$p\AppData\Roaming"
        $roots = [System.Collections.ArrayList]::new(); [void]$roots.Add(@($l0, $r0))
        # paquets du Microsoft Store : seulement ceux qui ressemblent à un navigateur (plusieurs centaines de dossiers sinon)
        foreach ($pk in (Get-SubDirectory "$l0\Packages")) {
            if ([IO.Path]::GetFileName($pk) -match '(?i)browser|arc|firefox|mozilla|opera|vivaldi|brave|chrom|edge|waterfox|librewolf|floorp|zen|yandex|thorium' -and [IO.Directory]::Exists("$pk\LocalCache")) { [void]$roots.Add(@("$pk\LocalCache\Local", "$pk\LocalCache\Roaming")) }
        }
        foreach ($rt in $roots) {
            $l = $rt[0]; $r = $rt[1]
            # Chromium
            foreach ($base in @($l, $r)) {
                if (-not ([IO.Directory]::Exists($base))) { continue }
                $cands = [System.Collections.ArrayList]::new()
                foreach ($a in (Get-SubDirectory $base)) { [void]$cands.Add($a); foreach ($b in (Get-SubDirectory $a)) { [void]$cands.Add($b) } }
                foreach ($c in $cands) {
                    $ud = "$c\User Data"
                    if (-not ([IO.File]::Exists("$ud\Local State"))) { continue }
                    $rel = $c.Substring($base.Length + 1)
                    & $add "C|$rel" @("$ud\*\Cache", "$ud\*\Code Cache", "$ud\*\GPUCache")
                }
            }
            # Opera (profil à la racine du canal, sous-profils éventuels)
            foreach ($o in (Get-SubDirectory "$r\Opera Software")) {
                if (-not ([IO.File]::Exists("$o\Local State"))) { continue }
                $n = Split-Path $o -Leaf; $lo = "$l\Opera Software\$n"
                & $add "O|$n" @("$lo\Cache", "$lo\*\Cache", "$o\Cache", "$o\Code Cache", "$o\GPUCache", "$o\*\Cache", "$o\*\Code Cache", "$o\*\GPUCache")
            }
            # Gecko
            if ([IO.Directory]::Exists($r)) {
                $cands = [System.Collections.ArrayList]::new()
                foreach ($a in (Get-SubDirectory $r)) { [void]$cands.Add($a); foreach ($b in (Get-SubDirectory $a)) { [void]$cands.Add($b) } }
                foreach ($c in $cands) {
                    if (-not ([IO.File]::Exists("$c\profiles.ini"))) { continue }
                    $rel = $c.Substring($r.Length + 1)
                    if ($rel -match '(?i)thunderbird|betterbird|postbox|interlink') { continue }
                    & $add "G|$rel" @("$l\$rel\Profiles\*\cache2", "$c\Profiles\*\cache2")
                }
            }
        }
    }
    foreach ($k in $found.Keys) {
        $rel = $k.Substring(2)
        $label = $BrowserNames[$k]
        if (-not $label) { $label = ($rel -replace '\\', ' ') -replace '(?i)\s*(stable|user data)$', '' }
        $tip = switch ($k.Substring(0, 1)) { 'C' { 'User Data\*\Cache, Code Cache, GPUCache (tous profils).' } 'O' { 'Cache, Code Cache, GPUCache (profil principal et sous-profils).' } default { 'Profiles\*\cache2 (tous profils).' } }
        [pscustomobject]@{ Id = 'Br_' + ($k -replace '[^A-Za-z0-9]', '_'); Group = 'Cache des navigateurs'; Label = $label; Tip = $tip
            Paths = @($found[$k] | Select-Object -Unique); Targets = { } }
    }
}
# navigateurs : détection (parcours des dossiers AppData de chaque profil, jusqu'à près d'une seconde sur un poste chargé)
# faite dans le runspace de mesure des tailles, jamais au chargement de l'interface ($CleanSkipBrowsers) ; la liste trouvée
# est publiée dans $Sync.CleanBrowsers et les lignes ajoutées par Sync-CleanBrowser (71-nettoyage.ps1)
if (-not $CleanSkipBrowsers) { $CleanItems = @($CleanItems) + @(Get-BrowserItem) }
# éléments absents du poste (protection système désactivée, pas de Windows.old...) : test Present fait par la mesure des
# tailles en arrière-plan ($CleanScanScript), jamais au chargement (requête Win32_ShadowStorage = démarrage du service
# VSS, jusqu'à une dizaine de secondes), ligne masquée ensuite par Update-CleanSize
# ordre fixe des catégories
$CleanGroupOrder = 'Système', 'Cache des navigateurs', 'Composants Windows'
# clichés dont la date de création est celle d'un point de restauration (5 min d'écart au plus)
function Select-RestoreShadow($Shadows, $PointTimes) {
    foreach ($s in @($Shadows)) {
        if (-not $s -or -not $s.InstallDate) { continue }
        foreach ($t in @($PointTimes)) { if ([math]::Abs(([DateTime]$s.InstallDate - [DateTime]$t).TotalMinutes) -le 5) { $s; break } }
    }
}
function Get-SysVolumeId { (Get-CimInstance Win32_Volume -Filter ("DriveLetter='{0}'" -f $env:SystemDrive) -ErrorAction Stop).DeviceID }
function Get-RestoreUsed {
    $vol = Get-SysVolumeId
    $st = @(Get-CimInstance Win32_ShadowStorage -ErrorAction SilentlyContinue | Where-Object { "$($_.Volume.DeviceID)" -eq $vol })
    $u = [double]0; foreach ($x in $st) { $u += [double]$x.UsedSpace }; $u
}
# cible, ou l'un de ses dossiers parents, qui est un lien (jonction, lien symbolique) : refusée. Un utilisateur standard
# pouvait remplacer un dossier de son profil (AppData\Local\CrashDumps, Temp...) par une jonction vers un dossier qu'il ne
# peut pas modifier, vidé ensuite par le nettoyage avec les droits administrateur. Attributs illisibles : refusée aussi.
function Test-CleanLinkPath([string]$Path) {
    $p = $Path
    while ($p) {
        try { if (([IO.File]::GetAttributes($p) -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return $true } } catch { return $true }
        $p = [IO.Path]::GetDirectoryName($p)
    }
    $false
}
# motif pour Get-Item -Path : partie fixe du chemin (avant le 1er dossier qui contient * ou ?) échappée. Avant, les crochets
# d'un nom de profil (C:\Users\Jean[1]) étaient lus comme des jokers : profil jamais nettoyé ni mesuré. Sans joker : $null
# (chemin pris tel quel, -LiteralPath)
function ConvertTo-CleanPattern([string]$Path) {
    $w = $Path.IndexOfAny([char[]]'*?'); if ($w -lt 0) { return $null }
    $cut = $Path.LastIndexOf('\', $w)
    if ($cut -lt 0) { return $Path }
    [WildcardPattern]::Escape($Path.Substring(0, $cut)) + $Path.Substring($cut)
}
function Resolve-CleanTarget($Item) {
    $src = $(if ($Item.Paths) { $Item.Paths } else { & $Item.Targets })
    foreach ($t in @($src)) {
        if (-not $t) { continue }
        $kind = $t.Substring(0, 1); $path = $t.Substring(2)
        $pat = ConvertTo-CleanPattern $path
        $found = $(if ($pat) { @(Get-Item -Path $pat -Force -ErrorAction SilentlyContinue) } else { @(Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue) })
        foreach ($o in $found) {
            if (Test-CleanLinkPath $o.FullName) { continue }
            if ($kind -eq 'D' -and $o.PSIsContainer) { [pscustomobject]@{ Kind = 'D'; Path = $o.FullName; Len = 0 } }
            elseif ($kind -eq 'F' -and -not $o.PSIsContainer) { [pscustomobject]@{ Kind = 'F'; Path = $o.FullName; Len = [double]$o.Length } }
        }
    }
}
'@

$CleanScanScript = @'
$ProgressPreference = 'SilentlyContinue'
# navigateurs trouvés publiés avant la mesure des tailles : lignes affichées tout de suite
$Sync.CleanBrowsers = @($CleanItems | Where-Object { $_.Group -eq 'Cache des navigateurs' } | ForEach-Object { @{ Id = $_.Id; Group = $_.Group; Label = $_.Label; Tip = $_.Tip; Paths = @($_.Paths) } })
foreach ($it in $CleanItems) {
    if ($Sync.CleanScanStop) { break }
    if ($it.Present) {
        $here = $true
        try { $here = [bool](& $it.Present) } catch { Write-Ignored "Présence de « $($it.Label) »" $_ }
        if (-not $here) { $Sync.CleanAbsent[$it.Id] = $true; continue }
    }
    $s = [double]0
    # taille non mesurable : aucune valeur publiée (« taille inconnue » à l'écran, jamais « vide »)
    if ($it.Size) { try { $s = [double](& $it.Size) } catch { Write-Ignored "Taille de « $($it.Label) »" $_; continue } }
    else { foreach ($t in @(Resolve-CleanTarget $it)) { if ($t.Kind -eq 'D') { $s += Get-FastSize $t.Path } else { $s += $t.Len } } }
    $Sync.CleanSizes[$it.Id] = $s
}
$Sync.CleanScanDone = $true
'@

$CleanSkipBrowsers = $true
. ([scriptblock]::Create($CleanLib))

