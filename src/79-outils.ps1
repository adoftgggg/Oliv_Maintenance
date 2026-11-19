# ---------- Onglet Outils : licence Windows, réseaux Wi-Fi enregistrés, fichier hosts, menu clic droit de l'Explorateur,
# variables d'environnement. Cartes construites à la 1re ouverture de l'onglet ; lectures longues en tâche de fond.
$ToolsUI = @{ Built = $false }
$HostsFile = Join-Path $env:windir 'System32\drivers\etc\hosts'
$HostsBackup = Join-Path (Get-LogPath 'Etat') 'hosts.sauvegarde'
$HostsMarkA = '# >>> Oliv_Maintenance : blocage pubs et traqueurs'
$HostsMarkB = '# <<< Oliv_Maintenance'
$HostsListUrl = 'https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts'

# ---- éléments communs : ligne (survol, hors index de la recherche), bouton icône, saisie de texte
function New-ToolRow([string]$Main, [string]$Sub, [object[]]$Buttons, [string]$Tip) {
    $b = [Windows.Controls.Border]::new(); $b.Style = $Window.FindResource('SvcRow'); $b.Padding = New-Thickness 10 4 6 4; $b.Margin = New-Thickness 30 1 10 1
    $g = [Windows.Controls.Grid]::new(); foreach ($w in 0, -1) { [void]$g.ColumnDefinitions.Add($(if ($w) { $c = [Windows.Controls.ColumnDefinition]::new(); $c.Width = [Windows.GridLength]::Auto; $c } else { New-SvcCol 0 })) }
    $sp = [Windows.Controls.StackPanel]::new(); $sp.VerticalAlignment = 'Center'; $sp.Margin = New-Thickness 0 0 8 0
    $t1 = New-Text $Main; $t1.FontWeight = [Windows.FontWeights]::SemiBold; $t1.TextTrimming = 'CharacterEllipsis'; [void]$sp.Children.Add($t1)
    $t2 = $null; if ($Sub) { $t2 = New-Text $Sub 'Muted'; $t2.FontSize = 12; $t2.TextTrimming = 'CharacterEllipsis'; [void]$sp.Children.Add($t2) }
    [void]$g.Children.Add($sp)
    $bp = [Windows.Controls.StackPanel]::new(); $bp.Orientation = 'Horizontal'; $bp.VerticalAlignment = 'Center'
    foreach ($x in $Buttons) { if ($x) { [void]$bp.Children.Add($x) } }
    [Windows.Controls.Grid]::SetColumn($bp, 1); [void]$g.Children.Add($bp)
    $b.Child = $g; if ($Tip) { $b.ToolTip = $Tip }
    @{ Row = $b; Main = $t1; Sub = $t2; Btns = $bp }
}
function New-ToolIconButton([int]$Glyph, [string]$Tip, $Tag, [scriptblock]$Click) {
    $x = [Windows.Controls.Button]::new(); $x.Style = $Window.FindResource('IconBtn'); $x.Content = [string][char]$Glyph; $x.Width = 32; $x.Height = 28; $x.Margin = New-Thickness 2 0 0 0
    $x.ToolTip = $Tip; $x.Tag = $Tag; $x.Add_Click($Click); $x
}
function New-ToolButton([string]$Text, $Tag, [scriptblock]$Click, [string]$StyleKey = 'ActionBtn') {
    $x = New-Button $Text $StyleKey; $x.Height = 30; $x.MinWidth = 0; $x.Padding = New-Thickness 12 0 12 0; $x.Margin = New-Thickness 0 0 8 0; $x.Tag = $Tag; $x.Add_Click($Click); $x
}
function New-ToolBar([object[]]$Buttons) {
    $w = [Windows.Controls.WrapPanel]::new(); $w.Margin = New-Thickness 38 8 10 12
    foreach ($x in $Buttons) { if ($x) { $x.Margin = New-Thickness 0 0 8 4; [void]$w.Children.Add($x) } }
    $w
}
function New-ToolTextBox([string]$Text, [bool]$Multi, [double]$Height = 0) {
    $t = [Windows.Controls.TextBox]::new(); $t.Text = $Text; $t.Padding = New-Thickness 8 6 8 6; $t.FontSize = 13
    $t.SetResourceReference([Windows.Controls.Control]::BackgroundProperty, 'BgBrush'); $t.SetResourceReference([Windows.Controls.Control]::ForegroundProperty, 'FgBrush')
    $t.SetResourceReference([Windows.Controls.Control]::BorderBrushProperty, 'LineBrush'); $t.SetResourceReference([Windows.Controls.TextBox]::CaretBrushProperty, 'FgBrush')
    if ($Multi) { $t.AcceptsReturn = $true; $t.TextWrapping = 'NoWrap'; $t.VerticalScrollBarVisibility = 'Auto'; $t.HorizontalScrollBarVisibility = 'Auto'; $t.FontFamily = [Windows.Media.FontFamily]::new('Consolas'); $t.Height = $(if ($Height) { $Height } else { 220 }) }
    $t
}
# saisie : champs @(@{ L = libellé; V = valeur; M = multiligne; H = hauteur }) ; renvoie les valeurs, ou $null si annulé
function Read-ToolInput([string]$Message, [object[]]$Fields, [string]$OkText = 'Enregistrer', [int]$Width = 640) {
    $sp = [Windows.Controls.StackPanel]::new(); $boxes = @()
    foreach ($f in $Fields) {
        if ($f.L) { $l = New-Text $f.L 'Muted'; $l.Margin = New-Thickness 0 6 0 4; [void]$sp.Children.Add($l) }
        $tb = New-ToolTextBox "$($f.V)" ([bool]$f.M) ([double]$f.H); if ($f.RO) { $tb.IsReadOnly = $true; $tb.Opacity = 0.7 }
        [void]$sp.Children.Add($tb); $boxes += $tb
    }
    $first = @($boxes | Where-Object { -not $_.IsReadOnly })[0]
    $v = Show-Dialog $Message 'Question' @(@{ T = 'Annuler'; V = 'no'; C = $true }, @{ T = $OkText; V = 'ok'; K = 'OkBtn' }) $null $null $Width $sp { param($d, $bp) $d.Tag = $first; foreach ($c in $bp.Children) { $c.IsDefault = $c.Name -eq 'OkBtn' } }
    if ($v -ne 'ok') { return $null }
    , @($boxes | ForEach-Object { $_.Text })
}

