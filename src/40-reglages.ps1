function Get-TweakState($Tw) {
    if ($Tw.Get) { return [bool](& $Tw.Get) }
    $r = $Tw.Reg[0]
    if ($r.T -eq 'Key') { return (Test-RegKey $r.P) }
    $cur = Get-RegValue $r.P $r.N
    if ($null -eq $cur) { $cur = $r.D }
    $onv = if ($null -eq $r.On) { $r.D } else { $r.On }
    return ("$cur" -eq "$onv")
}
function Set-TweakState($Tw, [bool]$On) {
    if ($Tw.Set) { & $Tw.Set $On; return }
    foreach ($r in $Tw.Reg) {
        if ($r.T -eq 'Key') {
            if ($On) { Set-RegValue $r.P '' '' 'String' }
            else { Remove-RegKey $(if ($r.KillPath) { $r.KillPath } else { $r.P }) }
            continue
        }
        $v = if ($On) { $r.On } else { $r.Off }
        Set-RegValue $r.P $r.N $v $r.T
    }
}
function Get-TweakValue($Tw) {
    if ($Tw.Kind -eq 'Choice' -and $Tw.GetV) { return "$(& $Tw.GetV)" }
    if ($Tw.Kind -eq 'Choice') {
        $r = $Tw.Reg[0]
        $v = Get-RegValue $r.P $r.N
        if ($null -eq $v) { $v = $r.D }
        return $v
    }
    Get-TweakState $Tw
}
function Set-TweakValue($Tw, $Value) {
    if ($Tw.Kind -eq 'Choice' -and $Tw.SetV) { & $Tw.SetV $Value }
    elseif ($Tw.Kind -eq 'Choice') { $r = $Tw.Reg[0]; Set-RegValue $r.P $r.N ([int]$Value) $r.T }
    else { Set-TweakState $Tw ([bool]$Value) }
    if ($Tw.PostSet) { & $Tw.PostSet }
}
function Format-TweakValue($Tw, $Value) {
    if ($Tw.Kind -eq 'Choice') {
        $o = $Tw.Options | Where-Object { "$($_.V)" -eq "$Value" } | Select-Object -First 1
        if ($o) { return $o.L } else { return "valeur $Value" }
    }
    if ($Value) { 'activé' } else { 'désactivé' }
}
function Set-RowDisplay($R, $Value) {
    if ($R.Tweak.Kind -eq 'Choice') {
        # toutes les options « Masquée / Icône / Zone », celle en vigueur en gras, les autres en gris
        $R.Shown = "$Value"
        if ($R.DdText) {
            $R.DdText.Inlines.Clear(); $first = $true
            # plus de 3 options (DNS...) : valeur en vigueur seule, liste complète dans le menu (ligne lisible en colonne étroite)
            $vis = @($R.Tweak.Options | Where-Object { -not $_.H -or "$($_.V)" -eq "$Value" })
            if ($vis.Count -gt 3) {
                $o = @($vis | Where-Object { "$($_.V)" -eq "$Value" })[0]
                $run = [Windows.Documents.Run]::new($(if ($o) { "$($o.L)" } else { "valeur $Value" })); $run.FontWeight = [Windows.FontWeights]::SemiBold
                $run.SetResourceReference([Windows.Documents.TextElement]::ForegroundProperty, 'FgBrush'); $R.DdText.Inlines.Add($run)
                return
            }
            foreach ($o in $R.Tweak.Options) {
                # option masquée (H) : affichée seulement si c'est la valeur en vigueur
                if ($o.H -and "$($o.V)" -ne "$Value") { continue }
                if (-not $first) {
                    $sp = [Windows.Documents.Run]::new('  /  ')
                    $sp.SetResourceReference([Windows.Documents.TextElement]::ForegroundProperty, 'LineBrush')
                    $R.DdText.Inlines.Add($sp)
                }
                $run = [Windows.Documents.Run]::new("$($o.L)")
                if ("$($o.V)" -eq "$Value") {
                    $run.FontWeight = [Windows.FontWeights]::SemiBold
                    $run.SetResourceReference([Windows.Documents.TextElement]::ForegroundProperty, 'FgBrush')
                }
                else { $run.SetResourceReference([Windows.Documents.TextElement]::ForegroundProperty, 'MutedBrush') }
                $R.DdText.Inlines.Add($run); $first = $false
            }
        }
    } else { $R.Toggle.IsChecked = [bool]$Value }
}
# menu des options d'un réglage à choix : fenêtre flottante aux couleurs de l'application (coins arrondis, ombre),
# alignée sur le bord droit de l'icône ; option en vigueur cochée ; clic = option retenue (à appliquer)
function Show-ChoiceMenu($Btn) {
    $r = $Btn.DataContext
    $pop = [Windows.Controls.Primitives.Popup]::new(); $pop.StaysOpen = $false; $pop.AllowsTransparency = $true; $pop.PopupAnimation = 'Fade'
    $pop.PlacementTarget = $Btn; $pop.Placement = 'Bottom'; $pop.VerticalOffset = 4
    $bd = [Windows.Controls.Border]::new()
    $bd.CornerRadius = [Windows.CornerRadius]::new(8)
    $bd.BorderThickness = New-Thickness 1 1 1 1
    $bd.Padding = New-Thickness 4 4 4 4
    $bd.Margin = New-Thickness 0 0 12 12
    $bd.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, 'PanelBrush')
    $bd.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, 'LineBrush')
    $sh = [Windows.Media.Effects.DropShadowEffect]::new(); $sh.BlurRadius = 16; $sh.ShadowDepth = 3; $sh.Opacity = 0.25; $bd.Effect = $sh
    $bd.MinWidth = 170
    # police explicite : une fenêtre flottante n'hérite pas de la police de la fenêtre (sinon police d'icônes du bouton)
    $bd.SetValue([Windows.Documents.TextElement]::FontFamilyProperty, [Windows.Media.FontFamily]::new('Segoe UI'))
    $bd.SetValue([Windows.Documents.TextElement]::FontSizeProperty, [double]13)
    $list = [Windows.Controls.StackPanel]::new(); $bd.Child = $list
    foreach ($o in $r.Tweak.Options) {
        if ($o.H) { continue }
        $on = "$($o.V)" -eq "$($r.Shown)"
        $it = [Windows.Controls.Border]::new()
        $it.CornerRadius = [Windows.CornerRadius]::new(5)
        $it.Padding = New-Thickness 8 6 14 6
        $it.Cursor = [Windows.Input.Cursors]::Hand
        $it.Background = [Windows.Media.Brushes]::Transparent; $it.Tag = @{ Row = $r; V = $o.V; Pop = $pop }
        $g = [Windows.Controls.StackPanel]::new(); $g.Orientation = 'Horizontal'
        $ck = New-Text $(if ($on) { [string][char]0xE73E } else { '' })
        $ck.FontFamily = [Windows.Media.FontFamily]::new('Segoe MDL2 Assets')
        $ck.FontSize = 12
        $ck.Width = 22
        $ck.VerticalAlignment = 'Center'
        $ck.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'AccentBrush')
        $tx = New-Text "$($o.L)"
        $tx.FontFamily = [Windows.Media.FontFamily]::new('Segoe UI')
        $tx.VerticalAlignment = 'Center'
        if ($on) { $tx.FontWeight = [Windows.FontWeights]::SemiBold }
        [void]$g.Children.Add($ck); [void]$g.Children.Add($tx); $it.Child = $g
        $it.Add_MouseEnter({ param($s, $e) $s.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, 'HoverBrush') })
        $it.Add_MouseLeave({ param($s, $e) $s.Background = [Windows.Media.Brushes]::Transparent })
        $it.Add_MouseLeftButtonUp({ param($s, $e) $t = $s.Tag; $t.Pop.IsOpen = $false; Set-RowDisplay $t.Row $t.V; Set-Staged $t.Row $t.V })
        [void]$list.Children.Add($it)
    }
    $pop.Child = $bd
    # bord droit du menu sur le bord droit de l'icône
    $bd.Measure([Windows.Size]::new([double]::PositiveInfinity, [double]::PositiveInfinity))
    $pop.HorizontalOffset = $Btn.ActualWidth - ($bd.DesiredSize.Width - 12)
    $pop.IsOpen = $true
}

