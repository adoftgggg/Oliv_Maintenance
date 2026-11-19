function Start-DiagCollector {
    Close-BgJob
    if ($Sync.DiagRunning -or $BgJobs.ContainsKey('Diag')) { return }
    $Sync.DiagRunning = $true
    Start-BgJob 'Diag' $DiagScript
}
# Ancienneté affichée : « à l'instant », « il y a N min », puis l'heure précise au-delà d'une heure
function Format-Age($T) {
    $m = [int][math]::Floor(([DateTime]::Now - $T).TotalMinutes)
    if ($m -lt 1) {
        'à l''instant'
    } elseif ($m -lt 60) {
        "il y a $m min"
    } elseif ($T.Date -eq [DateTime]::Today) {
        'à {0:HH:mm}' -f $T
    } else {
        'le {0:dd/MM} à {0:HH:mm}' -f $T
    }
}
function Update-WuAge {
    if (-not $InfoUI.WuAge) { return }
    Update-WuButton
    $w = $Sync.WuPending
    if ($Sync.WuSearching) {
        $InfoUI.WuAge.Text = $(if ($Sync.WuCancel) { 'arrêt de la recherche...' } elseif ($Sync.WuOnline) { 'recherche en ligne...' } else { 'lecture...' })
        return
    }
    if ($w -and $w.OwnScan -and $w.OwnScan -ne $Sync.WuOwnLast) {
        $Sync.WuOwnLast = $w.OwnScan
        try {
            [IO.File]::WriteAllText($WuScanFile, $w.OwnScan.ToString('o'))
        } catch {
            Write-Ignored 'Enregistrement de la dernière recherche Windows Update' $_
        }
        $sum = 'Recherche Windows Update en ligne : {0} disponible(s), {1} en attente de redémarrage ({2}).' -f @($w.Items).Count, @($w.Reboot).Count, $w.Detail
        Write-UiLog $sum
        # journal de la carte : Accueil\Mises a jour Windows, un fichier par mois avec le détail des KB
        $lines = @($sum) + @($w.Items | ForEach-Object { '   en attente : {0}' -f $_.Title }) + @($w.Reboot | ForEach-Object { '   installée, redémarrage requis : {0}' -f $_.Title })
        $cf = Join-Path (Get-LogPath 'AccueilWu') ('{0}_recherches_{1:yyyy-MM}.log' -f $env:COMPUTERNAME, (Get-Date))
        try {
            [IO.File]::AppendAllText($cf, (($lines | ForEach-Object { '{0:yyyy-MM-dd HH:mm:ss} {1}' -f (Get-Date), $_ }) -join [Environment]::NewLine) + [Environment]::NewLine, [Text.Encoding]::UTF8)
        } catch {
            Write-Ignored 'Journal des recherches Windows Update' $_
        }
    }
    $last = @($w.LastScan, $Sync.WuOwnLast) | Where-Object { $_ } | Sort-Object -Descending | Select-Object -First 1
    if ($last) {
        $InfoUI.WuAge.Text = 'dernière recherche : ' + (Format-Age $last)
        $InfoUI.WuAge.ToolTip = 'Dernière recherche Windows Update : {0:dd/MM/yyyy HH:mm:ss}' -f $last
    } else { $InfoUI.WuAge.Text = '' }
}
function Update-DiagAge {
    if (-not $InfoUI.DiagAge) { return }
    $d = $Sync.Diag
    if ($Sync.DiagRunning) { $InfoUI.DiagAge.Text = 'actualisation...'; return }
    if (-not $d) { $InfoUI.DiagAge.Text = ''; return }
    $InfoUI.DiagAge.Text = Format-Age $d.Stamp
    $InfoUI.DiagAge.ToolTip = 'Dernière actualisation : {0:dd/MM/yyyy HH:mm:ss}' -f $d.Stamp
}
function Show-DiagResult($D) {
    $InfoUI.DiagPanel.Children.Clear()
    foreach ($it in $D.Items) {
        if ($it.K -eq 'Clé de récupération' -and $it.V -match '^\d{6}(-\d{6}){7}$') { Add-RecoveryKeyRow $it.V }
        else {
            $v = Add-KV $InfoUI.DiagPanel $it.K $it.V $it.B; if ($it.T) { $v.ToolTip = $it.T }
            if ("$($it.X)" -like 'av:*') { Add-AvScanMenu $v "$($it.X)".Substring(3) }
            elseif ($it.X) { Add-BitLockerMenu $v "$($it.X)" }
        }
    }
    Update-DiagAge
}

