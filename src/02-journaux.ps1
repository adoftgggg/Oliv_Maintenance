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
        # incident non bloquant : fichier journal seulement (sans intérêt pour l'utilisateur, l'application continue)
        Write-FileLog "$What : $m" 'WARN'
    } else {
        $EarlyWarn.Add("$What : $m")
    }
}
# Écriture atomique : texte écrit dans <fichier>.tmp puis substitué d'un coup (File.Replace) ; une coupure pendant l'écriture
# laisse l'ancien fichier intact, jamais un fichier tronqué. Version précédente gardée en <fichier>.bak (sauf -NoBackup),
# relue par Read-JsonState si le fichier devient illisible. Droits et attributs du fichier remplacé conservés.
function Write-FileAtomic([string]$Path, [string]$Text, [Text.Encoding]$Encoding = $null, [switch]$NoBackup) {
    if (-not $Encoding) { $Encoding = [Text.UTF8Encoding]::new($false) }
    $tmp = $Path + '.tmp'
    [IO.File]::WriteAllText($tmp, $Text, $Encoding)
    try {
        # sans sauvegarde : [NullString]::Value (un $null passé à une méthode .NET devient une chaîne vide, refusée par Replace)
        if (-not [IO.File]::Exists($Path)) { [IO.File]::Move($tmp, $Path) }
        elseif ($NoBackup) { [IO.File]::Replace($tmp, $Path, [NullString]::Value) }
        else { [IO.File]::Replace($tmp, $Path, $Path + '.bak') }
    } catch { try { [IO.File]::Delete($tmp) } catch { $null = $_ }; throw }
}
# Lecture d'un fichier d'état JSON : le fichier, sinon sa version précédente (.bak, dernière écriture réussie). Fichier
# illisible (tronqué, corrompu) : copie gardée en <fichier>.illisible, signalée au fichier journal. Résultat :
#   Ok   = vrai si rien n'est perdu (fichier absent, ou contenu lu) ; faux si un fichier existe mais qu'aucun n'est lisible :
#          l'appelant ne doit alors pas le réécrire avec un contenu partiel
#   Data = objet lu (ConvertFrom-Json), $null sinon
function Read-JsonState([string]$Path, [string]$What) {
    $found = $false
    foreach ($f in $Path, ($Path + '.bak')) {
        if (-not [IO.File]::Exists($f)) { continue }
        $found = $true
        try {
            $t = [IO.File]::ReadAllText($f, [Text.Encoding]::UTF8)
            $d = $null; if ($t.Trim()) { $d = ConvertFrom-Json -InputObject $t -ErrorAction Stop }
            return @{ Ok = $true; Data = $d; From = $f }
        } catch {
            Write-Ignored $What $_
            try { [IO.File]::Copy($f, $f + '.illisible', $true) } catch { $null = $_ }
        }
    }
    @{ Ok = -not $found; Data = $null; From = $null }
}
# Fichier JSON Lines (une entrée par ligne, historiques) lu par paquets de 500 lignes : un seul ConvertFrom-Json par paquet
# (tableau JSON) au lieu d'un par ligne, plusieurs secondes de moins sur le fil d'interface pour un historique de
# plusieurs milliers de lignes, et taille de chaque paquet sous la limite de ConvertFrom-Json de Windows PowerShell 5.1.
# Paquet illisible (ligne corrompue) : relu ligne par ligne, lignes illisibles ignorées (fichier journal). Ordre conservé.
function Read-JsonLine([string]$Path, [string]$What) {
    if (-not [IO.File]::Exists($Path)) { return }
    $ls = @([IO.File]::ReadAllLines($Path, [Text.Encoding]::UTF8) | Where-Object { $_.Trim() })
    for ($i = 0; $i -lt $ls.Count; $i += 500) {
        $part = @($ls[$i..([math]::Min($i + 499, $ls.Count - 1))])
        $all = $null
        try { $all = ConvertFrom-Json -InputObject ('[' + ($part -join ',') + ']') -ErrorAction Stop } catch { $all = $null }
        if ($null -ne $all) { foreach ($o in $all) { $o }; continue }
        foreach ($l in $part) { try { ConvertFrom-Json -InputObject $l -ErrorAction Stop } catch { Write-Ignored $What $_ } }
    }
}
# copie en table de hachage d'un état en mémoire : table (résultat d'un runspace) ou objet relu d'un fichier JSON
# (ConvertFrom-Json : PSCustomObject, « @{} + objet » lève une erreur). Premier niveau seulement.
function ConvertTo-StateTable($Obj) {
    if ($Obj -is [hashtable]) { return (@{} + $Obj) }
    $h = @{}; if ($null -ne $Obj) { foreach ($p in $Obj.PSObject.Properties) { $h[$p.Name] = $p.Value } }
    $h
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
    # anciens dossiers vides supprimés (un fichier non déplaçable les laisse en place) ; dossiers de l'arborescence actuelle
    # ($LogCats : Systeme\Point de restauration...) et leurs parents gardés (avant : supprimés vides puis recréés à chaque lancement)
    $cur = @($LogCats.Values | ForEach-Object { (Join-Path $LogDir $_).TrimEnd('\') })
    foreach ($d in 'Nettoyage', 'Reparation', 'Disques', 'Batterie', 'Applications', 'Systeme', 'Reglages') {
        $p = Join-Path $LogDir $d
        if (Test-Path -LiteralPath $p) {
            foreach ($x in @(Get-ChildItem -LiteralPath $p -Directory -Recurse | Sort-Object { $_.FullName.Length } -Descending) + @(Get-Item -LiteralPath $p)) {
                $fx = $x.FullName.TrimEnd('\')
                if (@($cur | Where-Object { $_ -ieq $fx -or $_.StartsWith($fx + '\', [StringComparison]::OrdinalIgnoreCase) }).Count) { continue }
                if (-not @(Get-ChildItem -LiteralPath $x.FullName -Force).Count) { try { $x.Delete() } catch {} }
            }
        }
    }
}
function Get-LogFile([int]$Days = 0) {
    $limit = [DateTime]::Now.AddDays(-$Days)
    # Demarrage exclu : sauvegardes (.reg, raccourcis) des entrées retirées du démarrage, seules à permettre de les remettre
    foreach ($c in @($LogCats.Keys | Where-Object { $_ -notin 'Etat', 'Demarrage' })) {
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