$GpState = @{ Started = $false }
$GpRows = [Collections.ArrayList]::new()
function Complete-TweakChange($R, $Want, $Now) {
    $tw = $R.Tweak
    $R.Current = $Now
    Set-RowDisplay $R $Now
    if ("$Now" -ne "$Want") {
        Write-UiLog ('{0} : écrit mais relu « {1} » (stratégie de groupe prioritaire ?)' -f $tw.Label, (Format-TweakValue $tw $Now)) 'WARN'
        Set-Badge $R 'warn'
    } else {
        $fx = $EffectInfo[$R.Effect].Idle; $fx = $fx.Substring(0, 1).ToLower() + $fx.Substring(1)
        Write-UiLog ('{0} : {1} - {2}' -f $tw.Label, (Format-TweakValue $tw $Now), $fx) 'OK'
        Add-SessionEvent 'Réglages' $tw.Label ('{0} > {1}' -f (Format-TweakValue $tw $R.Orig), (Format-TweakValue $tw $Now)) 'ok' $fx
        if ("$Now" -eq "$($R.Orig)") { $R.Pending = $null; Set-Badge $R 'idle'; Remove-PendingRecord $R.Key }
        elseif ($EffectInfo[$R.Effect].Pending) {
            $R.Pending = $R.Effect
            Set-Badge $R 'pending'
            Add-PendingRecord $R.Key $R.Effect $tw.Label $R.Orig
        }
        else { $R.Pending = $null; Set-Badge $R 'ok' }
    }
}
function Invoke-TweakChange($R, $Want) {
    $tw = $R.Tweak
    try {
        $GpState.Started = $false
        Set-TweakValue $tw $Want
        $now = Get-TweakValue $tw
        $R.Staged = $null
        if ($GpState.Started -and "$now" -ne "$Want") {
            # stratégie locale : gpupdate tourne en arrière-plan, la valeur est relue par le minuteur (Update-GpRow)
            $R.GpWant = $Want; $R.GpUntil = [DateTime]::Now.AddSeconds(120)
            if (-not $GpRows.Contains($R)) { [void]$GpRows.Add($R) }
            Set-Badge $R 'wait'
        } else { Complete-TweakChange $R $Want $now }
    } catch {
        Write-UiLog ('{0} : {1}' -f $tw.Label, $_.Exception.Message) 'ERROR'
        $R.Staged = $null
        try { $R.Current = Get-TweakValue $tw; Set-RowDisplay $R $R.Current } catch { Write-Ignored "Lecture du réglage « $($tw.Label) »" $_ }
        Set-Badge $R 'error'
    }
    Update-PendingBar
}
function Update-GpRow {
    foreach ($r in @($GpRows)) {
        $now = try { Get-TweakValue $r.Tweak } catch { $null }
        if ("$now" -eq "$($r.GpWant)" -or [DateTime]::Now -gt $r.GpUntil) { $GpRows.Remove($r); Complete-TweakChange $r $r.GpWant $now }
    }
    Update-PendingBar
}

