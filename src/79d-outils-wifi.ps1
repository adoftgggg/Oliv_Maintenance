# ================= Réseaux Wi-Fi enregistrés (netsh wlan export profile key=clear : XML indépendant de la langue)
$WifiScript = @'
$r = @{ Items = @() }
$dir = Join-Path $env:TEMP ('olivm-wifi-' + [guid]::NewGuid().ToString('N'))
try {
    [void][IO.Directory]::CreateDirectory($dir)
    $out = & (Join-Path $env:windir 'System32\netsh.exe') wlan export profile key=clear folder="$dir" 2>&1
    $files = @(Get-ChildItem -LiteralPath $dir -Filter *.xml -File)
    if (-not $files.Count -and $LASTEXITCODE -ne 0) { $r.Error = ((@($out) | ForEach-Object { "$_".Trim() } | Where-Object { $_ }) -join ' ') }
    $seen = @{}
    foreach ($f in $files) {
        try {
            $x = [xml][IO.File]::ReadAllText($f.FullName)
            $n = "$($x.WLANProfile.name)"; if (-not $n -or $seen.ContainsKey($n)) { continue }; $seen[$n] = 1
            $sec = $x.WLANProfile.MSM.security
            $r.Items += [pscustomobject]@{ Name = $n; Auth = "$($sec.authEncryption.authentication)"; Key = "$($sec.sharedKey.keyMaterial)"; Auto = "$($x.WLANProfile.connectionMode)" -eq 'auto' }
        } catch { $null = $_ }
    }
} catch { $r.Error = $_.Exception.Message }
finally { try { [IO.Directory]::Delete($dir, $true) } catch { $null = $_ } }
$Sync.Wifi = $r
'@
function Start-WifiRead {
    if ($BgJobs.ContainsKey('Wifi')) { return }
    $ToolsUI.WifiBody.Children.Clear(); $t = New-Text 'Lecture des réseaux enregistrés...' 'Muted'; $t.Margin = New-Thickness 38 0 10 12; [void]$ToolsUI.WifiBody.Children.Add($t)
    $Sync.Wifi = $null; Start-BgJob 'Wifi' $WifiScript
}
$BgJobDone['Wifi'] = { Update-WifiCard $Sync.Wifi }
function Get-WifiAuthText([string]$A) { $(switch -Regex ($A) { '^open$' { 'ouvert, sans mot de passe' } 'WPA3' { 'WPA3' } 'WPA2PSK' { 'WPA2' } 'WPAPSK' { 'WPA' } 'WPA2$|WPA$' { 'WPA entreprise (identifiants)' } default { $A } }) }
function Update-WifiCard($R) {
    $b = $ToolsUI.WifiBody; $b.Children.Clear()
    $items = @($(if ($R) { $R.Items }) | Sort-Object Name)
    if (-not $items.Count) {
        $t = New-Text $(if ($R -and $R.Error) { "Aucun réseau lisible : $($R.Error)" } else { 'Aucun réseau Wi-Fi enregistré sur ce PC.' }) 'Muted'; $t.TextWrapping = 'Wrap'; $t.Margin = New-Thickness 38 0 10 12
        [void]$b.Children.Add($t); return
    }
    foreach ($w in $items) {
        $hasKey = [bool]$w.Key
        $sec = @{ Shown = $false; Clear = $w.Key + '   ·   ' + (Get-WifiAuthText $w.Auth); Masked = (Get-MaskedText 'xxxxxxxxxx') + '   ·   ' + (Get-WifiAuthText $w.Auth) }
        $eye = $(if ($hasKey) { New-ToolIconButton 0xE7B3 'Afficher / masquer le mot de passe' $sec { param($s, $e) Switch-ToolSecret $s.Tag 'Wifi' 'Afficher les mots de passe Wi-Fi enregistrés' } })
        $cp = $(if ($hasKey) { New-ToolIconButton 0xE8C8 'Copier le mot de passe' $w { param($s, $e) if (Request-ToolAuth 'Wifi' 'Copier un mot de passe Wi-Fi') { Set-ClipText $s.Tag.Key; Write-UiLog ('Mot de passe du réseau Wi-Fi « {0} » copié.' -f $s.Tag.Name) 'APP' } } })
        $del = New-ToolIconButton 0xE74D 'Oublier ce réseau' $w { param($s, $e) Remove-WifiProfile $s.Tag.Name }
        $sub = $(if ($hasKey) { (Get-MaskedText 'xxxxxxxxxx') + '   ·   ' + (Get-WifiAuthText $w.Auth) } else { Get-WifiAuthText $w.Auth })
        $row = New-ToolRow $w.Name $sub @($eye, $cp, $del) $(if ($w.Auto) { 'Connexion automatique' } else { 'Connexion manuelle' })
        $sec.Box = $row.Sub
        [void]$b.Children.Add($row.Row)
    }
    $n = New-Text ('{0} réseau(x) enregistré(s). Mot de passe en clair visible uniquement ici (droits administrateur).' -f $items.Count) 'Muted'; $n.FontSize = 12; $n.TextWrapping = 'Wrap'; $n.Margin = New-Thickness 40 6 10 12
    [void]$b.Children.Add($n)
}
function Remove-WifiProfile([string]$Name) {
    if (-not (Confirm-Action "Oublier le réseau Wi-Fi « $Name » ?`n`nLe PC ne s'y connecte plus automatiquement ; il faudra ressaisir le mot de passe.")) { return }
    $out = & (Join-Path $env:windir 'System32\netsh.exe') wlan delete profile name="$Name" 2>&1
    if ($LASTEXITCODE -eq 0) { Write-UiLog "Réseau Wi-Fi « $Name » oublié." 'OK'; Add-SessionEvent 'Réglages' 'Réseau Wi-Fi oublié' $Name 'ok' }
    else { $m = (@($out) -join ' ').Trim(); Write-UiLog "Réseau Wi-Fi « $Name » : $m" 'ERROR'; Show-Info "Suppression impossible.`n`n$m" 'Error' }
    Start-WifiRead
}

