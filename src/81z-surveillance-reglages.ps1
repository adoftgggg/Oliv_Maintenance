# ---------- Réglages modifiés en dehors de l'application, et mise à jour de Windows
# État de référence : valeurs de tous les réglages au dernier passage de l'application (_etat\reglages-reference.json, avec
# la build et la version de Windows). Mis à jour à chaque réglage appliqué par l'application et à la fermeture. À l'ouverture
# (une fois l'interface au repos), comparaison avec les valeurs du moment : un réglage qui a changé sans l'application (Windows,
# une mise à jour, un autre logiciel, une stratégie) est signalé par un bandeau d'activité ; si la version de Windows a changé
# entre-temps (mise à jour de fonctionnalité), le bandeau le dit et propose de réappliquer la configuration d'avant.
$TweakRefFile = Join-Path (Get-LogPath 'Etat') 'reglages-reference.json'
$GameTweakIds = 'PowerPlan', 'Hags', 'MousePrecision', 'GameModeWin'
$TweakWatch = @{ Row = $null; Diff = @(); Checked = $false }
function Get-WinVersionTag { '{0}|{1}' -f $Build, $WinDisplayVer }
function Save-TweakReference {
    if (-not $TweakWatch.Checked) { return }   # rien d'écrit avant la comparaison de l'ouverture (sinon les écarts seraient effacés)
    $vals = [ordered]@{}; foreach ($r in @($TweakRows)) { if ($r.Tweak -and $r.Enabled -and $null -ne $r.Current) { $vals["$($r.Tweak.Id)"] = $r.Current } }
    if (-not $vals.Count) { return }
    try { [IO.File]::WriteAllText($TweakRefFile, (ConvertTo-Json -InputObject ([ordered]@{ Win = (Get-WinVersionTag); Game = [bool](Get-GameModeOn); Display = "$WinDisplayVer"; Build = $Build; Date = [DateTime]::Now.ToString('o'); Values = $vals }) -Depth 3), [Text.UTF8Encoding]::new($false)) }
    catch { Write-Ignored 'Réglages de référence' $_ }
}
# changement fait par l'application (réglage, mode jeu, restauration) : valeurs relues et reportées tout de suite dans la
# référence, même avant la comparaison de l'ouverture (sinon la volonté de l'utilisateur était signalée comme un écart)
function Update-TweakReference([string[]]$Ids) {
    $ref = $null
    if (Test-Path -LiteralPath $TweakRefFile) { try { $ref = Get-Content -LiteralPath $TweakRefFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $ref = $null } }
    if (-not $ref) { if ($TweakWatch.Checked) { Save-TweakReference }; return }
    $vals = [ordered]@{}; foreach ($p in $ref.Values.PSObject.Properties) { $vals[$p.Name] = $p.Value }
    foreach ($id in $Ids) {
        $tw = @($Tweaks | Where-Object { "$($_.Id)" -eq $id })[0]; if (-not $tw) { continue }
        try { $v = Get-TweakValue $tw; if ($null -ne $v) { $vals[$id] = $v } } catch { Write-Ignored 'Réglages de référence' $_ }
    }
    # écart déjà signalé pour ces réglages : retiré du bandeau
    if ($TweakWatch.Diff) { $TweakWatch.Diff = @($TweakWatch.Diff | Where-Object { "$($_.R.Tweak.Id)" -notin $Ids }); if (-not $TweakWatch.Diff.Count) { Close-TweakDriftBanner } }
    try { [IO.File]::WriteAllText($TweakRefFile, (ConvertTo-Json -InputObject ([ordered]@{ Win = "$($ref.Win)"; Game = [bool](Get-GameModeOn); Display = "$($ref.Display)"; Build = $ref.Build; Date = [DateTime]::Now.ToString('o'); Values = $vals }) -Depth 3), [Text.UTF8Encoding]::new($false)) }
    catch { Write-Ignored 'Réglages de référence' $_ }
}
function Test-TweakReference {
    if ($TweakWatch.Checked) { return }
    if (-not $Lazy.Done) { New-DeferredPage }
    $ref = $null
    if (Test-Path -LiteralPath $TweakRefFile) { try { $ref = Get-Content -LiteralPath $TweakRefFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch { Write-Ignored 'Réglages de référence' $_ } }
    $TweakWatch.Checked = $true
    if (-not $ref) { Save-TweakReference; return }   # 1re ouverture : référence posée, rien à comparer
    # valeurs relues maintenant (la ligne garde la valeur de sa construction) ; seules les valeurs encore applicables sont comparées
    # réglages à lecture lente (Defender, pare-feu, partage SMB : modules CIM, plusieurs secondes sur le fil d'interface,
    # fenêtre figée) : pas relus, valeur de construction des lignes (lue en arrière-plan au démarrage, moins de 20 s avant)
    foreach ($r in @($TweakRows)) { if ($r.Tweak -and $r.Enabled -and -not $r.Pending -and -not ($r.Tweak.Get -and $r.Tweak.Get.ToString() -match $TwSlowPattern)) { try { $now = Get-TweakValue $r.Tweak; if ("$now" -ne "$($r.Current)") { $r.Current = $now; Set-RowDisplay $r $now } } catch { $null = $_ } } }
    $diff = Get-SnapshotDiff ([pscustomobject]@{ Values = $ref.Values })
    # mode jeu activé ou désactivé depuis (application ou raccourcis du Bureau) : ses réglages ont changé par la volonté de
    # l'utilisateur, jamais signalés
    if ($null -ne $ref.Game -and [bool]$ref.Game -ne [bool](Get-GameModeOn)) { $diff = @($diff | Where-Object { "$($_.R.Tweak.Id)" -notin $GameTweakIds }) }
    $TweakWatch.Diff = $diff
    $winChanged = "$($ref.Win)" -and "$($ref.Win)" -ne (Get-WinVersionTag)
    if ($winChanged) { Write-UiLog ('Windows a été mis à jour depuis la dernière ouverture : {0} (build {1}) > {2} (build {3}).' -f $ref.Display, $ref.Build, $WinDisplayVer, $Build) 'APP' }
    if (-not $diff.Count) { Save-TweakReference; return }
    Write-UiLog ('{0} {1} hors de l''application depuis la dernière ouverture : {2}' -f $diff.Count, (Get-Plural $diff.Count 'réglage modifié' 'réglages modifiés'), (@($diff | ForEach-Object { $_.Line }) -join ' ; ')) 'WARN'
    Show-TweakDriftBanner $diff $(if ($winChanged) { $ref } else { $null })
}
# bandeau d'activité (même zone que les erreurs et les mises à jour de logiciels) : Voir et rétablir / Garder les valeurs actuelles
function Show-TweakDriftBanner($Diff, $Ref) {
    if (-not $Ui.BgList) { return }
    if ($TweakWatch.Row) { [void]$Ui.BgList.Children.Remove($TweakWatch.Row) }
    $g = [Windows.Controls.Grid]::new(); $g.Margin = New-Thickness 0 2 0 2
    [void]$g.ColumnDefinitions.Add([Windows.Controls.ColumnDefinition]::new()); $c = [Windows.Controls.ColumnDefinition]::new(); $c.Width = [Windows.GridLength]::Auto; [void]$g.ColumnDefinitions.Add($c)
    $n = @($Diff).Count
    $txt = $(if ($Ref) { 'Windows mis à jour ({0} > {1}) : {2} {3} depuis' -f $Ref.Display, $WinDisplayVer, $n, (Get-Plural $n 'réglage a été remis à son état d''origine ou modifié' 'réglages ont été remis à leur état d''origine ou modifiés') } else { '{0} {1} en dehors de l''application depuis la dernière ouverture' -f $n, (Get-Plural $n 'réglage modifié' 'réglages modifiés') })
    $t = New-Text $txt; $t.FontWeight = [Windows.FontWeights]::SemiBold; $t.TextTrimming = 'CharacterEllipsis'; $t.VerticalAlignment = 'Center'
    $t.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'WarnFgBrush'); $t.ToolTip = (@($Diff | ForEach-Object { $_.Line }) -join "`n"); [void]$g.Children.Add($t)
    $sp = [Windows.Controls.StackPanel]::new(); $sp.Orientation = 'Horizontal'; [Windows.Controls.Grid]::SetColumn($sp, 1)
    $b1 = New-Button $(if ($Ref) { 'Réappliquer ma configuration' } else { 'Voir et rétablir' }) 'PrimaryBtn'; $b1.Height = 30; $b1.Margin = New-Thickness 12 0 0 0; $b1.Add_Click({ Restore-TweakReference })
    $b2 = New-Button 'Garder les valeurs actuelles'; $b2.Height = 30; $b2.Margin = New-Thickness 6 0 0 0
    $b2.Add_Click({ Close-TweakDriftBanner; Save-TweakReference; Write-UiLog 'Réglages modifiés hors de l''application : valeurs actuelles gardées (nouvelle référence).' 'APP'; Show-Toast 'Valeurs actuelles gardées' })
    [void]$sp.Children.Add($b1); [void]$sp.Children.Add($b2); [void]$g.Children.Add($sp)
    $Ui.BgList.Children.Insert(0, $g); $TweakWatch.Row = $g; $Ui.BgBar.Visibility = 'Visible'
}
function Close-TweakDriftBanner {
    if ($TweakWatch.Row) { [void]$Ui.BgList.Children.Remove($TweakWatch.Row); $TweakWatch.Row = $null }
    if (-not $Ui.BgList.Children.Count) { $Ui.BgBar.Visibility = 'Collapsed' }
}
function Restore-TweakReference {
    $diff = @($TweakWatch.Diff); if (-not $diff.Count) { Close-TweakDriftBanner; return }
    if ($Sync.Running) { Show-Info 'Une tâche est en cours : rétablir les réglages une fois terminée.'; return }
    if (-not (Confirm-List ('Rétablir {0} {1} ?' -f $diff.Count, (Get-Plural $diff.Count 'réglage' 'réglages')) @($diff | ForEach-Object { $_.Line }) 'Valeur actuelle > valeur rétablie (celle du dernier passage de l''application). Un instantané des réglages actuels est enregistré avant.' 'Rétablir')) { return }
    Save-TweakSnapshot 'Avant le rétablissement des réglages modifiés hors de l''application' @($diff | ForEach-Object { $_.Line })
    foreach ($d in $diff) { Invoke-TweakChange $d.R $d.V }
    Update-ApplyButton
    Close-TweakDriftBanner; $TweakWatch.Diff = @()
    Save-TweakReference
    Write-UiLog ('{0} {1}.' -f $diff.Count, (Get-Plural $diff.Count 'réglage rétabli' 'réglages rétablis')) 'OK'
    Add-SessionEvent 'Réglages' 'Réglages modifiés hors de l''application' ('{0} rétabli(s)' -f $diff.Count) 'ok'
    Show-Toast ('{0} {1}' -f $diff.Count, (Get-Plural $diff.Count 'réglage rétabli' 'réglages rétablis'))
}
# comparaison lancée une fois l'application au repos (pages de réglages construites en arrière-plan d'interface)
$TweakWatch.Timer = [Windows.Threading.DispatcherTimer]::new(); $TweakWatch.Timer.Interval = [TimeSpan]::FromSeconds(20)
$TweakWatch.Timer.Add_Tick({ $TweakWatch.Timer.Stop(); try { Test-TweakReference } catch { Write-Ignored 'Réglages modifiés hors de l''application' $_ } })
$TweakWatch.Timer.Start()