function Set-Staged($R, $Want) {
    if ("$Want" -eq "$($R.Current)") {
        $R.Staged = $null
        Set-Badge $R $(if ($R.BadgeState) { $R.BadgeState } else { 'idle' })
    } else {
        $R.Staged = $Want
        Set-Badge $R 'staged'
    }
    Update-ApplyButton
}
function Get-StagedRow { @(@($TweakRows) + @($StartupRows) | Where-Object { $null -ne $_.Staged }) }
# Pied de page affiché seulement s'il sert : sélection à appliquer (onglets de réglages et Maintenance), tâche en cours,
# ou résultat de la dernière tâche (fermable). Appliquer : sélection présente hors traitement ; Interrompre : pendant un traitement.
function Update-Footer {
    if (-not $Ui.Footer) { return }
    $run = [bool]$Sync.Running
    $sel = (-not $run) -and [int]$Sync.SelCount -gt 0 -and $Sync.CurPage -notin 'Info', 'Settings'
    $keep = (-not $run) -and [bool]$Sync.FooterKeep
    $set = { param($el, [bool]$on) $v = $(if ($on) { 'Visible' } else { 'Collapsed' }); if ("$($el.Visibility)" -ne $v) { $el.Visibility = $v } }
    & $set $Ui.Footer ($run -or $sel -or $keep)
    & $set $Ui.RunBtn $sel
    & $set $Ui.StopBtn $run
    & $set $Ui.AutoReboot $run
    & $set $Ui.FooterStatus ($run -or $keep)
    & $set $Ui.FooterClose $keep
    $m = New-Thickness $(if ($sel) { 0 } else { 14 }) 10 8 10
    if ("$($Ui.StopBtn.Margin)" -ne "$m") { $Ui.StopBtn.Margin = $m }
    # sans bouton à gauche : même marge que le contenu des pages
    $sm = New-Thickness $(if ($sel -or $run) { 10 } else { 20 }) 12 16 12
    if ("$($Ui.FooterStatus.Margin)" -ne "$sm") { $Ui.FooterStatus.Margin = $sm }
    # pendant une tâche : barre cliquable (ouvre la fenêtre Logiciels ou l'onglet Journal, voir 87-logiciels.ps1)
    $soft = $run -and $Sync.Selected -contains 'SoftUpgrade'
    $tip = $(if ($soft) { 'Afficher la mise à jour des logiciels' } elseif ($run) { 'Afficher le détail dans le Journal' } else { $null })
    if ("$($Ui.FooterStatus.ToolTip)" -ne "$tip") {
        $Ui.FooterStatus.ToolTip = $tip
        $Ui.FooterStatus.Cursor = $(if ($run) { [Windows.Input.Cursors]::Hand } else { $null })
        $Ui.FooterStatus.Background = [Windows.Media.Brushes]::Transparent
    }
}
function Update-ApplyButton {
    $nStaged = @(Get-StagedRow).Count
    $nClean  = 0
    if ($CleanUI -and $CleanUI.Count) { $nClean = @(Get-CleanSelection).Count }
    $nAppx = @(Get-AppxChecked).Count
    $n = $nStaged + $nClean + $nAppx
    # libellé selon le contenu : uniquement du nettoyage -> Nettoyer ; uniquement des applications -> Désinstaller ; sinon Appliquer
    if ($nAppx -and -not $nStaged -and -not $nClean) {
        $Ui.RunBtn.Content = $(if ($Resp.Short) { 'Désinstaller' } elseif ($nAppx -eq 1) { 'Désinstaller l''application sélectionnée' } else { "Désinstaller les $nAppx applications sélectionnées" })
    } else {
        $verb = $(if ($nClean -and -not $nStaged) { 'Nettoyer' } else { 'Appliquer' })
        $lbl = $(if ($Resp.Short) { $verb } else { "$verb la sélection" })
        $Ui.RunBtn.Content = $(if ($n) { "$lbl ($n)" } else { $lbl })
    }
    $Ui.RunBtn.IsEnabled  = ($n -gt 0) -and -not $Sync.Running
    $Ui.RunBtn.ToolTip = $(if ($Sync.Running) { 'Une exécution est déjà en cours' } elseif (-not $n) { 'Aucun élément sélectionné' } else { $null })
    $Sync.SelCount = $n
    try { Update-TabBadge } catch { Write-Ignored 'Compteurs des onglets' $_ }
    Update-Footer
}

$TweakRows   = [System.Collections.ArrayList]::new()
$StartupRows = [System.Collections.ArrayList]::new()

$ToggleClick = { param($s, $e) Set-Staged $s.DataContext ([bool]$s.IsChecked) }