# ================= Licence Windows
$LicScript = @'
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
function Update-LicCard($R) {
    $b = $ToolsUI.LicBody; $b.Children.Clear()
    if (-not $R -or $R.Error) { $t = New-Text ('Licence illisible : ' + $(if ($R) { $R.Error } else { 'lecture interrompue' })) 'Muted'; $t.Margin = New-Thickness 38 0 10 12; [void]$b.Children.Add($t); return }
    $st = $(switch ($R.Status) { 1 { 'Activé' } 0 { 'Non activé' } 2 { 'Période de grâce initiale' } 3 { 'Période de grâce (changement matériel)' } 4 { 'Période de grâce (licence non authentique)' } 5 { 'Notifications : Windows non activé' } 6 { 'Période de grâce prolongée' } default { 'inconnu' } })
    $grace = $(if ($R.Status -ne 1 -and $R.Grace -gt 0) { ' ({0} jours restants)' -f [math]::Floor($R.Grace / 1440) } else { '' })
    [void](Add-KV $b 'État' ($st + $grace) $(if ($R.Status -eq 1) { 'OkFgBrush' } else { 'ErrFgBrush' }))
    [void](Add-KV $b 'Édition' $(if ($R.Family) { $R.Family } else { $R.Name }))
    [void](Add-KV $b 'Type de licence' (Get-LicChannel $R.Desc))
    [void](Add-KV $b 'Clé installée' $(if ($R.Partial) { 'XXXXX-XXXXX-XXXXX-XXXXX-' + $R.Partial } else { 'aucune' }))
    # clé d'origine du BIOS / UEFI (PC de marque) : masquée, affichable et copiable
    if ($R.Oa3) {
        $ToolsUI.LicKey = $R.Oa3
        $sec = @{ Shown = $false; Clear = $R.Oa3; Masked = (Get-MaskedText $R.Oa3) }
        $eye = New-ToolIconButton 0xE7B3 'Afficher / masquer la clé (compte administrateur demandé)' $sec { param($s, $e) Switch-ToolSecret $s.Tag 'Lic' 'Afficher la clé Windows du BIOS' }
        $cp = New-ToolIconButton 0xE8C8 'Copier la clé (compte administrateur demandé)' $null { if (Request-ToolAuth 'Lic' 'Copier la clé Windows du BIOS') { Set-ClipText $ToolsUI.LicKey; Write-UiLog 'Clé Windows du BIOS copiée dans le presse-papiers.' 'APP' } }
        $ToolsUI.LicOa3Row = New-ToolRow 'Clé d''origine du BIOS' (Get-MaskedText $R.Oa3) @($eye, $cp) $(if ($R.Oa3Desc) { $R.Oa3Desc } else { $null })
        $ToolsUI.LicOa3Row.Row.Margin = New-Thickness 30 6 10 0; $sec.Box = $ToolsUI.LicOa3Row.Sub
        [void]$b.Children.Add($ToolsUI.LicOa3Row.Row)
    } else { [void](Add-KV $b 'Clé du BIOS' 'aucune (PC assemblé, ou licence numérique liée au matériel)') }
    $btns = @()
    if ($R.Oa3 -and $R.Status -ne 1) { $btns += New-ToolButton 'Activer avec la clé du BIOS' $null { if (Confirm-Action "Installer la clé du BIOS et activer Windows ?`n`nActivation en ligne auprès de Microsoft.") { Start-LicRead @{ Key = $ToolsUI.LicKey } } } 'PrimaryBtn' }
    $btns += New-ToolButton 'Changer de clé de produit' $null {
        $v = Read-ToolInput "Nouvelle clé de produit Windows`n`n25 caractères (XXXXX-XXXXX-XXXXX-XXXXX-XXXXX). La clé est installée puis Windows est activé en ligne ; une clé d'une autre édition (Famille vers Pro) change l'édition au redémarrage." @(@{ L = 'Clé'; V = '' }) 'Installer et activer' 560
        if (-not $v) { return }
        $k = ("$($v[0])".ToUpper() -replace '[^A-Z0-9]', '')
        if ($k.Length -ne 25) { Show-Info 'Clé invalide : 25 lettres et chiffres attendus.' 'Warn'; return }
        Start-LicRead @{ Key = ($k -replace '(.{5})(?!$)', '$1-') }
    }
    if ($R.Status -ne 1) { $btns += New-ToolButton 'Réessayer l''activation' $null { Start-LicRead @{ Key = '' } } }
    $btns += New-ToolButton 'Paramètres d''activation' $null { Start-Process 'ms-settings:activation' }
    [void]$b.Children.Add((New-ToolBar $btns))
}
# secrets (clé du BIOS, mots de passe Wi-Fi) : compte administrateur demandé, puis valable 20 s pour toute la liste
# (autre ligne affichée sans nouvelle saisie) ; chaque secret affiché se masque seul au bout de 20 s
function Request-ToolAuth([string]$Scope, [string]$Purpose) {
    if (-not $ToolsUI.Auth) { $ToolsUI.Auth = @{} }
    $u = $ToolsUI.Auth[$Scope]; if ($u -and [DateTime]::Now -lt $u) { return $true }
    $acc = Request-AdminAuth $Purpose; if (-not $acc) { return $false }
    $ToolsUI.Auth[$Scope] = [DateTime]::Now.AddSeconds(20)
    Write-UiLog "$Purpose (authentification : $acc)." 'WARN'
    $true
}
function Switch-ToolSecret($Sec, [string]$Scope, [string]$Purpose) {
    if ($Sec.Shown) { $Sec.Box.Text = $Sec.Masked; $Sec.Shown = $false; return }
    if (-not (Request-ToolAuth $Scope $Purpose)) { return }
    $Sec.Box.Text = $Sec.Clear; $Sec.Shown = $true
    $tm = [Windows.Threading.DispatcherTimer]::new(); $tm.Interval = [TimeSpan]::FromSeconds(20); $tm.Tag = $Sec
    $tm.Add_Tick({ param($x, $y) $x.Stop(); $o = $x.Tag; if ($o.Shown) { $o.Box.Text = $o.Masked; $o.Shown = $false } })
    $tm.Start()
}
function Get-MaskedText([string]$S) { ($S -replace '[A-Za-z0-9]', [string][char]0x2022) }

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
        $eye = $(if ($hasKey) { New-ToolIconButton 0xE7B3 'Afficher / masquer le mot de passe (compte administrateur demandé, valable 20 s pour toute la liste)' $sec { param($s, $e) Switch-ToolSecret $s.Tag 'Wifi' 'Afficher les mots de passe Wi-Fi enregistrés' } })
        $cp = $(if ($hasKey) { New-ToolIconButton 0xE8C8 'Copier le mot de passe (compte administrateur demandé)' $w { param($s, $e) if (Request-ToolAuth 'Wifi' 'Copier un mot de passe Wi-Fi') { Set-ClipText $s.Tag.Key; Write-UiLog ('Mot de passe du réseau Wi-Fi « {0} » copié.' -f $s.Tag.Name) 'APP' } } })
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

