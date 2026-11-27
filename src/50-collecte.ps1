$HealthFr = @{ Healthy = @('Sain', 'OkFgBrush'); Warning = @('Avertissement', 'WarnFgBrush'); Unhealthy = @('Défaillant', 'ErrFgBrush') }

# ---------- Informations de l'Accueil, sans runspace permanent :
#   - passe initiale ($InfoScript, une fois au démarrage) : poste, processeur, mémoire, GPU, batterie, détections des réglages ;
#   - imprimantes ($InfoPrnScript) et santé des disques ($InfoDiskScript) : à la demande (démarrage, Actualiser, F5,
#     changement de volumes), runspace libéré à la fin ;
#   - volumes : fil .NET natif ([_OlivM.VolWatch], native\Systeme.cs), 5 s quand l'Accueil est affiché, 30 s sinon.
# Chaque passe fusionne son résultat dans $Sync.InfoSlow sous verrou (passes simultanées sans perte).
$InfoLib = @'
function Publish-InfoSlow([hashtable]$Part) {
    [Threading.Monitor]::Enter($Sync.SyncRoot)
    try {
        $o = $(if ($Sync.InfoSlow) { $Sync.InfoSlow.Clone() } else { @{} })
        foreach ($k in $Part.Keys) { $o[$k] = $Part[$k] }
        $o.Stamp = [DateTime]::Now
        $Sync.InfoSlow = $o
    }
    finally { [Threading.Monitor]::Exit($Sync.SyncRoot) }
}
'@
$InfoScript = @'
$ProgressPreference = 'SilentlyContinue'
$slow = @{}
try {
    $bios = Get-CimInstance Win32_BIOS -Property SerialNumber
    $cpu  = Get-CimInstance Win32_Processor -Property NumberOfCores | Select-Object -First 1
    $cs   = Get-CimInstance Win32_ComputerSystem -Property Domain, PartOfDomain, Workgroup
    $os   = Get-CimInstance Win32_OperatingSystem -Property Caption
    $ram  = [double]0; foreach ($m in @(Get-CimInstance Win32_PhysicalMemory -Property Capacity)) { $ram += [double]$m.Capacity }
    # n° de série : le BIOS d'un PC assemblé renvoie souvent une valeur par défaut (« To be filled by O.E.M. »...) ;
    # on prend alors la 1re valeur réelle parmi produit, châssis puis carte mère (SMBIOS types 1, 3, 2)
    $junk = '^(?i)(to be filled.*|default string|system serial number|chassis serial number|base ?board serial number|serial ?number|not (specified|applicable|available)|none|n/?a|oem|o\.e\.m\.?|unknown|invalid|empty|x+|0+|1234567890?|123456789|[\s.\-_0]*)$'
    $sn = ''; $snSrc = ''
    $csp = $null; try { $csp = Get-CimInstance Win32_ComputerSystemProduct -Property IdentifyingNumber, UUID } catch {}
    $cand = @(@("$($bios.SerialNumber)", 'BIOS', ''), @("$($csp.IdentifyingNumber)", 'produit', ''))
    try {
        foreach ($e in @(Get-CimInstance Win32_SystemEnclosure -Property SerialNumber)) { $cand += , @("$($e.SerialNumber)", 'châssis', 'châssis') }
    } catch {}
    try {
        $bb = Get-CimInstance Win32_BaseBoard -Property SerialNumber | Select-Object -First 1
        $cand += , @("$($bb.SerialNumber)", 'carte mère', 'carte mère')
    } catch {}
    foreach ($c in $cand) {
        $v = $c[0].Trim().TrimEnd('.').Trim()
        if ($v -and $v -notmatch $junk) { $sn = $v + $(if ($c[2]) { "  ($($c[2]))" } else { '' }); $snSrc = $c[1]; break }
    }
    if (-not $sn) {
        $u = "$($csp.UUID)".Trim()
        $sn = 'non renseigné par le fabricant' + $(if ($u -and $u -notmatch '^(?i)[0f\-]+$|^03000200-0400-0500-0006-000700080009$') { "  (UUID $u)" } else { '' }); $snSrc = 'aucun'
    }
    $slow = @{ Serial = $sn; SerialSrc = $snSrc; Cores = $cpu.NumberOfCores; Caption = $os.Caption; Ram = $ram
               Domain = $(if ($cs.PartOfDomain) { $cs.Domain } else { "$($cs.Workgroup) (groupe de travail)" }) }
    # cartes graphiques : périphériques PCI ou ACPI uniquement (écarte les adaptateurs virtuels : bureau à distance,
    # pilote de base Microsoft, DisplayLink, Parsec...). Intégrée = puce graphique du processeur (Intel hors Arc A/B,
    # APU AMD « Radeon Graphics / Vega N / 780M », ASPEED et Matrox des serveurs) ; NVIDIA toujours dédiée.
    # VRAM : HardwareInformation.qwMemorySize de la clé pilote (Win32_VideoController.AdapterRAM plafonne à 4 Go).
    $gpus = @()
    try {
        foreach ($vc in @(Get-CimInstance Win32_VideoController -Property Name, PNPDeviceID, DriverVersion, DriverDate)) {
            $pnp = "$($vc.PNPDeviceID)"; $nm = "$($vc.Name)".Trim()
            if (-not $nm -or $pnp -notmatch '^(PCI|ACPI)\\' -or $nm -match '(?i)basic (display|render)|remote|virtual|hyper-v|parsec|citrix|vmware|virtualbox|displaylink|idd') { continue }
            $ven = if ($pnp -match 'VEN_([0-9A-F]{4})') { $Matches[1] } elseif ($pnp -match '^ACPI\\QCOM') { 'QCOM' } else { '' }
            $integ = switch ($ven) {
                '10DE' { $false }
                '8086' { $nm -notmatch '(?i)Arc.*\b[AB]\d{3}|Iris Xe MAX|DG[12]' }
                '1002' { $nm -notmatch '(?i)\bRX\b|\bPro\b|FirePro|Instinct|Radeon VII|Vega (56|64|Frontier)|\bR[579] \d{3}|\bHD \d{4}|\bW\d{4}' }
                default { $true }
            }
            $vram = [double]0
            try {
                $drv = (Get-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Enum\$pnp" -Name Driver -ErrorAction Stop).Driver
                $hk = Get-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Control\Class\$drv" -ErrorAction Stop
                $q = $hk.'HardwareInformation.qwMemorySize'
                if ($q) { $vram = [double]$q } else {
                    $m = $hk.'HardwareInformation.MemorySize'
                    if ($m -is [byte[]] -and $m.Length -ge 4) { $vram = [double][BitConverter]::ToUInt32($m, 0) } elseif ($m) { $vram = [double]$m }
                }
            } catch {}
            $dd = ''; try { if ($vc.DriverDate) { $dd = ([datetime]$vc.DriverDate).ToString('dd/MM/yyyy') } } catch {}
            $gpus += @{ Name = $nm; Integrated = [bool]$integ; Vram = $vram; Driver = "$($vc.DriverVersion)"; DriverDate = $dd }
        }
    } catch {}
    $slow.Gpu = $gpus
    # batterie (mWh) : classes root\wmi, sinon rapport powercfg /batteryreport /xml ; aucune batterie (Win32_Battery) = poste fixe
    $slow.Battery = @{ None = $true }
    try {
        # portable : PCSystemType = 2 (Mobile) ou châssis portable (Win32_SystemEnclosure.ChassisTypes)
        $mob = [int](Get-CimInstance Win32_ComputerSystem -Property PCSystemType -ErrorAction SilentlyContinue).PCSystemType -eq 2
        $ch = @((Get-CimInstance Win32_SystemEnclosure -Property ChassisTypes -ErrorAction SilentlyContinue).ChassisTypes)
        $isLaptop = $mob -or @($ch | Where-Object { [int]$_ -in 8, 9, 10, 11, 12, 14, 18, 21, 30, 31, 32 }).Count -gt 0
        $hasBat = $isLaptop
        if ($isLaptop) {
            $dsg = [double]0; $ful = [double]0; $cyc = $null; $src = ''
            try {
                foreach ($x in @(Get-CimInstance -Namespace 'root/wmi' -ClassName BatteryStaticData -ErrorAction Stop)) { $dsg += [double]$x.DesignedCapacity }
                foreach ($x in @(Get-CimInstance -Namespace 'root/wmi' -ClassName BatteryFullChargedCapacity -ErrorAction Stop)) { $ful += [double]$x.FullChargedCapacity }
                $bc = @(Get-CimInstance -Namespace 'root/wmi' -ClassName BatteryCycleCount -ErrorAction SilentlyContinue); if ($bc.Count) { $cyc = ($bc | Measure-Object -Property CycleCount -Sum).Sum }
                $src = 'WMI root\wmi'
            } catch {}
            if ($dsg -le 0 -or $ful -le 0) {
                $xf = Join-Path $env:TEMP 'olivm-batterie.xml'
                & "$env:windir\System32\powercfg.exe" /batteryreport /xml /output $xf 2>&1 | Out-Null
                if (Test-Path -LiteralPath $xf) {
                    [xml]$bx = Get-Content -LiteralPath $xf -Raw
                    $dsg = [double]0; $ful = [double]0; $cyc = $null
                    foreach ($bn in @($bx.SelectNodes("//*[local-name()='Battery']"))) {
                        $d = $bn.SelectSingleNode("*[local-name()='DesignCapacity']"); $f = $bn.SelectSingleNode("*[local-name()='FullChargeCapacity']"); $c = $bn.SelectSingleNode("*[local-name()='CycleCount']")
                        if ($d) { $dsg += [double]$d.InnerText }; if ($f) { $ful += [double]$f.InnerText }; if ($c -and "$($c.InnerText)" -match '^\d+$') { $cyc = [int]$cyc + [int]$c.InnerText }
                    }
                    Remove-Item -LiteralPath $xf -Force -ErrorAction SilentlyContinue
                    $src = 'powercfg /batteryreport'
                }
            }
            $slow.Battery = $(if ($dsg -gt 0 -and $ful -gt 0) { @{ Design = $dsg; Full = $ful; Cycles = $cyc; Source = $src } } elseif ($hasBat) { @{ Unknown = $true } } else { @{ None = $true } })
        }
    } catch { $slow.Battery = @{ Unknown = $true; Error = $_.Exception.Message } }
    # détections pour les réglages (40-reglages.ps1) : même passe que l'Accueil, aucune requête WMI en double
    $need = @{ LaptopCim = [bool]$isLaptop }
    try { $need.Camera = @(Get-CimInstance Win32_PnPEntity -Filter "PNPClass='Camera' OR PNPClass='Image'" -ErrorAction Stop | Where-Object { "$($_.Status)" -eq 'OK' }).Count -gt 0 } catch { Write-Ignored 'Détection de la caméra' $_ }
    try { $need.CopilotPlus = @(Get-CimInstance Win32_PnPEntity -Filter "PNPClass='ComputeAccelerator'" -ErrorAction Stop).Count -gt 0 } catch { Write-Ignored 'Détection du processeur IA (NPU)' $_ }
    # Defender actif (réglages Defender de Sécurité) : lu ici, en arrière-plan (chargement du module CIM, plusieurs secondes
    # au 1er appel sur le fil d'interface) ; exception = antivirus tiers ou service arrêté
    try { $need.Defender = "$((Get-MpComputerStatus -ErrorAction Stop).AMRunningMode)" -eq 'Normal' } catch { $need.Defender = $false }
    $Sync.NeedPre = $need
    Publish-InfoSlow $slow
} catch { Write-Ignored 'Informations du poste' $_ }
$Sync.InfoBaseDone = $true
'@

$InfoPrnScript = @'
$slow = @{}
# imprimantes installées sur le poste (hors connexions réseau \\serveur, lues par utilisateur dans le registre) et hors virtuelles
try {
    $ports = @{}; foreach ($pp in @(Get-CimInstance Win32_TCPIPPrinterPort -ErrorAction SilentlyContinue)) { $ports["$($pp.Name)"] = "$($pp.HostAddress)" }
    $slow.Printers = @(Get-CimInstance Win32_Printer -ErrorAction Stop | Where-Object { -not $_.Network -and "$($_.PortName)" -notmatch '^(PORTPROMPT:|nul:|SHRFAX:|XPSPort:|FILE:|OneNote|Microsoft\.Office)' -and "$($_.Name)" -notmatch '^(Microsoft Print to PDF|Microsoft XPS Document Writer|Fax|OneNote)' } | ForEach-Object {
        $pn = "$($_.PortName)"
        $src = $(if ($ports.ContainsKey($pn)) { 'IP ' + $ports[$pn] } elseif ($pn -like 'WSD*') { 'WSD (découverte réseau)' } elseif ($pn -like 'USB*') { "USB ($pn)" } else { $pn })
        @{ Name = "$($_.Name)"; Source = $src } })
} catch { $slow.Printers = @() }
$slow.PrnStamp = [DateTime]::Now
Publish-InfoSlow $slow
'@
$InfoDiskScript = @'
$MediaFr = @{ 0 = ''; 3 = 'HDD'; 4 = 'SSD'; 5 = 'SCM' }
$BusFr   = @{ 1 = 'SCSI'; 3 = 'ATA'; 6 = 'Fibre'; 7 = 'USB'; 8 = 'RAID'; 9 = 'iSCSI'; 10 = 'SAS'; 11 = 'SATA'; 12 = 'SD'; 13 = 'MMC'; 15 = 'Fichier'; 16 = 'Espaces de stockage'; 17 = 'NVMe' }
$HealthEn = @{ 0 = 'Healthy'; 1 = 'Warning'; 2 = 'Unhealthy' }
$slow = @{}
try {
    # lettre de lecteur -> numéro de disque (MSFT_Partition.DiskNumber = MSFT_PhysicalDisk.DeviceId)
    $vd = @{}
    try {
        foreach ($pt in @(Get-CimInstance -Namespace 'root/Microsoft/Windows/Storage' -ClassName MSFT_Partition -ErrorAction Stop)) {
            $dl = "$($pt.DriveLetter)".Trim([char]0, ' ')
            if ($dl) {
                $k = "$($dl):"
                if (-not $vd[$k]) { $vd[$k] = [Collections.ArrayList]::new() }
                if ("$($pt.DiskNumber)" -notin $vd[$k]) { [void]$vd[$k].Add("$($pt.DiskNumber)") }
            }
        }
    } catch {}
    $slow.VolDisk = @{}; foreach ($k in $vd.Keys) { $slow.VolDisk[$k] = @($vd[$k]) }
    $slow.Disks = @(Get-CimInstance -Namespace 'root/Microsoft/Windows/Storage' -ClassName MSFT_PhysicalDisk -ErrorAction Stop | Sort-Object { [int]"$($_.DeviceId)" } | ForEach-Object {
        $id = "$($_.DeviceId)"
        @{ Id = $id; Name = "$($_.FriendlyName)"; Media = $MediaFr[[int]$_.MediaType]; Bus = $BusFr[[int]$_.BusType]; Size = [double]$_.Size; Health = $HealthEn[[int]$_.HealthStatus]
           Letters = (@($vd.Keys | Where-Object { $id -in $vd[$_] } | Sort-Object) -join ', ') } })
} catch { $slow.Disks = @() }
Publish-InfoSlow $slow
'@

# Runspace d'arrière-plan (stratégie d'exécution levée, table $Sync partagée) : @{ PS ; Handle }
# Sortie de l'application : arrêt des tâches de fond, des processus enfants restants (sauf ceux annoncés comme poursuivis
# à la fermeture et la relance après réinitialisation), puis fin du processus PowerShell (et de sa console cachée)
function Exit-App([int]$Code = 0) {
    try { if ($script:Notif) { $script:Notif.Visible = $false; $script:Notif.Dispose() } } catch {}
    try { $Sync.InfoStop = $true; $Sync.CleanScanStop = $true; $Sync.Cancel = $true; $Sync.WuCancel = $true } catch {}
    try { foreach ($k in @($BgJobs.Keys)) { try { [void]$BgJobs[$k].PS.BeginStop($null, $null) } catch {} } } catch {}
    try { if ($TreeUI.Job) { [_OlivM.DirScan]::Cancel = $true } } catch {}
    $keep = @()
    foreach ($v in $Sync.ChildPid, $Sync.RelaunchPid) { if ($v) { $keep += [int]$v } }
    # mise à jour prête (94-mise-a-jour) : script de remplacement lancé maintenant que la fenêtre est fermée, jamais arrêté
    try { if ($Sync.UpdHelper) { $up = Start-UpdHelper; if ($up) { $keep += [int]$up } } } catch {}
    # installation constructeur en cours (BIOS, micrologiciel, pilotes : installeurs lancés par le module ou l'outil du
    # constructeur, sans PID connu) : aucun processus enfant arrêté, l'installeur en cours va jusqu'à sa fin (un flash du
    # BIOS interrompu peut rendre le PC inutilisable) ; seules les tâches de fond de l'application sont arrêtées
    if ($Sync.OemInstalling) { [Environment]::Exit($Code) }
    try {
        foreach ($c in @(Get-CimInstance Win32_Process -Filter "ParentProcessId=$PID" -ErrorAction Stop)) {
            if ([int]$c.ProcessId -in $keep) { continue }
            & "$env:windir\System32\taskkill.exe" /PID $c.ProcessId /T /F 2>&1 | Out-Null
        }
    } catch {}
    [Environment]::Exit($Code)
}
# Nom du réseau Wi-Fi : tâche dédiée, lancée à l'ouverture puis à chaque changement de réseau détecté par l'Accueil
$SsidScript = @'
$SsidCache = @{}
function Get-SsidFromNetworkList([string]$Name) {
    if ($SsidCache.ContainsKey($Name)) { return $SsidCache[$Name] }
    $base = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\NetworkList'
    $res = $Name
    $prof = Get-ChildItem -LiteralPath "$base\Profiles" -ErrorAction SilentlyContinue | Where-Object { (Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue).ProfileName -eq $Name } | Select-Object -First 1
    if ($prof) {
        $found = $null
        foreach ($k in @(Get-ChildItem -LiteralPath "$base\Signatures\Unmanaged", "$base\Signatures\Managed" -ErrorAction SilentlyContinue)) {
            $pp = Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction SilentlyContinue
            if ("$($pp.ProfileGuid)" -eq $prof.PSChildName -and $pp.FirstNetwork) { $found = "$($pp.FirstNetwork)"; break }
        }
        if (-not $found) { $found = "$((Get-ItemProperty -LiteralPath $prof.PSPath -ErrorAction SilentlyContinue).Description)" }
        if ($found) { $res = $found }
    }
    $SsidCache[$Name] = $res
    $res
}
function Get-WlanKnownSsid([string]$IfGuid) {
    $dir = Join-Path $env:ProgramData ('Microsoft\Wlansvc\Profiles\Interfaces\{' + $IfGuid.Trim('{}').ToUpper() + '}')
    foreach ($f in @(Get-ChildItem -LiteralPath $dir -Filter '*.xml' -File -ErrorAction SilentlyContinue)) {
        try {
            $x = [xml][IO.File]::ReadAllText($f.FullName)
            foreach ($n in @($x.WLANProfile.SSIDConfig.SSID)) { if ($n.name) { "$($n.name)" } }
        } catch {}
    }
}
function Resolve-Ssid([string]$Name, [string]$IfGuid) {
    $known = @(Get-WlanKnownSsid $IfGuid)
    if (-not $known.Count -or $known -contains $Name) { return $Name }
    if ($Name -match '^(.+?)\s+\d+$' -and $known -contains $Matches[1]) { return $Matches[1] }
    $Name
}
function Update-Ssid {
    $wl = @([Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces() | Where-Object { "$($_.NetworkInterfaceType)" -eq 'Wireless80211' -and "$($_.OperationalStatus)" -eq 'Up' })
    $map = @{}
    if ($wl.Count) {
        $g = $null
        foreach ($l in @(& "$env:windir\System32\netsh.exe" wlan show interfaces 2>$null)) {
            if ($l -match '^\s*GUID\s*:\s*(\S+)') { $g = $Matches[1].Trim('{}').ToLower() }
            elseif ($l -match '^\s*SSID\s*:\s*(.+?)\s*$' -and $g) { $map[$g] = $Matches[1] }
        }
        # sans localisation : SSID de la dernière connexion réussie de la carte (WLAN-AutoConfig, événement 8001)
        foreach ($w in $wl) {
            $k = $w.Id.Trim('{}').ToLower()
            if ($map.ContainsKey($k)) { continue }
            try {
                foreach ($e in @(Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-WLAN-AutoConfig/Operational'; Id = 8001 } -MaxEvents 20 -ErrorAction Stop)) {
                    $d = @{}; foreach ($x in ([xml]$e.ToXml()).Event.EventData.Data) { $d[$x.Name] = "$($x.'#text')" }
                    if ("$($d['InterfaceGuid'])".Trim('{}').ToLower() -eq $k -and $d['SSID']) { $map[$k] = $d['SSID']; break }
                }
            } catch {}
        }
        $prof = @{}
        if (@($wl | Where-Object { -not $map.ContainsKey($_.Id.Trim('{}').ToLower()) }).Count) {
            try {
                $nlm = [Activator]::CreateInstance([Type]::GetTypeFromCLSID([Guid]'DCB00C01-570F-4A9B-8D69-199FDBA5723B'))
                foreach ($c in $nlm.GetNetworkConnections()) { $prof["$($c.GetAdapterId())".Trim('{}').ToLower()] = "$($c.GetNetwork().GetName())" }
            } catch {}
        }
        foreach ($w in $wl) {
            $k = $w.Id.Trim('{}').ToLower()
            if ($map.ContainsKey($k)) { continue }
            $pn = $prof[$k]
            if ($pn -match '^(Identification|Identifying)') { $pn = $null }
            if (-not $pn) {
                $pr = Get-NetConnectionProfile -InterfaceAlias $w.Name -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($pr) { $pn = "$($pr.Name)" }
            }
            $map[$k] = $(if ($pn) { Resolve-Ssid (Get-SsidFromNetworkList $pn) $w.Id } else { '' })
        }
    }
    $Sync.Ssid = $map
}
try { Update-Ssid } catch { Write-Ignored 'Nom du réseau Wi-Fi' $_ }
$Sync.SsidRunning = $false
'@
function Start-SsidJob {
    Close-BgJob
    if ($BgJobs.ContainsKey('Ssid')) { $Sync.SsidAgain = $true; return }
    $Sync.SsidRunning = $true
    Start-BgJob 'Ssid' $SsidScript
}
function Start-InfoCollector {
    Start-BgJob 'Info' ($InfoLib + "`n" + $InfoScript)
    $Sync.PrnRequest = $true; $Sync.DiskRequest = $true
    [_OlivM.VolWatch]::Start()
}
# minuteur : passes imprimantes / disques demandées (Actualiser, F5, changement de volumes) et volumes lus par VolWatch
function Watch-InfoRequest {
    if ($Sync.PrnRequest -and -not $BgJobs.ContainsKey('InfoPrn')) {
        $Sync.PrnRequest = $false
        Start-BgJob 'InfoPrn' ($InfoLib + "`n" + $InfoPrnScript)
    }
    if ($Sync.DiskRequest -and -not $BgJobs.ContainsKey('InfoDisk')) {
        $Sync.DiskRequest = $false
        Start-BgJob 'InfoDisk' ($InfoLib + "`n" + $InfoDiskScript)
    }
    [_OlivM.VolWatch]::IntervalMs = $(if ($Sync.InfoVisible) { 5000 } else { 30000 })
    if ($Sync.VolRequest) { $Sync.VolRequest = $false; [_OlivM.VolWatch]::Refresh() }
    $st = [_OlivM.VolWatch]::Stamp
    if ($st -ne $script:VolStamp) {
        $script:VolStamp = $st; $Sync.Vols = @([_OlivM.VolWatch]::Vols); $sig = [_OlivM.VolWatch]::Sig
        if ($null -ne $script:VolSigLast -and $sig -ne $script:VolSigLast) { $Sync.DiskRequest = $true }
        $script:VolSigLast = $sig
    }
}
# passe initiale lancée dès le chargement (détections des réglages comprises), en parallèle de la préparation de la fenêtre
Start-InfoCollector

$DiagScript = @'
$ProgressPreference = 'SilentlyContinue'
$items = [Collections.ArrayList]::new()
function Add-D([string]$K, [string]$V, [string]$B, [string]$T) { [void]$items.Add(@{ K = $K; V = $V; B = $B; T = $T }) }
# âge en jours des signatures les plus anciennes parmi les antivirus actifs (non passifs) de date connue ; $null si aucune
function Get-AvWorstAge($Avs) {
    $ages = @($Avs | Where-Object { $_.Date -and -not $_.Passive } | ForEach-Object { ([DateTime]::Now - [DateTime]$_.Date).TotalDays })
    if ($ages.Count) { ($ages | Measure-Object -Maximum).Maximum } else { $null }
}
$since = (Get-Date).AddDays(-30)
# ---------- Historique des installations Windows Update : 2 sources réelles fusionnées, rapprochées par numéro KB
#  - historique de l'agent Windows Update (IUpdateSearcher.QueryHistory, 1 000 entrées au plus) ;
#  - journal Système, source Microsoft-Windows-WindowsUpdateClient (19 = installée, 20 = échec, 120 derniers jours) :
#    complète l'historique quand celui-ci a été vidé (réinitialisation de Windows Update) ou ne garde pas l'opération.
# Enregistrement commun : @{ Date (locale); Kb; Title; Ok (bool); Code (HRESULT ou 0); Src }.
# Définitions Defender (KB2267602, quotidiennes) écartées : la ligne Antivirus donne déjà leur date.
function ConvertFrom-WuHistory($H) {
    @($H | Where-Object { $_.Operation -eq 1 -and $_.ResultCode -in 2, 3, 4 } | ForEach-Object {
        $k = Get-KB $_.Title
        if ($k -and $k -ne 'KB2267602') { @{ Date = $_.Date.ToLocalTime(); Kb = $k; Title = "$($_.Title)"; Ok = $_.ResultCode -in 2, 3; Code = $(if ($_.ResultCode -eq 4) {
            $hr = [int64]$_.HResult
            if ($hr -lt 0) { $hr + 4294967296 } else { $hr }
        } else { 0 }); Src = 'historique Windows Update' } }
    })
}
function ConvertFrom-WuEvent($E) {
    @($E | ForEach-Object {
        $m = "$($_.Message)"; $k = Get-KB $m
        if ($k -and $k -ne 'KB2267602') {
            $code = 0; if ($_.Id -eq 20 -and $m -match '0x([0-9A-Fa-f]{8})') { $code = [Convert]::ToInt64($Matches[1], 16) }
            $t = $m; try { $t = "$($_.Properties[$(if ($_.Id -eq 20) { 1 } else { 0 })].Value)" } catch {}
            @{ Date = $_.TimeCreated; Kb = $k; Title = $t; Ok = $_.Id -eq 19; Code = $code; Src = 'journal Système' }
        }
    })
}
# famille d'une mise à jour : titre sans date, KB ni numéros de version (« Mise à jour cumulative pour Windows 11 Version 26H2
# pour systèmes x64 ») ; une installation réussie plus récente de la même famille remplace un échec (version ultérieure)
function Get-WuFamily([string]$Title) {
    $t = $Title -replace '\(KB\d+\)', '' -replace 'KB\d+', '' -replace '^\s*\d{4}-\d{2}\s+', '' -replace '\b\d+(\.\d+)+\b', '' -replace '\(\s*\)', ''
    ($t.ToLower() -replace '[^\p{L}\p{Nd}]+', ' ').Trim()
}
# Ok : installations réussies, la plus récente en tête. Fail : échec le plus récent encore valable, c'est-à-dire sans
# installation réussie après lui de la même KB ni de la même famille, et KB absente des correctifs installés ($Installed).
# Attempts : nombre d'échecs de cette KB ; Codes : codes d'erreur distincts ; Sources : origines de l'information.
function Get-WuHistorySummary($Records, [string[]]$Installed = @()) {
    $r = @($Records | Where-Object { $_ } | Sort-Object { $_.Date } -Descending)
    $ok = @($r | Where-Object { $_.Ok })
    $fail = $null
    foreach ($f in @($r | Where-Object { -not $_.Ok })) {
        if ($Installed -contains $f.Kb) { continue }
        $fam = Get-WuFamily $f.Title
        $fixed = @($ok | Where-Object { $_.Date -gt $f.Date -and ($_.Kb -eq $f.Kb -or ($fam -and (Get-WuFamily $_.Title) -eq $fam)) }).Count
        if (-not $fixed) {
            $same = @($r | Where-Object { -not $_.Ok -and $_.Kb -eq $f.Kb })
            $fail = @{ Date = $f.Date; Kb = $f.Kb; Title = $f.Title; Code = $f.Code; Attempts = @($same | ForEach-Object { '{0:yyyyMMddHH}{1}' -f $_.Date, [int][math]::Floor($_.Date.Minute / 10) } | Select-Object -Unique).Count
                       First = ($same | Sort-Object { $_.Date } | Select-Object -First 1).Date; Codes = @($same | Where-Object { $_.Code } | ForEach-Object { '0x{0:X8}' -f $_.Code } | Select-Object -Unique)
                       Sources = @($same | ForEach-Object { $_.Src } | Select-Object -Unique) }
            break
        }
    }
    @{ Ok = $ok; Fail = $fail }
}
# signification des codes d'erreur Windows Update les plus fréquents (orientation du dépannage)
$WuErrText = @{
    '0x800F0922' = 'échec du traitement : partition système (EFI / réservée) trop petite, ou connexion VPN / serveur de mise à jour coupée'
    '0x800F081F' = 'fichiers source introuvables : magasin de composants à réparer (DISM /RestoreHealth)'
    '0x800F0988' = 'magasin de composants à nettoyer (DISM /StartComponentCleanup) avant nouvel essai'
    '0x800F0831' = 'mise à jour préalable manquante ou magasin de composants endommagé'
    '0x80073712' = 'magasin de composants endommagé (DISM /RestoreHealth)'
    '0x80073701' = 'composant système manquant (DISM /RestoreHealth)'
    '0x80070002' = 'fichier introuvable : réinitialiser les composants Windows Update'
    '0x80070003' = 'chemin introuvable : réinitialiser les composants Windows Update'
    '0x80070005' = 'accès refusé (antivirus, droits sur les dossiers système)'
    '0x8007000D' = 'données non valides : téléchargement corrompu, réinitialiser les composants Windows Update'
    '0x80070070' = 'espace disque insuffisant'
    '0x800705B4' = 'délai dépassé'
    '0x8024200D' = 'téléchargement incomplet : relancer la recherche puis l''installation'
    '0x80240034' = 'téléchargement en échec'
    '0x80242016' = 'installation interrompue (redémarrage en cours d''opération)'
    '0x8024402C' = 'serveur de mise à jour injoignable (proxy, DNS, pare-feu)'
    '0x80244022' = 'serveur de mise à jour indisponible (HTTP 503)'
    '0x80240FFF' = 'catégorie de mise à jour inconnue (WSUS)'
}

$ev = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WER-SystemErrorReporting'; Id = 1001; StartTime = $since } -ErrorAction SilentlyContinue)
if ($ev.Count) {
    $code = ("$($ev[0].Properties[0].Value)" -split '\s')[0]
    Add-D 'Écrans bleus (30 derniers jours)' ('{0}  ·  dernier le {1:dd/MM/yyyy HH:mm}  ·  code {2}' -f $ev.Count, $ev[0].TimeCreated, $code) 'ErrFgBrush'
} else { Add-D 'Écrans bleus (30 derniers jours)' 'aucun' 'OkFgBrush' }

try {
    $recs = [Collections.Generic.List[object]]::new(); $srcErr = @()
    try {
        $srch = (New-Object -ComObject Microsoft.Update.Session).CreateUpdateSearcher()
        $cnt = $srch.GetTotalHistoryCount()
        if ($cnt -gt 0) { foreach ($x in ConvertFrom-WuHistory @($srch.QueryHistory(0, [math]::Min($cnt, 1000)))) { $recs.Add($x) } }
    } catch { $srcErr += "historique : $($_.Exception.Message)" }
    try {
        $wev = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WindowsUpdateClient'; Id = 19, 20; StartTime = (Get-Date).AddDays(-120) } -ErrorAction Stop)
        foreach ($x in ConvertFrom-WuEvent $wev) { $recs.Add($x) }
    } catch { if ($_.Exception.Message -notmatch 'No events|Aucun événement') { $srcErr += "journal : $($_.Exception.Message)" } }
    if (-not $recs.Count -and $srcErr.Count) { throw ($srcErr -join ' / ') }
    $qfe = @(); try { $qfe = @(Get-CimInstance Win32_QuickFixEngineering -Property HotFixID -ErrorAction Stop | ForEach-Object { "$($_.HotFixID)".ToUpper() }) } catch {}
    $sum = Get-WuHistorySummary $recs.ToArray() $qfe; $ok = $sum.Ok; $fail = $sum.Fail
    if ($ok.Count) {
        $d = $ok[0].Date
        Add-D 'Dernière mise à jour installée' ('{0:dd/MM/yyyy} - {1}' -f $d, $ok[0].Kb) $(if (([DateTime]::Now - $d).Days -gt 45) { 'WarnFgBrush' } else { 'OkFgBrush' }) $ok[0].Title
    } else { Add-D 'Dernière mise à jour installée' 'aucune KB dans l''historique' 'WarnFgBrush' }
    if ($fail) {
        $c = $(if ($fail.Code) { '0x{0:X8}' -f $fail.Code } else { 'code inconnu' })
        $tip = @($fail.Title, ('{0} {1} : {2}' -f $fail.Attempts, (Get-Plural $fail.Attempts 'tentative en échec' 'tentatives en échec'), $(if ($fail.Attempts -gt 1) { 'du {0:dd/MM/yyyy} au {1:dd/MM/yyyy}' -f $fail.First, $fail.Date } else { '{0:dd/MM/yyyy HH:mm}' -f $fail.Date })))
        if (@($fail.Codes).Count -gt 1) { $tip += 'codes : ' + ($fail.Codes -join ', ') }
        if ($WuErrText[$c]) { $tip += "$c : $($WuErrText[$c])" }
        $tip += 'non installée depuis (ni elle ni une version plus récente) - source : ' + ($fail.Sources -join ' + ')
        Add-D 'Dernière mise à jour en échec' ('{0:dd/MM/yyyy} - {1} - {2}' -f $fail.Date, $fail.Kb, $c) $(if (([DateTime]::Now - $fail.Date).Days -le 30) { 'ErrFgBrush' } else { 'WarnFgBrush' }) ($tip -join "`n")
    } else { Add-D 'Dernière mise à jour en échec' 'aucune' 'OkFgBrush' 'Aucun échec sans installation réussie ensuite (historique Windows Update + journal Système, 120 jours)' }
} catch { Add-D 'Windows Update' ('historique illisible : ' + $_.Exception.Message) 'WarnFgBrush' }

try {
    $bv = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction Stop
    # X : état transmis au menu de la ligne (activer / désactiver / reprendre), opération en cours = menu inactif
    $bk = "BitLocker ($env:SystemDrive)"; $vs = "$($bv.VolumeStatus)"; $pc = [int]$bv.EncryptionPercentage
    if ($vs -eq 'EncryptionInProgress') { [void]$items.Add(@{ K = $bk; V = "chiffrement en cours ($pc %)"; B = 'WarnFgBrush'; X = 'encrypting' }) }
    elseif ($vs -eq 'DecryptionInProgress') { [void]$items.Add(@{ K = $bk; V = "déchiffrement en cours ($pc %)"; B = 'WarnFgBrush'; X = 'decrypting' }) }
    # chiffrement ou déchiffrement en pause : distinct de la protection suspendue (reprise de la conversion, pas de la protection)
    elseif ($vs -in 'EncryptionPaused', 'DecryptionPaused') { [void]$items.Add(@{ K = $bk; V = $(if ($vs -eq 'EncryptionPaused') { "chiffrement en pause ($pc %)" } else { "déchiffrement en pause ($pc %)" }); B = 'WarnFgBrush'; X = 'paused' }) }
    elseif ("$($bv.ProtectionStatus)" -eq 'On') { [void]$items.Add(@{ K = $bk; V = 'activé'; B = 'OkFgBrush'; X = 'on' }) }
    elseif ($pc -gt 0) { [void]$items.Add(@{ K = $bk; V = 'activé, protection suspendue'; B = 'WarnFgBrush'; X = 'suspended' }) }
    else { [void]$items.Add(@{ K = $bk; V = 'désactivé'; B = 'WarnFgBrush'; X = 'off' }) }
    if ($bv.EncryptionPercentage -gt 0) {
        $rp = @($bv.KeyProtector | Where-Object { "$($_.KeyProtectorType)" -eq 'RecoveryPassword' -and $_.RecoveryPassword })
        if ($rp.Count) { foreach ($k in $rp) { Add-D 'Clé de récupération' "$($k.RecoveryPassword)" '' } }
        else { Add-D 'Clé de récupération' 'aucune sur ce volume' 'ErrFgBrush' }
    }
} catch { }   # BitLocker absent de l'édition (Famille) : ligne non affichée

# Antivirus : un produit par ligne « Produit (maj le : date) »
$avs = [Collections.Generic.List[object]]::new()
$av = @(); try { $av = @(Get-CimInstance -Namespace 'root\SecurityCenter2' -ClassName AntiVirusProduct -ErrorAction Stop) } catch {}
foreach ($n in @($av | ForEach-Object { "$($_.displayName)" } | Where-Object { $_ -and $_ -notmatch 'Defender' } | Select-Object -Unique)) {
    $d = $null
    if ($n -match 'Sophos') {
        # Sophos AutoUpdate : ...\Sophos\AutoUpdate\UpdateStatus\LastUpdateTime (secondes depuis 1970, UTC), sinon date du fichier d'état
        foreach ($k in 'HKLM:\SOFTWARE\WOW6432Node\Sophos\AutoUpdate\UpdateStatus', 'HKLM:\SOFTWARE\Sophos\AutoUpdate\UpdateStatus') {
            $v = (Get-ItemProperty -LiteralPath $k -Name LastUpdateTime -ErrorAction SilentlyContinue).LastUpdateTime
            if ($v) { $d = [DateTimeOffset]::FromUnixTimeSeconds([long]$v).LocalDateTime; break }
        }
        if (-not $d) {
            $f = Join-Path $env:ProgramData 'Sophos\AutoUpdate\data\status\SophosUpdateStatus.xml'
            if (Test-Path -LiteralPath $f) { $d = (Get-Item -LiteralPath $f).LastWriteTime }
        }
    }
    $avs.Add(@{ Name = $n; Date = $d; Passive = $false })
}
$mpMode = ''
# Defender passif ou arrêté (autre antivirus actif) : affiché comme tel, ses signatures ne comptent pas dans la couleur
try { $mp = Get-MpComputerStatus -ErrorAction Stop; $mpMode = "$($mp.AMRunningMode)"; $avs.Add(@{ Name = 'Windows Defender'; Date = $mp.AntivirusSignatureLastUpdated; Passive = $mpMode -ne 'Normal' }) } catch {}
if ($avs.Count) {
    $txt = ($avs | ForEach-Object { '{0} ({1}maj le : {2})' -f $_.Name, $(if ($_.Passive) { 'passif, ' } else { '' }), $(if ($_.Date) { '{0:dd/MM/yyyy HH:mm}' -f $_.Date } else { 'inconnue' }) }) -join "`n"
    # couleur : âge des signatures des antivirus actifs dont la date est connue (date illisible pour la plupart des produits
    # tiers : avant, comptée 99 jours, ligne toujours rouge) ; aucune date connue = orange
    $worst = Get-AvWorstAge @($avs)
    # antivirus principal (menu d'analyse de la ligne) : Defender actif (mode Normal, ni passif ni désactivé au profit d'un
    # autre produit), sinon 1er antivirus tiers activé d'après le Centre de sécurité (productState, bits 12-15 = 1)
    # Sophos installé = antivirus principal (Defender alors passif ou désactivé), quel que soit son productState
    $names = @($av | ForEach-Object { "$($_.displayName)" } | Where-Object { $_ -and $_ -notmatch 'Defender' })
    $third = @($av | Where-Object { "$($_.displayName)" -notmatch 'Defender' -and ((([int]$_.productState) -shr 12) -band 0xF) -eq 1 } | ForEach-Object { "$($_.displayName)" })
    $soph = @($names | Where-Object { $_ -match '(?i)sophos' })
    $main = $(if ($soph.Count) { 'other:' + $soph[0] } elseif ($mpMode -eq 'Normal') { 'defender' } elseif ($third.Count) { 'other:' + $third[0] } elseif ($names.Count) { 'other:' + $names[0] } elseif ($mpMode) { 'defender' } else { '' })
    [void]$items.Add(@{ K = 'Antivirus'; V = $txt; B = $(if ($null -eq $worst) { 'WarnFgBrush' } elseif ($worst -le 2) { 'OkFgBrush' } elseif ($worst -le 7) { 'WarnFgBrush' } else { 'ErrFgBrush' }); X = $(if ($main) { 'av:' + $main } else { '' }) })
} else { Add-D 'Antivirus' 'aucun antivirus détecté' 'ErrFgBrush' }

try {
    $rp = @(Get-ComputerRestorePoint -ErrorAction Stop | Sort-Object SequenceNumber)
    $Sync.RestoreLast = if ($rp.Count) { @{ Time = [Management.ManagementDateTimeConverter]::ToDateTime($rp[-1].CreationTime); Desc = "$($rp[-1].Description)" } } else { @{ Time = $null } }
} catch { $Sync.RestoreLast = @{ Time = $null; Error = $true } }
$Sync.Diag = @{ Items = $items.ToArray(); Stamp = [DateTime]::Now }
$Sync.DiagRunning = $false
'@