function Get-SortedByLabel($Items, [string]$Prop = 'Label') {
    @($Items | Sort-Object -Culture 'fr-FR' -Property { "$($_.$Prop)" -replace '^[^\p{L}\p{N}]+', '' })
}
# Présence du matériel / de la fonction avant d'afficher une option (une seule détection par session) :
# Laptop (châssis portable ou capot), Hibernate (état S4 pris en charge), Camera, CopilotPlus (NPU présent), Widgets, Notepad.
# Les détections lentes sont faites en arrière-plan dès le démarrage, sans requête en double : matériel par la passe
# initiale de l'Accueil ($InfoScript : LaptopCim, Camera, CopilotPlus dans $Sync.NeedPre), Widgets et Bloc-notes par la
# lecture des applications installées ($AppxScanScript, $Sync.AppxScan). Test-Need ne refait une détection au premier plan
# que si le résultat n'est pas encore arrivé.
$NeedAppx = @{ Widgets = 'MicrosoftWindows.Client.WebExperience'; Notepad = 'Microsoft.WindowsNotepad'; Paint = 'Microsoft.Paint' }
function Get-NeedPre([string]$Key) {
    if ($NeedAppx.ContainsKey($Key)) {
        $a = $Sync.AppxScan
        if ($a -and -not $a.Error) { return [bool](@($a.Inst) -contains $NeedAppx[$Key]) }
        return $null
    }
    $p = $Sync.NeedPre; if ($p -and $p.ContainsKey($Key)) { [bool]$p[$Key] } else { $null }
}
function Test-NeedPreReady { [bool]($Sync.InfoBaseDone -and $Sync.AppxScan) }
# portable : capot (lecture native instantanée), sinon type de châssis (WMI, détection d'arrière-plan si déjà arrivée)
function Test-IsLaptop {
    if ($null -eq $script:IsLaptopCache) {
        $v = $false
        $pc = Get-PowerCapability; if ($pc -and $pc.Lid) { $v = $true }
        if (-not $v) {
            $pre = Get-NeedPre 'LaptopCim'
            if ($null -ne $pre) { $v = $pre }
            else {
                try {
                    $mob = [int](Get-CimInstance Win32_ComputerSystem -Property PCSystemType -ErrorAction Stop).PCSystemType -eq 2
                    $ch = @((Get-CimInstance Win32_SystemEnclosure -Property ChassisTypes -ErrorAction SilentlyContinue).ChassisTypes)
                    $v = $mob -or @($ch | Where-Object { [int]$_ -in 8, 9, 10, 11, 12, 14, 18, 21, 30, 31, 32 }).Count -gt 0
                } catch { Write-Ignored 'Détection du type de poste' $_ }
            }
        }
        $script:IsLaptopCache = $v
    }
    $script:IsLaptopCache
}
$NeedCache = @{}
function Test-Need([string]$Need) {
    if (-not $Need) { return $true }
    if ($NeedCache.ContainsKey($Need)) { return $NeedCache[$Need] }
    $v = $true
    try {
        switch ($Need) {
            'Laptop' { $v = Test-IsLaptop }
            'Hibernate' { $c = Get-PowerCapability; $v = $(if ($c) { $c.S4 } else { $true }) }
            # veille moderne (S0, AoAc) : Windows ne prévoit que le plan Équilibré
            'ClassicPower' { $c = Get-PowerCapability; $v = $(if ($c) { -not $c.AoAc } else { $true }) }
            'Hags' { $h = [_OlivM.Gpu]::HwSch(); $v = $h -ge 0 -and ($h -band 1) -ne 0 }
            # signature SMB : exigée par défaut depuis Windows 11 24H2 (build 26100), réglage utile avant
            'OldSmb' { $v = $Build -lt 26100 }
            'NotHome' { $v = "$(Get-RegValue 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion' 'EditionID')" -notlike 'Core*' }
            # Defender actif (ni passif ni désactivé au profit d'un autre antivirus) : réglages Defender utiles
            'Defender' { $v = "$((Get-MpComputerStatus -ErrorAction Stop).AMRunningMode)" -eq 'Normal' }
            # version cible : éditions Pro / Entreprise / Éducation (pas Famille = Core*), version affichée lisible (24H2...)
            'TargetRelease' { $v = "$(Get-RegValue 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion' 'EditionID')" -notlike 'Core*' -and "$WinDisplayVer" -match '^\d{2}H\d$' }
            default {
                $pre = Get-NeedPre $Need
                if ($null -ne $pre) { $v = $pre }
                else {
                    switch ($Need) {
                        'Camera' { $v = @(Get-CimInstance Win32_PnPEntity -Filter "PNPClass='Camera' OR PNPClass='Image'" -ErrorAction Stop | Where-Object { "$($_.Status)" -eq 'OK' }).Count -gt 0 }
                        'CopilotPlus' { $v = @(Get-CimInstance Win32_PnPEntity -Filter "PNPClass='ComputeAccelerator'" -ErrorAction Stop).Count -gt 0 }
                        'Widgets' { $v = @(Get-AppxPackage -AllUsers -Name 'MicrosoftWindows.Client.WebExperience' -ErrorAction Stop).Count -gt 0 }
                        'Notepad' { $v = @(Get-AppxPackage -AllUsers -Name 'Microsoft.WindowsNotepad' -ErrorAction Stop).Count -gt 0 }
                        'Paint' { $v = @(Get-AppxPackage -AllUsers -Name 'Microsoft.Paint' -ErrorAction Stop).Count -gt 0 }
                    }
                }
            }
        }
    } catch { Write-Ignored "Détection préalable ($Need)" $_; $v = $true }
    $NeedCache[$Need] = [bool]$v
    [bool]$v
}
# GetPwrCapabilities (powrprof) : SYSTEM_POWER_CAPABILITIES, octets 0..7 = bouton, veille, capot, S1..S5, octet 20 = AoAc
# (veille moderne) : 20 champs BOOLEAN d'un octet avant lui
function Get-PowerCapability {
    try {
        $buf = [Runtime.InteropServices.Marshal]::AllocHGlobal(256)
        try {
            if ([_OlivM.Pwr]::GetPwrCapabilities($buf) -eq 0) { return $null }
            @{ Lid = [Runtime.InteropServices.Marshal]::ReadByte($buf, 2) -ne 0; S3 = [Runtime.InteropServices.Marshal]::ReadByte($buf, 5) -ne 0; S4 = [Runtime.InteropServices.Marshal]::ReadByte($buf, 6) -ne 0; AoAc = [Runtime.InteropServices.Marshal]::ReadByte($buf, 20) -ne 0 }
        } finally { [Runtime.InteropServices.Marshal]::FreeHGlobal($buf) }
    } catch { $null }
}
function Add-TweakCard([string]$Page, $LeftPanel, $RightPanel, [string[]]$RightGroups, [string]$OnlyGroup) {
    $groups = @($Tweaks | Where-Object { $_.Page -eq $Page } | ForEach-Object { $_.Group } | Select-Object -Unique)
    if ($OnlyGroup) { $groups = @($OnlyGroup) }
    foreach ($grp in $groups) {
        $info = $GroupInfo[$grp]
        # options masquées si elles n'existent pas sur ce poste : version de Windows ou matériel / fonction absents
        $list = @(Get-SortedByLabel ($Tweaks | Where-Object { $_.Page -eq $Page -and $_.Group -eq $grp -and $Build -ge $_.MinBuild -and (Test-Need $_.Need) }))
        if (-not $list.Count) { continue }
        $c = New-Card $grp '' $info.Glyph
        foreach ($tw in $list) {
            $ok   = $Build -ge $tw.MinBuild
            $desc = if ($ok) { '' } else { "Non disponible sur cette version de Windows (build $Build)" }
            $r = New-SettingRow $tw.Label $desc ("{0}`n`n{1}" -f $tw.Desc, $tw.Tip) $tw.Effect
            $r.Tweak = $tw; $r.Enabled = $ok
            try { $r.Orig = Get-TweakValue $tw } catch { $r.Orig = $null }
            $r.Current = $r.Orig; $r.Staged = $null
            $r.Key = "T|$($tw.Id)|$UserSid"
            if ($tw.Kind -eq 'Choice') {
                # valeur actuelle en texte à gauche de la pastille ; icône à la place de l'interrupteur (même colonne, même
                # alignement) qui ouvre le menu des options, valeur actuelle cochée
                $r.Buttons = [System.Collections.ArrayList]::new()
                $r.DdText = New-Text ''; $r.DdText.VerticalAlignment = 'Center'; $r.DdText.TextWrapping = 'NoWrap'; $r.DdText.FontSize = 13
                [void]$r.Choices.Children.Add($r.DdText)
                $dd = [Windows.Controls.Button]::new(); $dd.Style = $Window.FindResource('IconBtn'); $dd.Content = [string][char]0xE70D
                $dd.Width = 40; $dd.Height = 28; $dd.ToolTip = 'Choisir'; $dd.IsEnabled = $ok; $dd.DataContext = $r
                $dd.Add_Click({ param($s, $e) Show-ChoiceMenu $s })
                [void]$r.Host.Children.Add($dd); $r.Dropdown = $dd
            } else {
                $tg = [Windows.Controls.CheckBox]::new()
                $tg.Style = $Window.FindResource('Toggle'); $tg.IsEnabled = $ok
                $tg.DataContext = $r
                $tg.Add_Click($ToggleClick)
                [void]$r.Host.Children.Add($tg)
                $r.Toggle = $tg
            }
            if ($null -ne $r.Orig) { Set-RowDisplay $r $r.Orig }
            Restore-PendingRow $r $r.Key
            [void]$c.Body.Children.Add($r.Row)
            [void]$TweakRows.Add($r)
        }
        Add-Spacer $c.Body; Add-EffectHeader $c
        if ($RightGroups -contains $grp) { [void]$RightPanel.Children.Add($c.Card) } else { [void]$LeftPanel.Children.Add($c.Card) }
    }
}