# ================= Fichier hosts : blocage pubs / traqueurs (liste StevenBlack, entre 2 repères), édition, sauvegarde
function Read-HostsFile { try { [IO.File]::ReadAllText($HostsFile) } catch { '' } }
# contenu hors bloc de blocage, et bloc (lignes) séparés
function Split-HostsContent([string]$Text) {
    $own = [Collections.Generic.List[string]]::new(); $blk = [Collections.Generic.List[string]]::new(); $in = $false
    foreach ($l in ($Text -split "`r?`n")) {
        if ($l.StartsWith($HostsMarkA)) { $in = $true; [void]$blk.Add($l); continue }
        if ($in) { [void]$blk.Add($l); if ($l.StartsWith($HostsMarkB)) { $in = $false }; continue }
        [void]$own.Add($l)
    }
    @{ Own = (($own -join "`r`n").TrimEnd()); Block = @($blk) }
}
function Write-HostsFile([string]$Own, [string[]]$Block) {
    if (-not (Test-Path -LiteralPath $HostsBackup)) { try { [void][IO.Directory]::CreateDirectory((Split-Path $HostsBackup)); Copy-Item -LiteralPath $HostsFile -Destination $HostsBackup -Force } catch { Write-Ignored 'Sauvegarde du fichier hosts' $_ } }
    $fi = [IO.FileInfo]::new($HostsFile); if ($fi.Exists -and $fi.IsReadOnly) { $fi.IsReadOnly = $false }
    $txt = $Own.TrimEnd() + "`r`n" + $(if ($Block -and $Block.Count) { "`r`n" + ($Block -join "`r`n").TrimEnd() + "`r`n" } else { '' })
    [IO.File]::WriteAllText($HostsFile, $txt, [Text.Encoding]::ASCII)
    try { Clear-DnsClientCache -ErrorAction Stop } catch { Write-Ignored 'Vidage du cache DNS' $_ }
}
function Update-HostsCard {
    $b = $ToolsUI.HostsBody; $b.Children.Clear()
    $p = Split-HostsContent (Read-HostsFile)
    $own = @($p.Own -split "`r`n" | Where-Object { $_.Trim() -and -not $_.Trim().StartsWith('#') }).Count
    $nb = @($p.Block | Where-Object { $_ -match '^0\.0\.0\.0\s' }).Count
    $date = $(if ($p.Block.Count -and $p.Block[0] -match '\((\d{2}/\d{2}/\d{4})\)') { $Matches[1] } else { '' })
    [void](Add-KV $b 'Entrées personnelles' $(if ($own) { "$own" } else { 'aucune' }))
    [void](Add-KV $b 'Blocage pubs et traqueurs' $(if ($nb) { '{0:N0} domaines bloqués (liste du {1})' -f $nb, $date } else { 'désactivé' }) $(if ($nb) { 'OkFgBrush' } else { '' }))
    $btns = @()
    $btns += $(if ($nb) { New-ToolButton 'Mettre à jour la liste' $null { Start-HostsBlock $true } 'PrimaryBtn' } else { New-ToolButton 'Bloquer pubs et traqueurs' $null { Start-HostsBlock $true } 'PrimaryBtn' })
    if ($nb) { $btns += New-ToolButton 'Retirer le blocage' $null { Start-HostsBlock $false } }
    $btns += New-ToolButton 'Modifier mes entrées' $null { Edit-HostsFile }
    if (Test-Path -LiteralPath $HostsBackup) { $btns += New-ToolButton 'Restaurer l''original' $null { Restore-HostsFile } }
    [void]$b.Children.Add((New-ToolBar $btns))
}
$HostsScript = @'
$r = @{}
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $wc = New-Object Net.WebClient; $wc.Encoding = [Text.Encoding]::UTF8
    $t = $wc.DownloadString($Sync.HostsUrl)
    $l = @($t -split "`r?`n" | Where-Object { $_ -match '^0\.0\.0\.0\s+[^\s#]+' -and $_ -notmatch '^0\.0\.0\.0\s+0\.0\.0\.0' } | ForEach-Object { ($_ -replace '\s*#.*$', '').Trim() } | Select-Object -Unique)
    if ($l.Count -lt 1000) { throw "liste inattendue ($($l.Count) entrées)" }
    $r.Lines = $l
} catch { $r.Error = $_.Exception.Message }
$Sync.HostsDl = $r
'@
function Start-HostsBlock([bool]$On) {
    if (-not $On) {
        if (-not (Confirm-Action 'Retirer le blocage des pubs et traqueurs du fichier hosts ?')) { return }
        try { $p = Split-HostsContent (Read-HostsFile); Write-HostsFile $p.Own @(); Write-UiLog 'Fichier hosts : blocage des pubs et traqueurs retiré.' 'OK' } catch { Show-Info "Écriture du fichier hosts impossible.`n`n$($_.Exception.Message)" 'Error' }
        Update-HostsCard; return
    }
    if ($BgJobs.ContainsKey('Hosts')) { return }
    if (-not (Test-Path -LiteralPath $HostsBackup) -and -not (Confirm-Action "Bloquer les pubs, traqueurs et sites malveillants connus dans le fichier hosts ?`n`nListe StevenBlack/hosts (environ 80 000 domaines, mise à jour régulièrement), ajoutée à la fin du fichier sans toucher à vos entrées ; sauvegarde du fichier d'origine dans le dossier d'état. Un site qui ne s'affiche plus se débloque en retirant le blocage.")) { return }
    $Sync.HostsUrl = $HostsListUrl; $Sync.HostsDl = $null
    $ToolsUI.HostsBody.Children.Clear(); $t = New-Text 'Téléchargement de la liste de blocage...' 'Muted'; $t.Margin = New-Thickness 38 0 10 12; [void]$ToolsUI.HostsBody.Children.Add($t)
    Start-BgJob 'Hosts' $HostsScript
}
$BgJobDone['Hosts'] = {
    $r = $Sync.HostsDl
    if (-not $r -or $r.Error) { $m = $(if ($r) { $r.Error } else { 'tâche interrompue' }); Write-UiLog "Fichier hosts : liste de blocage non téléchargée - $m" 'ERROR'; Show-Info "Téléchargement de la liste impossible.`n`n$m" 'Error'; Update-HostsCard; return }
    try {
        $p = Split-HostsContent (Read-HostsFile)
        $blk = @("$HostsMarkA ($((Get-Date).ToString('dd/MM/yyyy'))) - source : $HostsListUrl - ne pas modifier") + @($r.Lines) + @($HostsMarkB)
        Write-HostsFile $p.Own $blk
        Write-UiLog ('Fichier hosts : {0:N0} domaines de pubs et traqueurs bloqués.' -f $r.Lines.Count) 'OK'; Add-SessionEvent 'Réglages' 'Blocage pubs et traqueurs (hosts)' ('{0:N0} domaines' -f $r.Lines.Count) 'ok'
    } catch { Write-UiLog "Fichier hosts : $($_.Exception.Message)" 'ERROR'; Show-Info "Écriture du fichier hosts impossible (antivirus ?).`n`n$($_.Exception.Message)" 'Error' }
    Update-HostsCard
}
function Edit-HostsFile {
    $p = Split-HostsContent (Read-HostsFile)
    $v = Read-ToolInput "Fichier hosts : vos entrées`n`nUne entrée par ligne : adresse IP, espace, nom (ex. 192.168.1.20 nas.maison ; 0.0.0.0 site-a-bloquer.com). Lignes commençant par # = commentaires. La liste de blocage, si elle est active, est conservée à part." @(@{ V = $p.Own; M = $true; H = 380 }) 'Enregistrer' 860
    if (-not $v) { return }
    try { Write-HostsFile "$($v[0])" $p.Block; Write-UiLog 'Fichier hosts modifié.' 'OK'; Add-SessionEvent 'Réglages' 'Fichier hosts' 'modifié' 'ok' }
    catch { Show-Info "Écriture du fichier hosts impossible (antivirus ?).`n`n$($_.Exception.Message)" 'Error' }
    Update-HostsCard
}
function Restore-HostsFile {
    if (-not (Confirm-Action "Remettre le fichier hosts d'origine (sauvegardé avant la 1re modification par l'application) ?`n`nVos entrées et le blocage ajoutés depuis sont retirés.")) { return }
    try {
        $fi = [IO.FileInfo]::new($HostsFile); if ($fi.Exists -and $fi.IsReadOnly) { $fi.IsReadOnly = $false }
        Copy-Item -LiteralPath $HostsBackup -Destination $HostsFile -Force; try { Clear-DnsClientCache -ErrorAction Stop } catch { Write-Ignored 'Vidage du cache DNS' $_ }
        Write-UiLog 'Fichier hosts d''origine restauré.' 'OK'
    } catch { Show-Info "Restauration impossible.`n`n$($_.Exception.Message)" 'Error' }
    Update-HostsCard
}