# ---------- Clé de récupération BitLocker : blocs 3 à 6 masqués, affichage après authentification administrateur ----------
function Get-MaskedKey([string]$K) {
    $b = $K -split '-'
    if ($b.Count -ne 8) { return $K }
    (@($b[0], $b[1]) + @('XXXXXX') * 4 + @($b[6], $b[7])) -join '-'
}
function Add-RecoveryKeyRow([string]$Key) {
    $v = Add-KV $InfoUI.DiagPanel 'Clé de récupération' (Get-MaskedKey $Key)
    $g = $v.Parent
    $v.VerticalAlignment = 'Center'; $g.Children[0].VerticalAlignment = 'Center'; $v.FontFamily = [Windows.Media.FontFamily]::new('Consolas')
    $col = Add-AutoColumn $g
    $b = New-Button 'Afficher'; $b.Height = 26; $b.MinWidth = 84; $b.Margin = New-Thickness 8 0 0 0; $b.VerticalAlignment = 'Center'
    $b.Tag = @{ Box = $v; Key = $Key; Shown = $false }
    $b.Add_Click($KeyRevealClick)
    [Windows.Controls.Grid]::SetColumn($b, $col); [void]$g.Children.Add($b)
}
$KeyRevealClick = {
    param($s, $e)
    $t = $s.Tag
    if ($t.Shown) { $t.Box.Text = Get-MaskedKey $t.Key; $t.Shown = $false; $s.Content = 'Afficher'; return }
    $acc = Request-AdminAuth 'Afficher la clé de récupération BitLocker'
    if (-not $acc) { return }
    $t.Box.Text = $t.Key; $t.Shown = $true; $s.Content = 'Masquer'
    Write-UiLog ("Clé de récupération BitLocker affichée (authentification : $acc)." ) 'WARN'
    # masquage automatique au bout de 20 secondes
    $tm = [Windows.Threading.DispatcherTimer]::new(); $tm.Interval = [TimeSpan]::FromSeconds(20); $tm.Tag = $s
    $tm.Add_Tick({ param($x, $y)
        $x.Stop()
        $b = $x.Tag
        if ($b.Tag.Shown) { $b.Tag.Box.Text = Get-MaskedKey $b.Tag.Key; $b.Tag.Shown = $false; $b.Content = 'Afficher' }
    })
    $tm.Start()
}
# Vérification d'un compte administrateur : ouverture de session réseau (sinon interactive) avec LogonUser,
# puis présence du SID Administrateurs (S-1-5-32-544) dans le jeton, y compris en « refus seul » (jeton filtré par l'UAC).
function Test-AdminCredential([string]$User, [string]$Pass) {
    if ($User -match '^(.+?)\\(.+)$') {
        $dom = $Matches[1]
        $u = $Matches[2]
    } elseif ($User -like '*@*') {
        $dom = $null
        $u = $User
    } else {
        $dom = '.'
        $u = $User
    }
    if ($dom -eq '.' -or $dom -eq $env:COMPUTERNAME) { $dom = '.' }
    $tok = [IntPtr]::Zero
    $ok = [_OlivM.Auth]::LogonUserW($u, $dom, $Pass, 3, 0, [ref]$tok)
    if (-not $ok) { $ok = [_OlivM.Auth]::LogonUserW($u, $dom, $Pass, 2, 0, [ref]$tok) }
    if (-not $ok) { return @{ Ok = $false; Msg = 'Identifiants refusés.' } }
    try {
        $id = [Security.Principal.WindowsIdentity]::new($tok)
        $adm = @($id.Claims | Where-Object { $_.Value -eq 'S-1-5-32-544' }).Count -gt 0
        if (-not $adm) { return @{ Ok = $false; Msg = "Le compte $($id.Name) n'est pas administrateur de ce poste." } }
        @{ Ok = $true; Account = $id.Name }
    } finally { [void][_OlivM.Auth]::CloseHandle($tok) }
}

