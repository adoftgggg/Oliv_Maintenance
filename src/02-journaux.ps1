$LogDir = Join-Path $env:ProgramData 'Oliv_Maintenance\Maintenance'
# Journaux rangés comme l'interface : onglet \ carte (noms sans accents pour les scripts et outils tiers)
$LogCats = [ordered]@{
    AccueilWu    = 'Accueil\Mises a jour Windows'
    AccueilOem   = 'Accueil\Mises a jour constructeur'
    Nettoyage    = 'Maintenance\Nettoyage'
    Reparation   = 'Maintenance\Reparation'
    Disques      = 'Maintenance\Disques et batterie'
    Depannage    = 'Maintenance\Depannage'
    Logiciels    = 'Maintenance\Logiciels'
    Restauration = 'Systeme\Point de restauration'
    Demarrage    = 'Systeme\Applications au demarrage'
    Applications = 'Personnalisation\Applications preinstallees'
    Journal      = 'Journal'
    Rapports     = 'Rapports'
    Erreurs      = 'Erreurs'
    Etat         = '_etat'
}
foreach ($d in $LogCats.Values) { [void][IO.Directory]::CreateDirectory((Join-Path $LogDir $d)) }
try { $e = [IO.DirectoryInfo]::new((Join-Path $LogDir '_etat')); $e.Attributes = $e.Attributes -bor [IO.FileAttributes]::Hidden } catch {}
function Get-LogPath([string]$Cat) { Join-Path $LogDir $LogCats[$Cat] }
# Erreurs non bloquantes : journalisées en WARN une seule fois par sujet et par message, l'application continue. Avant
# l'interface (Write-UiLog absent) : mises en attente puis affichées au démarrage (99-demarrage.ps1). Table partagée avec
# les runspaces ($Sync.WarnOnce, même fonction dans $IgnoreLib, 49-arriere-plan.ps1).
$WarnOnce = [hashtable]::Synchronized(@{}); $EarlyWarn = [Collections.Generic.List[string]]::new()
function Get-ErrText($Err) { if ($Err -is [Management.Automation.ErrorRecord]) { $Err.Exception.Message } elseif ($Err -is [Exception]) { $Err.Message } elseif ($Err) { "$Err" } else { 'erreur inconnue' } }
function Write-Ignored([string]$What, $Err) {
    $m = Get-ErrText $Err; $k = "$What|$m"
    if ($WarnOnce.ContainsKey($k)) { return }; $WarnOnce[$k] = 1
    if ($Sync -and $Sync.Queue -and (Get-Command Write-UiLog -ErrorAction SilentlyContinue)) {
        Write-UiLog "$What : $m" 'WARN'
    } else {
        $EarlyWarn.Add("$What : $m")
    }
}
if ($NativeErr) { Write-Ignored 'Code natif (fenêtres, mesures, analyse disque)' $NativeErr }
# cache de DLL des versions antérieures à la 0.104 (code natif désormais embarqué dans le script) : supprimé
$OldCache = Join-Path $LogDir '_etat\cache'
if (Test-Path -LiteralPath $OldCache) {
    try { Remove-Item -LiteralPath $OldCache -Recurse -Force -ErrorAction Stop } catch { Write-Ignored 'Suppression de l''ancien cache de code natif' $_ }
}
$TweakLog = Join-Path (Get-LogPath 'Journal') ('{0}_journal_{1:yyyy-MM}.log' -f $env:COMPUTERNAME, (Get-Date))