# ================= Menu clic droit de l'Explorateur : entrées ajoutées par les logiciels (éditeur autre que Microsoft)
# Extensions COM (shellex\ContextMenuHandlers) masquées par la liste Shell Extensions\Blocked (tout l'Explorateur) ;
# commandes simples (shell\<verbe>) masquées par la valeur LegacyDisable. Windows 11 : entrées du menu « Afficher plus
# d'options » ; les entrées des applications empaquetées (MSIX) n'y figurent pas.
$CtxScript = @'
$r = @{ Items = @() }
$locs = [ordered]@{ '*' = 'fichiers'; 'AllFilesystemObjects' = 'fichiers et dossiers'; 'Directory' = 'dossiers'; 'Folder' = 'dossiers'; 'Directory\Background' = 'fond de dossier'; 'DesktopBackground' = 'Bureau'; 'Drive' = 'lecteurs' }
$roots = @('HKLM:\SOFTWARE\Classes'); if ($Sync.CtxSid) { $roots += "Registry::HKEY_USERS\$($Sync.CtxSid)\Software\Classes" }
$blocked = @{}; try { $bk = Get-Item -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked' -ErrorAction Stop; foreach ($n in $bk.GetValueNames()) { $blocked[$n.ToUpper()] = 1 } } catch { $null = $_ }
$co = @{}
function Get-Co([string]$F) {
    if (-not $F) { return '' }; $F = [Environment]::ExpandEnvironmentVariables($F.Trim('"'))
    if (-not $co.ContainsKey($F)) { $c = ''; try { if (Test-Path -LiteralPath $F) { $c = "$([Diagnostics.FileVersionInfo]::GetVersionInfo($F).CompanyName)".Trim() } } catch { $null = $_ }; $co[$F] = $c }
    $co[$F]
}
function Get-Ind([string]$S) { if ($S -like '@*') { try { $v = [_OlivM.Shell]::Indirect($S); if ($v) { return $v } } catch { $null = $_ } }; $S }
$h = @{}; $v = @{}
foreach ($root in $roots) {
    foreach ($loc in $locs.Keys) {
        # extensions COM
        $hk = "$root\$loc\shellex\ContextMenuHandlers"
        if (Test-Path -LiteralPath $hk) {
            foreach ($k in @(Get-ChildItem -LiteralPath $hk -ErrorAction SilentlyContinue)) {
                $id = "$($k.GetValue(''))"; if ($id -notmatch '^\{[0-9A-Fa-f\-]{36}\}$') { $id = $k.PSChildName }
                if ($id -notmatch '^\{[0-9A-Fa-f\-]{36}\}$') { continue }
                $id = $id.ToUpper()
                if (-not $h.ContainsKey($id)) {
                    $nm = ''; $dll = ''
                    foreach ($cr in $roots) { if (-not $nm) { $nm = "$((Get-ItemProperty -LiteralPath "$cr\CLSID\$id" -ErrorAction SilentlyContinue).'(default)')" }; if (-not $dll) { $dll = "$((Get-ItemProperty -LiteralPath "$cr\CLSID\$id\InprocServer32" -ErrorAction SilentlyContinue).'(default)')" } }
                    $c = Get-Co $dll
                    $h[$id] = [pscustomobject]@{ Kind = 'ext'; Id = $id; Name = $(if ($nm) { $nm } else { $k.PSChildName }); Handler = $k.PSChildName; File = $dll; Co = $c; Ms = $c -match '^Microsoft'; Off = $blocked.ContainsKey($id); Where = [Collections.Generic.List[string]]::new(); Keys = @() }
                }
                if (-not $h[$id].Where.Contains($locs[$loc])) { $h[$id].Where.Add($locs[$loc]) }
            }
        }
        # commandes simples
        $sk = "$root\$loc\shell"
        if (Test-Path -LiteralPath $sk) {
            foreach ($k in @(Get-ChildItem -LiteralPath $sk -ErrorAction SilentlyContinue)) {
                $cmd = "$((Get-ItemProperty -LiteralPath "$($k.PSPath)\command" -ErrorAction SilentlyContinue).'(default)')"
                if (-not $cmd) { continue }
                $exe = $(if ($cmd -match '^\s*"([^"]+)"') { $Matches[1] } elseif ($cmd -match '^\s*(\S+)') { $Matches[1] } else { '' })
                $c = Get-Co $exe; if ($c -match '^Microsoft' -or $exe -match '(?i)\\(cmd|powershell|explorer|rundll32|regsvr32|msiexec)\.exe$') { continue }
                $p = Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction SilentlyContinue
                $lb = "$($p.MUIVerb)"; if (-not $lb) { $lb = "$($p.'(default)')" }; if (-not $lb) { $lb = $k.PSChildName }
                $key = "$($k.PSChildName)|$exe"
                if (-not $v.ContainsKey($key)) { $v[$key] = [pscustomobject]@{ Kind = 'verb'; Id = $key; Name = ((Get-Ind $lb) -replace '&', ''); Handler = $k.PSChildName; File = $exe; Co = $c; Ms = $false; Off = $false; Where = [Collections.Generic.List[string]]::new(); Keys = @() } }
                $v[$key].Keys += $k.PSPath
                if ($null -ne $p.LegacyDisable) { $v[$key].Off = $true }
                if (-not $v[$key].Where.Contains($locs[$loc])) { $v[$key].Where.Add($locs[$loc]) }
            }
        }
    }
}
$r.Items = @(@($h.Values | Where-Object { -not $_.Ms }) + @($v.Values)) | Sort-Object Name
$Sync.Ctx = $r
'@
function Start-CtxRead {
    if ($BgJobs.ContainsKey('Ctx')) { return }
    $ToolsUI.CtxBody.Children.Clear(); $t = New-Text 'Lecture des entrées du menu...' 'Muted'; $t.Margin = New-Thickness 38 0 10 12; [void]$ToolsUI.CtxBody.Children.Add($t)
    $Sync.CtxSid = $(if ($HkuSidOk) { $UserSid } else { $null }); $Sync.Ctx = $null
    Start-BgJob 'Ctx' $CtxScript
}
$BgJobDone['Ctx'] = { Update-CtxCard $Sync.Ctx }
function Update-CtxCard($R) {
    $b = $ToolsUI.CtxBody; $b.Children.Clear()
    $items = @($(if ($R) { $R.Items }))
    if (-not $items.Count) { $t = New-Text 'Aucune entrée ajoutée par un logiciel.' 'Muted'; $t.Margin = New-Thickness 38 0 10 12; [void]$b.Children.Add($t) }
    foreach ($it in $items) {
        $tg = New-ToolButton $(if ($it.Off) { 'Afficher' } else { 'Masquer' }) $it { param($s, $e) Switch-CtxEntry $s.Tag }
        $tg.Width = 90; $tg.Margin = New-Thickness 4 0 0 0
        $sub = '{0}  ·  {1}' -f $(if ($it.Co) { $it.Co } else { 'éditeur inconnu' }), ($it.Where -join ', ')
        $row = New-ToolRow $it.Name $sub @($tg) ('{0}{1}' -f $(if ($it.File) { 'Fichier : ' + $it.File } else { '' }), $(if ($it.Kind -eq 'ext') { "`nExtension $($it.Handler) $($it.Id)" } else { "`nCommande « $($it.Handler) »" }))
        if ($it.Off) { $row.Main.Opacity = 0.55; $row.Sub.Text = 'masquée  ·  ' + $sub }
        [void]$b.Children.Add($row.Row)
    }
    $btns = @((New-ToolButton 'Redémarrer l''Explorateur' $null { Restart-Explorer }), (New-ToolButton 'Actualiser' $null { Start-CtxRead }))
    [void]$b.Children.Add((New-ToolBar $btns))
}
function Switch-CtxEntry($It) {
    try {
        if ($It.Kind -eq 'ext') {
            $k = Open-RegKey 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked' $true $true
            try { if ($It.Off) { $k.DeleteValue($It.Id, $false) } else { $k.SetValue($It.Id, $It.Name, [Microsoft.Win32.RegistryValueKind]::String) } } finally { $k.Close() }
        } else {
            foreach ($p in $It.Keys) { if ($It.Off) { Remove-ItemProperty -LiteralPath $p -Name 'LegacyDisable' -ErrorAction SilentlyContinue } else { Set-ItemProperty -LiteralPath $p -Name 'LegacyDisable' -Value '' -Type String -ErrorAction Stop } }
        }
        $It.Off = -not $It.Off
        Write-UiLog ('Menu clic droit : « {0} » {1} (effectif après redémarrage de l''Explorateur).' -f $It.Name, $(if ($It.Off) { 'masquée' } else { 'réaffichée' })) 'OK'
    } catch { Write-UiLog "Menu clic droit : $($_.Exception.Message)" 'ERROR'; Show-Info "Modification impossible.`n`n$($_.Exception.Message)" 'Error' }
    Update-CtxCard $Sync.Ctx
}
function Restart-Explorer {
    if (-not (Confirm-Action "Redémarrer l'Explorateur Windows ?`n`nLa barre des tâches et les fenêtres de l'Explorateur se ferment quelques secondes ; les autres programmes restent ouverts.")) { return }
    try { Get-Process -Name explorer -ErrorAction Stop | Stop-Process -Force -ErrorAction Stop } catch { Write-Ignored 'Arrêt de l''Explorateur' $_ }
    # relancé automatiquement par Windows en principe ; sinon lancé dans la session (lancement par l'interface de l'utilisateur)
    $t = [Windows.Threading.DispatcherTimer]::new(); $t.Interval = [TimeSpan]::FromSeconds(3)
    $t.Add_Tick({ param($s, $e) $s.Stop(); if (-not (Get-Process -Name explorer -ErrorAction SilentlyContinue)) { Start-Process (Join-Path $env:windir 'explorer.exe') } })
    $t.Start(); Write-UiLog 'Explorateur Windows redémarré.' 'APP'
}

# ================= Variables d'environnement (utilisateur ciblé : HKCU\Environment ; système : Session Manager\Environment)
$EnvSys = 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment'
$EnvUsr = 'HKCU\Environment'
$EnvProtected = @('Path', 'ComSpec', 'windir', 'SystemRoot', 'OS', 'PATHEXT', 'PSModulePath', 'TEMP', 'TMP', 'NUMBER_OF_PROCESSORS', 'PROCESSOR_ARCHITECTURE', 'PROCESSOR_IDENTIFIER', 'PROCESSOR_LEVEL', 'PROCESSOR_REVISION', 'DriverData', 'USERNAME', 'OneDrive')
function Get-EnvVar([string]$Path) {
    $k = Open-RegKey $Path; if (-not $k) { return @() }
    try { @($k.GetValueNames() | Where-Object { $_ } | Sort-Object | ForEach-Object { [pscustomobject]@{ Name = $_; Value = "$($k.GetValue($_, '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames))"; Kind = "$($k.GetValueKind($_))" } }) } finally { $k.Close() }
}
function Update-EnvCard {
    $b = $ToolsUI.EnvBody; $b.Children.Clear()
    foreach ($sc in @(@{ P = $EnvUsr; T = "Utilisateur ($UserName)"; S = 'U' }, @{ P = $EnvSys; T = 'Système (tous les comptes)'; S = 'S' })) {
        $hd = [Windows.Controls.Grid]::new(); $hd.Margin = New-Thickness 38 8 10 4
        [void]$hd.ColumnDefinitions.Add((New-SvcCol 0)); $c = [Windows.Controls.ColumnDefinition]::new(); $c.Width = [Windows.GridLength]::Auto; [void]$hd.ColumnDefinitions.Add($c)
        $t = New-Text $sc.T; $t.FontWeight = [Windows.FontWeights]::SemiBold; $t.VerticalAlignment = 'Center'; [void]$hd.Children.Add($t)
        $ab = New-ToolButton 'Ajouter' $sc { param($s, $e) Edit-EnvVar $s.Tag.P $null }; $ab.Height = 28; $ab.Margin = New-Thickness 0 0 0 0
        [Windows.Controls.Grid]::SetColumn($ab, 1); [void]$hd.Children.Add($ab)
        [void]$b.Children.Add($hd)
        foreach ($v in (Get-EnvVar $sc.P)) {
            $multi = $v.Value -like '*;*'
            $sub = $(if ($multi) { $parts = @($v.Value -split ';' | Where-Object { $_ }); '{0} éléments  ·  {1}' -f $parts.Count, ($parts -join ' ; ') } else { $v.Value })
            $ed = New-ToolIconButton 0xE70F 'Modifier' @{ P = $sc.P; V = $v } { param($s, $e) Edit-EnvVar $s.Tag.P $s.Tag.V }
            $prot = $v.Name -in $EnvProtected
            $dl = New-ToolIconButton 0xE74D $(if ($prot) { 'Variable indispensable : suppression non proposée' } else { 'Supprimer' }) @{ P = $sc.P; V = $v } { param($s, $e) Remove-EnvVar $s.Tag.P $s.Tag.V }
            $dl.IsEnabled = -not $prot; [Windows.Controls.ToolTipService]::SetShowOnDisabled($dl, $true)
            $row = New-ToolRow $v.Name $sub @($ed, $dl) $(if ($multi) { ($v.Value -split ';' | Where-Object { $_ }) -join "`n" } else { $v.Value })
            $row.Row.Cursor = [Windows.Input.Cursors]::Hand; $row.Row.Tag = @{ P = $sc.P; V = $v }
            $row.Row.Add_MouseLeftButtonUp({ param($s, $e) if (-not (Test-InButton $e.OriginalSource)) { Edit-EnvVar $s.Tag.P $s.Tag.V } })
            [void]$b.Children.Add($row.Row)
        }
    }
    $n = New-Text 'Clic sur une variable pour la modifier. Effectif pour les programmes ouverts ensuite.' 'Muted'; $n.FontSize = 12; $n.Margin = New-Thickness 40 8 10 12
    [void]$b.Children.Add($n)
}
# édition : listes (« ; ») présentées un élément par ligne ; dossiers absents signalés avant l'enregistrement
function Edit-EnvVar([string]$Path, $Var) {
    $isNew = -not $Var; $multi = (-not $isNew) -and ($Var.Value -like '*;*' -or $Var.Name -in 'Path', 'PSModulePath', 'PATHEXT')
    $val = $(if ($isNew) { '' } elseif ($multi) { (@($Var.Value -split ';' | Where-Object { $_ }) -join "`r`n") } else { $Var.Value })
    $where = $(if ($Path -eq $EnvSys) { 'système' } else { 'utilisateur' })
    $msg = $(if ($isNew) { "Nouvelle variable ($where)" } else { "Variable $($Var.Name) ($where)" }) + $(if ($multi) { "`n`nUn élément par ligne (dossiers du PATH...). %VARIABLE% est remplacé à l'utilisation." } else { "`n`n%VARIABLE% est remplacé à l'utilisation." })
    $f = @(@{ L = 'Nom'; V = $(if ($isNew) { '' } else { $Var.Name }); RO = -not $isNew }, @{ L = 'Valeur'; V = $val; M = $multi; H = 260 })
    $r = Read-ToolInput $msg $f 'Enregistrer' 760
    if (-not $r) { return }
    $name = "$($r[0])".Trim(); if (-not $name -or $name -match '[=\s]') { Show-Info 'Nom invalide : ni espace ni signe =.' 'Warn'; return }
    $value = $(if ($multi) { (@("$($r[1])" -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ }) -join ';') } else { "$($r[1])" })
    if ($multi -and $name -in 'Path', 'PSModulePath') {
        $miss = @($value -split ';' | Where-Object { $_ -and -not (Test-Path -LiteralPath ([Environment]::ExpandEnvironmentVariables($_))) })
        if ($miss.Count -and -not (Confirm-Action ("Dossiers introuvables :`n`n" + ($miss -join "`n") + "`n`nEnregistrer quand même ?"))) { return }
    }
    if ($Var -and $Var.Name -eq 'Path' -and $Path -eq $EnvSys -and $value.Length -lt 20) { Show-Info 'PATH système presque vide : enregistrement refusé (Windows ne trouverait plus ses propres programmes).' 'Warn'; return }
    try {
        $k = Open-RegKey $Path $true $true
        try {
            $kind = $(if ($value -match '%[^%]+%' -or ($Var -and $Var.Kind -eq 'ExpandString')) { [Microsoft.Win32.RegistryValueKind]::ExpandString } else { [Microsoft.Win32.RegistryValueKind]::String })
            $k.SetValue($name, $value, $kind)
        } finally { $k.Close() }
        [void][_OlivM.Shell]::NotifySettingChange('Environment')
        Write-UiLog ('Variable d''environnement {0} ({1}) enregistrée.' -f $name, $where) 'OK'; Add-SessionEvent 'Réglages' 'Variable d''environnement' "$name ($where)" 'ok'
    } catch { Show-Info "Enregistrement impossible.`n`n$($_.Exception.Message)" 'Error' }
    Update-EnvCard
}
function Remove-EnvVar([string]$Path, $Var) {
    if ($Var.Name -in $EnvProtected) { return }
    if (-not (Confirm-Action "Supprimer la variable $($Var.Name) ?`n`nValeur : $($Var.Value)")) { return }
    try {
        $k = Open-RegKey $Path $true; try { $k.DeleteValue($Var.Name, $false) } finally { $k.Close() }
        [void][_OlivM.Shell]::NotifySettingChange('Environment')
        Write-UiLog "Variable d'environnement $($Var.Name) supprimée." 'OK'
    } catch { Show-Info "Suppression impossible.`n`n$($_.Exception.Message)" 'Error' }
    Update-EnvCard
}

