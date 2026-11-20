$cvTop = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$OsCaption = "$($cvTop.ProductName)"; if ([int]$cvTop.CurrentBuild -ge 22000) { $OsCaption = $OsCaption -replace '^Windows 10', 'Windows 11' }
$verTop = if ($cvTop.DisplayVersion) { $cvTop.DisplayVersion } else { $cvTop.ReleaseId }
$Ui.AppInfo.Text = ('Oliv_Maintenance v{0}   ·   Poste {1}   ·   {2} {3} (build {4}.{5})   ·   Utilisateur ciblé : {6}' -f `
    $AppVersion, $env:COMPUTERNAME, $OsCaption, $verTop, $cvTop.CurrentBuild, $cvTop.UBR, $UserName)

$PageNames = 'Info', 'Maint', 'Perf', 'Secu', 'Perso', 'Apps', 'Svc', 'Tools', 'Log'
# Trait sous l'onglet actif : glisse d'un onglet à l'autre (animation de Canvas.Left, 260 ms, décélération)
function Move-TabIndicator([string]$Name, [bool]$Animate = $true) {
    $b = $Ui["Nav$Name"]; $ind = $Ui.TabIndicator; $cv = $Ui.TabCanvas
    if (-not $b -or $b.ActualWidth -le 0) { return }
    $p = $b.TranslatePoint([Windows.Point]::new(0, 0), $cv)
    $x = $p.X + ($b.ActualWidth - $ind.Width) / 2
    [Windows.Controls.Canvas]::SetTop($ind, $p.Y + $b.ActualHeight - 6)
    $from = [Windows.Controls.Canvas]::GetLeft($ind)
    if ($Animate -and $ind.Visibility -eq 'Visible' -and -not [double]::IsNaN($from)) {
        $ind.BeginAnimation([Windows.Controls.Canvas]::LeftProperty, (New-Anim $from $x 280))
        Lock-Anim 280
    } else {
        $ind.BeginAnimation([Windows.Controls.Canvas]::LeftProperty, $null)
        [Windows.Controls.Canvas]::SetLeft($ind, $x)
    }
    $ind.Visibility = 'Visible'
}
# Changement d'onglet : page affichée (avec son effet de glissement) puis trait déplacé sous l'onglet
function Show-Page([string]$Name) {
    foreach ($p in $PageNames) { $Ui["Nav$p"].Tag = $(if ($p -eq $Name) { 'on' } else { '' }) }
    $Sync.CurPage = $Name
    if ($Name -eq 'Settings') { $Ui.TabIndicator.Opacity = 0; Show-PageContent $Name; return }
    $Sync.LastPage = $Name
    $back = $Ui.TabIndicator.Opacity -eq 0; $Ui.TabIndicator.Opacity = 1
    $Sync.TabMoveTime = [DateTime]::Now
    # page d'abord (sa mise en page est faite avant le départ des horloges), puis le trait : les 2 effets partent ensemble
    Show-PageContent $Name
    Move-TabIndicator $Name (-not $back)
}
function Show-PageContent([string]$Name) {
    if ($Name -in 'Perf', 'Secu', 'Perso' -and -not $Lazy.Done) {
        $Window.Cursor = [Windows.Input.Cursors]::Wait
        try { New-DeferredPage } finally { $Window.Cursor = $null }
    }
    if ($Name -eq 'Settings' -and -not $SetUI.Built) { New-SettingsPage }
    if ($Name -eq 'Svc' -and -not $SvcUI.Fresh -and -not $SvcUI.Reading) { Start-SvcRead }
    if ($Name -eq 'Tools' -and -not $ToolsUI.Built) { New-ToolsPage }
    # Applications : ouverture sur les applications installées (Mes applications)
    if ($Name -eq 'Apps' -and -not $AppsUI.Mode) { Set-AppsMode 'Mine' }
    foreach ($p in $PageNames) { $Ui["Page$p"].Visibility = $(if ($p -eq $Name) { 'Visible' } else { 'Collapsed' }) }
    $Ui.PageSettings.Visibility = $(if ($Name -eq 'Settings') { 'Visible' } else { 'Collapsed' })
    if ($Name -eq 'Settings') { Update-SnapshotList; try { Update-CardSetting } catch { Write-Ignored 'Cartes affichées' $_ } }
    try { Update-CardVisibility $Name } catch { Write-Ignored 'Cartes masquées' $_ }
    # cartes construites après coup (collectes de l'Accueil...) : 2e passage une fois la page affichée
    Invoke-AfterAnim { try { Update-CardVisibility "$($Sync.ShownPage)" } catch { Write-Ignored 'Cartes masquées' $_ } }
    # sens du glissement : Paramètres arrive par la droite et en repart vers la page d'avant (par la gauche) ;
    # d'onglet à onglet, la page arrive du côté de l'onglet choisi
    $prev = $Sync.ShownPage
    if ($prev -and $prev -ne $Name) {
        $dx = $(if ($Name -eq 'Settings') { 32 } elseif ($prev -eq 'Settings') { -32 }
                elseif ([array]::IndexOf([string[]]$PageNames, $Name) -ge [array]::IndexOf([string[]]$PageNames, [string]$prev)) { 24 } else { -24 })
        Show-PageTransition $Ui["Page$Name"] $dx
    }
    $Sync.ShownPage = $Name
    if ($Name -eq 'Log') { Sync-LogView }
    $Sync.InfoVisible = ($Name -eq 'Info'); if ($Sync.InfoVisible) { $Sync.VolRequest = $true }
    Update-Footer
    # rafraîchissement de l'Accueil après l'effet (le fil d'interface reste libre pendant le glissement)
    if ($Name -eq 'Info' -and $InfoUI.F) {
        Invoke-AfterAnim {
            if ($Sync.ShownPage -ne 'Info') { return }
            try { Update-InfoFast -Force } catch { Write-Ignored 'Accueil' $_ }
            if ($Sync.Diag -and ([DateTime]::Now - $Sync.Diag.Stamp).TotalMinutes -ge 5) { Start-DiagCollector }
        }
    }
}

