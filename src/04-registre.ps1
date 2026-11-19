function Open-RegKey([string]$Path, [bool]$Write = $false, [bool]$Create = $false) {
    if ($Path -like 'HKCU\*') {
        if ($HkuSidOk) { $root = [Microsoft.Win32.Registry]::Users; $sub = "$UserSid\" + $Path.Substring(5) }
        else { $root = [Microsoft.Win32.Registry]::CurrentUser; $sub = $Path.Substring(5) }
    }
    elseif ($Path -like 'HKLM\*') { $root = [Microsoft.Win32.Registry]::LocalMachine; $sub = $Path.Substring(5) }
    elseif ($Path -like 'HKU\*')  { $root = [Microsoft.Win32.Registry]::Users; $sub = $Path.Substring(4) }
    else { return $null }
    if ($Create) { return $root.CreateSubKey($sub) }
    try { $root.OpenSubKey($sub, $Write) } catch { $null }
}
function Get-RegValue([string]$Path, [string]$Name) {
    $k = Open-RegKey $Path
    if (-not $k) { return $null }
    try { $v = $k.GetValue($Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames) } finally { $k.Close() }
    if ($v -is [array]) { return ,$v }
    $v
}
function Set-RegValueDirect([string]$Path, [string]$Name, $Value, [string]$Type = 'DWord') {
    if ($null -eq $Value) {
        $k = Open-RegKey $Path $true
        if ($k) { try { $k.DeleteValue($Name, $false) } finally { $k.Close() } }
        return
    }
    $k = Open-RegKey $Path $true $true
    try {
        switch ($Type) {
            'DWord'  { $k.SetValue($Name, [int]$Value, [Microsoft.Win32.RegistryValueKind]::DWord) }
            'QWord'  { $k.SetValue($Name, [long]$Value, [Microsoft.Win32.RegistryValueKind]::QWord) }
            'Binary' { $k.SetValue($Name, [byte[]]$Value, [Microsoft.Win32.RegistryValueKind]::Binary) }
            default  { $k.SetValue($Name, [string]$Value, [Microsoft.Win32.RegistryValueKind]::String) }
        }
    } finally { $k.Close() }
}
# Écriture refusée sous HKLM\SOFTWARE\Policies (pilote UCPD ou ACL) : la valeur passe par la stratégie de groupe locale
# (Registry.pol + gpupdate), appliquée par le service Stratégie de groupe et non par PowerShell.
function Set-RegValue([string]$Path, [string]$Name, $Value, [string]$Type = 'DWord') {
    try { Set-RegValueDirect $Path $Name $Value $Type }
    catch {
        $inner = $_.Exception; while ($inner.InnerException) { $inner = $inner.InnerException }
        if ($Path -like 'HKLM\SOFTWARE\Policies\*' -and $Type -eq 'DWord' -and ($inner -is [UnauthorizedAccessException] -or $inner -is [Security.SecurityException])) {
            Write-UiLog ("Écriture directe refusée ($Path\$Name) : application par stratégie de groupe locale.") 'WARN'
            Set-LocalPolicyValue $Path.Substring(5) $Name $Value
        } else { throw }
    }
}
# Registry.pol : en-tête « PReg » + version 1, puis entrées [clé;valeur;type;taille;données] en UTF-16LE
# Registry.pol (format PReg) : en-tête « PReg » + version 1, puis entrées [clé;valeur;type;taille;données] en UTF-16LE.
# Lecture stricte : tout écart de format arrête la lecture avec une erreur (jamais de réécriture d'un fichier lu partiellement).
function Read-PolFile([string]$File) {
    $list = [Collections.Generic.List[object]]::new()
    if (-not (Test-Path -LiteralPath $File)) { return ,$list }
    $b = [IO.File]::ReadAllBytes($File)
    if ($b.Length -eq 0) { return ,$list }
    if ($b.Length -lt 8 -or [BitConverter]::ToUInt32($b, 0) -ne 0x67655250 -or [BitConverter]::ToUInt32($b, 4) -ne 1) { throw "en-tête PReg invalide ($File)" }
    $u = [Text.Encoding]::Unicode; $i = 8
    $need = { param([int]$Pos, [int]$Len) if ($Pos + $Len -gt $b.Length) { throw "fin de fichier inattendue à l'octet $Pos ($File)" } }
    $sep = { param([int]$Pos, [int]$Code)
        & $need $Pos 2
        if ([BitConverter]::ToUInt16($b, $Pos) -ne $Code) { throw ("séparateur 0x{0:X2} attendu à l'octet {1} ($File)" -f $Code, $Pos) }
    }
    $str = { param([int]$Pos)
        $st = $Pos
        while ($true) { & $need $Pos 2; if ([BitConverter]::ToUInt16($b, $Pos) -eq 0) { break }; $Pos += 2 }
        ,@($u.GetString($b, $st, $Pos - $st), ($Pos + 2))
    }
    while ($i -lt $b.Length) {
        & $sep $i 0x5B; $i += 2
        $r = & $str $i; $k = $r[0]; $i = $r[1]; & $sep $i 0x3B; $i += 2
        $r = & $str $i; $n = $r[0]; $i = $r[1]; & $sep $i 0x3B; $i += 2
        & $need $i 4; $t = [BitConverter]::ToUInt32($b, $i); $i += 4; & $sep $i 0x3B; $i += 2
        & $need $i 4; $sz = [BitConverter]::ToUInt32($b, $i); $i += 4; & $sep $i 0x3B; $i += 2
        & $need $i $sz; $d = [byte[]]::new($sz); [Array]::Copy($b, $i, $d, 0, $sz); $i += $sz
        & $sep $i 0x5D; $i += 2
        $list.Add([pscustomobject]@{ Key = $k; Name = $n; Type = $t; Data = $d })
    }
    ,$list
}
function ConvertTo-PolData($List) {
    $ms = [IO.MemoryStream]::new(); $u = [Text.Encoding]::Unicode
    $w = { param([byte[]]$x) $ms.Write($x, 0, $x.Length) }
    & $w ([byte[]](0x50, 0x52, 0x65, 0x67, 1, 0, 0, 0))
    foreach ($e in $List) {
        & $w $u.GetBytes('['); & $w $u.GetBytes($e.Key + [char]0); & $w $u.GetBytes(';'); & $w $u.GetBytes($e.Name + [char]0); & $w $u.GetBytes(';')
        & $w ([BitConverter]::GetBytes([uint32]$e.Type)); & $w $u.GetBytes(';'); & $w ([BitConverter]::GetBytes([uint32]$e.Data.Length)); & $w $u.GetBytes(';')
        & $w $e.Data; & $w $u.GetBytes(']')
    }
    ,$ms.ToArray()
}
# Écriture sûre : fichier temporaire, relecture et comparaison entrée par entrée, puis remplacement de l'original
function Write-PolFile([string]$File, $List) {
    $ErrorActionPreference = 'Stop'
    $bytes = ConvertTo-PolData $List
    $tmp = "$File.olivm.tmp"
    [IO.File]::WriteAllBytes($tmp, $bytes)
    try {
        $chk = Read-PolFile $tmp
        if ($chk.Count -ne $List.Count) { throw "vérification : $($chk.Count) entrée(s) relue(s) sur $($List.Count)" }
        for ($x = 0; $x -lt $chk.Count; $x++) {
            $a = $chk[$x]; $e = $List[$x]
            if ($a.Key -ne $e.Key -or $a.Name -ne $e.Name -or $a.Type -ne $e.Type -or [Convert]::ToBase64String($a.Data) -ne [Convert]::ToBase64String([byte[]]$e.Data)) {
                throw "vérification : entrée $($x + 1) différente après écriture"
            }
        }
        [IO.File]::Copy($tmp, $File, $true)
    } finally { if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue } }
}
# Sauvegarde datée de Registry.pol et gpt.ini avant toute modification (20 dernières conservées)
function Backup-LocalPolicy([string]$Pol, [string]$Ini) {
    $ErrorActionPreference = 'Stop'
    $bk = Join-Path (Get-LogPath 'Etat') 'gpo-sauvegarde'
    [void][IO.Directory]::CreateDirectory($bk)
    $stamp = '{0:yyyyMMdd-HHmmss}' -f (Get-Date)
    $saved = @()
    if (Test-Path -LiteralPath $Pol) {
        $d = Join-Path $bk "Registry_$stamp.pol"
        Copy-Item -LiteralPath $Pol -Destination $d -Force -ErrorAction Stop
        $saved += $d
    }
    if (Test-Path -LiteralPath $Ini) {
        $d = Join-Path $bk "gpt_$stamp.ini"
        Copy-Item -LiteralPath $Ini -Destination $d -Force -ErrorAction Stop
        $saved += $d
    }
    foreach ($f in 'Registry_*.pol', 'gpt_*.ini') {
        Get-ChildItem -LiteralPath $bk -Filter $f -File -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -Skip 20 | Remove-Item -Force -ErrorAction SilentlyContinue
    }
    $saved
}
function Set-LocalPolicyValue([string]$Key, [string]$Name, $Value) {
    # toute erreur interrompt la procédure (pas de gpt.ini ni de gpupdate si Registry.pol n'a pas été écrit)
    $ErrorActionPreference = 'Stop'
    $root = Join-Path $env:windir 'System32\GroupPolicy'
    $dir = Join-Path $root 'Machine'; [void][IO.Directory]::CreateDirectory($dir)
    $pol = Join-Path $dir 'Registry.pol'
    $ini = Join-Path $root 'gpt.ini'
    # lecture stricte AVANT toute écriture : un fichier non conforme n'est jamais modifié
    try { $list = Read-PolFile $pol }
    catch { Write-UiLog ('Stratégie locale non modifiée : Registry.pol illisible ({0}).' -f $_.Exception.Message) 'ERROR'; throw }
    $saved = Backup-LocalPolicy $pol $ini
    if ($saved) { Write-UiLog ('Sauvegarde de la stratégie locale : ' + ($saved -join ', ')) }
    $keep = [Collections.Generic.List[object]]::new()
    foreach ($e in $list) { if (-not ($e.Key -eq $Key -and ($e.Name -eq $Name -or $e.Name -eq "**del.$Name"))) { $keep.Add($e) } }
    if ($null -eq $Value) { $keep.Add([pscustomobject]@{ Key = $Key; Name = "**del.$Name"; Type = 1; Data = [Text.Encoding]::Unicode.GetBytes(' ' + [char]0) }) }
    else { $keep.Add([pscustomobject]@{ Key = $Key; Name = $Name; Type = 4; Data = [BitConverter]::GetBytes([int]$Value) }) }
    Write-PolFile $pol $keep
    # gpt.ini : valeurs modifiées sur place dans la section [General] (les autres sections et lignes sont conservées)
    $lines = [Collections.Generic.List[string]]::new()
    if (Test-Path -LiteralPath $ini) { foreach ($l in @(Get-Content -LiteralPath $ini -Encoding Default)) { $lines.Add($l) } }
    $gen = -1; for ($x = 0; $x -lt $lines.Count; $x++) { if ($lines[$x] -match '^\s*\[General\]\s*$') { $gen = $x; break } }
    if ($gen -lt 0) { $lines.Insert(0, '[General]'); $gen = 0 }
    $end = $lines.Count; for ($x = $gen + 1; $x -lt $lines.Count; $x++) { if ($lines[$x] -match '^\s*\[') { $end = $x; break } }
    $cse = '[{35378EAC-683F-11D2-A89A-00C04FBBCFA2}{D02B1F72-3407-48AE-BA88-E8213C6761F1}]'
    $vi = -1; $ei = -1
    for ($x = $gen + 1; $x -lt $end; $x++) {
        if ($lines[$x] -match '^\s*Version\s*=') { $vi = $x } elseif ($lines[$x] -match '^\s*gPCMachineExtensionNames\s*=') { $ei = $x }
    }
    $ver = [uint32]0; if ($vi -ge 0 -and $lines[$vi] -match '=\s*(\d+)') { $ver = [uint32]$Matches[1] }
    $mach = ($ver -band 0xFFFF) + 1; $ver = ($ver -band 0xFFFF0000) -bor ($mach -band 0xFFFF)
    if ($ei -ge 0) {
        $ext = ($lines[$ei] -split '=', 2)[1].Trim()
        if ($ext -notmatch '35378EAC-683F-11D2-A89A-00C04FBBCFA2') { $lines[$ei] = "gPCMachineExtensionNames=$cse$ext" }
    }
    else { $lines.Insert($end, "gPCMachineExtensionNames=$cse"); $end++ }
    if ($vi -ge 0) { $lines[$vi] = "Version=$ver" } else { $lines.Insert($end, "Version=$ver") }
    Set-Content -LiteralPath $ini -Value $lines -Encoding Default
    Write-UiLog ("Stratégie locale écrite : HKLM\$Key\$Name = " + $(if ($null -eq $Value) { '(supprimée)' } else { $Value }) + ' (visible dans gpedit.msc), application par gpupdate en cours.') 'OK'
    Start-Process -FilePath "$env:windir\System32\gpupdate.exe" -ArgumentList '/target:computer', '/wait:0' -WindowStyle Hidden
    $GpState.Started = $true
}
function Test-RegKey([string]$Path) { $k = Open-RegKey $Path; if ($k) { $k.Close(); return $true }; $false }
function Remove-RegKey([string]$Path) {
    $i = $Path.LastIndexOf('\')
    $pk = Open-RegKey $Path.Substring(0, $i) $true
    if ($pk) { try { $pk.DeleteSubKeyTree($Path.Substring($i + 1), $false) } finally { $pk.Close() } }
}

