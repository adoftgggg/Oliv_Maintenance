# ================= Licence Windows
$LicScript = @'
# clé installée complète : décodage de DigitalProductId (HKLM\...\Windows NT\CurrentVersion, octets 52 à 66, base 24,
# format Windows 8 et plus avec la lettre N insérée) ; retenue seulement si ses 5 derniers caractères sont ceux de la
# clé partielle déclarée par le service de licences (sinon licence numérique / clé générique : rien d'inventé)
function Get-InstalledKey([string]$Partial) {
    try {
        $id = [byte[]](Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name DigitalProductId -ErrorAction Stop).DigitalProductId
        if ($id.Length -lt 67) { return $null }
        # bit 3 de l'octet 66 : format Windows 8 et plus (retiré avant le décodage)
        $k = [byte[]]$id[52..66]; $w8 = ($k[14] -shr 3) -band 1; $k[14] = [byte]($k[14] -band 0xF7)
        $ch = 'BCDFGHJKMPQRTVWXY2346789'; $out = ''; $last = 0
        for ($i = 24; $i -ge 0; $i--) {
            $cur = 0
            for ($x = 14; $x -ge 0; $x--) { $cur = $cur * 256 + $k[$x]; $k[$x] = [byte][math]::Floor($cur / 24); $cur = $cur % 24 }
            $out = $ch[$cur] + $out; $last = $cur
        }
        # 1er caractère = position de la lettre N dans la clé
        if ($w8) { $out = $out.Substring(1).Insert($last, 'N') }
        $key = ($out -replace '(.{5})(?!$)', '$1-')
        if ($Partial -and $key.EndsWith($Partial, [StringComparison]::OrdinalIgnoreCase)) { return $key }
    } catch { $null = $_ }
    $null
}
$r = @{}
try {
    $p = @(Get-CimInstance SoftwareLicensingProduct -Filter "ApplicationID='55c92734-d682-4d71-983e-d6ec3f16059f' AND PartialProductKey IS NOT NULL" -ErrorAction Stop | Sort-Object LicenseStatus)[0]
    if ($p) { $r.Name = "$($p.Name)"; $r.Desc = "$($p.Description)"; $r.Status = [int]$p.LicenseStatus; $r.Partial = "$($p.PartialProductKey)"; $r.Grace = [int]$p.GracePeriodRemaining; $r.Family = "$($p.LicenseFamily)" }
    $s = Get-CimInstance SoftwareLicensingService -ErrorAction Stop
    $r.Oa3 = "$($s.OA3xOriginalProductKey)".Trim(); $r.Oa3Desc = "$($s.OA3xOriginalProductKeyDescription)"
} catch { $r.Error = $_.Exception.Message }
if ($Sync.LicAct) {
    # changement de clé / activation : slmgr.vbs (installe la clé puis active en ligne)
    $a = $Sync.LicAct; $out = @()
    try {
        $sl = Join-Path $env:windir 'System32\slmgr.vbs'; $cs = Join-Path $env:windir 'System32\cscript.exe'
        if ($a.Key) { $out += @(& $cs //nologo $sl /ipk $a.Key 2>&1); if ($LASTEXITCODE -ne 0) { throw ((@($out) -join ' ').Trim()) } }
        $out += @(& $cs //nologo $sl /ato 2>&1)
        $r.ActOk = $LASTEXITCODE -eq 0; $r.ActMsg = ((@($out) | ForEach-Object { "$_".Trim() } | Where-Object { $_ }) -join ' ')
    } catch { $r.ActOk = $false; $r.ActMsg = $_.Exception.Message }
    $p = @(Get-CimInstance SoftwareLicensingProduct -Filter "ApplicationID='55c92734-d682-4d71-983e-d6ec3f16059f' AND PartialProductKey IS NOT NULL" -ErrorAction SilentlyContinue | Sort-Object LicenseStatus)[0]
    if ($p) { $r.Name = "$($p.Name)"; $r.Desc = "$($p.Description)"; $r.Status = [int]$p.LicenseStatus; $r.Partial = "$($p.PartialProductKey)"; $r.Family = "$($p.LicenseFamily)" }
}
if ($r.Partial) { $r.Full = Get-InstalledKey $r.Partial }
$Sync.Lic = $r
'@
function Start-LicRead($Act) {
    if ($BgJobs.ContainsKey('Lic')) { return }
    $Sync.LicAct = $Act; $Sync.Lic = $null
    $ToolsUI.LicBody.Children.Clear(); $t = New-Text $(if ($Act) { 'Activation en cours (serveurs Microsoft)...' } else { 'Lecture de la licence...' }) 'Muted'; $t.Margin = New-Thickness 38 0 10 12
    [void]$ToolsUI.LicBody.Children.Add($t)
    Start-BgJob 'Lic' $LicScript
}
$BgJobDone['Lic'] = {
    $r = $Sync.Lic; $act = $Sync.LicAct; $Sync.LicAct = $null
    if ($act -and $r) {
        $m = $(if ($r.ActOk) { 'Windows : clé installée et activation réussie.' } else { "Windows : activation en échec - $($r.ActMsg)" })
        Write-UiLog $m $(if ($r.ActOk) { 'OK' } else { 'ERROR' }); Add-SessionEvent 'Réglages' 'Activation de Windows' $(if ($r.ActOk) { 'réussie' } else { 'échec' }) $(if ($r.ActOk) { 'ok' } else { 'error' })
        if (-not $r.ActOk) { Show-Info "Activation de Windows impossible.`n`n$($r.ActMsg)" 'Error' }
    }
    Update-LicCard $r
}
function Get-LicChannel([string]$Desc) {
    $(switch -Regex ($Desc) { 'RETAIL' { 'Retail (clé achetée séparément)' } 'OEM' { 'OEM (livrée avec le PC)' } 'VOLUME_KMSCLIENT' { 'Volume KMS (serveur d''entreprise)' } 'VOLUME_MAK' { 'Volume MAK (entreprise)' } default { $Desc } })
}
# Licence Windows : une ligne d'état (activation, édition, type de licence), puis les clés sur des lignes alignées
# (valeur masquée, icônes œil et copier, même présentation que la clé de récupération BitLocker), puis les actions.
# Clé installée identique à celle du BIOS : une seule ligne.
function Add-LicKeyRow($Body, [string]$Label, [string]$Key, [string]$Tip) {
    [void](Add-SecretKeyRow $Body $Label $Key $Tip $null 'Clé Windows copiée dans le presse-papiers.')
}
function Update-LicCard($R) {
    $b = $ToolsUI.LicBody; $b.Children.Clear()
    if (-not $R -or $R.Error) { $t = New-Text ('Licence illisible : ' + $(if ($R) { $R.Error } else { 'lecture interrompue' })) 'Muted'; $t.Margin = New-Thickness 38 0 10 12; [void]$b.Children.Add($t); return }
    $on = $R.Status -eq 1
    $st = $(switch ($R.Status) { 1 { 'Activé' } 0 { 'Non activé' } 2 { 'Période de grâce initiale' } 3 { 'Période de grâce (changement de matériel)' } 4 { 'Période de grâce (licence non authentique)' } 5 { 'Non activé (notifications)' } 6 { 'Période de grâce prolongée' } default { 'État inconnu' } })
    if (-not $on -and $R.Grace -gt 0) { $st += ' ({0} jours restants)' -f [math]::Floor($R.Grace / 1440) }
    $ed = "$(if ($R.Family) { $R.Family } else { $R.Name })"
    [void](Add-KV $b 'Windows' ('{0}  ·  {1}  ·  {2}' -f $st, $ed, (Get-LicChannel $R.Desc)) $(if ($on) { 'OkFgBrush' } else { 'ErrFgBrush' }))
    # clés
    $same = $R.Full -and $R.Oa3 -and $R.Full -eq $R.Oa3
    if ($R.Full) { Add-LicKeyRow $b $(if ($same) { 'Clé (installée = BIOS)' } else { 'Clé installée' }) $R.Full $null }
    elseif ($R.Partial) { $v = Add-KV $b 'Clé installée' ((Get-MaskedText 'XXXXX-XXXXX-XXXXX-XXXXX-') + $R.Partial); $v.FontFamily = [Windows.Media.FontFamily]::new('Consolas'); $v.ToolTip = 'Windows ne conserve que la fin de la clé : licence numérique ou clé générique d''édition' }
    else { [void](Add-KV $b 'Clé installée' 'aucune') }
    if ($R.Oa3 -and -not $same) { Add-LicKeyRow $b 'Clé du BIOS' $R.Oa3 $(if ($R.Oa3Desc) { "$($R.Oa3Desc)" } else { $null }) }
    elseif (-not $R.Oa3) { $v = Add-KV $b 'Clé du BIOS' 'aucune'; $v.ToolTip = 'PC assemblé, ou licence numérique liée au matériel' }
    $ToolsUI.LicKey = $R.Oa3
    # actions : activation en premier quand Windows n'est pas activé
    $btns = @()
    if (-not $on) { $btns += $(if ($R.Oa3) { New-ToolButton 'Activer avec la clé du BIOS' $null { if (Confirm-Action "Installer la clé du BIOS et activer Windows ?`n`nActivation en ligne auprès de Microsoft.") { Start-LicRead @{ Key = $ToolsUI.LicKey } } } 'PrimaryBtn' } else { New-ToolButton 'Activer' $null { Start-LicRead @{ Key = '' } } 'PrimaryBtn' }) }
    $btns += New-ToolButton 'Changer de clé' $null {
        $v = Read-ToolInput "Nouvelle clé de produit Windows`n`n25 caractères (XXXXX-XXXXX-XXXXX-XXXXX-XXXXX). La clé est installée puis Windows est activé en ligne ; une clé d'une autre édition (Famille vers Pro) change l'édition au redémarrage." @(@{ L = 'Clé'; V = '' }) 'Installer et activer' 560
        if (-not $v) { return }
        $k = ("$($v[0])".ToUpper() -replace '[^A-Z0-9]', '')
        if ($k.Length -ne 25) { Show-Info 'Clé invalide : 25 lettres et chiffres attendus.' 'Warn'; return }
        Start-LicRead @{ Key = ($k -replace '(.{5})(?!$)', '$1-') }
    }
    $btns += New-ToolButton 'Paramètres d''activation' $null { Start-Process 'ms-settings:activation' }
    [void]$b.Children.Add((New-ToolBar $btns))
}
# secrets (clé du BIOS, mots de passe Wi-Fi) : compte administrateur demandé, puis valable 20 s pour toute la liste
# (autre ligne affichée sans nouvelle saisie) ; chaque secret affiché se masque seul au bout de 20 s
# secrets (clé du BIOS, mots de passe Wi-Fi) : masqués par défaut, affichés / masqués par l'œil (application déjà lancée
# en administrateur : pas de nouvelle saisie d'identifiants)
function Request-ToolAuth([string]$Scope, [string]$Purpose) { $true }
function Switch-ToolSecret($Sec, [string]$Scope, [string]$Purpose, $Btn) {
    if ($Sec.Shown) { $Sec.Box.Text = $Sec.Masked; $Sec.Shown = $false } else { $Sec.Box.Text = $Sec.Clear; $Sec.Shown = $true }
    # œil barré une fois le secret affiché (retour visuel de l'action)
    if ($Btn) { Set-EyeState $Btn $Sec.Shown }
}

