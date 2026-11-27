$Lazy = @{ Done = $false; Steps = $null; Clock = $null }
$StartupSort = 'Nom'
function New-StartupCard {
    $script:su = New-Card 'Applications au démarrage' "Utilisateur : $UserName" ([string][char]0xE768)
    # barre : dossier Démarrage à gauche (aligné sur les noms), tri à droite (aligné sur la colonne des interrupteurs)
    $script:suBar = [Windows.Controls.DockPanel]::new()
    $suBar.Margin = New-Thickness 50 0 16 10; $suBar.LastChildFill = $false
    $script:suFolder  = New-Button 'Ouvrir le dossier Démarrage'
    [void]$suBar.Children.Add($suFolder)
    $sortBox = [Windows.Controls.StackPanel]::new(); $sortBox.Orientation = 'Horizontal'; [Windows.Controls.DockPanel]::SetDock($sortBox, 'Right')
    [void](Add-CardIcon $su 0xE72C 'Actualiser' { Update-StartupList; Update-PendingBar; Write-FileLog 'Applications au démarrage relues (modifications non appliquées conservées).' 'APP' })
    $sl = New-Text 'Trier :' 'Muted'; $sl.FontSize = 13; $sl.VerticalAlignment = 'Center'; $sl.Margin = New-Thickness 12 0 8 0
    [void]$sortBox.Children.Add($sl)
    $script:suSortName  = New-Button 'Nom'
    $script:suSortState = New-Button 'Actives d''abord'
    $suSortName.MinWidth = 70; $suSortName.Tag = 'Nom'; $suSortState.Tag = ''
    $suSortState.Margin = New-Thickness 0 0 0 0
    [void]$sortBox.Children.Add($suSortName); [void]$sortBox.Children.Add($suSortState); [void]$suBar.Children.Add($sortBox)
    [void]$su.Body.Children.Add($suBar)
    $script:StartupList = [Windows.Controls.StackPanel]::new()
    [void]$su.Body.Children.Add($StartupList)
    Add-Spacer $su.Body; [Windows.Controls.Grid]::SetIsSharedSizeScope($su.Card, $true)
    [void]$Ui.PerfRight.Children.Add($su.Card)
    try { Update-StartupList } catch { Write-UiLog "Lecture des applications au démarrage : $($_.Exception.Message)" 'ERROR' }

    $sortClick = {
        param($s, $e)
        $script:StartupSort = $(if ($s -eq $suSortState) { 'Etat' } else { 'Nom' })
        $suSortName.Tag  = $(if ($StartupSort -eq 'Nom') { 'on' } else { '' })
        $suSortState.Tag = $(if ($StartupSort -eq 'Etat') { 'on' } else { '' })
        Update-StartupList
    }
    $suSortName.Add_Click($sortClick); $suSortState.Add_Click($sortClick)
    $suSortName.Tag = 'on'
    $suFolder.Add_Click({ Start-Process explorer.exe -ArgumentList ('"{0}"' -f (Join-Path $UserProfilePath 'AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup')) })
}
function New-DebloatCard {
    $script:dx = New-Card 'Applications préinstallées' '' ([string][char]0xE74D)
    # liste lue en arrière-plan dès la construction de la carte ; icône Actualiser pour la relire (désinstallation : bandeau du bas)
    $script:dxRefresh = Add-CardIcon $dx 0xE72C 'Actualiser' { Update-AppxList }
    $script:AppxList = [Windows.Controls.StackPanel]::new()
    $AppxList.Margin = New-Thickness 50 0 16 12
    [void]$dx.Body.Children.Add($AppxList)
    # onglet Applications, mode « Préinstallées »
    [void]$Ui.AppsPreList.Children.Add($dx.Card)
    # lecture lancée au démarrage (fin de ce fichier) : résultat affiché s'il est arrivé, sinon à son arrivée (minuteur)
    if ($Sync.AppxScan) { Show-AppxList }
    elseif ($Sync.AppxRunning) {
        $t = New-Text 'Lecture des applications installées...' 'Muted'
        $t.Margin = New-Thickness 8 4 0 4
        [void]$AppxList.Children.Add($t)
    }
    else { Update-AppxList }
}
function Initialize-LazyStep {
    $q = [System.Collections.Queue]::new()
    $q.Enqueue(@{ K = 'GameMode' })
    $q.Enqueue(@{ K = 'Startup' })
    foreach ($g in @($Tweaks | Where-Object { $_.Page -eq 'Perf' } | ForEach-Object { $_.Group } | Select-Object -Unique)) {
        $q.Enqueue(@{ K = 'T'; Page = 'Perf'; Group = $g })
    }
    foreach ($g in @($Tweaks | Where-Object { $_.Page -eq 'Secu' } | ForEach-Object { $_.Group } | Select-Object -Unique)) {
        $q.Enqueue(@{ K = 'T'; Page = 'Secu'; Group = $g })
    }
    foreach ($g in @($Tweaks | Where-Object { $_.Page -eq 'Perso' } | ForEach-Object { $_.Group } | Select-Object -Unique)) {
        $q.Enqueue(@{ K = 'T'; Page = 'Perso'; Group = $g })
    }
    $q.Enqueue(@{ K = 'Lang' })
    $q.Enqueue(@{ K = 'Debloat' })
    $q.Enqueue(@{ K = 'End' })
    $Lazy.Steps = $q
    $Lazy.Clock = [Diagnostics.Stopwatch]::StartNew()
}
function Invoke-LazyStep {
    if (-not $Lazy.Steps -or $Lazy.Steps.Count -eq 0) { return $false }
    $s = $Lazy.Steps.Dequeue()
    # cartes de réglages : attente des lectures lentes faites en arrière-plan (Start-TweakPrefetch), 30 s au plus
    if ($s.K -eq 'T' -and $Sync.TwPreSrc -and -not $Sync.TwPreDone -and -not $Lazy.PreWait) { $Lazy.PreWait = [DateTime]::Now }
    if ($s.K -eq 'T' -and $Sync.TwPreSrc -and -not $Sync.TwPreDone -and ([DateTime]::Now - $Lazy.PreWait).TotalSeconds -lt 30) {
        $q2 = [Collections.Queue]::new(); $q2.Enqueue($s); while ($Lazy.Steps.Count) { $q2.Enqueue($Lazy.Steps.Dequeue()) }; $Lazy.Steps = $q2
        Start-Sleep -Milliseconds 50; return $true
    }
    switch ($s.K) {
        'T' {
            if ($s.Page -eq 'Perf') { Add-TweakCard 'Perf' $Ui.PerfLeft $Ui.PerfRight @('Windows Update') $s.Group }
            elseif ($s.Page -eq 'Secu') {
                # Sécurité + Réseau | Confidentialité | Publicités et suggestions (Set-SecuLayout)
                $pn = $(switch ($s.Group) { 'Confidentialité' { $Ui.SecuMid } 'Publicités et suggestions' { $Ui.SecuRight } default { $Ui.SecuLeft } })
                Add-TweakCard 'Secu' $pn $pn @() $s.Group
            }
            else { Add-TweakCard 'Perso' $Ui.PersoLeft $Ui.PersoRight @('Explorateur, souris et presse-papiers', 'Intelligence artificielle') $s.Group }
        }
        'GameMode' { New-GameCard }
        'Startup' { New-StartupCard }
        'Lang' { try { New-LangCard } catch { Write-Ignored 'Langues et claviers' $_ } }
        'Debloat' { New-DebloatCard }
        'End' {
            $Lazy.Done = $true
            Update-ApplyButton; Update-PendingBar
            # libération de la mémoire du démarrage, une fois les premières collectes terminées
            $mt = [Windows.Threading.DispatcherTimer]::new(); $mt.Interval = [TimeSpan]::FromSeconds(15)
            $mt.Add_Tick({ param($s, $e)
                $s.Stop()
                try { Invoke-MemoryTrim } catch { Write-Ignored 'Libération de la mémoire' $_ }
            })
            $mt.Start()
        }
    }
    $true
}
function Invoke-LazyNext {
    # réglages : attente de la détection matérielle d'arrière-plan (8 s au plus, fil d'interface libre) plutôt que de la
    # refaire au premier plan (requêtes WMI et Appx bloquantes)
    if (-not (Test-NeedPreReady) -and $Lazy.Steps -and $Lazy.Steps.Count -and $Lazy.Steps.Peek().K -eq 'T' -and $Lazy.Clock.Elapsed.TotalSeconds -lt 8) {
        if (-not $Lazy.Wait) {
            $Lazy.Wait = [Windows.Threading.DispatcherTimer]::new()
            $Lazy.Wait.Interval = [TimeSpan]::FromMilliseconds(150)
            $Lazy.Wait.Add_Tick({ $Lazy.Wait.Stop(); Invoke-LazyNext })
        }
        $Lazy.Wait.Start(); return
    }
    if (Invoke-LazyStep) { [void]$Window.Dispatcher.BeginInvoke([Action]{ Invoke-LazyNext }, [Windows.Threading.DispatcherPriority]::Background) }
}
function New-DeferredPage {
    if ($Lazy.Done) { return }
    if (-not $Lazy.Steps) { Initialize-LazyStep }
    while (Invoke-LazyStep) { }
}

