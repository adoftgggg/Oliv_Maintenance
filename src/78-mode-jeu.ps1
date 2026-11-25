# ---------- Mode jeu : un interrupteur pour les réglages qui comptent en jeu, état précédent restauré à l'arrêt
# Activé : plan Performances optimales (pas sur les postes en veille moderne, où Windows ne prévoit que le plan Équilibré),
# planification GPU accélérée par le matériel (cartes compatibles, effet après redémarrage), accélération de la souris
# coupée (appliquée tout de suite), mode jeu de Windows activé, planificateur multimédia orienté jeu (réseau non bridé,
# priorité processeur / GPU / disque des jeux, après redémarrage), services SysMain et Windows Search suspendus. Valeurs d'avant enregistrées dans mode-jeu.json et
# remises à l'arrêt du mode jeu, à l'identique (valeur absente = supprimée).
# Un seul script ($GameModeScript) pour l'application et pour les raccourcis du Bureau « Mode jeu ON / OFF » : écrit dans
# C:\ProgramData\Oliv_Maintenance\Outils (droits d'écriture réservés aux administrateurs, hors du dossier vidé à chaque
# nouvelle version), lancé par l'application dans sa session, ou par les raccourcis (élévation demandée).
$GameDir = Join-Path $env:ProgramData 'Oliv_Maintenance\Outils'
$GameScriptFile = Join-Path $GameDir 'mode-jeu.ps1'
$GameScript = @'
param([ValidateSet('on', 'off', 'status')][string]$Mode = 'status', [string]$UserRoot = 'HKCU:', [switch]$NoPower, [switch]$NoHags)
$ErrorActionPreference = 'Stop'
$dir = Join-Path $env:ProgramData 'Oliv_Maintenance\Outils'; $sf = Join-Path $dir 'mode-jeu.json'; $cf = Join-Path $dir 'mode-jeu-poste.json'
# capacités du poste relevées par l'application (veille moderne, carte graphique compatible HAGS)
if (Test-Path -LiteralPath $cf) { $cap = Get-Content -LiteralPath $cf -Raw | ConvertFrom-Json; if ($cap.NoPower) { $NoPower = $true }; if ($cap.NoHags) { $NoHags = $true } }
$pk = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes'; $gd = 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'
$ms = "$UserRoot\Control Panel\Mouse"; $gb = "$UserRoot\Software\Microsoft\GameBar"
$pc = "$env:windir\System32\powercfg.exe"
# planificateur multimédia (MMCSS) : bridage réseau pendant les lectures, part du processeur réservée, priorité des jeux
$mm = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'; $mg = "$mm\Tasks\Games"
$svcs = 'SysMain', 'WSearch'
# powercfg : sortie d'erreur jamais transformée en erreur bloquante (Windows PowerShell 5.1 avec $ErrorActionPreference
# = 'Stop' arrêtait tout le script sur le 1er message de powercfg, ex. plan Performances optimales absent sur ce poste) ;
# réussite lue sur le code de retour
function Invoke-Pc([string[]]$A) { $ErrorActionPreference = 'Continue'; & $pc @A 2>&1 | Out-Null; $LASTEXITCODE }
function Get-V($P, $N) { (Get-ItemProperty -LiteralPath $P -Name $N -ErrorAction SilentlyContinue).$N }
function Set-V($P, $N, $V, $T) {
    if ($null -eq $V) { Remove-ItemProperty -LiteralPath $P -Name $N -ErrorAction SilentlyContinue; return }
    if (-not (Test-Path -LiteralPath $P)) { [void](New-Item -Path $P -Force) }
    Set-ItemProperty -LiteralPath $P -Name $N -Value $V -Type $T
}
function Set-Mouse([int]$T1, [int]$T2, [int]$Sp) {
    if (-not ('_OlivM.Mouse' -as [type])) {
        Add-Type -Namespace _OlivMJeu -Name Spi -MemberDefinition '[DllImport("user32.dll")] public static extern bool SystemParametersInfo(uint a, uint p, int[] v, uint f);'
        [void][_OlivMJeu.Spi]::SystemParametersInfo(4, 0, [int[]]@($T1, $T2, $Sp), 2)
    } else { [void][_OlivM.Mouse]::Apply($T1, $T2, $Sp) }
}
$on = Test-Path -LiteralPath $sf
if ($Mode -eq 'status') { return $(if ($on) { 'on' } else { 'off' }) }
if ($Mode -eq 'on') {
    if ($on) { return 'déjà activé' }
    $b = [ordered]@{ Since = (Get-Date).ToString('o'); Plan = "$(Get-V $pk 'ActivePowerScheme')"; HwSchMode = (Get-V $gd 'HwSchMode')
                     MouseSpeed = (Get-V $ms 'MouseSpeed'); MouseThreshold1 = (Get-V $ms 'MouseThreshold1'); MouseThreshold2 = (Get-V $ms 'MouseThreshold2')
                     AutoGameModeEnabled = (Get-V $gb 'AutoGameModeEnabled'); NoPower = [bool]$NoPower; NoHags = [bool]$NoHags
                     NetworkThrottlingIndex = (Get-V $mm 'NetworkThrottlingIndex'); SystemResponsiveness = (Get-V $mm 'SystemResponsiveness')
                     GpuPriority = (Get-V $mg 'GPU Priority'); Priority = (Get-V $mg 'Priority'); SchedCat = (Get-V $mg 'Scheduling Category'); SfioPriority = (Get-V $mg 'SFIO Priority')
                     Stopped = @($svcs | Where-Object { "$((Get-Service -Name $_ -ErrorAction SilentlyContinue).Status)" -eq 'Running' }) }
    [void][IO.Directory]::CreateDirectory($dir)
    ConvertTo-Json -InputObject $b | Set-Content -LiteralPath $sf -Encoding UTF8
    $done = @()
    try {
    if (-not $NoPower) {
        $ok = $false
        foreach ($id in 'e9a42b02-d5df-448d-aa00-03f14749eb61', 'b7a4e9c1-4c53-4a1f-9e2b-0a4d53595302') { if ((Invoke-Pc @('/setactive', $id)) -eq 0) { $ok = $true; break } }
        if (-not $ok) { [void](Invoke-Pc @('/duplicatescheme', 'e9a42b02-d5df-448d-aa00-03f14749eb61', 'b7a4e9c1-4c53-4a1f-9e2b-0a4d53595302')); $ok = (Invoke-Pc @('/setactive', 'b7a4e9c1-4c53-4a1f-9e2b-0a4d53595302')) -eq 0 }
        $done += $(if ($ok) { 'Performances optimales' } else { 'plan d''alimentation inchangé (refusé)' })
    }
    if (-not $NoHags) { Set-V $gd 'HwSchMode' 2 'DWord'; $done += 'planification GPU (après redémarrage)' }
    Set-V $ms 'MouseSpeed' '0' 'String'; Set-V $ms 'MouseThreshold1' '0' 'String'; Set-V $ms 'MouseThreshold2' '0' 'String'; Set-Mouse 0 0 0
    $done += 'accélération de la souris coupée'
    Set-V $gb 'AutoGameModeEnabled' 1 'DWord'; $done += 'mode jeu de Windows'
    Set-V $mm 'NetworkThrottlingIndex' -1 'DWord'; Set-V $mm 'SystemResponsiveness' 10 'DWord'
    Set-V $mg 'GPU Priority' 8 'DWord'; Set-V $mg 'Priority' 6 'DWord'; Set-V $mg 'Scheduling Category' 'High' 'String'; Set-V $mg 'SFIO Priority' 'High' 'String'
    $done += 'priorité aux jeux et réseau non bridé (après redémarrage)'
    $st = @(foreach ($n in $b.Stopped) { try { Stop-Service -Name $n -Force -ErrorAction Stop; $n } catch { $null = $_ } })
    if ($st.Count) { $done += 'services suspendus : ' + ($st -join ', ') }
    } catch {
        # échec en cours d'activation : réglages déjà changés remis à leur valeur d'avant, mode jeu laissé désactivé
        $err = $_.Exception.Message
        try { & $MyInvocation.MyCommand.ScriptBlock -Mode off -UserRoot $UserRoot | Out-Null } catch { Remove-Item -LiteralPath $sf -Force -ErrorAction SilentlyContinue }
        throw "activation impossible ($err) : réglages d'avant restaurés"
    }
    return ('activé : ' + ($done -join ', '))
}
# off : valeurs d'avant remises à l'identique
if (-not $on) { return 'déjà désactivé' }
$b = Get-Content -LiteralPath $sf -Raw | ConvertFrom-Json
if (-not $b.NoPower -and $b.Plan) { [void](Invoke-Pc @('/setactive', $b.Plan)) }
if (-not $b.NoHags) { Set-V $gd 'HwSchMode' $b.HwSchMode 'DWord' }
Set-V $ms 'MouseSpeed' $b.MouseSpeed 'String'; Set-V $ms 'MouseThreshold1' $b.MouseThreshold1 'String'; Set-V $ms 'MouseThreshold2' $b.MouseThreshold2 'String'
$sp = $(if ($null -ne $b.MouseSpeed) { [int]$b.MouseSpeed } else { 1 }); $t1 = $(if ($null -ne $b.MouseThreshold1) { [int]$b.MouseThreshold1 } else { 6 }); $t2 = $(if ($null -ne $b.MouseThreshold2) { [int]$b.MouseThreshold2 } else { 10 })
Set-Mouse $t1 $t2 $sp
Set-V $gb 'AutoGameModeEnabled' $b.AutoGameModeEnabled 'DWord'
if ($b.PSObject.Properties['SystemResponsiveness']) {
    Set-V $mm 'NetworkThrottlingIndex' $b.NetworkThrottlingIndex 'DWord'; Set-V $mm 'SystemResponsiveness' $b.SystemResponsiveness 'DWord'
    Set-V $mg 'GPU Priority' $b.GpuPriority 'DWord'; Set-V $mg 'Priority' $b.Priority 'DWord'; Set-V $mg 'Scheduling Category' $b.SchedCat 'String'; Set-V $mg 'SFIO Priority' $b.SfioPriority 'String'
    foreach ($n in @($b.Stopped)) { try { Start-Service -Name $n -ErrorAction Stop } catch { $null = $_ } }
}
Remove-Item -LiteralPath $sf -Force
'désactivé : réglages d''avant restaurés' + $(if (-not $b.NoHags) { ' (planification GPU après redémarrage)' } else { '' })
'@
$GameUI = @{}
# script et capacités du poste écrits à chaque usage (version du script toujours celle de l'application)
function Write-GameScript {
    [void][IO.Directory]::CreateDirectory($GameDir)
    [IO.File]::WriteAllText($GameScriptFile, $GameScript, [Text.UTF8Encoding]::new($true))
    $cap = @{ NoPower = -not (Test-Need 'ClassicPower'); NoHags = -not (Test-Need 'Hags') }
    [IO.File]::WriteAllText((Join-Path $GameDir 'mode-jeu-poste.json'), (ConvertTo-Json -InputObject $cap), [Text.UTF8Encoding]::new($false))
    $cap
}
function Get-GameModeOn { Test-Path -LiteralPath (Join-Path $GameDir 'mode-jeu.json') }
function Switch-GameMode {
    $want = $(if (Get-GameModeOn) { 'off' } else { 'on' })
    try {
        [void](Write-GameScript)
        $root = $(if ($HkuSidOk) { "Registry::HKEY_USERS\$UserSid" } else { 'HKCU:' })
        $res = & ([scriptblock]::Create($GameScript)) -Mode $want -UserRoot $root
        Write-UiLog "Mode jeu $res." 'OK'
        Add-SessionEvent 'Réglages' 'Mode jeu' "$res" 'ok'
    } catch { Write-UiLog "Mode jeu : $($_.Exception.Message)" 'ERROR' }
    # lignes des réglages concernés relues (plan, HAGS, souris, mode jeu de Windows), badges « redémarrage requis »
    foreach ($r in @($TweakRows | Where-Object { $_.Tweak -and $_.Tweak.Id -in 'PowerPlan', 'Hags', 'MousePrecision', 'GameModeWin' })) {
        try { $v = Get-TweakValue $r.Tweak; if ("$v" -ne "$($r.Current)") { Complete-TweakChange $r $v $v } } catch { Write-Ignored 'Mode jeu (lecture des réglages)' $_ }
    }
    # référence des réglages : changements du mode jeu voulus par l'utilisateur, jamais signalés comme modifiés hors de l'application
    try { Update-TweakReference $GameTweakIds } catch { Write-Ignored 'Réglages de référence' $_ }
    Update-PendingBar
    Update-GameCard
}
function Update-GameCard {
    if (-not $GameUI.Btn) { return }
    $on = Get-GameModeOn
    $GameUI.Btn.Content = $(if ($on) { 'Désactiver le mode jeu' } else { 'Activer le mode jeu' })
    $GameUI.Btn.Style = $Window.FindResource($(if ($on) { 'WarnBtn' } else { 'PrimaryBtn' }))
    $since = ''
    if ($on) { try { $since = ' depuis le {0:dd/MM à HH:mm}' -f [DateTime]::Parse((Get-Content -LiteralPath (Join-Path $GameDir 'mode-jeu.json') -Raw | ConvertFrom-Json).Since) } catch { $since = '' } }
    $GameUI.State.Text = $(if ($on) { "Activé$since" } else { 'Désactivé' })
    $GameUI.State.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, $(if ($on) { 'OkFgBrush' } else { 'MutedBrush' }))
}
function New-GameCard {
    $c = New-Card 'Mode jeu' '' ([string][char]0xE7FC)
    $g = [Windows.Controls.Grid]::new(); $g.Margin = New-Thickness 46 0 18 6
    foreach ($w in '*', 'Auto') { $cd = [Windows.Controls.ColumnDefinition]::new(); $cd.Width = $(if ($w -eq '*') { [Windows.GridLength]::new(1, 'Star') } else { [Windows.GridLength]::Auto }); [void]$g.ColumnDefinitions.Add($cd) }
    $sp = [Windows.Controls.StackPanel]::new()
    $GameUI.State = New-Text ''; $GameUI.State.FontSize = 15; $GameUI.State.FontWeight = [Windows.FontWeights]::SemiBold
    [void]$sp.Children.Add($GameUI.State)
    $items = @()
    $items += $(if (Test-Need 'ClassicPower') { 'Plan Performances optimales' } else { 'Plan d''alimentation : inchangé (veille moderne, Équilibré seul prévu)' })
    $items += $(if (Test-Need 'Hags') { 'Planification GPU accélérée par le matériel (après redémarrage)' } else { 'Planification GPU : non prise en charge par la carte graphique' })
    $items += 'Accélération de la souris coupée (tout de suite)'
    $items += 'Mode jeu de Windows activé'
    $items += 'Priorité processeur, GPU et disque aux jeux, réseau non bridé (après redémarrage)'
    $items += 'SysMain et Windows Search suspendus, relancés à l''arrêt'
    foreach ($it in $items) { $t = New-Text ([string][char]0x2022 + '  ' + $it) 'Muted'; $t.Margin = New-Thickness 0 3 0 0; [void]$sp.Children.Add($t) }
    $t = New-Text 'À l''arrêt, chaque réglage revient exactement à sa valeur d''avant.' 'Muted'; $t.Margin = New-Thickness 0 8 0 0; $t.FontStyle = [Windows.FontStyles]::Italic; [void]$sp.Children.Add($t)
    [void]$g.Children.Add($sp)
    $bp = [Windows.Controls.StackPanel]::new(); $bp.VerticalAlignment = 'Center'; [Windows.Controls.Grid]::SetColumn($bp, 1)
    $GameUI.Btn = New-Button 'Activer le mode jeu' 'PrimaryBtn'; $GameUI.Btn.MinWidth = 190; $GameUI.Btn.Height = 36
    $GameUI.Btn.Add_Click({ Switch-GameMode })
    $lnk = New-Button 'Raccourcis sur le Bureau'; $lnk.MinWidth = 190; $lnk.Height = 30; $lnk.Margin = New-Thickness 0 8 0 0
    $lnk.ToolTip = 'Crée « Mode jeu ON » et « Mode jeu OFF » sur le Bureau : bascule sans ouvrir l''application (élévation demandée)'
    $lnk.Add_Click({ New-GameShortcut })
    [void]$bp.Children.Add($GameUI.Btn); [void]$bp.Children.Add($lnk); [void]$g.Children.Add($bp)
    [void]$c.Body.Children.Add($g); Add-Spacer $c.Body
    [void]$Ui.PerfLeft.Children.Insert(0, $c.Card)
    Update-GameCard
}
# raccourcis du Bureau de l'utilisateur ciblé : PowerShell masqué sur le script, « exécuter en tant qu'administrateur »
# (octet 0x15 du fichier .lnk, bit 0x20 : SLDF_RUNAS_USER), icône de l'application
function New-GameShortcut {
    try {
        [void](Write-GameScript)
        $ico = Join-Path $GameDir 'oliv_maintenance.ico'; [IO.File]::WriteAllBytes($ico, [Convert]::FromBase64String($LogoIcoB64))
        $dk = "$(Get-RegValue 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders' 'Desktop')"
        $desk = $(if ($dk) { $dk -replace '(?i)%USERPROFILE%', $UserProfilePath } else { Join-Path $UserProfilePath 'Desktop' })
        $desk = [Environment]::ExpandEnvironmentVariables($desk)
        $sh = New-Object -ComObject WScript.Shell
        foreach ($m in 'on', 'off') {
            $f = Join-Path $desk ('Mode jeu {0}.lnk' -f $m.ToUpper())
            $l = $sh.CreateShortcut($f)
            $l.TargetPath = "$env:windir\System32\WindowsPowerShell\v1.0\powershell.exe"
            $l.Arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -Mode {1}' -f $GameScriptFile, $m
            $l.IconLocation = "$ico,0"; $l.Description = $(if ($m -eq 'on') { 'Oliv_Maintenance : activer le mode jeu' } else { 'Oliv_Maintenance : désactiver le mode jeu' })
            $l.WindowStyle = 7; $l.Save()
            $by = [IO.File]::ReadAllBytes($f); $by[0x15] = $by[0x15] -bor 0x20; [IO.File]::WriteAllBytes($f, $by)
        }
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($sh)
        Write-UiLog "Mode jeu : raccourcis « Mode jeu ON » et « Mode jeu OFF » créés sur le Bureau ($desk)." 'OK'
        Show-Info "Raccourcis créés sur le Bureau : « Mode jeu ON » et « Mode jeu OFF ».`n`nWindows demande l'élévation à chaque utilisation (réglages du poste)." 'Ok'
    } catch { Write-UiLog "Mode jeu, raccourcis : $($_.Exception.Message)" 'ERROR' }
}
