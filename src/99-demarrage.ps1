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
# erreur non interceptée dans un gestionnaire d'interface (clic, minuteur) : consignée dans le journal, l'application reste
# ouverte au lieu de se fermer en erreur fatale
$Window.Dispatcher.Add_UnhandledException({
    param($s, $e)
    $x = $e.Exception; $er = $(if ($x -is [Management.Automation.IContainsErrorRecord]) { $x.ErrorRecord } else { $null })
    $where = $(if ($er -and $er.InvocationInfo) { ' (ligne {0} : {1})' -f $er.InvocationInfo.ScriptLineNumber, "$($er.InvocationInfo.Line)".Trim() } else { '' })
    try { Write-UiLog ('Erreur interne interceptée : {0}{1}' -f $x.Message, $where) 'ERROR' } catch { if ($SelfTest) { [void]$SelfTest.Errors.Add($x.Message) } }
    $e.Handled = $true
})
Start-MainWindow
# Autotest (variable d'environnement _OLIVM_SELFTEST=1, lancé par le test automatique Windows de GitHub avant toute
# publication) : chaque onglet affiché tour à tour (pages différées construites, Paramètres compris), 4 s par onglet pour
# laisser tourner minuteurs et lectures de fond, puis bilan : erreurs consignées (ERROR) et exceptions de l'interface.
# Code de sortie = nombre d'erreurs ; bilan écrit dans le fichier désigné par _OLIVM_SELFTEST_OUT.
if ($SelfTest) {
    $SelfTest.Pages = [Collections.Queue]::new([object[]]@($PageNames + 'Settings' + 'Info'))
    $SelfTest.Timer = [Windows.Threading.DispatcherTimer]::new(); $SelfTest.Timer.Interval = [TimeSpan]::FromSeconds(4)
    $SelfTest.Timer.Add_Tick({
        try {
            if ($SelfTest.Pages.Count) { $pg = $SelfTest.Pages.Dequeue(); $SelfTest.Seen.Add($pg); Show-Page $pg; return }
            if ($Ui.AppsModePre) { foreach ($m in 'Inst', 'Pre') { try { Set-AppsMode $m } catch { [void]$SelfTest.Errors.Add("Applications ($m) : $($_.Exception.Message)") } } }
        } catch { [void]$SelfTest.Errors.Add("Onglet $pg : $($_.Exception.Message)") ; return }
        $SelfTest.Timer.Stop()
        $out = @('Oliv_Maintenance {0} - autotest {1:yyyy-MM-dd HH:mm:ss}' -f $AppVersion, (Get-Date), ('onglets : ' + ($SelfTest.Seen -join ', ')), ('erreurs : {0}' -f $SelfTest.Errors.Count)) + @($SelfTest.Errors | ForEach-Object { '  - ' + $_ })
        try { if ($env:_OLIVM_SELFTEST_OUT) { [IO.File]::WriteAllLines($env:_OLIVM_SELFTEST_OUT, [string[]]$out, [Text.UTF8Encoding]::new($false)) } } catch { $null = $_ }
        [Environment]::Exit([math]::Min(250, $SelfTest.Errors.Count))
    })
    $SelfTest.Timer.Start()
}
[Windows.Threading.Dispatcher]::Run()
Exit-App 0