function Get-AppxRow { if (-not $AppxList) { return @() }; @($AppxList.Children) + @($AppxList.Children | Where-Object { $_ -is [Windows.Controls.StackPanel] } | ForEach-Object { $_.Children }) | Where-Object { $_ -is [Windows.Controls.Border] -and $_.Tag.Check } }
function Get-AppxChecked { @(Get-AppxRow | Where-Object { $_.Tag.Check.IsChecked }) }
function Update-AppxRemoveBtn { Update-ApplyButton }
$AppxAfter = { Update-AppxRemoveBtn }
# Lecture des applications installées et provisionnées en arrière-plan (Get-AppxPackage -AllUsers prend plusieurs secondes)
$AppxScanScript = @'
$r = @{ Inst = @(); Prov = @(); Error = $null }
try { $r.Inst = @(Get-AppxPackage -AllUsers -ErrorAction Stop | ForEach-Object { $_.Name }) } catch { $r.Error = $_.Exception.Message }
try { $r.Prov = @(Get-AppxProvisionedPackage -Online -ErrorAction Stop | ForEach-Object { $_.DisplayName }) } catch {
    if (-not $r.Error) { $r.Error = $_.Exception.Message }
}
$r.Stamp = [DateTime]::Now
$Sync.AppxScan = $r
$Sync.AppxRunning = $false
'@
function Update-AppxList {
    if (-not $AppxList) { return }
    Close-BgJob
    if ($Sync.AppxRunning -or $BgJobs.ContainsKey('Appx')) { return }
    $Sync.AppxRunning = $true
    $AppxList.Children.Clear()
    $t = New-Text 'Lecture des applications installées...' 'Muted'; $t.Margin = New-Thickness 8 4 0 4; [void]$AppxList.Children.Add($t)
    Update-AppxRemoveBtn
    Start-BgJob 'Appx' $AppxScanScript
}
function Show-AppxList {
    $r = $Sync.AppxScan; if (-not $r -or -not $AppxList) { return }
    # résultat affiché une seule fois (carte construite après l'arrivée du résultat : pas de 2e rendu par le minuteur)
    $script:AppxShown = $r.Stamp
    $AppxList.Children.Clear()
    $inst = @($r.Inst); $prov = @($r.Prov)
    $count = 0; $more = [Windows.Controls.StackPanel]::new()
    foreach ($a in (Get-SortedByLabel $AppxCatalog 'L')) {
        if (($inst -contains $a.N) -or ($prov -contains $a.N)) {
            $cb = New-HoverCheck $(if ($count -lt $ListMax) { $AppxList } else { $more }) ('{0}  ({1})' -f $a.L, $a.N) $(if ($a.C) { 'Application souvent utilisée (assistance, messagerie, jeux) : ne la supprimer que si elle ne sert pas sur ce poste.' } else { '' }) $AppxAfter
            $cb.Uid = '{0}  ({1})' -f $a.L, $a.N
            if ($a.C) {
                $sp = [Windows.Controls.StackPanel]::new(); $sp.Orientation = 'Horizontal'
                [void]$sp.Children.Add((New-Text $cb.Uid))
                $tg = New-Text 'à conserver si utilisée'
                $tg.FontSize = 11
                $tg.Margin = New-Thickness 10 1 0 0
                $tg.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'WarnFgBrush')
                [void]$sp.Children.Add($tg); $cb.Content = $sp
            }
            $cb.Tag = $a.N; $count++
        }
    }
    if ($count -eq 0) {
        $t = New-Text $(if ($r.Error) { "Lecture impossible : $($r.Error)" } else { 'Aucune application de la liste n''est installée.' }) 'Muted'
        $t.Margin = New-Thickness 8 4 0 4
        [void]$AppxList.Children.Add($t)
    }
    Add-FoldMore $AppxList $more $count 'Appx'
    Update-AppxRemoveBtn
    Write-UiLog $(if ($r.Error) { "Applications préinstallées : $($r.Error)" } else { "Applications préinstallées : $count de la liste $(Get-Plural $count 'présente' 'présentes')." }) $(if ($r.Error) { 'WARN' } else { 'APP' })
}
# applications installées lues dès le chargement (partagées avec les détections des réglages : une seule lecture Appx)
$Sync.AppxRunning = $true; Start-BgJob 'Appx' $AppxScanScript
