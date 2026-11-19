# Tâches d'arrière-plan (runspaces) : création, lancement avec la bibliothèque Windows Update, nettoyage des tâches terminées.
# Ouvrir un runspace (CreateDefault2 + Open) prend 100 à 300 ms sur le fil d'interface. Des runspaces de réserve sont
# ouverts à l'avance (OpenAsync, hors fil d'interface) : 3 au démarrage (collectes lancées à l'affichage de la fenêtre),
# 1 ensuite (chaque runspace ouvert occupe plusieurs Mo) ; une tâche prend une réserve déjà ouverte et ne démarre en synchrone que si aucune n'est prête.
$SpareRs = [Collections.Generic.List[object]]::new()
# erreurs non bloquantes dans les runspaces : même règle que Write-Ignored (02-journaux.ps1), dans le journal de la tâche
# (Write-TaskLog) s'il existe, sinon directement à l'interface
$Sync.WarnOnce = $WarnOnce
$IgnoreLib = @'
function Write-Ignored([string]$What, $Err) {
    $m = $(if ($Err -is [Management.Automation.ErrorRecord]) { $Err.Exception.Message } elseif ($Err -is [Exception]) { $Err.Message } elseif ($Err) { "$Err" } else { 'erreur inconnue' })
    $k = "$What|$m"
    if ($Sync.WarnOnce) { if ($Sync.WarnOnce.ContainsKey($k)) { return }; $Sync.WarnOnce[$k] = 1 }
    if (Get-Command Write-TaskLog -CommandType Function -ErrorAction SilentlyContinue) { Write-TaskLog "$What : $m" 'WARN' }
    else { $Sync.Queue.Enqueue(('{0} [WARN ] {1} : {2}' -f (Get-Date -Format 'HH:mm:ss'), $What, $m)) }
}
'@
function New-BgRunspace([bool]$Async = $false) {
    $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault2()
    try { $iss.ExecutionPolicy = [Microsoft.PowerShell.ExecutionPolicy]::Bypass } catch {}
    $rs = [runspacefactory]::CreateRunspace($iss)
    if ($Async) { $rs.OpenAsync() } else { $rs.Open() }
    $rs
}
function Add-SpareRunspace([int]$Count) {
    while ($SpareRs.Count -lt $Count) { try { $SpareRs.Add((New-BgRunspace $true)) } catch { break } }
}
function Get-BgRunspace {
    $rs = $null
    foreach ($r in @($SpareRs)) {
        $st = "$($r.RunspaceStateInfo.State)"
        if ($st -eq 'Opened') { $rs = $r; [void]$SpareRs.Remove($r); break }
        if ($st -in 'Broken', 'Closed') { [void]$SpareRs.Remove($r); try { $r.Dispose() } catch {} }
    }
    if (-not $rs) { $rs = New-BgRunspace }
    Add-SpareRunspace 1
    $rs
}
function New-PsJob([string]$Script) {
    $rs = Get-BgRunspace
    $rs.SessionStateProxy.SetVariable('Sync', $Sync)
    $ps = [powershell]::Create(); $ps.Runspace = $rs
    [void]$ps.AddScript($IgnoreLib + "`n" + $Script)
    @{ PS = $ps; Handle = $ps.BeginInvoke() }
}
# état « en cours » remis à zéro à la fin de chaque tâche (y compris interrompue par une erreur) : nouvelle tentative possible
$BgJobDone = @{
    Ssid    = { $Sync.SsidRunning = $false; if ($Sync.SsidAgain) { $Sync.SsidAgain = $false; Start-SsidJob } }
    Diag    = { $Sync.DiagRunning = $false }
    Wu      = { $Sync.WuSearching = $false }
    Clean   = { $Sync.CleanScanDone = $true }
    Oem     = { $Sync.OemRunning = $false }
    OemInst = { $Sync.OemInstalling = $false; $Sync.OemInstFinished = $true }
    OemTool = { $Sync.OemInstalling = $false; $Sync.OemToolFinished = $true }
    Soft    = { $Sync.WgRunning = $false }
    Appx    = { $Sync.AppxRunning = $false }
    Info    = { $Sync.InfoBaseDone = $true }
}
# libération d'une tâche : arrêt si demandé, fin d'invocation, runspace et instance libérés
# Tâche encore en cours à remplacer : arrêt demandé sans attendre (PowerShell.Stop attend la fin de l'appel en cours, un
# appel COM Windows Update pouvait figer l'interface plusieurs secondes) ; libérée par Close-BgJob une fois arrêtée.
$BgOrphans = [Collections.Generic.List[object]]::new()
function Remove-BgJob([string]$Key, [bool]$Stop = $false) {
    $j = $BgJobs[$Key]; if (-not $j) { return }
    $BgJobs.Remove($Key)
    if ($Stop -and "$($j.PS.InvocationStateInfo.State)" -in 'Running', 'NotStarted') {
        try { [void]$j.PS.BeginStop($null, $null) } catch {}
        $BgOrphans.Add($j)
        return
    }
    Close-PsJob $j
}
function Close-PsJob($J) {
    try { [void]$J.PS.EndInvoke($J.Handle) } catch {}
    try { $J.PS.Runspace.Dispose() } catch {}
    try { $J.PS.Dispose() } catch {}
}
# Tâches d'arrière-plan ponctuelles (diagnostic, recherche Windows Update...) : runspace mémorisé puis libéré par le
# minuteur dès la fin du script. Une tâche de même clé encore présente est arrêtée et libérée avant (sinon elle continuait
# sans suivi, en écrivant dans $Sync en même temps que la nouvelle).
function Start-BgJob([string]$Key, [string]$Script) {
    if ($BgJobs.ContainsKey($Key)) { Remove-BgJob $Key $true }
    $BgJobs[$Key] = New-PsJob ($WuLib + "`n" + $Script)
}
function Close-BgJob([bool]$Force = $false) {
    foreach ($k in @($BgJobs.Keys)) {
        $st = "$($BgJobs[$k].PS.InvocationStateInfo.State)"
        if (-not $Force -and $st -notin 'Completed', 'Failed', 'Stopped') { continue }
        Remove-BgJob $k $Force
        if ($BgJobDone[$k]) { & $BgJobDone[$k] }
    }
    foreach ($j in @($BgOrphans)) {
        if ("$($j.PS.InvocationStateInfo.State)" -in 'Completed', 'Failed', 'Stopped') { Close-PsJob $j; [void]$BgOrphans.Remove($j) }
    }
    if ($Force) { foreach ($r in @($SpareRs)) { try { $r.Dispose() } catch {} }; $SpareRs.Clear() }
}
# Mémoire : PowerShell et .NET gardent la mémoire des objets devenus inutiles (analyse du script, XAML, résultats des
# collectes, runspaces terminés) jusqu'au prochain passage du ramasse-miettes, déclenché seulement sous pression. Libération
# complète (tas des gros objets compacté) aux moments sans interaction : 15 s après le démarrage, fin d'une exécution de
# tâches, réduction de la fenêtre.
function Invoke-MemoryTrim([string]$When) {
    [Runtime.GCSettings]::LargeObjectHeapCompactionMode = [Runtime.GCLargeObjectHeapCompactionMode]::CompactOnce
    [GC]::Collect(); [GC]::WaitForPendingFinalizers(); [GC]::Collect()

}
$BgJobs = @{}
Add-SpareRunspace 3