# ---------- BitLocker du volume système : menu « ... » de la ligne du diagnostic rapide ----------
# Activer : protecteur TPM + mot de passe de récupération numérique, espace utilisé seul, sans test matériel (chiffrement
# en arrière-plan dès maintenant), clé sauvegardée dans Entra ID / Active Directory si le poste y est joint.
# Désactiver : déchiffrement complet en arrière-plan, après confirmation et authentification administrateur (comme
# l'affichage de la clé). Reprendre : protection suspendue (mise à jour du BIOS...) réactivée. Opérations dans une tâche
# de fond (module BitLocker, CIM), diagnostic relancé à la fin.
function Add-BitLockerMenu($V, [string]$State) {
    $InfoUI.BlValue = $V
    if ($State -in 'encrypting', 'decrypting') { Start-BlWatch }
    $g = $V.Parent
    $V.VerticalAlignment = 'Center'; $g.Children[0].VerticalAlignment = 'Center'
    $col = Add-AutoColumn $g
    $b = [Windows.Controls.Button]::new(); $b.Style = $Window.FindResource('IconBtn')
    $b.Content = [string][char]0xE712; $b.Width = 30; $b.Height = 26; $b.Margin = New-Thickness 6 0 0 0; $b.VerticalAlignment = 'Center'
    $b.LayoutTransform = [Windows.Media.RotateTransform]::new(90); $b.ToolTip = 'Actions BitLocker'
    $cm = [Windows.Controls.ContextMenu]::new()
    $busy = $State -in 'encrypting', 'decrypting' -or $BgJobs.ContainsKey('BitLocker')
    $add = { param([string]$T, [string]$A, [bool]$On) $mi = [Windows.Controls.MenuItem]::new(); $mi.Header = $T; $mi.Tag = $A; $mi.IsEnabled = $On -and -not $busy; $mi.Add_Click({ param($s, $e) Invoke-BitLockerAction "$($s.Tag)" }); [void]$cm.Items.Add($mi) }
    if ($busy) { $mi = [Windows.Controls.MenuItem]::new(); $mi.Header = $(if ($State -eq 'encrypting') { 'Chiffrement en cours' } elseif ($State -eq 'decrypting') { 'Déchiffrement en cours' } else { 'Opération BitLocker en cours' }); $mi.IsEnabled = $false; [void]$cm.Items.Add($mi) }
    & $add 'Activer BitLocker...' 'enable' ($State -eq 'off')
    if ($State -eq 'suspended') { & $add 'Reprendre la protection' 'resume' $true }
    & $add 'Désactiver BitLocker...' 'disable' ($State -in 'on', 'suspended')
    $b.ContextMenu = $cm
    $b.Add_Click({ param($s, $e) $s.ContextMenu.PlacementTarget = $s; $s.ContextMenu.Placement = 'Bottom'; $s.ContextMenu.IsOpen = $true })
    [Windows.Controls.Grid]::SetColumn($b, $col); [void]$g.Children.Add($b)
}
function Invoke-BitLockerAction([string]$Action) {
    if ($BgJobs.ContainsKey('BitLocker')) { return }
    $vol = $env:SystemDrive
    switch ($Action) {
        'enable' {
            $msg = "Activer BitLocker sur $vol ?`n`nChiffrement de l'espace utilisé du volume, en arrière-plan (le poste reste utilisable), avec la puce TPM et une clé de récupération numérique.`n`n" +
                   'Notez la clé de récupération, affichée ensuite dans le diagnostic rapide : sans elle, les données sont perdues après un changement de carte mère, de TPM ou certains réglages du BIOS. Elle est aussi sauvegardée dans Entra ID ou Active Directory si le poste y est joint.'
            if ((Show-Dialog $msg 'Warn' @(@{ T = 'Annuler'; V = $false; D = $true; C = $true }, @{ T = 'Activer'; V = $true; S = 'WarnBtn' })) -ne $true) { return }
        }
        'disable' {
            $msg = "Désactiver BitLocker sur $vol ?`n`nLe volume est entièrement déchiffré en arrière-plan (de quelques minutes à plus d'une heure selon le disque). Les données ne sont plus protégées en cas de perte ou de vol du poste."
            if ((Show-Dialog $msg 'Warn' @(@{ T = 'Annuler'; V = $false; D = $true; C = $true }, @{ T = 'Désactiver'; V = $true; S = 'WarnBtn' })) -ne $true) { return }
            $acc = Request-AdminAuth 'Désactiver BitLocker'
            if (-not $acc) { return }
            Write-UiLog "BitLocker : désactivation demandée (authentification : $acc)." 'WARN'
        }
        'resume' { }
        default { return }
    }
    $Sync.BlAction = $Action; $Sync.BlVolume = $vol; $Sync.BlResult = $null
    Write-UiLog ('BitLocker ({0}) : {1}...' -f $vol, @{ enable = 'activation'; disable = 'désactivation'; resume = 'reprise de la protection' }[$Action]) 'APP'
    Start-BgJob 'BitLocker' $BitLockerScript
}
$BitLockerScript = @'
$vol = $Sync.BlVolume; $r = @{ Ok = $false; Msg = ''; Backup = '' }
try {
    Import-Module BitLocker -ErrorAction Stop
    switch ($Sync.BlAction) {
        'enable' {
            $tpm = Get-Tpm -ErrorAction Stop
            if (-not ($tpm.TpmPresent -and $tpm.TpmReady)) { throw 'puce TPM absente ou non prête (activer le TPM dans le BIOS / UEFI).' }
            [void](Enable-BitLocker -MountPoint $vol -TpmProtector -UsedSpaceOnly -SkipHardwareTest -ErrorAction Stop)
            [void](Add-BitLockerKeyProtector -MountPoint $vol -RecoveryPasswordProtector -WarningAction SilentlyContinue -ErrorAction Stop)
            $kp = @((Get-BitLockerVolume -MountPoint $vol -ErrorAction Stop).KeyProtector | Where-Object { "$($_.KeyProtectorType)" -eq 'RecoveryPassword' })
            # sauvegarde de la clé : Entra ID (poste joint) puis Active Directory (domaine), chacune tentée si possible
            $bk = @()
            foreach ($k in $kp) {
                try { [void](BackupToAAD-BitLockerKeyProtector -MountPoint $vol -KeyProtectorId $k.KeyProtectorId -ErrorAction Stop); $bk += 'Entra ID' } catch {}
                if ((Get-CimInstance Win32_ComputerSystem -Property PartOfDomain -ErrorAction SilentlyContinue).PartOfDomain) {
                    try { [void](Backup-BitLockerKeyProtector -MountPoint $vol -KeyProtectorId $k.KeyProtectorId -ErrorAction Stop); $bk += 'Active Directory' } catch {}
                }
            }
            $r.Backup = (@($bk | Select-Object -Unique) -join ' + ')
            $r.Ok = $true; $r.Msg = 'activé, chiffrement en cours en arrière-plan'
        }
        'disable' { [void](Disable-BitLocker -MountPoint $vol -ErrorAction Stop); $r.Ok = $true; $r.Msg = 'désactivé, déchiffrement en cours en arrière-plan' }
        'resume'  { [void](Resume-BitLocker -MountPoint $vol -ErrorAction Stop); $r.Ok = $true; $r.Msg = 'protection reprise' }
    }
} catch { $r.Msg = $_.Exception.Message }
$Sync.BlResult = $r
'@
$BgJobDone['BitLocker'] = {
    $r = $Sync.BlResult; $vol = $Sync.BlVolume
    if ($r -and $r.Ok) {
        Write-UiLog ('BitLocker ({0}) : {1}.' -f $vol, $r.Msg) 'OK'
        if ($Sync.BlAction -eq 'enable') {
            Write-UiLog $(if ($r.Backup) { "Clé de récupération sauvegardée dans : $($r.Backup)." } else { 'Clé de récupération non sauvegardée hors du poste (ni Entra ID ni Active Directory) : la noter depuis le diagnostic rapide (Afficher).' }) $(if ($r.Backup) { 'OK' } else { 'WARN' })
        }
        Add-SessionEvent 'Sécurité' "BitLocker ($vol)" $r.Msg 'ok'
        if ($Sync.BlAction -in 'enable', 'disable') { Start-BlWatch }
    } else {
        $m = $(if ($r) { $r.Msg } else { 'tâche interrompue' })
        Write-UiLog ('BitLocker ({0}) : échec - {1}' -f $vol, $m) 'ERROR'
        [void](Show-Dialog ("BitLocker ($vol) : échec.`n`n$m") 'Error')
    }
    Start-DiagCollector
}

