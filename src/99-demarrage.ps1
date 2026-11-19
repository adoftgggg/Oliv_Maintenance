Initialize-InfoPage
Update-CleanSize
Update-ApplyButton
Update-MaxState
$sp = 'Info'
try {
    if (Test-Path -LiteralPath $StartFile) { $sp = [IO.File]::ReadAllText($StartFile).Trim() }
} catch {
    Write-Ignored 'Lecture de l''onglet de démarrage' $_
}
if ($sp -notin $PageNames) { $sp = 'Info' }
Show-Page $sp
$Sync.TimeUi = $AppClock.Elapsed.TotalSeconds
# redimensionnement : repositionnement direct, sauf juste après un changement d'onglet (l'animation est alors recalée)
$Ui.TabStrip.Add_SizeChanged({
    if (-not $Sync.CurPage) { return }
    $recent = $Sync.TabMoveTime -and ([DateTime]::Now - $Sync.TabMoveTime).TotalMilliseconds -lt 500
    Move-TabIndicator $Sync.CurPage $recent
})
$Window.Add_ContentRendered({
    if ($Sync.CurPage) { Move-TabIndicator $Sync.CurPage $false }
    if ($Sync.Started) { return }
    $Sync.Started = $true
    Write-UiLog ('Fenêtre affichée en {0:N1} s (préparation {1:N1} s).' -f $AppClock.Elapsed.TotalSeconds, $Sync.TimeUi) 'APP'
    Start-CleanScan
    Start-DiagCollector
    $Sync.WuOnline = $false; [void](Start-WuSearch)
    # recherche constructeur automatique dès l'affichage : premier lancement ou dernière recherche de plus de 7 jours
    $last = $null
    try { $last = [DateTime]::Parse("$($Sync.OemResult.Time)", [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind) } catch {}
    if (-not $last -or ([DateTime]::Now - $last).TotalDays -ge 7) { Start-OemScan $true }
    Initialize-LazyStep
    [void]$Window.Dispatcher.BeginInvoke([Action]{ Invoke-LazyNext }, [Windows.Threading.DispatcherPriority]::Background)
})
Write-UiLog ('Oliv_Maintenance {0} démarré - réglages utilisateur appliqués à {1} ({2})' -f $AppVersion, $UserName, $UserSid) 'APP'
if ($UpgradeNote) { Write-UiLog $UpgradeNote 'APP' }
if ($env:_OLIVM_EXE) { Write-UiLog "Lancé par $env:_OLIVM_EXE (script extrait dans $SelfPath)." 'APP' }
if ($AppDirState -eq 'fixed') { Write-UiLog "Droits du dossier $env:ProgramData\Oliv_Maintenance corrigés : écriture réservée aux administrateurs et à SYSTEM." }
elseif (-not $AppDirSafe) { Write-UiLog "Droits du dossier $env:ProgramData\Oliv_Maintenance non conformes ($AppDirState) : vérifier le propriétaire et les droits (icacls)." 'WARN' }
# erreurs survenues avant l'interface (rangement des journaux...)
foreach ($w in $EarlyWarn) { Write-UiLog $w 'WARN' }; $EarlyWarn.Clear()
# boucle de messages du répartiteur (et non ShowDialog) : la fenêtre peut être masquée dans la zone de notification sans
# terminer l'application ; fin de la boucle à la fermeture de la fenêtre
$Window.Add_Closed({ $Window.Dispatcher.InvokeShutdown() })
Start-MainWindow
[Windows.Threading.Dispatcher]::Run()
Exit-App 0