function Update-PendingBar {
    $counts = @{}
    foreach ($r in @($TweakRows) + @($StartupRows)) {
        if ($r.Pending -and $EffectInfo[$r.Pending].Bar) { $counts[$r.Pending] = 1 + [int]$counts[$r.Pending] }
    }
    if ($counts.Count -eq 0) { $Ui.PendingBar.Visibility = 'Collapsed'; return }
    $parts = @()
    if ($counts.E) { $parts += "redémarrer l'Explorateur ($($counts.E))" }
    if ($counts.L) { $parts += "déconnecter l'utilisateur ($($counts.L))" }
    if ($counts.R) { $parts += "redémarrer le poste ($($counts.R))" }
    $Ui.PendingText.Text = 'Changements en attente : ' + ($parts -join '  ·  ')
    $Ui.PendingExplorer.Visibility = $(if ($counts.E) { 'Visible' } else { 'Collapsed' })
    $Ui.PendingLogoff.Visibility   = $(if ($counts.L) { 'Visible' } else { 'Collapsed' })
    $Ui.PendingReboot.Visibility   = $(if ($counts.R) { 'Visible' } else { 'Collapsed' })
    $Ui.PendingBar.Visibility = 'Visible'
}

$PendingFile = Join-Path (Get-LogPath 'Etat') 'en-attente.json'
function Get-RefTime {
    $ex = Get-Process -Name explorer -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $UserSession } | Sort-Object StartTime | Select-Object -First 1
    $si = Get-Process -Name sihost -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $UserSession } | Sort-Object StartTime | Select-Object -First 1
    $min = [DateTime]::MinValue
    @{
        Explorer = $(if ($ex) { $ex.StartTime } else { $min })
        Logon    = $(if ($si) { $si.StartTime } elseif ($ex) { $ex.StartTime } else { $min })
        Boot     = $(if ($BootTime) { $BootTime } else { $min })
    }
}
function Read-PendingStore {
    $h = @{}
    if (Test-Path -LiteralPath $PendingFile) {
        try {
            foreach ($o in @(Get-Content -LiteralPath $PendingFile -Raw -Encoding UTF8 | ConvertFrom-Json)) { if ($o.Key) { $h[$o.Key] = $o } }
        } catch {
            Write-Ignored 'Lecture des réglages en attente' $_
        }
    }
    $ref = Get-RefTime
    foreach ($k in @($h.Keys)) {
        $o = $h[$k]
        try { $when = if ($o.Time -is [DateTime]) { $o.Time } else { [DateTime]::Parse("$($o.Time)", [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind) } }
        catch { $h.Remove($k); continue }
        $limit = switch ($o.Effect) { 'E' { $ref.Explorer } 'L' { $ref.Logon } 'N' { $ref.Logon } default { $ref.Boot } }
        if ($when -le $limit) { $h.Remove($k) }
    }
    $h
}
function Save-PendingStore {
    try {
        ConvertTo-Json -InputObject @($PendingStore.Values) -Depth 3 | Set-Content -LiteralPath $PendingFile -Encoding UTF8
    } catch {
        Write-Ignored 'Enregistrement des réglages en attente' $_
    }
}
function Add-PendingRecord([string]$Key, [string]$Effect, [string]$Label, $Before) {
    if ($PendingStore.ContainsKey($Key)) { $Before = $PendingStore[$Key].Before }
    $PendingStore[$Key] = [pscustomobject]@{ Key = $Key; Effect = $Effect; Label = $Label; Before = $Before; Time = [DateTime]::Now.ToString('o') }
    Save-PendingStore
}
function Remove-PendingRecord([string]$Key) {
    if ($PendingStore.ContainsKey($Key)) { $PendingStore.Remove($Key); Save-PendingStore }
}
function Restore-PendingRow($R, [string]$Key) {
    $rec = $PendingStore[$Key]
    if (-not $rec) { return }
    if ("$($R.Current)" -eq "$($rec.Before)") { Remove-PendingRecord $Key; return }
    $R.Orig = $rec.Before
    $R.Pending = $(if ($rec.Effect -eq 'S') { 'R' } else { $rec.Effect })
    Set-Badge $R 'pending'
}
$PendingStore = Read-PendingStore
Save-PendingStore

function Get-StartupEntry {
    $list = [System.Collections.ArrayList]::new()
    $sources = @(
        @{ Scope = "Utilisateur ($UserName)"; Reg = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Run'; Approved = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run' }
        @{ Scope = 'Tous les utilisateurs';   Reg = 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'; Approved = 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run' }
        @{ Scope = 'Tous les utilisateurs (32 bits)'; Reg = 'HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'; Approved = 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32' }
    )
    foreach ($s in $sources) {
        $k = Open-RegKey $s.Reg
        if (-not $k) { continue }
        try {
            foreach ($n in $k.GetValueNames()) {
                if (-not $n) { continue }
                [void]$list.Add([pscustomobject]@{ Name = $n; Command = "$($k.GetValue($n, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames))"; Scope = $s.Scope; Approved = $s.Approved; ValueName = $n; Reg = $s.Reg; Kind = "$($k.GetValueKind($n))"; File = $null })
            }
        } finally { $k.Close() }
    }
    $folders = @(
        @{ Scope = "Dossier Démarrage ($UserName)"; Path = Join-Path $UserProfilePath 'AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup'; Approved = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder' }
        @{ Scope = 'Dossier Démarrage commun'; Path = Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\StartUp'; Approved = 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder' }
    )
    foreach ($f in $folders) {
        if (-not (Test-Path -LiteralPath $f.Path)) { continue }
        foreach ($file in Get-ChildItem -LiteralPath $f.Path -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'desktop.ini' }) {
            [void]$list.Add([pscustomobject]@{ Name = $file.BaseName; Command = $file.FullName; Scope = $f.Scope; Approved = $f.Approved; ValueName = $file.Name; Reg = $null; Kind = $null; File = $file.FullName })
        }
    }
    foreach ($e in $list) {
        $b = Get-RegValue $e.Approved $e.ValueName
        $en = $true
        if ($b -is [byte[]] -and $b.Length -gt 0) { $en = (($b[0] -band 1) -eq 0) }
        $e | Add-Member -NotePropertyName Enabled -NotePropertyValue $en
    }
    $list | Sort-Object Name
}
function Set-StartupEntry($Entry, [bool]$Enable) {
    if ($Enable) { $bytes = [byte[]](2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0) }
    else { $bytes = [byte[]](@(3, 0, 0, 0) + [BitConverter]::GetBytes([DateTime]::Now.ToFileTime())) }
    Set-RegValue $Entry.Approved $Entry.ValueName $bytes 'Binary'
}

$StartupClick = { param($s, $e) Set-Staged $s.DataContext ([bool]$s.IsChecked) }

function Remove-StartupEntry($Entry) {
    $bak = Get-LogPath 'Demarrage'
    [void][IO.Directory]::CreateDirectory($bak)
    $stamp = '{0:yyyyMMdd-HHmmss}' -f (Get-Date)
    $safe = ($Entry.Name -replace '[\\/:*?"<>|]', '_')
    if ($Entry.File) {
        $dest = Join-Path $bak ('{0}_{1}' -f $stamp, (Split-Path $Entry.File -Leaf))
        Move-Item -LiteralPath $Entry.File -Destination $dest -Force -ErrorAction Stop
        $saved = $dest
    } else {
        $regPath = if ($Entry.Reg -like 'HKCU\*' -and $HkuSidOk) { "HKEY_USERS\$UserSid\" + $Entry.Reg.Substring(5) } else { $Entry.Reg -replace '^HKLM\\', 'HKEY_LOCAL_MACHINE\' -replace '^HKCU\\', 'HKEY_CURRENT_USER\' }
        $esc = { param($t) $t.Replace('\', '\\').Replace('"', '\"') }
        if ($Entry.Kind -eq 'ExpandString') {
            $hex = (([Text.Encoding]::Unicode.GetBytes($Entry.Command + [char]0)) | ForEach-Object { '{0:x2}' -f $_ }) -join ','
            $line = '"{0}"=hex(2):{1}' -f (& $esc $Entry.ValueName), $hex
        } else { $line = '"{0}"="{1}"' -f (& $esc $Entry.ValueName), (& $esc $Entry.Command) }
        $saved = Join-Path $bak ('{0}_{1}.reg' -f $stamp, $safe)
        Set-Content -LiteralPath $saved -Encoding Unicode -Value @('Windows Registry Editor Version 5.00', '', "[$regPath]", $line, '')
        $k = Open-RegKey $Entry.Reg $true
        if (-not $k) { throw "clé $($Entry.Reg) inaccessible en écriture" }
        try { $k.DeleteValue($Entry.ValueName, $true) } finally { $k.Close() }
    }
    Set-RegValue $Entry.Approved $Entry.ValueName $null
    $saved
}
$StartupDeleteClick = {
    param($s, $e)
    $r = $s.DataContext; $en = $r.Entry
    if (-not (Confirm-Action ("Supprimer « {0} » du démarrage ?`n`n{1}`n{2}`n`nLe programme n'est pas désinstallé. Une sauvegarde .reg est conservée dans {3}." -f $en.Name, $en.Scope, $en.Command, (Get-LogPath 'Demarrage')))) {
        return
    }
    try {
        $saved = Remove-StartupEntry $en
        Remove-PendingRecord $r.Key
        Write-UiLog ('Démarrage - {0} [{1}] supprimé. Sauvegarde : {2}' -f $en.Name, $en.Scope, $saved) 'OK'
        Add-SessionEvent 'Applications au démarrage' $en.Name 'supprimée du démarrage' 'ok' "sauvegarde : $saved"
    } catch { Write-UiLog ('Démarrage - suppression de {0} : {1}' -f $en.Name, $_.Exception.Message) 'ERROR' }
    Update-StartupList
}

function Invoke-StartupChange($R) {
    $want = [bool]$R.Staged
    try {
        Set-StartupEntry $R.Entry $want
        $b = Get-RegValue $R.Entry.Approved $R.Entry.ValueName
        $now = if ($b -is [byte[]] -and $b.Length -gt 0) { (($b[0] -band 1) -eq 0) } else { $true }
        $R.Current = $now; $R.Staged = $null; $R.Toggle.IsChecked = $now
        if ($now -ne $want) {
            Write-UiLog ('Démarrage - {0} : écriture non confirmée dans {1}\{2}' -f $R.Entry.Name, $R.Entry.Approved, $R.Entry.ValueName) 'WARN'
            Set-Badge $R 'warn'; return
        }
        Write-UiLog ('Démarrage - {0} [{1}] : {2} - écrit dans {3}, pris en compte après déconnexion' -f $R.Entry.Name, $R.Entry.Scope, $(if ($want) { 'activé' } else { 'désactivé' }), $R.Entry.Approved) 'OK'
        Add-SessionEvent 'Applications au démarrage' $R.Entry.Name $(if ($want) { 'activée' } else { 'désactivée' }) 'ok' 'à la prochaine session'
        if ("$want" -eq "$($R.Orig)") { $R.Pending = $null; Set-Badge $R 'idle'; Remove-PendingRecord $R.Key }
        else { $R.Pending = 'N'; Set-Badge $R 'pending'; Add-PendingRecord $R.Key 'N' ("Démarrage - $($R.Entry.Name)") $R.Orig }
    } catch {
        Write-UiLog ('Démarrage - {0} : {1}' -f $R.Entry.Name, $_.Exception.Message) 'ERROR'
        $R.Staged = $null; $R.Toggle.IsChecked = [bool]$R.Current
        Set-Badge $R 'error'
    }
}

function Update-StartupList {
    $keep = @{}
    foreach ($r in $StartupRows) { if ($null -ne $r.Staged) { $keep[$r.Key] = $r.Staged } }
    $StartupList.Children.Clear()
    $StartupRows.Clear()
    $entries = @(Get-StartupEntry)
    if ($StartupSort -eq 'Etat') { $entries = @($entries | Sort-Object @{ Expression = { $_.Enabled }; Descending = $true }, Name) }
    if ($entries.Count -eq 0) {
        $t = New-Text 'Aucune entrée.'; $t.Margin = New-Thickness 50 8 16 8
        [void]$StartupList.Children.Add($t); return
    }
    # 4 entrées affichées, les suivantes dans un panneau déplié par « Afficher tout (N) »
    $more = [Windows.Controls.StackPanel]::new(); $idx = 0
    foreach ($e in $entries) {
        $r = New-SettingRow $e.Name ('{0}  ·  {1}' -f $e.Scope, $e.Command) '' 'N'
        $r.Entry = $e; $r.Orig = $e.Enabled; $r.Current = $e.Enabled; $r.Staged = $null; $r.Badge.Visibility = 'Collapsed'
        $r.Key = "S|$($e.Approved)|$($e.ValueName)|$UserSid"
        $tg = [Windows.Controls.CheckBox]::new()
        $tg.Style = $Window.FindResource('Toggle'); $tg.IsChecked = $e.Enabled; $tg.DataContext = $r
        $tg.Add_Click($StartupClick)
        $r.Toggle = $tg
        [void]$r.Host.Children.Add($tg)
        $del = [Windows.Controls.Button]::new()
        $del.Style = $Window.FindResource('IconBtn'); $del.Content = [string][char]0xE74D; $del.Margin = New-Thickness 10 0 0 0
        $del.ToolTip = 'Supprimer'; $del.DataContext = $r
        $del.Add_Click($StartupDeleteClick)
        [void]$r.Extra.Children.Add($del)
        ($r.Row.Child.Children[0].Children[1]).TextWrapping = 'Wrap'
        if ($idx -lt $ListMax) { [void]$StartupList.Children.Add($r.Row) } else { [void]$more.Children.Add($r.Row) }
        $idx++
        [void]$StartupRows.Add($r)
        Restore-PendingRow $r $r.Key
        if ($keep.ContainsKey($r.Key) -and "$($keep[$r.Key])" -ne "$($r.Current)") {
            $tg.IsChecked = [bool]$keep[$r.Key]
            Set-Staged $r ([bool]$keep[$r.Key])
        }
    }
    Add-FoldMore $StartupList $more $entries.Count 'Startup'
    Update-ApplyButton
    Update-PendingBar
}


# Plans d'alimentation : modèles Windows, plus une copie à identifiant fixe créée par l'application quand le plan n'est pas
# installé (Performances élevées masqué par certains constructeurs, Performances optimales jamais installé par défaut)
$PowerSchemesKey = 'HKLM\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes'
$PowerPlans = [ordered]@{
    Balanced = @('381b4222-f694-41f0-9685-ff5bb260df2e')
    High     = @('8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c', 'b7a4e9c1-4c53-4a1f-9e2b-0a4d53595301')
    Ultimate = @('e9a42b02-d5df-448d-aa00-03f14749eb61', 'b7a4e9c1-4c53-4a1f-9e2b-0a4d53595302')
}
function Get-PowerPlanKey {
    $g = "$(Get-RegValue $PowerSchemesKey 'ActivePowerScheme')".ToLower()
    foreach ($k in $PowerPlans.Keys) { if ($PowerPlans[$k] -contains $g) { return $k } }
    'Other'
}
function Set-PowerPlan([string]$Key) {
    if (-not $PowerPlans.Contains($Key)) { return }
    $pc = "$env:windir\System32\powercfg.exe"; $ids = $PowerPlans[$Key]
    foreach ($id in $ids) { & $pc /setactive $id 2>&1 | Out-Null; if ($LASTEXITCODE -eq 0) { return } }
    # aucun plan installé : copie du modèle Windows sous l'identifiant fixe de l'application, puis activation
    $out = & $pc /duplicatescheme $ids[0] $ids[-1] 2>&1
    if ($LASTEXITCODE -ne 0) { throw ('plan indisponible sur ce poste (powercfg /duplicatescheme : {0})' -f ("$out".Trim())) }
    $out = & $pc /setactive $ids[-1] 2>&1
    if ($LASTEXITCODE -ne 0) { throw ('activation refusée (powercfg /setactive : {0})' -f ("$out".Trim())) }
}

# ---------- DNS des cartes réseau actives (physiques, connectées) : fournisseurs connus et modèles DNS over HTTPS
$DnsProviders = [ordered]@{
    Cloudflare = @{ V4 = @('1.1.1.1', '1.0.0.1'); V6 = @('2606:4700:4700::1111', '2606:4700:4700::1001'); Doh = 'https://cloudflare-dns.com/dns-query' }
    Quad9      = @{ V4 = @('9.9.9.9', '149.112.112.112'); V6 = @('2620:fe::fe', '2620:fe::9'); Doh = 'https://dns.quad9.net/dns-query' }
    Google     = @{ V4 = @('8.8.8.8', '8.8.4.4'); V6 = @('2001:4860:4860::8888', '2001:4860:4860::8844'); Doh = 'https://dns.google/dns-query' }
    AdGuard    = @{ V4 = @('94.140.14.14', '94.140.15.15'); V6 = @('2a10:50c0::ad1:ff', '2a10:50c0::ad2:ff'); Doh = 'https://dns.adguard-dns.com/dns-query' }
}
function Get-DnsAdapter { @(Get-NetAdapter -Physical -ErrorAction Stop | Where-Object { "$($_.Status)" -eq 'Up' }) }
# fournisseur en vigueur : DNS IPv4 de la 1re carte active ; DHCP (aucun serveur fixé dans le registre de la carte) = Auto
function Get-DnsProvider {
    $ad = @(Get-DnsAdapter); if (-not $ad.Count) { return 'Auto' }
    $a = $ad[0]
    $static = "$(Get-RegValue "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$($a.InterfaceGuid)" 'NameServer')".Trim()
    if (-not $static) { return 'Auto' }
    $ips = @($static -split '[ ,]+' | Where-Object { $_ })
    foreach ($k in $DnsProviders.Keys) { if ($DnsProviders[$k].V4 -contains $ips[0]) { return $k } }
    'Other'
}
function Set-DnsProvider([string]$Key) {
    if ($Key -ne 'Auto' -and -not $DnsProviders.Contains($Key)) { return }
    $ad = @(Get-DnsAdapter); if (-not $ad.Count) { throw 'aucune carte réseau active.' }
    $p = $DnsProviders[$Key]
    # chiffrement (Windows 11) : modèle DoH enregistré pour chaque adresse du fournisseur, montée en DoH automatique,
    # repli en clair autorisé (pas de coupure si le chiffrement échoue)
    if ($p -and $Build -ge 22000) {
        foreach ($ip in @($p.V4) + @($p.V6)) {
            try {
                if (Get-DnsClientDohServerAddress -ServerAddress $ip -ErrorAction SilentlyContinue) { Set-DnsClientDohServerAddress -ServerAddress $ip -DohTemplate $p.Doh -AllowFallbackToUdp $true -AutoUpgrade $true -ErrorAction Stop }
                else { Add-DnsClientDohServerAddress -ServerAddress $ip -DohTemplate $p.Doh -AllowFallbackToUdp $true -AutoUpgrade $true -ErrorAction Stop }
            } catch { Write-Ignored "DNS chiffré ($ip)" $_ }
        }
    }
    foreach ($a in $ad) {
        if ($Key -eq 'Auto') { Set-DnsClientServerAddress -InterfaceIndex $a.ifIndex -ResetServerAddresses -ErrorAction Stop }
        else { Set-DnsClientServerAddress -InterfaceIndex $a.ifIndex -ServerAddresses (@($p.V4) + @($p.V6)) -ErrorAction Stop }
    }
    Clear-DnsClientCache -ErrorAction SilentlyContinue
    Write-UiLog ('DNS : {0} sur {1}.' -f $(if ($Key -eq 'Auto') { 'automatique (box / routeur)' } else { "$Key ($($p.V4 -join ', '))" + $(if ($Build -ge 22000) { ', chiffré si possible' } else { '' }) }), ((@($ad | ForEach-Object { $_.Name })) -join ', ')) 'APP'
}
