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
function Clear-Folder {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return [double]0 }
    $before = Get-DirSize $Path
    foreach ($item in Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue) {
        try {
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                if ($item.PSIsContainer) { [IO.Directory]::Delete($item.FullName, $false) } else { [IO.File]::Delete($item.FullName) }
            } else {
                Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction SilentlyContinue
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
    while (Get-Process -Name cleanmgr -ErrorAction SilentlyContinue) { Start-Sleep -Seconds 2 }
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
# winget : alias de l'utilisateur, sinon exécutable du paquet App Installer (contexte administrateur où l'alias manque)
function Find-Winget {
    $c = (Get-Command winget.exe -ErrorAction SilentlyContinue).Source; if ($c -and (Test-Path -LiteralPath $c)) { return $c }
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
function Invoke-SoftTool([string]$Exe, [string[]]$A, [string]$Name, [scriptblock]$OnLine) {
    Write-TaskLog ('> {0} {1}' -f $Name, ($A -join ' ')) 'CMD'
    $psi = [Diagnostics.ProcessStartInfo]::new($Exe, ($A -join ' ')); $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
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
        [IO.File]::WriteAllText((Join-Path $dir 'run.cmd'), $cmd, [Text.Encoding]::ASCII)
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
    if ($rc -ne 0 -and $re -and "$($X.Src)" -eq 'winget' -and -not $Sync.Cancel) {
        Write-TaskLog 'Désinstallation en échec : dernière version installée par-dessus l''existante (winget install --force).' 'WARN'
        $rc = & $run @('install', '-e', '--id', $id, '--force', '--silent', '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity') 'installation par-dessus'
        if ($rc -eq 0) { $note = 'réinstallé (par-dessus)'; $Sync.SoftRun.Ok++; Set-SoftItem $id @{ State = 'ok'; Note = $note; NoteBrush = 'OkFgBrush'; Phase = ''; Pct = 100; End = [DateTime]::Now }; Write-TaskLog 'Réinstallé par-dessus l''installation existante.' 'OK'; return }
    }
    $note = ''; $state = 'ok'
    if ($rc -ne 0) {
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
    $live = @(foreach ($c in $List) { if ($c) { Get-Process -Id $c.Pid -ErrorAction SilentlyContinue } })
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
        if ($x.Lock) { $cl = @(Find-SoftLocker $x.Lock); if ($cl.Count) { Close-SoftProc $cl } }
        if (-not $wg) { Write-TaskLog 'winget introuvable.' 'ERROR'; continue }
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