# ================= Comptes locaux : type (administrateur / standard), compte Microsoft ou local, dernière connexion ;
# actions par le menu d'actions (3 points) de chaque compte. Garde-fous : jamais le dernier administrateur actif, ni le compte ciblé,
# ni le compte qui exécute l'application ; comptes système (DefaultAccount, WDAGUtilityAccount) masqués.
$AccScript = @'
$r = @{ Items = @() }
try {
    $adm = @{}
    try {
        $gn = ([Security.Principal.SecurityIdentifier]'S-1-5-32-544').Translate([Security.Principal.NTAccount]).Value.Split('\')[-1]
        $grp = [ADSI]"WinNT://$env:COMPUTERNAME/$gn,group"
        foreach ($m in @($grp.psbase.Invoke('Members'))) {
            try { $sid = [Security.Principal.SecurityIdentifier]::new([byte[]]$m.GetType().InvokeMember('objectSid', 'GetProperty', $null, $m, $null), 0); $adm[$sid.Value] = 1 } catch { $null = $_ }
        }
    } catch { $null = $_ }
    foreach ($u in @(Get-LocalUser -ErrorAction Stop)) {
        $sid = "$($u.SID.Value)"; if ($sid -match '-(503|504)$') { continue }
        $r.Items += [pscustomobject]@{ Name = "$($u.Name)"; Full = "$($u.FullName)"; Desc = "$($u.Description)"; Enabled = [bool]$u.Enabled; Sid = $sid; Admin = $adm.ContainsKey($sid)
            Last = $u.LastLogon; Ms = "$($u.PrincipalSource)" -eq 'MicrosoftAccount'; Builtin = $sid -match '-(500|501)$'; PwdSet = $u.PasswordLastSet; NoExpire = -not $u.PasswordExpires }
    }
} catch { $r.Error = $_.Exception.Message }
$Sync.Acc = $r
'@
function Start-AccRead {
    if ($BgJobs.ContainsKey('Acc')) { return }
    $ToolsUI.AccBody.Children.Clear(); $t = New-Text 'Lecture des comptes...' 'Muted'; $t.Margin = New-Thickness 38 0 10 12; [void]$ToolsUI.AccBody.Children.Add($t)
    $Sync.Acc = $null; Start-BgJob 'Acc' $AccScript
}
$BgJobDone['Acc'] = { Update-AccCard $Sync.Acc }
$AccSelf = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
function Update-AccCard($R) {
    $b = $ToolsUI.AccBody; $b.Children.Clear()
    $items = @($(if ($R) { $R.Items }) | Sort-Object @{ E = { -not $_.Enabled } }, @{ E = { $_.Builtin } }, Name)
    if (-not $items.Count) { $t = New-Text $(if ($R -and $R.Error) { "Comptes illisibles : $($R.Error)" } else { 'Aucun compte local.' }) 'Muted'; $t.Margin = New-Thickness 38 0 10 12; [void]$b.Children.Add($t) }
    $ToolsUI.AccAdmins = @($items | Where-Object { $_.Admin -and $_.Enabled }).Count
    foreach ($a in $items) {
        $me = $a.Sid -in $UserSid, $AccSelf
        $sub = @($(if ($a.Admin) { 'Administrateur' } else { 'Standard' }), $(if ($a.Ms) { 'compte Microsoft' } elseif ($a.Builtin) { 'compte intégré' } else { 'compte local' }),
            $(if ($a.Last) { 'connexion ' + (Format-TskDate $a.Last) } else { 'jamais connecté' }), $(if (-not $a.Enabled) { 'désactivé' }), $(if ($me) { 'compte en cours' })) | Where-Object { $_ }
        $mb = New-ToolIconButton 0xE712 'Actions' $a { param($s, $e) Show-AccMenu $s }
        $mb.LayoutTransform = [Windows.Media.RotateTransform]::new(90)
        $nm = $(if ($a.Full -and $a.Full -ne $a.Name) { '{0}  ({1})' -f $a.Full, $a.Name } else { $a.Name })
        $row = New-ToolRow $nm ($sub -join '  ·  ') @($mb) $(if ($a.Desc) { $a.Desc } else { $null })
        if (-not $a.Enabled) { $row.Main.Opacity = 0.55 }
        [void]$b.Children.Add($row.Row)
    }
    $btns = @((New-ToolButton 'Créer un compte' $null { New-LocalAccount } 'PrimaryBtn'), (New-ToolButton 'Paramètres des comptes' $null { Start-Process 'ms-settings:otherusers' }), (New-ToolButton 'Actualiser' $null { Start-AccRead }))
    [void]$b.Children.Add((New-ToolBar $btns))
}
function Show-AccMenu($Btn) {
    $a = $Btn.Tag; $me = $a.Sid -in $UserSid, $AccSelf; $lastAdm = $a.Admin -and $a.Enabled -and $ToolsUI.AccAdmins -le 1
    $cm = [Windows.Controls.ContextMenu]::new()
    $add = { param([string]$T, [string]$Op, [bool]$On, [string]$Why)
        $mi = [Windows.Controls.MenuItem]::new(); $mi.Header = $T; $mi.Tag = @{ A = $a; Op = $Op }; $mi.IsEnabled = $On
        if (-not $On -and $Why) { $mi.ToolTip = $Why; [Windows.Controls.ToolTipService]::SetShowOnDisabled($mi, $true) }
        $mi.Add_Click({ param($s, $e) Invoke-AccAction $s.Tag.A $s.Tag.Op }); [void]$cm.Items.Add($mi) }
    $why = $(if ($me) { 'Compte en cours d''utilisation' } elseif ($lastAdm) { 'Dernier administrateur actif du PC' } else { '' })
    if ($a.Admin) { & $add 'Rendre standard' 'std' (-not $me -and -not $lastAdm -and -not ($a.Sid -match '-500$')) $why } else { & $add 'Rendre administrateur' 'adm' $true '' }
    if ($a.Enabled) { & $add 'Désactiver le compte' 'off' (-not $me -and -not $lastAdm) $why } else { & $add 'Activer le compte' 'on' $true '' }
    & $add 'Changer le mot de passe...' 'pwd' (-not $a.Ms) 'Compte Microsoft : mot de passe à changer sur account.microsoft.com'
    [void]$cm.Items.Add([Windows.Controls.Separator]::new())
    & $add 'Supprimer le compte...' 'del' (-not $me -and -not $a.Builtin -and -not $lastAdm) $(if ($a.Builtin) { 'Compte intégré de Windows : à désactiver plutôt' } else { $why })
    $Btn.ContextMenu = $cm; $cm.PlacementTarget = $Btn; $cm.Placement = 'Bottom'; $cm.IsOpen = $true
}
# mot de passe saisi 2 fois (champs masqués) ; renvoie $null si annulé, '' si laissé vide (autorisé seulement si $AllowEmpty)
function Read-AccPassword([string]$Message, [bool]$AllowEmpty, $Extra) {
    $sp = [Windows.Controls.StackPanel]::new(); $pb = @()
    foreach ($l in 'Mot de passe', 'Confirmation') {
        $t = New-Text $l 'Muted'; $t.Margin = New-Thickness 0 6 0 4; [void]$sp.Children.Add($t)
        $p = [Windows.Controls.PasswordBox]::new(); $p.Padding = New-Thickness 8 6 8 6
        $p.SetResourceReference([Windows.Controls.Control]::BackgroundProperty, 'BgBrush'); $p.SetResourceReference([Windows.Controls.Control]::ForegroundProperty, 'FgBrush'); $p.SetResourceReference([Windows.Controls.Control]::BorderBrushProperty, 'LineBrush')
        [void]$sp.Children.Add($p); $pb += $p
    }
    if ($Extra) { foreach ($x in $Extra) { [void]$sp.Children.Add($x) } }
    while ($true) {
        $v = Show-Dialog $Message 'Question' @(@{ T = 'Annuler'; V = 'no'; C = $true }, @{ T = 'Valider'; V = 'ok'; K = 'OkBtn' }) $null $null 520 $sp { param($d, $bp) $d.Tag = $pb[0]; foreach ($c in $bp.Children) { $c.IsDefault = $c.Name -eq 'OkBtn' } }
        if ($sp.Parent) { $sp.Parent.Content = $null }
        if ($v -ne 'ok') { return $null }
        if ($pb[0].Password -ne $pb[1].Password) { Show-Info 'Les 2 saisies sont différentes.' 'Warn'; $pb[0].Clear(); $pb[1].Clear(); continue }
        if (-not $pb[0].Password -and -not $AllowEmpty) { Show-Info 'Mot de passe vide refusé.' 'Warn'; continue }
        return $pb[0].SecurePassword
    }
}
function Invoke-AccAction($A, [string]$Op) {
    $nm = $A.Name
    try {
        Import-Module Microsoft.PowerShell.LocalAccounts -ErrorAction SilentlyContinue
        switch ($Op) {
            'adm' { if (-not (Confirm-Action "Rendre « $nm » administrateur ?`n`nCe compte pourra installer des logiciels et modifier tout le PC.")) { return }; Add-LocalGroupMember -SID 'S-1-5-32-544' -Member (Get-LocalUser -SID $A.Sid) -ErrorAction Stop; $v = 'administrateur' }
            'std' { if (-not (Confirm-Action "Rendre « $nm » utilisateur standard ?`n`nIl ne pourra plus modifier le PC sans les identifiants d'un administrateur.")) { return }
                    Add-LocalGroupMember -SID 'S-1-5-32-545' -Member (Get-LocalUser -SID $A.Sid) -ErrorAction SilentlyContinue
                    Remove-LocalGroupMember -SID 'S-1-5-32-544' -Member (Get-LocalUser -SID $A.Sid) -ErrorAction Stop; $v = 'standard' }
            'off' { if (-not (Confirm-Action "Désactiver le compte « $nm » ?`n`nPlus aucune ouverture de session possible avec ce compte ; ses fichiers sont conservés. Réactivable ici.")) { return }; Disable-LocalUser -SID $A.Sid -ErrorAction Stop; $v = 'désactivé' }
            'on' { if ($A.Builtin -and -not (Confirm-Action "Activer le compte intégré « $nm » ?`n`n" + $(if ($A.Sid -match '-500$') { 'Compte administrateur intégré : définir un mot de passe solide ensuite, il est souvent ciblé.' } else { 'Compte Invité : accès sans mot de passe au PC.' }))) { return }; Enable-LocalUser -SID $A.Sid -ErrorAction Stop; $v = 'activé' }
            'pwd' { $p = Read-AccPassword "Nouveau mot de passe de « $nm »`n`nLaisser vide pour retirer le mot de passe. Attention : les fichiers chiffrés (EFS) et mots de passe enregistrés par Windows pour ce compte deviennent illisibles." $true $null
                    if ($null -eq $p) { return }; Set-LocalUser -SID $A.Sid -Password $p -ErrorAction Stop; $v = 'mot de passe changé' }
            'del' { if ((Show-Dialog "Supprimer le compte « $nm » ?`n`nLe compte est supprimé ; son dossier C:\Users\$nm reste sur le disque (à supprimer ensuite à la main si inutile)." 'Warn' @(@{ T = 'Annuler'; V = $false; C = $true }, @{ T = 'Supprimer'; V = $true; S = 'WarnBtn' })) -ne $true) { return }
                    Remove-LocalUser -SID $A.Sid -ErrorAction Stop; $v = 'supprimé' }
        }
        Write-UiLog "Compte « $nm » : $v." 'OK'; Add-SessionEvent 'Réglages' "Compte $nm" $v 'ok'
    } catch { Write-UiLog "Compte « $nm » : $($_.Exception.Message)" 'ERROR'; Show-Info "Action impossible sur le compte « $nm ».`n`n$($_.Exception.Message)" 'Error' }
    Start-AccRead
}
function New-LocalAccount {
    $n = Read-ToolInput "Créer un compte local`n`nNom d'ouverture de session : 20 caractères au plus, sans / \ [ ] : ; | = , + * ? < > `" @. Mot de passe demandé ensuite (facultatif)." @(@{ L = 'Nom du compte'; V = '' }, @{ L = 'Nom complet (facultatif)'; V = '' }) 'Suivant' 560
    if (-not $n) { return }
    $name = "$($n[0])".Trim(); $full = "$($n[1])".Trim()
    if (-not $name -or $name.Length -gt 20 -or $name -match '[/\\\[\]:;|=,+*?<>"@]' -or $name.Trim('.') -eq '') { Show-Info 'Nom de compte invalide.' 'Warn'; return }
    $ck = [Windows.Controls.CheckBox]::new(); $ck.Content = 'Administrateur du PC'; $ck.Margin = New-Thickness 0 12 0 0; $ck.SetResourceReference([Windows.Controls.Control]::ForegroundProperty, 'FgBrush')
    $p = Read-AccPassword "Mot de passe du compte « $name »`n`nLaisser vide pour un compte sans mot de passe (déconseillé pour un administrateur)." $true @($ck)
    if ($null -eq $p) { return }
    try {
        Import-Module Microsoft.PowerShell.LocalAccounts -ErrorAction SilentlyContinue
        $prm = @{ Name = $name; ErrorAction = 'Stop' }; if ($full) { $prm.FullName = $full }
        if ($p.Length) { $prm.Password = $p; $prm.PasswordNeverExpires = $true } else { $prm.NoPassword = $true }
        $u = New-LocalUser @prm
        Add-LocalGroupMember -SID 'S-1-5-32-545' -Member $u -ErrorAction Stop
        if ($ck.IsChecked) { Add-LocalGroupMember -SID 'S-1-5-32-544' -Member $u -ErrorAction Stop }
        Write-UiLog ('Compte local « {0} » créé ({1}).' -f $name, $(if ($ck.IsChecked) { 'administrateur' } else { 'standard' })) 'OK'; Add-SessionEvent 'Réglages' "Compte $name" 'créé' 'ok'
    } catch { Write-UiLog "Création du compte « $name » : $($_.Exception.Message)" 'ERROR'; Show-Info "Création impossible.`n`n$($_.Exception.Message)" 'Error' }
    Start-AccRead
}

# ================= construction de l'onglet
function New-ToolsCard([string]$Title, [string]$Desc, [int]$Glyph, $Column) {
    $c = New-Card $Title $Desc ([string][char]$Glyph)
    $body = [Windows.Controls.StackPanel]::new(); [void]$c.Body.Children.Add($body)
    [void]$Column.Children.Add($c.Card)
    $body
}
function New-ToolsPage {
    $ToolsUI.Built = $true
    $ToolsUI.LicBody = New-ToolsCard 'Licence Windows' 'Activation, type de licence et clé d''origine du PC' 0xE8D7 $Ui.ToolsLeft
    $ToolsUI.WifiBody = New-ToolsCard 'Réseaux Wi-Fi enregistrés' 'Mots de passe des réseaux déjà utilisés sur ce PC' 0xE701 $Ui.ToolsLeft
    $ToolsUI.HostsBody = New-ToolsCard 'Fichier hosts' 'Blocage des pubs et traqueurs pour tout le PC, noms locaux' 0xE774 $Ui.ToolsLeft
    $ToolsUI.AccBody = New-ToolsCard 'Comptes locaux' 'Comptes du PC, administrateurs, activation, mots de passe' 0xE716 $Ui.ToolsRight
    $ToolsUI.CtxBody = New-ToolsCard 'Menu clic droit de l''Explorateur' 'Entrées ajoutées par les logiciels (Windows 11 : « Afficher plus d''options »)' 0xE8A4 $Ui.ToolsRight
    $ToolsUI.EnvBody = New-ToolsCard 'Variables d''environnement' 'PATH et autres variables, de l''utilisateur et du système' 0xE943 $Ui.ToolsRight
    Update-ToolsPage
}
function Update-ToolsPage {
    if (-not $ToolsUI.Built) { return }
    Start-LicRead $null; Start-WifiRead; Update-HostsCard; Start-AccRead; Start-CtxRead; Update-EnvCard
}
