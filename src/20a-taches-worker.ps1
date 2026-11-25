# Tâches exécutées en arrière-plan (runspace du worker), partie 1 : outils communs, nettoyage, journal des tâches
$WorkerScript = @'
$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'
$SysDrive  = $env:SystemDrive
$SysLetter = $SysDrive.TrimEnd(':')

function Write-TaskLog {
    param([string]$Message, [string]$Level = 'INFO')
    if ([string]::IsNullOrEmpty($Message)) { $line = '' }
    else { $line = '{0} [{1,-5}] {2}' -f (Get-Date -Format 'HH:mm:ss'), $Level, $Message }
    # bilan par tâche pour le rapport d'intervention : erreurs, avertissements, dernier message de résultat
    if ($Sync.TaskRes) {
        if ($Level -eq 'ERROR') { $Sync.TaskRes.Err++ } elseif ($Level -eq 'WARN') { $Sync.TaskRes.Warn++ }
        if ($Level -in 'OK', 'BILAN', 'WARN', 'ERROR' -and $Message) { $Sync.TaskRes.Last = $Message }
    }
    $Sync.Queue.Enqueue($line)
    try { [IO.File]::AppendAllText($Sync.LogFile, $line + [Environment]::NewLine, [Text.Encoding]::UTF8) }
    catch {
        if (-not $Sync.LogFileErr) {
            $Sync.LogFileErr = $true
            $Sync.Queue.Enqueue(('{0} [WARN ] Écriture du journal de la tâche impossible ({1}) : {2}' -f (Get-Date -Format 'HH:mm:ss'), $Sync.LogFile, $_.Exception.Message))
        }
    }
}
function V($x) { if ($null -eq $x -or "$x" -eq '') { 'n/d' } else { $x } }
# espace libre en octets (pas d'arrondi en Go : un gain de quelques Mo doit rester visible)
function Get-FreeSpace { try { [double]([IO.DriveInfo]::new($SysLetter).AvailableFreeSpace) } catch { [double]0 } }
# jamais « 0 Ko » : $Zero pour une taille nulle, octets sous 1 Ko
function Format-Size {
    param([double]$Bytes, [string]$Zero = 'néant')
    if ($Bytes -le 0) { return $Zero }
    if ($Bytes -lt 1KB) { return '{0:N0} o' -f $Bytes }
    if ($Bytes -ge 1GB) { '{0:N2} Go' -f ($Bytes / 1GB) } elseif ($Bytes -ge 1MB) { '{0:N1} Mo' -f ($Bytes / 1MB) } else { '{0:N0} Ko' -f ($Bytes / 1KB) }
}
function Get-DirSize { param([string]$Path) Get-FastSize $Path }
# suppression récursive qui ne traverse jamais un point de jonction ou un lien (le lien seul est supprimé, jamais sa cible)
function Remove-TreeSafe([string]$Dir) {
    foreach ($e in [IO.DirectoryInfo]::new($Dir).EnumerateFileSystemInfos()) {
        try {
            if ($e.Attributes -band [IO.FileAttributes]::ReparsePoint) { if ($e -is [IO.DirectoryInfo]) { [IO.Directory]::Delete($e.FullName, $false) } else { [IO.File]::Delete($e.FullName) }; continue }
            if ($e -is [IO.DirectoryInfo]) { Remove-TreeSafe $e.FullName } else { if ($e.Attributes -band [IO.FileAttributes]::ReadOnly) { $e.Attributes = 'Normal' }; $e.Delete() }
        } catch { $null = $_ }
    }
    try { [IO.Directory]::Delete($Dir, $false) } catch { $null = $_ }
}
function Clear-Folder {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return [double]0 }
    $before = Get-DirSize $Path
    foreach ($item in Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue) {
        try {
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                if ($item.PSIsContainer) { [IO.Directory]::Delete($item.FullName, $false) } else { [IO.File]::Delete($item.FullName) }
            } else {
                if ($item.PSIsContainer) { Remove-TreeSafe $item.FullName } else { if ($item.Attributes -band [IO.FileAttributes]::ReadOnly) { $item.Attributes = 'Normal' }; $item.Delete() }
            }
        } catch {}
    }
    # éléments restants (fichiers ouverts par une application, droits) : comptés pour le journal de la tâche
    $script:ClearLeft += @(Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue).Count
    $after = Get-DirSize $Path
    # fichiers écrits pendant le nettoyage par d'autres processus (Temp) : pas de « Libéré » négatif
    [double][math]::Max([double]0, $before - $after)
}
function Invoke-Native {
    param([string]$FilePath, [string[]]$ArgumentList, [switch]$Utf16, [switch]$Console)
    if ($Sync.Aborted) { return -1 }
    Write-TaskLog ('> {0} {1}' -f $FilePath, ($ArgumentList -join ' ')) 'CMD'
    $Sync.TaskPct = -1
    $hCon = [IntPtr]::Zero
    if ($Console) {
        try {
            $hCon = Open-ConOut
            if ($hCon -eq [IntPtr]::Zero -or $hCon -eq [IntPtr]::new(-1)) { throw 'console inaccessible' }
            if (-not (Get-ConInfo $hCon)) { [void][_OlivM.Con2]::CloseHandle($hCon); throw 'informations de console illisibles' }
        } catch {
            Write-TaskLog "Lecture de la console impossible ($($_.Exception.Message)) : sortie texte sans pourcentage." 'WARN'
            $hCon = [IntPtr]::Zero
        }
    }
    $useCon = $hCon -ne [IntPtr]::Zero
    $psi = [Diagnostics.ProcessStartInfo]::new($FilePath, ($ArgumentList -join ' '))
    $psi.UseShellExecute = $false
    if ($useCon) {
        try { [Console]::Clear() } catch {}
        [void][_OlivM.Con2]::CloseHandle($hCon)
        $psi.CreateNoWindow = $false
    } else {
        $psi.RedirectStandardOutput = $true; $psi.CreateNoWindow = $true
        if ($Utf16) { $psi.StandardOutputEncoding = [Text.Encoding]::Unicode }
    }
    $p = [Diagnostics.Process]::Start($psi)
    $Sync.ChildPid = $p.Id
    $Sync.ChildName = [IO.Path]::GetFileNameWithoutExtension($FilePath).ToUpper()
    try {
        if ($useCon) {
            # lecture de l'écran de la console : lignes nouvelles vers le journal, pourcentage dans les 12 dernières lignes
            $logged = 0; $done = $false
            while (-not $done) {
                $done = $p.HasExited
                $h = Open-ConOut
                try {
                    $ci = Get-ConInfo $h
                    if ($ci) {
                        $top = [int]$ci.Y; $width = [int]$ci.Width
                        if ($top -lt $logged) { $logged = 0 }
                        $end = if ($done) { $top + 1 } else { $top }
                        while ($logged -lt $end) { Write-ConLine (Read-ConRow $h $logged $width); $logged++ }
                        for ($r = $top; $r -ge [math]::Max([double]0, $top - 12); $r--) {
                            if (Update-PctFromText (Read-ConRow $h $r $width)) { break }
                        }
                    }
                } finally { [void][_OlivM.Con2]::CloseHandle($h) }
                if (-not $done) { Start-Sleep -Milliseconds 250 }
            }
        } else {
            if ($Utf16) { while ($null -ne ($line = $p.StandardOutput.ReadLine())) { Write-ConLine ($line -replace "`0", '') } }
            else { Read-NativeLine $p.StandardOutput.BaseStream { param($l) Write-ConLine $l } }
        }
        $p.WaitForExit()
        $code = $p.ExitCode
    } finally { $Sync.ChildPid = $null; $Sync.ChildName = $null }
    if ($Sync.Aborted) { Write-TaskLog 'Interrompu par l''utilisateur.' 'WARN' }
    else {
        if ($code -eq 0 -and $Sync.TaskPct -ge 0) { $Sync.TaskPct = 100 }
        Write-TaskLog "Code retour : $code" $(if ($code -eq 0) { 'OK' } else { 'WARN' })
    }
    return $code
}
function Open-ConOut { [_OlivM.Con2]::CreateFileW('CONOUT$', [uint32]3221225472, [uint32]3, [IntPtr]::Zero, [uint32]3, [uint32]0, [IntPtr]::Zero) }
function Get-ConInfo([IntPtr]$Handle) {
    $b = [byte[]]::new(22)
    if (-not [_OlivM.Con2]::GetConsoleScreenBufferInfo($Handle, $b)) { return $null }
    @{ Width = [BitConverter]::ToInt16($b, 0); Height = [BitConverter]::ToInt16($b, 2); X = [BitConverter]::ToInt16($b, 4); Y = [BitConverter]::ToInt16($b, 6) }
}
function Read-ConRow([IntPtr]$Handle, [int]$Row, [int]$Width) {
    $buf = [char[]]::new($Width); $n = [uint32]0
    if ([_OlivM.Con2]::ReadConsoleOutputCharacterW($Handle, $buf, [uint32]$Width, [uint32]($Row -shl 16), [ref]$n)) { return ([string]::new($buf, 0, [int]$n)).TrimEnd() }
    $null
}
function Update-PctFromText([string]$Text) {
    $m = [regex]::Match("$Text", '(\d{1,3}(?:[.,]\d+)?)\s?%')
    if (-not $m.Success) { return $false }
    $v = [double]::Parse(($m.Groups[1].Value -replace ',', '.'), [Globalization.CultureInfo]::InvariantCulture)
    if ($v -ge 0 -and $v -le 100) { $Sync.TaskPct = $v }
    $true
}
# Sorties de commandes : chaque ligne décodée en UTF-8 si valide, sinon dans la page OEM de la console (850 en français),
# pour que les accents soient corrects dans le journal quel que soit l'outil (UTF-8 ou OEM)
$Utf8Strict = [Text.UTF8Encoding]::new($false, $true)
$OemEnc = [Text.Encoding]::GetEncoding([Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage)
$AnsiEnc = [Text.Encoding]::GetEncoding([Globalization.CultureInfo]::CurrentCulture.TextInfo.ANSICodePage)
function ConvertFrom-NativeOutput([byte[]]$B) {
    # UTF-8 valide d'abord ; sinon ANSI (1252) si les octets accentués sont dans 0xC0-0xFF sans aucun dans 0x80-0x9F, sinon OEM (850)
    $t = try { $Utf8Strict.GetString($B) } catch {
        $hi = 0; $lo = 0; foreach ($x in $B) { if ($x -ge 0xC0) { $hi++ } elseif ($x -ge 0x80 -and $x -le 0x9F) { $lo++ } }
        $(if ($hi -and -not $lo) { $AnsiEnc.GetString($B) } else { $OemEnc.GetString($B) })
    }
    $t.TrimEnd("`r").Replace("`0", '')
}
function Read-NativeLine($Stream, [scriptblock]$OnLine) {
    $buf = New-Object byte[] 8192; $pend = [Collections.Generic.List[byte]]::new()
    while (($n = $Stream.Read($buf, 0, $buf.Length)) -gt 0) {
        $start = 0
        while ($start -lt $n) {
            $i = [Array]::IndexOf($buf, [byte]10, $start, $n - $start)
            if ($i -lt 0) { $pend.AddRange([ArraySegment[byte]]::new($buf, $start, $n - $start)); break }
            $pend.AddRange([ArraySegment[byte]]::new($buf, $start, $i - $start)); & $OnLine (ConvertFrom-NativeOutput $pend.ToArray()); $pend.Clear()
            $start = $i + 1
        }
    }
    if ($pend.Count) { & $OnLine (ConvertFrom-NativeOutput $pend.ToArray()) }
}
function Invoke-Capture([string]$FilePath, [string]$Arguments) {
    $psi = [Diagnostics.ProcessStartInfo]::new($FilePath, $Arguments); $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.RedirectStandardOutput = $true
    $p = [Diagnostics.Process]::Start($psi); $out = [Collections.Generic.List[string]]::new()
    Read-NativeLine $p.StandardOutput.BaseStream { param($l) $out.Add($l) }
    $p.WaitForExit(); , $out.ToArray()
}
function Write-ConLine([string]$Line) {
    $t = "$Line".Trim()
    if (-not $t) { return }
    if ($t -match '^\[[=\s\d.,%]*\]$') { [void](Update-PctFromText $t); return }
    if ((Update-PctFromText $t) -and $t.Length -lt 70) { return }
    Write-TaskLog $t 'OUT'
}
function Start-CleanMgr {
    param([int]$Id, [string[]]$Include, [string[]]$Exclude)
    $root  = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches'
    $value = 'StateFlags{0:D4}' -f $Id
    $base  = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($root)
    foreach ($n in $base.GetSubKeyNames()) {
        $on = if ($Include) { $Include -contains $n } else { -not ($Exclude -contains $n) }
        try {
            [Microsoft.Win32.Registry]::SetValue("HKEY_LOCAL_MACHINE\$root\$n", $value, [int]$(if ($on) { 2 } else { 0 }), [Microsoft.Win32.RegistryValueKind]::DWord)
            if ($on) { Write-TaskLog "  + $n" }
        } catch { Write-TaskLog "  ! $n : $($_.Exception.Message)" 'WARN' }
    }
    $base.Close()
    Write-TaskLog "> cleanmgr.exe /sagerun:$Id" 'CMD'
    $p = Start-Process -FilePath "$env:windir\System32\cleanmgr.exe" -ArgumentList "/sagerun:$Id" -PassThru
    $Sync.ChildPid = $p.Id; $Sync.ChildName = 'CLEANMGR'; $Sync.TaskPct = -1
    $p.WaitForExit()
    $Sync.ChildPid = $null; $Sync.ChildName = $null
    # cleanmgr relance un processus enfant : attente des seuls processus apparus après le lancement (avant : tout cleanmgr,
    # y compris un Nettoyage de disque ouvert par l'utilisateur, bloquait la tâche sans fin), 2 h au plus, interruption possible
    $t0 = $p.StartTime; $lim = [DateTime]::Now.AddHours(2)
    while (-not $Sync.Aborted -and [DateTime]::Now -lt $lim -and @(Get-Process -Name cleanmgr -ErrorAction SilentlyContinue | Where-Object { try { $_.StartTime -ge $t0 } catch { $false } }).Count) { Start-Sleep -Seconds 2 }
    Write-TaskLog "cleanmgr terminé (code $($p.ExitCode))."
}
function Invoke-SfcRun {
    param([string]$Switch)
    [void](Invoke-Native "$env:windir\System32\sfc.exe" @($Switch) -Utf16 -Console)
    try {
        $out = Join-Path (Split-Path $Sync.LogFile) ('{0}_{1:yyyyMMdd-HHmmss}_sfc-detail.txt' -f $env:COMPUTERNAME, (Get-Date))
        Select-String -Path "$env:windir\Logs\CBS\CBS.log" -Pattern '\[SR\]' -ErrorAction Stop | ForEach-Object { $_.Line } | Set-Content -Path $out -Encoding UTF8
        Write-TaskLog "Détail SFC ([SR] de CBS.log) : $out"
    } catch { Write-TaskLog "Extraction CBS.log impossible : $($_.Exception.Message)" 'WARN' }
}

function Invoke-Task_RestorePoint {
    $key = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
    $old = (Get-ItemProperty -Path $key -Name SystemRestorePointCreationFrequency -ErrorAction SilentlyContinue).SystemRestorePointCreationFrequency
    try {
        Set-ItemProperty -Path $key -Name SystemRestorePointCreationFrequency -Value 0 -Type DWord -ErrorAction Stop
        Checkpoint-Computer -Description ('Oliv_Maintenance {0:yyyy-MM-dd HH:mm}' -f (Get-Date)) -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        Write-TaskLog 'Point de restauration créé.' 'OK'
        try {
            $rp = @(Get-ComputerRestorePoint -ErrorAction Stop | Sort-Object SequenceNumber)
            if ($rp.Count) { $Sync.RestoreLast = @{ Time = [Management.ManagementDateTimeConverter]::ToDateTime($rp[-1].CreationTime); Desc = "$($rp[-1].Description)" } }
        } catch { Write-Ignored 'Lecture des points de restauration' $_ }
    } catch {
        Write-TaskLog "Point de restauration impossible : $($_.Exception.Message) - protection système active sur $SysDrive ?" 'WARN'
    } finally {
        if ($null -eq $old) { Remove-ItemProperty -Path $key -Name SystemRestorePointCreationFrequency -ErrorAction SilentlyContinue }
        else { Set-ItemProperty -Path $key -Name SystemRestorePointCreationFrequency -Value $old -Type DWord -ErrorAction SilentlyContinue }
    }
}
function Get-AtaAttribute([byte[]]$V) {
    $h = @{}
    for ($i = 2; $i + 12 -le 362 -and $i + 12 -le $V.Length; $i += 12) {
        $id = [int]$V[$i]; if ($id -eq 0) { continue }
        $raw = [uint64]0; for ($k = 5; $k -ge 0; $k--) { $raw = $raw * 256 + $V[$i + 5 + $k] }
        $h[$id] = @{ Value = [int]$V[$i + 3]; Worst = [int]$V[$i + 4]; Raw = $raw }
    }
    $h
}
function Invoke-Task_Smart {
    $dir = $Sync.DisksDir
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $file = Join-Path $dir ('{0}_SMART_{1:yyyyMMdd-HHmmss}.txt' -f $env:COMPUTERNAME, (Get-Date))
    $sb = [System.Text.StringBuilder]::new()
    $l = { param($k, $v) if ($null -ne $v -and "$v" -ne '') { [void]$sb.AppendLine(('  {0,-44}: {1}' -f $k, $v)) } }
    [void]$sb.AppendLine('RAPPORT D''ÉTAT DE SANTÉ DES DISQUES (SMART) - Oliv_Maintenance ' + $Sync.Version)
    [void]$sb.AppendLine(('Poste : {0}    Date : {1:dd/MM/yyyy HH:mm:ss}' -f $env:COMPUTERNAME, (Get-Date)))
    [void]$sb.AppendLine(('Système : {0}' -f (Get-CimInstance Win32_OperatingSystem).Caption))
    [void]$sb.AppendLine('')
    $ata = @{}; $predict = @{}
    $dd = @(Get-CimInstance Win32_DiskDrive -ErrorAction SilentlyContinue)
    $diskOf = { param($inst) foreach ($x in $dd) { if ($x.PNPDeviceID -and $inst -like ($x.PNPDeviceID + '*')) { return "$($x.Index)" } } }
    try {
        foreach ($x in @(Get-CimInstance -Namespace 'root\wmi' -ClassName MSStorageDriver_FailurePredictData -ErrorAction Stop)) {
            $n = & $diskOf $x.InstanceName
            if ($n) { $ata[$n] = Get-AtaAttribute ([byte[]]$x.VendorSpecific) }
        }
    } catch {}
    try {
        foreach ($x in @(Get-CimInstance -Namespace 'root\wmi' -ClassName MSStorageDriver_FailurePredictStatus -ErrorAction Stop)) {
            $n = & $diskOf $x.InstanceName
            if ($n) { $predict[$n] = $x }
        }
    } catch {}

    $disks = @(Get-PhysicalDisk | Sort-Object { [int]$_.DeviceId })
    foreach ($d in $disks) {
        $num = "$($d.DeviceId)"
        $r = $null
        try { $r = $d | Get-StorageReliabilityCounter -ErrorAction Stop } catch {}
        $nv = $null
        if ("$($d.BusType)" -eq 'NVMe') { try { $nv = [_OlivM.Nvme]::HealthLog([int]$num) } catch {} }
        $at = $ata[$num]
        $alerts = @()
        if ("$($d.HealthStatus)" -ne 'Healthy') { $alerts += "état de santé signalé par Windows : $($d.HealthStatus)" }
        if ("$($d.OperationalStatus)" -notmatch 'OK') { $alerts += "état opérationnel : $($d.OperationalStatus -join ', ')" }
        if ($predict[$num] -and $predict[$num].PredictFailure) { $alerts += "panne prévue par le firmware (SMART, code $($predict[$num].Reason))" }

        [void]$sb.AppendLine(('===== Disque {0} : {1} =====' -f $num, $d.FriendlyName))
        $body = $sb.Length
        & $l 'Numéro de série' "$($d.SerialNumber)".Trim().TrimEnd('.')
        & $l 'Micrologiciel (firmware)' $d.FirmwareVersion
        & $l 'Type / bus' ('{0} / {1}' -f $d.MediaType, $d.BusType)
        & $l 'Capacité' ('{0:N1} Go' -f ($d.Size / 1GB))
        & $l 'Santé (Windows)' $(switch ("$($d.HealthStatus)") { 'Healthy' { 'Sain' } 'Warning' { 'Avertissement' } 'Unhealthy' { 'Défaillant' } default { "$($d.HealthStatus)" } })
        & $l 'État opérationnel' ($d.OperationalStatus -join ', ')
        $src = @()
        if ($nv) {
            $src += 'journal SMART/Health NVMe'
            $u = { param($o) [BitConverter]::ToUInt64($nv, $o) }
            $cw = [int]$nv[0]
            $cwTxt = @(); $bits = @{ 0 = 'réserve sous le seuil'; 1 = 'température hors limites'; 2 = 'fiabilité dégradée'; 3 = 'support en lecture seule'; 4 = 'sauvegarde mémoire volatile en échec' }
            foreach ($b in 0..4) { if ($cw -band (1 -shl $b)) { $cwTxt += $bits[$b] } }
            $temp = [int]([BitConverter]::ToUInt16($nv, 1)) - 273
            $spare = [int]$nv[3]; $spareThr = [int]$nv[4]; $used = [int]$nv[5]
            $media = & $u 160
            & $l 'Avertissement critique (NVMe)' $(if ($cw) { $cwTxt -join ', ' } else { 'aucun' })
            if ($temp -gt -273) { & $l 'Température actuelle (°C)' $temp }
            if ($r -and $r.TemperatureMax) { & $l 'Température maximale (°C)' $r.TemperatureMax }
            & $l 'Usure (% de l''endurance prévue)' $used
            & $l 'Réserve disponible (%)' ('{0} (seuil d''alerte : {1})' -f $spare, $spareThr)
            & $l 'Heures de fonctionnement' ('{0:N0} h' -f (& $u 128))
            & $l 'Cycles d''alimentation' ('{0:N0}' -f (& $u 112))
            & $l 'Arrêts non sécurisés (coupures)' ('{0:N0}' -f (& $u 144))
            & $l 'Données lues' (Format-Size ((& $u 32) * 512000))
            & $l 'Données écrites' (Format-Size ((& $u 48) * 512000))
            & $l 'Erreurs média / intégrité des données' ('{0:N0}' -f $media)
            & $l 'Entrées du journal d''erreurs' ('{0:N0}' -f (& $u 176))
            & $l 'Temps au-dessus du seuil d''avertissement' ('{0:N0} min' -f [BitConverter]::ToUInt32($nv, 192))
            & $l 'Temps au-dessus du seuil critique' ('{0:N0} min' -f [BitConverter]::ToUInt32($nv, 196))
            if ($cw) { $alerts += "avertissement critique NVMe : $($cwTxt -join ', ')" }
            if ($media -gt 0) { $alerts += "erreurs média / intégrité : $media" }
            if ($spare -lt $spareThr) { $alerts += "réserve disponible sous le seuil : $spare %" }
            if ($used -ge 80) { $alerts += "usure élevée : $used %" }
            if ($temp -ge 70) { $alerts += "température élevée : $temp °C" }
        }
        elseif ($at -and $at.Count) {
            $src += 'attributs SMART ATA'
            $a = { param($id) if ($at.ContainsKey($id)) { $at[$id].Raw } }
            $t194 = & $a 194; if ($null -ne $t194) { & $l 'Température actuelle (°C)' ([int]($t194 -band 0xFF)) }
            if ($r -and $r.TemperatureMax) { & $l 'Température maximale (°C)' $r.TemperatureMax }
            if ($r -and $null -ne $r.Wear) { & $l 'Usure (%)' $r.Wear }
            $h9 = & $a 9; if ($null -ne $h9) { & $l 'Heures de fonctionnement' ('{0:N0} h' -f ($h9 -band 0xFFFFFFFF)) }
            foreach ($p in @(@(12, 'Cycles d''alimentation'), @(5, 'Secteurs réalloués (05)'), @(197, 'Secteurs en attente de réallocation (C5)'),
                             @(198, 'Secteurs non corrigeables (C6)'), @(187, 'Erreurs non corrigées signalées (BB)'), @(199, 'Erreurs CRC interface (C7)'),
                             @(192, 'Arrêts non sécurisés (C0)'))) {
                $v = & $a $p[0]; if ($null -ne $v) { & $l $p[1] ('{0:N0}' -f ($v -band 0xFFFFFFFF)) }
            }
            foreach ($id in 5, 197, 198, 187) {
                $v = & $a $id
                if ($v -gt 0) { $alerts += ('attribut SMART {0:X2} = {1}' -f $id, ($v -band 0xFFFFFFFF)) }
            }
            $t = & $a 194; if ($null -ne $t -and ($t -band 0xFF) -ge 60) { $alerts += "température élevée : $($t -band 0xFF) °C" }
        }
        if ($r) {
            $src += 'compteurs de fiabilité Windows'
            if (-not $nv -and -not ($at -and $at.Count)) {
                & $l 'Température actuelle (°C)' $r.Temperature
                & $l 'Température maximale (°C)' $r.TemperatureMax
                & $l 'Usure (%)' $r.Wear
                if ($r.PowerOnHours) { & $l 'Heures de fonctionnement' ('{0:N0} h' -f $r.PowerOnHours) }
                & $l 'Cycles démarrage / arrêt' $r.StartStopCycleCount
                if ($r.Temperature -ge 70) { $alerts += "température élevée : $($r.Temperature) °C" }
                if ($r.Wear -ge 80) { $alerts += "usure élevée : $($r.Wear) %" }
            }
            & $l 'Erreurs de lecture non corrigées' $r.ReadErrorsUncorrected
            & $l 'Erreurs d''écriture non corrigées' $r.WriteErrorsUncorrected
            & $l 'Latence de lecture max (ms)' $r.ReadLatencyMax
            & $l 'Latence d''écriture max (ms)' $r.WriteLatencyMax
            & $l 'Latence de vidage max (ms)' $r.FlushLatencyMax
            if ($r.ReadErrorsUncorrected -gt 0) { $alerts += "erreurs de lecture non corrigées : $($r.ReadErrorsUncorrected)" }
            if ($r.WriteErrorsUncorrected -gt 0) { $alerts += "erreurs d'écriture non corrigées : $($r.WriteErrorsUncorrected)" }
        }
        if ($predict.ContainsKey($num)) { & $l 'Prédiction de panne (firmware)' $(if ($predict[$num].PredictFailure) { 'PANNE PRÉVUE' } else { 'aucune' }) }
        if (-not $src) { [void]$sb.AppendLine('  Aucune donnée SMART exposée par le contrôleur (RAID, USB, disque virtuel...).') }
        $verdict = if ($alerts) { 'ATTENTION' } else { 'OK' }
        [void]$sb.Insert($body, ('  VERDICT : {0}{1}' -f $verdict, [Environment]::NewLine))
        & $l 'Sources' ($src -join ', ')
        [void]$sb.AppendLine(('  Alertes : {0}' -f $(if ($alerts) { $alerts -join ' ; ' } else { 'aucune' })))
        [void]$sb.AppendLine('')
        Write-TaskLog ('{0} : {1}{2}' -f $d.FriendlyName, $verdict, $(if ($alerts) { ' - ' + ($alerts -join ' ; ') } else { '' })) $(if ($alerts) { 'WARN' } else { 'OK' })
    }
    Set-Content -LiteralPath $file -Value $sb.ToString() -Encoding UTF8
    $Sync.SmartReport = $file
    Write-TaskLog "Rapport SMART : $file" 'OK'
}
function Invoke-Task_Battery {
    $bat = @(Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue)
    if ($bat.Count -eq 0) {
        Write-TaskLog 'Aucune batterie détectée sur ce poste : rapport non généré.' 'WARN'
        return
    }
    $dir = $Sync.DisksDir
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $file = Join-Path $dir ('{0}_batterie_{1:yyyyMMdd-HHmmss}.html' -f $env:COMPUTERNAME, (Get-Date))
    [void](Invoke-Native "$env:windir\System32\powercfg.exe" @('/batteryreport', '/output', "`"$file`""))
    try {
        $des  = [double](@(Get-CimInstance -Namespace 'root\wmi' -ClassName BatteryStaticData -ErrorAction Stop)[0].DesignedCapacity)
        $full = [double](@(Get-CimInstance -Namespace 'root\wmi' -ClassName BatteryFullChargedCapacity -ErrorAction Stop)[0].FullChargedCapacity)
        if ($des -gt 0) {
            $pct = 100 * $full / $des
            Write-TaskLog ('Capacité de pleine charge : {0:N0} mWh sur {1:N0} mWh d''origine ({2:N1} %)' -f $full, $des, $pct) $(if ($pct -lt 60) { 'WARN' } else { 'OK' })
        }
    } catch { Write-Ignored 'Capacité de la batterie' $_ }
    if (Test-Path -LiteralPath $file) {
        $Sync.BatteryReport = $file
        Write-TaskLog "Rapport de batterie : $file" 'OK'
    } else { Write-TaskLog 'Le rapport de batterie n''a pas été créé.' 'WARN' }
}
function Invoke-Task_DismScan    { [void](Invoke-Native "$env:windir\System32\dism.exe" @('/Online', '/Cleanup-Image', '/ScanHealth') -Console) }
function Invoke-Task_DismRestore { [void](Invoke-Native "$env:windir\System32\dism.exe" @('/Online', '/Cleanup-Image', '/RestoreHealth') -Console) }
'@