# Reprise des journaux des versions précédentes (racine puis anciens dossiers par type) dans l'arborescence onglet \ carte
function Move-OldLog {
    $kw = [ordered]@{ 'constructeur' = 'AccueilOem'; 'Installation des mises à jour Windows' = 'AccueilWu'; 'point de restauration' = 'Restauration'
                      DISM = 'Reparation'; SFC = 'Reparation'; CHKDSK = 'Reparation'; Nettoyage = 'Nettoyage'; SMART = 'Disques'; 'disque système' = 'Disques'
                      batterie = 'Disques'; 'applications préinstallées' = 'Applications' }
    $guess = {
        param([string]$File)
        $n = [IO.Path]::GetFileName($File)
        if ($n -like 'crash*.log') { return 'Erreurs' }
        if ($n -like '*.json') { return 'Etat' }
        if ($n -like '*_reglages*.log') { return 'Journal' }
        if ($n -like '*_sfc.txt' -or $n -like '*_reparation.log') { return 'Reparation' }
        if ($n -like '*_SMART_*' -or $n -like '*_batterie_*' -or $n -like '*_disques.log') { return 'Disques' }
        if ($n -like '*_nettoyage.log') { return 'Nettoyage' }
        if ($n -like '*_applications.log') { return 'Applications' }
        if ($n -like '*_constructeur*.log') { return 'AccueilOem' }
        if ($n -like '*.reg') { return 'Demarrage' }
        if ($n -like '*.log') {
            try {
                $head = (Get-Content -LiteralPath $File -TotalCount 14 -Encoding UTF8 -ErrorAction Stop) -join ' '
                foreach ($k in $kw.Keys) { if ($head -like "*$k*") { return $kw[$k] } }
            } catch {}
            return 'Depannage'
        }
        $null
    }
    $old = @([IO.Directory]::GetFiles($LogDir))
    foreach ($d in 'Nettoyage', 'Reparation', 'Disques', 'Batterie', 'Applications', 'Systeme', 'Reglages') {
        $p = Join-Path $LogDir $d
        # « Systeme » est aussi la racine des nouveaux dossiers de l'onglet Système : seuls ses fichiers directs sont repris
        if (Test-Path -LiteralPath $p) {
            $old += @([IO.Directory]::GetFiles($p, '*', $(if ($d -eq 'Systeme') { [IO.SearchOption]::TopDirectoryOnly } else { [IO.SearchOption]::AllDirectories })))
        }
    }
    foreach ($f in $old) {
        $cat = & $guess $f
        if (-not $cat) { continue }
        $dest = Join-Path (Get-LogPath $cat) ([IO.Path]::GetFileName($f))
        if (-not (Test-Path -LiteralPath $dest)) { try { [IO.File]::Move($f, $dest) } catch { Write-Ignored 'Rangement des journaux' $_ } }
    }
    # anciens dossiers vides supprimés (un fichier non déplaçable les laisse en place)
    foreach ($d in 'Nettoyage', 'Reparation', 'Disques', 'Batterie', 'Applications', 'Systeme', 'Reglages') {
        $p = Join-Path $LogDir $d
        if (Test-Path -LiteralPath $p) {
            foreach ($x in @(Get-ChildItem -LiteralPath $p -Directory -Recurse | Sort-Object { $_.FullName.Length } -Descending) + @(Get-Item -LiteralPath $p)) {
                if (-not @(Get-ChildItem -LiteralPath $x.FullName -Force).Count) { try { $x.Delete() } catch {} }
            }
        }
    }
}
function Get-LogFile([int]$Days = 0) {
    $limit = [DateTime]::Now.AddDays(-$Days)
    foreach ($c in @($LogCats.Keys | Where-Object { $_ -ne 'Etat' })) {
        $dp = Get-LogPath $c; if (-not (Test-Path -LiteralPath $dp)) { continue }
        foreach ($f in [IO.DirectoryInfo]::new($dp).GetFiles()) {
            if ($Days -gt 0 -and $f.LastWriteTime -ge $limit) { continue }
            if ($Sync -and $Sync.Running -and $f.FullName -eq $Sync.LogFile) { continue }
            $f
        }
    }
}
try { Move-OldLog } catch { Write-Ignored 'Rangement des journaux' $_ }
foreach ($d in $LogCats.Values) { [void][IO.Directory]::CreateDirectory((Join-Path $LogDir $d)) }