# ---------- Analyse antivirus : clic sur la ligne Antivirus du diagnostic rapide ----------
# Antivirus principal détecté par la collecte :
#  - Microsoft Defender (mode Normal) : Start-MpScan QuickScan / FullScan, menaces détectées pendant l'analyse relues
#    ensuite (Get-MpThreatDetection) ;
#  - Sophos Intercept X / Sophos Endpoint : outil en ligne de commande installé avec l'agent
#    (Program Files\Sophos\Endpoint Defense\SophosInterceptXCLI.exe scan --system --quick|--full --noui --json),
#    exécuté avec les droits système ; codes de retour 0 aucune menace, 3 menace, 4 à 7 fichiers non analysés, 1-2 erreur
#    (documentation Sophos « Scan from the command line »). Détections remontées aussi dans Sophos Central.
#  - autre antivirus tiers : pas de commande d'analyse connue, menu informatif.
# Analyse dans une tâche de fond, un seul lancement à la fois.
$SophosCli = Join-Path $env:ProgramFiles 'Sophos\Endpoint Defense\SophosInterceptXCLI.exe'
function Add-AvScanMenu($V, [string]$Main) {
    $g = $V.Parent
    $cm = [Windows.Controls.ContextMenu]::new()
    $eng = $(if ($Main -eq 'defender') { 'Defender' } elseif ($Main -match '(?i)^other:.*sophos' -and (Test-Path -LiteralPath $SophosCli)) { 'Sophos' } else { '' })
    $name = $(if ($eng -eq 'Defender') { 'Microsoft Defender' } elseif ($eng -eq 'Sophos') { 'Sophos' } else { $Main -replace '^other:', '' })
    if ($eng) {
        $busy = $BgJobs.ContainsKey('AvScan')
        if ($busy) { $mi = [Windows.Controls.MenuItem]::new(); $mi.Header = "Analyse $($Sync.AvScanLabel) $($Sync.AvScanName) en cours"; $mi.IsEnabled = $false; [void]$cm.Items.Add($mi) }
        foreach ($o in @(@('Quick', 'Analyse rapide'), @('Full', 'Analyse complète'))) {
            $mi = [Windows.Controls.MenuItem]::new(); $mi.Header = "$($o[1]) ($name)"; $mi.Tag = @{ Eng = $eng; Type = $o[0]; Name = $name }; $mi.IsEnabled = -not $busy
            $mi.Add_Click({ param($s, $e) Start-AvScan $s.Tag.Eng $s.Tag.Type $s.Tag.Name }); [void]$cm.Items.Add($mi)
        }
        $g.ToolTip = "Clic : lancer une analyse $name"
    } else {
        $mi = [Windows.Controls.MenuItem]::new(); $mi.Header = $(if ($Main -match '(?i)sophos') { "Analyse impossible : $SophosCli introuvable" } else { "Analyse à lancer depuis la console de $name" }); $mi.IsEnabled = $false; [void]$cm.Items.Add($mi)
        $g.ToolTip = "Antivirus principal : $name"
    }
    # libellé « Antivirus » en lien (couleur d'accent, souligné, chevron) : ligne cliquable visible sans survol. Libellé
    # d'origine (TextBox, lu par la copie de la carte) masqué ; textes de la ligne transparents aux clics (une TextBox
    # garde le clic pour la sélection, le menu ne s'ouvrait pas)
    $k = $g.Children[0]; $k.Visibility = 'Collapsed'
    $sp = [Windows.Controls.StackPanel]::new(); $sp.Orientation = 'Horizontal'; $sp.VerticalAlignment = 'Top'; $sp.Margin = New-Thickness 0 0 12 0
    $t = New-Text "$($k.Text)"; $t.FontSize = 13; $t.FontWeight = [Windows.FontWeights]::SemiBold; $t.TextDecorations = [Windows.TextDecorations]::Underline
    $t.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'AccentBrush')
    $ch = New-Text ([string][char]0xE70D); $ch.FontFamily = [Windows.Media.FontFamily]::new('Segoe MDL2 Assets'); $ch.FontSize = 10; $ch.Margin = New-Thickness 6 4 0 0
    $ch.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'AccentBrush')
    [void]$sp.Children.Add($t); [void]$sp.Children.Add($ch)
    [Windows.Controls.Grid]::SetColumn($sp, 0); [void]$g.Children.Add($sp)
    $V.IsHitTestVisible = $false; $sp.IsHitTestVisible = $false
    $g.Background = [Windows.Media.Brushes]::Transparent; $g.Cursor = [Windows.Input.Cursors]::Hand; $g.ContextMenu = $cm
    $g.Add_MouseLeftButtonUp({ param($s, $e) $s.ContextMenu.PlacementTarget = $s; $s.ContextMenu.Placement = 'Bottom'; $s.ContextMenu.IsOpen = $true })
}
function Start-AvScan([string]$Engine, [string]$Type, [string]$Name) {
    if ($BgJobs.ContainsKey('AvScan')) { return }
    $lbl = $(if ($Type -eq 'Full') { 'complète' } else { 'rapide' })
    if ($Type -eq 'Full' -and -not (Confirm-Action "Lancer une analyse complète $Name ?`n`nTous les fichiers du poste sont analysés : de plusieurs dizaines de minutes à plusieurs heures, disque et processeur fortement sollicités pendant l'analyse.")) { return }
    $Sync.AvScan = @{ Engine = $Engine; Type = $Type; Cli = $SophosCli }
    $Sync.AvScanLabel = $lbl; $Sync.AvScanName = $Name; $Sync.AvScanResult = $null; $Sync.AvScanStart = [DateTime]::Now
    Write-UiLog "$Name : analyse $lbl lancée." 'APP'
    Start-BgJob 'AvScan' $AvScanScript
    Start-AvActivity
}
$AvScanScript = @'
$a = $Sync.AvScan; $r = @{ Ok = $false; Msg = ''; Threats = @(); Warn = '' }
try {
    $t0 = [DateTime]::Now
    if ($a.Engine -eq 'Defender') {
        Start-MpScan -ScanType $(if ($a.Type -eq 'Full') { 'FullScan' } else { 'QuickScan' }) -ErrorAction Stop
        $r.Threats = @(Get-MpThreatDetection -ErrorAction SilentlyContinue | Where-Object { $_.InitialDetectionTime -ge $t0.AddMinutes(-1) } | ForEach-Object {
            $id = $_.ThreatID; $n = "$((Get-MpThreat -ThreatID $id -ErrorAction SilentlyContinue).ThreatName)"
            '{0}{1}' -f $(if ($n) { $n } else { "menace $id" }), $(if ($_.Resources) { ' : ' + (@($_.Resources)[0] -replace '^file:_', '') } else { '' }) })
        $r.Ok = $true
    } else {
        $out = & $a.Cli scan --system $(if ($a.Type -eq 'Full') { '--full' } else { '--quick' }) --noui --json 2>&1 | Out-String
        $rc = $LASTEXITCODE
        if ($rc -in 1, 2) { throw ('SophosInterceptXCLI : code {0} ({1}) - {2}' -f $rc, $(if ($rc -eq 1) { 'erreur de commande' } else { 'erreur au démarrage de l''outil' }), $out.Trim()) }
        # résumé JSON d'une analyse système : { type, summary } ; détail des détections dans la console Sophos / Sophos Central
        $sum = ''
        try { $j = $out.Substring($out.IndexOf('{')) | ConvertFrom-Json; $sum = (@($j.summary.PSObject.Properties | ForEach-Object { '{0} : {1}' -f $_.Name, (ConvertTo-Json -Compress -InputObject $_.Value) })) -join ', ' } catch { $sum = $out.Trim() }
        if ($rc -eq 3) { $r.Threats = @('Menace(s) détectée(s) par Sophos - ' + $sum) }
        elseif ($rc -ge 4) { $r.Warn = "analyse terminée, certains fichiers non analysés (code $rc : " + @{ 4 = 'erreur d''analyse'; 5 = 'fichiers chiffrés'; 6 = 'formats non pris en charge'; 7 = 'fichiers inaccessibles' }[[int]$rc] + ')' }
        $r.Summary = $sum
        $r.Ok = $true
    }
} catch { $r.Msg = $_.Exception.Message }
$Sync.AvScanResult = $r
'@
$BgJobDone['AvScan'] = {
    $r = $Sync.AvScanResult; $lbl = $Sync.AvScanLabel; $nm = $Sync.AvScanName
    $dur = [DateTime]::Now - $Sync.AvScanStart
    Remove-BgActivity 'AvScan'
    if ($Sync.AvCancel) {
        $Sync.AvCancel = $false
        Write-UiLog ('{0} : analyse {1} interrompue après {2:hh\:mm\:ss}.' -f $nm, $lbl, $dur) 'WARN'; Add-SessionEvent 'Sécurité' "Analyse $lbl $nm" 'interrompue' 'warn'
        Start-DiagCollector; return
    }
    $where = $(if ($nm -eq 'Sophos') { 'console Sophos Endpoint sur le poste ou Sophos Central' } else { 'Sécurité Windows > Protection contre les virus et menaces > Historique de protection' })
    if ($r -and $r.Ok) {
        $n = @($r.Threats).Count
        if ($r.Summary) { Write-UiLog "$nm : résumé de l'analyse - $($r.Summary)" 'APP' }
        if ($n) {
            Write-UiLog ('{0} : analyse {1} terminée ({2:hh\:mm\:ss}), menace(s) détectée(s).' -f $nm, $lbl, $dur) 'WARN'
            [void](Show-Dialog ("Analyse $lbl ${nm} : menace(s) détectée(s).`n`nTraitement et détail : $where.") 'Warn' $null @($r.Threats))
        } else {
            Write-UiLog ('{0} : analyse {1} terminée ({2:hh\:mm\:ss}), aucune menace détectée{3}.' -f $nm, $lbl, $dur, $(if ($r.Warn) { " - $($r.Warn)" } else { '' })) $(if ($r.Warn) { 'WARN' } else { 'OK' })
            Send-AppNotification "Analyse $lbl terminée" "${nm} : aucune menace détectée." 'Info' $dur
        }
        Add-SessionEvent 'Sécurité' "Analyse $lbl $nm" $(if ($n) { 'menace(s) détectée(s)' } else { 'aucune menace' }) $(if ($n) { 'warn' } else { 'ok' })
    } else {
        $m = $(if ($r) { $r.Msg } else { 'tâche interrompue' })
        Write-UiLog "${nm} : analyse $lbl en échec - $m" 'ERROR'
        [void](Show-Dialog "Analyse $lbl ${nm} : échec.`n`n$m" 'Error')
    }
    Start-DiagCollector
}
