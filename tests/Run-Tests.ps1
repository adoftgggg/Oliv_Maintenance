<#
.SYNOPSIS
    Tests unitaires des fonctions sans interface de Oliv_Maintenance (aucune dépendance : pas de Pester requis).

.DESCRIPTION
    Les fonctions testées sont lues directement dans src\ (y compris dans les scripts embarqués des runspaces),
    puis chargées seules : aucune fenêtre n'est ouverte, rien n'est modifié sur le poste.
    Code de sortie : 0 si tout passe, 1 sinon.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-Tests.ps1
#>
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$utf8 = [Text.UTF8Encoding]::new($false)

# ---------- chargement des fonctions par leur nom (script principal + here-strings PowerShell)
$code = (@(Get-ChildItem -LiteralPath (Join-Path $root 'src') -Filter '*.ps1' | Sort-Object Name | ForEach-Object { [IO.File]::ReadAllText($_.FullName, $utf8) }) -join "`n")
$asts = [Collections.Generic.List[object]]::new()
$main = [System.Management.Automation.Language.Parser]::ParseInput($code, [ref]$null, [ref]$null); $asts.Add($main)
foreach ($h in $main.FindAll({ param($n) $n -is [System.Management.Automation.Language.StringConstantExpressionAst] -and $n.StringConstantType -eq 'SingleQuotedHereString' }, $true)) {
    if (-not $h.Value.TrimStart().StartsWith('<')) { $asts.Add([System.Management.Automation.Language.Parser]::ParseInput($h.Value, [ref]$null, [ref]$null)) }
}
function Import-SrcFunction([string[]]$Name) {
    foreach ($n in $Name) {
        $f = $null
        foreach ($a in $asts) { $f = $a.Find({ param($x) $x -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -eq $n }, $true); if ($f) { break } }
        if (-not $f) { throw "Fonction introuvable dans src : $n" }
        . ([scriptblock]::Create($f.Extent.Text))
        Set-Item -Path "function:global:$n" -Value (Get-Item "function:$n").ScriptBlock
    }
}
function Get-SrcValue([string]$Var) {
    $a = $main.Find({ param($x) $x -is [System.Management.Automation.Language.AssignmentStatementAst] -and "$($x.Left)" -eq "`$$Var" }, $true)
    if (-not $a) { throw "Variable introuvable dans src : `$$Var" }
    & ([scriptblock]::Create("$($a.Right)"))
}

# ---------- mini-moteur de tests
$script:Pass = 0; $script:Fail = [Collections.Generic.List[string]]::new()
function Test-Eq([string]$Name, $Actual, $Expected) {
    if ("$Actual" -ceq "$Expected") { $script:Pass++ } else { $script:Fail.Add("$Name : obtenu « $Actual », attendu « $Expected »") }
}

# ---------- code natif : DLL compilée par build.ps1 (dist\obj), tous les types attendus par les sources présents
$natDll = Join-Path $root 'dist\obj\olivm_natif.dll'
if (Test-Path -LiteralPath $natDll) {
    [void][Reflection.Assembly]::Load([IO.File]::ReadAllBytes($natDll))
    $used = @([regex]::Matches($code, '\[_OlivM\.(\w+)\]') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
    foreach ($t in $used) { Test-Eq "Code natif : type _OlivM.$t" ([bool]("_OlivM.$t" -as [type])) $true }
}

# ---------- erreurs non bloquantes : une seule trace par sujet et par message (avant l'interface : mise en attente)
Import-SrcFunction Get-ErrText, Write-Ignored
$WarnOnce = @{}; $EarlyWarn = [Collections.Generic.List[string]]::new(); $Sync = $null
try { throw 'fichier verrouillé' } catch { Write-Ignored 'Enregistrement du zoom' $_; Write-Ignored 'Enregistrement du zoom' $_ }
Write-Ignored 'Enregistrement du zoom' 'autre motif'
Test-Eq 'Write-Ignored : doublon ignoré'      $EarlyWarn.Count 2
Test-Eq 'Write-Ignored : texte'               $EarlyWarn[0] 'Enregistrement du zoom : fichier verrouillé'
Test-Eq 'Get-ErrText : vide'                  (Get-ErrText $null) 'erreur inconnue'

# ---------- importance des mises à jour en attente (rapport d'intervention)
Import-SrcFunction Get-OemImportance, Get-WuImportance, Get-ImportanceSummary
$ImportanceLabels = Get-SrcValue 'ImportanceLabels'
$o1 = Get-OemImportance @{ Title = 'Lenovo Ltd. Firmware Driver Update (1.15.0.0)'; Category = 'Firmware  ·  Lenovo Ltd.'; Severity = '' }
$o2 = Get-OemImportance @{ Title = 'Advanced Micro Devices Inc. SecurityDevices Driver Update (5.46.0.0)'; Category = 'OtherHardware  ·  Advanced Micro Devices Inc.'; Severity = '' }
$o3 = Get-OemImportance @{ Title = 'Advanced Micro Devices, Inc. SoftwareComponent Driver Update (32.2610.0.0)'; Category = 'OtherHardware  ·  Advanced Micro Devices, Inc.'; Severity = '' }
$o4 = Get-OemImportance @{ Title = 'BIOS Update'; Category = 'BIOS'; Severity = 'Critical' }
Test-Eq 'Importance : firmware estimé'        $o1.Label 'Importante'
Test-Eq 'Importance : sécurité estimée'       $o2.Label 'Importante'
Test-Eq 'Importance : composant logiciel'     $o3.Label 'Facultative'
Test-Eq 'Importance : gravité constructeur'   $o4.Label 'Critique'
Test-Eq 'Importance : origine constructeur'   $o4.Basis 'indiquée par le constructeur (Critical)'
Test-Eq 'Importance : origine estimée'        ($o3.Basis -like 'estimée*') $true
Test-Eq 'Importance WU : gravité Microsoft'   (Get-WuImportance @{ Severity = 'Important'; Class = 'Security Updates' }).Label 'Importante'
Test-Eq 'Importance WU : définitions'         (Get-WuImportance @{ Severity = ''; Class = 'Definition Updates' }).Label 'Recommandée'
Test-Eq 'Importance : résumé'                 (Get-ImportanceSummary @($o1, $o2, $o3)) '2 importantes, 1 facultative'

# ---------- comparaison de versions (logiciels)
Import-SrcFunction Compare-Ver
Test-Eq 'Compare-Ver 1.10 > 1.9'            (Compare-Ver '1.10' '1.9') 1
Test-Eq 'Compare-Ver 1.2 = 1.2.0.0'         (Compare-Ver '1.2' '1.2.0.0') 0
Test-Eq 'Compare-Ver 2.56.1 > 2.56.0.4'     (Compare-Ver '2.56.1' '2.56.0.4') 1
Test-Eq 'Compare-Ver 4.4.4 < 4.4.5'         (Compare-Ver '4.4.4' '4.4.5') -1
Test-Eq 'Compare-Ver 26288.2004 > 26276.513' (Compare-Ver '26288.2004.5269.3420' '26276.513.5241.9675') 1

# ---------- noms de logiciels (correspondance catalogue winget, boutons)
Import-SrcFunction Get-NormName, Get-BaseName, Get-SoftShortName
Test-Eq 'Get-NormName'                      (Get-NormName 'Notepad++ (x64)') 'notepadx64'
Test-Eq 'Get-BaseName 7-Zip'                (Get-BaseName '7-Zip 23.01 (x64)') '7-Zip'
Test-Eq 'Get-BaseName CMake'                (Get-BaseName 'CMake') 'CMake'
Test-Eq 'Get-SoftShortName VC++'            (Get-SoftShortName 'Microsoft Visual C++ v14 Redistributable (x86)') 'Microsoft Visual C++ Redistributable'
Test-Eq 'Get-SoftShortName version'         (Get-SoftShortName 'NVIDIA App 11.0.9.565') 'NVIDIA App'

# ---------- accords singulier / pluriel
Import-SrcFunction Get-Plural, Get-PluralOf
Test-Eq 'Get-Plural 0'                      (Get-Plural 0 'mise à jour' 'mises à jour') 'mise à jour'
Test-Eq 'Get-Plural 1'                      (Get-Plural 1 'mise à jour' 'mises à jour') 'mise à jour'
Test-Eq 'Get-Plural 2'                      (Get-Plural 2 'mise à jour' 'mises à jour') 'mises à jour'
Test-Eq 'Get-PluralOf 1,5 Go'               (Get-PluralOf '1,5 Go' 'libre' 'libres') 'libre'
Test-Eq 'Get-PluralOf 220,4 Go'             (Get-PluralOf '220,4 Go' 'libre' 'libres') 'libres'

# ---------- libellé des boutons d'installation (Windows Update, constructeur)
Import-SrcFunction Get-InstallLabel
Test-Eq 'Get-InstallLabel 1 élément'        (Get-InstallLabel 1 0) 'Installer tout (1)'
Test-Eq 'Get-InstallLabel 1 élément coché'  (Get-InstallLabel 1 1) 'Installer la sélection (1)'
Test-Eq 'Get-InstallLabel tout'             (Get-InstallLabel 6 0) 'Installer tout (6)'
Test-Eq 'Get-InstallLabel sélection'        (Get-InstallLabel 6 2) 'Installer la sélection (2)'

# ---------- journal : découpe des lignes, filtre des messages de l'application, niveaux, recherche
Import-SrcFunction Get-LogLinePart, Test-LogLine
$LogView = @{ Level = 'All'; Text = ''; App = $false }
Test-Eq 'LogView messages app par défaut'   (Get-SrcValue 'LogView').App $true
$x = Get-LogLinePart '10:42:07 [WARN ] Disque presque plein'
Test-Eq 'Get-LogLinePart heure'            $x.Time '10:42:07'
Test-Eq 'Get-LogLinePart niveau'           $x.Level 'WARN'
Test-Eq 'Get-LogLinePart message'          $x.Msg 'Disque presque plein'
Test-Eq 'Get-LogLinePart bilan'           (Get-LogLinePart '09:03:10 [BILAN] Durée : 00:00:07').Level 'BILAN'
Test-Eq 'Get-LogLinePart ligne libre'      ($null -eq (Get-LogLinePart '   sortie de commande')) $true
Test-Eq 'Test-LogLine APP masqué'           (Test-LogLine '10:42:07 [APP  ] Thème : sombre') $false
Test-Eq 'Test-LogLine action visible'       (Test-LogLine '10:42:07 [OK   ] SFC terminé') $true
Test-Eq 'Test-LogLine texte APP non masqué' (Test-LogLine '10:42:07 [INFO ] [APP  ] dans le message') $true
$LogView.App = $true
Test-Eq 'Test-LogLine APP affiché'          (Test-LogLine '10:42:07 [APP  ] Thème : sombre') $true
$LogView.Level = 'Warn'
Test-Eq 'Test-LogLine APP hors niveau'      (Test-LogLine '10:42:07 [APP  ] Thème : sombre') $false
Test-Eq 'Test-LogLine erreur dans Warn'     (Test-LogLine '10:42:07 [ERROR] Échec') $true
$LogView.Level = 'All'; $LogView.Text = 'sfc'
Test-Eq 'Test-LogLine recherche casse'      (Test-LogLine '10:42:07 [OK   ] SFC terminé') $true
Test-Eq 'Test-LogLine recherche absente'    (Test-LogLine '10:42:07 [OK   ] DISM terminé') $false
Import-SrcFunction Measure-LogLine
$LogView = @{ Level = 'All'; Text = ''; App = $false }
$c = Measure-LogLine @('10:00:00 [ERROR] a', '10:00:01 [WARN ] b', '10:00:02 [APP  ] c', '10:00:03 [OK   ] d', '')
Test-Eq 'Measure-LogLine erreurs'          $c.E 1
Test-Eq 'Measure-LogLine avertissements'   $c.W 1
Test-Eq 'Measure-LogLine application'      $c.A 1
Test-Eq 'Measure-LogLine affichées'        $c.Shown 4
Import-SrcFunction Get-LogZoomValue
Test-Eq 'Zoom journal + 10 %'               (Get-LogZoomValue 1.1) 1.1
Test-Eq 'Zoom journal - 10 %'               (Get-LogZoomValue 0.9) 0.9
Test-Eq 'Zoom journal minimum'              (Get-LogZoomValue 0.6) 0.7
Test-Eq 'Zoom journal maximum'              (Get-LogZoomValue 2.3) 2

# ---------- débits réseau (moniteur d'activité) : séparateur décimal de la culture courante
Import-SrcFunction Format-Rate
$d = [Globalization.CultureInfo]::CurrentCulture.NumberFormat.NumberDecimalSeparator
Test-Eq 'Format-Rate o/s'                   (Format-Rate 785) '785 o/s'
Test-Eq 'Format-Rate Ko/s'                  (Format-Rate 1536) "1${d}5 Ko/s"
Test-Eq 'Format-Rate Mo/s'                  (Format-Rate (5.3 * 1MB)) "5${d}3 Mo/s"

# ---------- avancement réel des recherches (étapes + fraction mesurée)
Import-SrcFunction Get-JobProgress
$global:Sync = [hashtable]::Synchronized(@{}); $global:BgJobs = @{}
Test-Eq 'Get-JobProgress sans étape'        (Get-JobProgress 'Wu' 'Wu').Text 'préparation'
$Sync.WuStep = @{ Step = 2; Steps = 4; Label = 'recherche sur Microsoft Update'; Sub = -1 }
Test-Eq 'Get-JobProgress début étape 2/4'   (Get-JobProgress 'Wu' 'Wu').Pct 25
$Sync.WuStep = @{ Step = 4; Steps = 4; Label = 'analyse'; Sub = 50 }
Test-Eq 'Get-JobProgress étape 4/4 à 50 %'  (Get-JobProgress 'Wu' 'Wu').Pct 87
$Sync.WuStep = @{ Step = 4; Steps = 4; Label = 'analyse'; Sub = 100 }
Test-Eq 'Get-JobProgress plafonné à 99 %'   (Get-JobProgress 'Wu' 'Wu').Pct 99

# ---------- historique Windows Update (Diagnostic rapide) : fusion historique + journal, échecs encore valables
Import-SrcFunction Get-KB, Get-Plural, ConvertFrom-WuHistory, Get-WuFamily, Get-WuHistorySummary
function New-R([string]$T, [bool]$Ok, [double]$DaysAgo, [int64]$Code = 0) { @{ Date = [DateTime]::Now.AddDays(-$DaysAgo); Kb = (Get-KB $T); Title = $T; Ok = $Ok; Code = $Code; Src = 'test' } }
$lcuNov = '2026-11 Cumulative Update for Windows 11 Version 26H2 for x64-based Systems (KB5132061)'
$lcuOct = '2026-10 Cumulative Update for Windows 11 Version 26H2 for x64-based Systems (KB5120001)'
$net    = '2026-11 Cumulative Update for .NET Framework 3.5 and 4.8.1 for Windows 11 (KB5099999)'
$r = Get-WuHistorySummary @((New-R $lcuNov $true 3), (New-R $lcuNov $false 3.2 0x800F0922L), (New-R $net $false 5 0x80073712L), (New-R $net $false 6 0x80073712L))
Test-Eq 'Historique : dernière KB installée'                  $r.Ok[0].Kb 'KB5132061'
Test-Eq 'Historique : échec corrigé ensuite ignoré'           $r.Fail.Kb 'KB5099999'
Test-Eq 'Historique : 2 tentatives comptées'                  $r.Fail.Attempts 2
Test-Eq 'Historique : code conservé'                          ('0x{0:X8}' -f $r.Fail.Code) '0x80073712'
$r = Get-WuHistorySummary @((New-R $lcuNov $true 2), (New-R $lcuOct $false 30 0x800F0922L))
Test-Eq 'Historique : échec remplacé par une version plus récente' ($null -eq $r.Fail) $true
$r = Get-WuHistorySummary @((New-R $net $false 4 0x80073712L)) @('KB5099999')
Test-Eq 'Historique : KB présente dans les correctifs installés'   ($null -eq $r.Fail) $true
Test-Eq 'Get-WuFamily ignore date, KB et version'             (Get-WuFamily $lcuNov) (Get-WuFamily $lcuOct)
$h = @([pscustomobject]@{ Operation = 1; ResultCode = 4; HResult = -2146498270; Title = $lcuNov; Date = [DateTime]::UtcNow },
       [pscustomobject]@{ Operation = 1; ResultCode = 2; HResult = 0; Title = 'Security Intelligence Update - KB2267602 (Version 1.1)'; Date = [DateTime]::UtcNow })
$c = @(ConvertFrom-WuHistory $h)
Test-Eq 'ConvertFrom-WuHistory : Defender écarté'             $c.Count 1
Test-Eq 'ConvertFrom-WuHistory : HRESULT négatif converti'    ('0x{0:X8}' -f $c[0].Code) '0x800F0922'

# ---------- avancement de l'analyse d'espace disque
Import-SrcFunction Format-SizeUi, Get-TreeScanProgress
Test-Eq 'Format-SizeUi zéro'                  (Format-SizeUi 0) 'vide'
Test-Eq 'Format-SizeUi zéro personnalisé'     (Format-SizeUi 0 'plein') 'plein'
Test-Eq 'Espace disque : début de lecture'    (Get-TreeScanProgress 0 0 0 0).Text 'Lecture en cours'
Import-SrcFunction Format-Size
Test-Eq 'Format-Size zéro'                    (Format-Size 0) 'néant'
Test-Eq 'Format-Size sous 1 Ko'               (Format-Size 300) '300 o'
Test-Eq 'Format-Size 9,7 Mo'                  ((Format-Size 10171187) -replace '[.,]', ',') '9,7 Mo'
Test-Eq 'Espace disque : lecteur à 50 %'        (Get-TreeScanProgress 50GB 100GB 3 10).Pct 50
Test-Eq 'Espace disque : lecteur plafonné 99 %' (Get-TreeScanProgress 120GB 100GB 3 10).Pct 99
Test-Eq 'Espace disque : dossier 3 sur 12'      (Get-TreeScanProgress 1GB 0 3 12).Pct 25
Test-Eq 'Espace disque : libellé dossier'       (Get-TreeScanProgress 1GB 0 3 12).Text '3 dossiers sur 12'
Test-Eq 'Espace disque : dossier vide'          (Get-TreeScanProgress 0 0 0 0).Pct 0

# ---------- mise à jour des logiciels : lecture de la sortie de winget, état affiché
Import-SrcFunction ConvertFrom-WingetLine, Get-SoftItemText, Format-WingetCode, Get-SoftDownloadByte, Format-SizeUi
Test-Eq 'winget : téléchargement MB'            (ConvertFrom-WingetLine '  ██████▒▒▒▒  12.0 MB / 48.0 MB').Pct 25
Test-Eq 'winget : téléchargement Mo (fr)'       (ConvertFrom-WingetLine '24,0 Mo / 48,0 Mo').Pct 50
Test-Eq 'winget : étape téléchargement'         (ConvertFrom-WingetLine '1.5 KB / 3 KB').Phase 'téléchargement'
Test-Eq 'winget : pourcentage seul'             (ConvertFrom-WingetLine '87%').Pct 87
Test-Eq 'winget : hachage vérifié'              (ConvertFrom-WingetLine 'Successfully verified installer hash').Phase 'vérification'
Test-Eq 'winget : installation (en)'            (ConvertFrom-WingetLine 'Starting package install...').Phase 'installation'
Test-Eq 'winget : installation (fr)'            (ConvertFrom-WingetLine 'Démarrage de l''installation du package...').Phase 'installation'
Test-Eq 'winget : installation accents perdus' (ConvertFrom-WingetLine 'DÃ©marrage de lâ€™installation du package...').Phase 'installation'
Test-Eq 'winget : installation terminée'        (ConvertFrom-WingetLine 'Successfully installed').Pct 100
Test-Eq 'winget : installé correctement (fr)'   (ConvertFrom-WingetLine 'Installé correctement').Pct 100
Test-Eq 'winget : barre MSIX 42 %'              (ConvertFrom-WingetLine '▒▒▒▒  42%').Pct 42
Test-Eq 'winget : ligne sans avancement'        ($null -eq (ConvertFrom-WingetLine 'Found Google Chrome [Google.Chrome] Version 157.0')) $true
Test-Eq 'État : téléchargement 42 %'            (Get-SoftItemText @{ State = 'run'; Phase = 'téléchargement'; Pct = 42 }).Text 'téléchargement 42 %'
Test-Eq 'État : échec code winget'              (Get-SoftItemText @{ State = 'fail'; Code = -1978335189 }).Text 'échec (0x8A15002B)'
Test-Eq 'État : installation 42 %'             (Get-SoftItemText @{ State = 'run'; Phase = 'installation'; Pct = 42 }).Text 'installation 42 %'
Test-Eq 'État : installation sans progression' (Get-SoftItemText @{ State = 'run'; Phase = 'installation'; Pct = -1 }).Text 'installation  0:00'
Test-Eq 'État : en attente'                     (Get-SoftItemText @{ State = 'wait' }).Text 'en attente'

# ---------- erreurs winget copiables, pourcentages non nuls
Import-SrcFunction Format-SoftError, Get-SoftErrorText, Format-Pct, Format-SoftHistLine, Format-SoftAppLine
$global:WingetErr = Get-SrcValue 'WingetErr'
Test-Eq 'Format-WingetCode négatif'            (Format-WingetCode -1978334975) '0x8A150101'
$Sync.SoftRun = @{ Items = @{ 'Notepad++.Notepad++' = @{ State = 'fail'; Code = -1978334975; Name = 'Notepad++'; From = '8.9.8.1'; To = '8.9.9.1'; End = [DateTime]'2026-11-16 14:02'; Out = @('Installer failed with exit code: 1') } } }
$et = Get-SoftErrorText 'Notepad++.Notepad++'
Test-Eq 'Erreur : code et signification'      ($et -match 'INSTALL_PACKAGE_IN_USE\) - le logiciel est ouvert') $true
Test-Eq 'Erreur : sortie winget incluse'       ($et -match 'Installer failed with exit code: 1') $true
Test-Eq 'Erreur : versions'                    ($et -match '8\.9\.8\.1 > 8\.9\.9\.1') $true
$hh = [pscustomobject]@{ Date = '2026-11-16T13:58:00'; Name = 'Microsoft Visual C++ v14 Redistributable (x64)'; Id = 'Microsoft.VCRedist.2015+.x64'; From = '14.50.35719.0'; To = '14.52.37029.0'; Ok = $false; Code = 1; User = 'utilisateur'; Computer = 'PC1'; Out = @('Installer failed with exit code: 1') }
Test-Eq 'Historique : erreur code installeur'  ((Format-SoftError $hh) -match '0x00000001 \(code de sortie de l''installeur') $true
Test-Eq 'Historique : ligne copiée'            (Format-SoftHistLine $hh) '16/11/2026 13:58  ·  Microsoft Visual C++ v14 Redistributable (x64) (Microsoft.VCRedist.2015+.x64)  ·  14.50.35719.0 > 14.52.37029.0  ·  échec (0x00000001)  ·  utilisateur'
Test-Eq 'Liste : ligne copiée'                 (Format-SoftAppLine @{ Name = 'Notepad++'; Id = 'Notepad++.Notepad++'; From = '8.9.8.1'; To = '8.9.9.1'; SrcLabel = 'winget' }) 'Notepad++ (Notepad++.Notepad++)  ·  installée 8.9.8.1  ·  disponible 8.9.9.1  ·  winget'
Test-Eq 'Format-Pct 0 masqué'                  (Format-Pct 0) ''
Test-Eq 'Format-Pct 42'                        (Format-Pct 42) '42 %  ·  '
Test-Eq 'État : téléchargement à 0 % masqué'   (Get-SoftItemText @{ State = 'run'; Phase = 'téléchargement'; Pct = 0 }).Text 'téléchargement...'

# ---------- installation des mises à jour constructeur : état affiché
Import-SrcFunction Get-OemItemText
Test-Eq 'Constructeur : installation 35 %'      (Get-OemItemText @{ State = 'run'; Phase = 'installation'; Pct = 35 }).Text 'installation 35 %'
Test-Eq 'Constructeur : outil Lenovo sans %'    (Get-OemItemText @{ State = 'run'; Phase = 'téléchargement et installation'; Pct = -1 }).Text 'téléchargement et installation...'
Test-Eq 'Constructeur : installé + redémarrage' (Get-OemItemText @{ State = 'ok'; Phase = 'redémarrage requis' }).Text 'installé, redémarrage requis'
Test-Eq 'Constructeur : échec HRESULT'          (Get-OemItemText @{ State = 'fail'; Code = 2149842967L }).Text 'échec (0x80240017)'
Test-Eq 'Constructeur : plus proposé'           (Get-OemItemText @{ State = 'skip'; Phase = 'plus proposé' }).Text 'plus proposé'

# ---------- journal filtrable
Import-SrcFunction Test-LogLine
$global:LogView = @{ Level = 'All'; Text = '' }
$le = '10:02:11 [ERROR] DISM : échec 0x800F081F'; $lw = '10:02:12 [WARN ] Redémarrage requis'; $li = '10:02:13 [INFO ] Analyse terminée'
Test-Eq 'Journal : tout'                       (@($le, $lw, $li | Where-Object { Test-LogLine $_ }).Count) 3
$LogView.Level = 'Warn'; Test-Eq 'Journal : avertissements + erreurs' (@($le, $lw, $li | Where-Object { Test-LogLine $_ }).Count) 2
$LogView.Level = 'Err';  Test-Eq 'Journal : erreurs seules'           (@($le, $lw, $li | Where-Object { Test-LogLine $_ }).Count) 1
$LogView.Level = 'All'; $LogView.Text = 'dism'; Test-Eq 'Journal : texte sans casse' (@($le, $lw, $li | Where-Object { Test-LogLine $_ }).Count) 1

# ---------- rapport d'intervention (génération complète avec des données de test)
Import-SrcFunction ConvertTo-HtmlText, Get-InfoField, New-InterventionReport, Format-SizeUi, Get-LiveEvent, Get-RunEvent, Get-Plural, Get-PendingUpdateRow, Write-Ignored, Get-ErrText
Test-Eq 'Rapport : échappement HTML'           (ConvertTo-HtmlText '<b>&"') '&lt;b&gt;&amp;&quot;'
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('olivm-test-' + [guid]::NewGuid()); [void][IO.Directory]::CreateDirectory($tmp)
function global:Get-LogPath([string]$Cat) { $tmp }
function global:Get-SoftUpdate { @() }
function global:Get-SoftKey($A) { '' }
$global:SoftExcl = @{}; $global:LogoFullB64 = ''; $global:AppVersion = '0.0.0-test'; $global:UserName = 'TEST\utilisateur'
$global:InfoUI = @{ F = @{} }
$global:Session = @{ Start = [DateTime]::Now.AddMinutes(-30); Events = [Collections.ArrayList]::new() }
[void]$Session.Events.Add(@{ Time = [DateTime]::Now; Cat = 'Windows Update'; Title = 'KB5099999 - Mise à jour <cumulative>'; Result = 'échec (0x80073712)'; Level = 'error'; Detail = '' })
$Sync.Diag = @{ Items = @(@{ K = 'Clé de récupération'; V = '123456-123456'; B = '' }, @{ K = 'Écrans bleus (30 derniers jours)'; V = 'aucun'; B = 'OkFgBrush' }) }
$Sync.Vols = @(@{ Name = 'C:\'; Label = 'OS'; Total = 100GB; Free = 10GB })
$Sync.WuPending = @{ Items = @(@{ Title = 'x'; KB = 'KB5099998'; Severity = 'Critical'; Class = 'Security Updates' }); Online = $true }
$Sync.OemResult = @{ Items = @(@{ Title = 'Lenovo Ltd. Firmware Driver Update (1.15.0.0)'; Category = 'Firmware'; Severity = ''; Source = 'WU' }, @{ Title = 'AMD SoftwareComponent Driver Update'; Category = 'OtherHardware'; Severity = '' }); Error = $null }
$Sync.Running = $true; $Sync.Selected = @('Sfc'); $Sync.TaskIdx = 1; $Sync.TaskPct = -1; $Sync.TaskStart = [DateTime]::Now; $Sync.Labels = @{ Sfc = 'Réparation des fichiers système (SFC)' }; $Sync.TaskResults = @(); $Sync.WuInstalled = @()
$Sync.WuSearching = $true; $Sync.WuOnline = $true; $Sync.WuCancel = $false; $Sync.WuStartT = [DateTime]::Now
$rf = New-InterventionReport; $html = [IO.File]::ReadAllText($rf)
Test-Eq 'Rapport : fichier créé'               (Test-Path -LiteralPath $rf) $true
Test-Eq 'Rapport : action échappée'            ($html -match 'Mise à jour &lt;cumulative&gt;') $true
Test-Eq 'Rapport : clé BitLocker absente'      ($html -match '123456-123456') $false
Test-Eq 'Rapport : disque plein signalé'       ($html -match 'Lecteur C:\\ occupé à 90') $true
Test-Eq 'Rapport : mise à jour restante'       ($html -match '1 mise à jour Windows Update : 1 critique') $true
Test-Eq 'Rapport : constructeur par importance' ($html -match '2 mises à jour constructeur : 1 importante, 1 facultative') $true
Test-Eq 'Rapport : détail constructeur'       ($html -match 'Lenovo Ltd\. Firmware Driver Update \(1\.15\.0\.0\)') $true
Test-Eq 'Rapport : importance estimée notée'  ($html -match 'estimée : micrologiciel') $true
Test-Eq 'Rapport : tâche en cours tracée'      ($html -match 'Réparation des fichiers système \(SFC\)<br><span class="muted">démarré à [0-9:]+</span></td><td class="info">en cours') $true
Test-Eq 'Rapport : recherche en cours tracée'  ($html -match 'Recherche des mises à jour</td><td class="info">en cours') $true
Test-Eq 'Rapport : non terminé signalé'        ($html -match 'Non terminé au moment du rapport') $true
$Sync.Running = $false; $Sync.WuSearching = $false
Remove-Item -LiteralPath $tmp -Recurse -Force

# ---------- valeurs SMBIOS par défaut (n° de série, modèle)
$junk = Get-SrcValue 'SmbJunk'
foreach ($v in 'To be filled by O.E.M.', 'Default string', 'System Product Name', '0000000', '') { Test-Eq "SmbJunk « $v » écarté" ($v -match $junk) $true }
foreach ($v in '07C9123_N31E142228', 'MS-7C91', 'PF3ABCDE') { Test-Eq "SmbJunk « $v » conservé" ($v -match $junk) $false }

# ---------- droits du dossier C:\ProgramData\Oliv_Maintenance (Test-AclSafe : même règle que le lanceur)
foreach ($v in 'SidAdmins', 'SidSystem', 'SidUsers') { Set-Variable -Name $v -Value (Get-SrcValue $v) -Scope Global }
Import-SrcFunction 'Test-AclSafe'
function New-AclRule($Sid, $Rights, $Allow = $true) { @{ Sid = $Sid; Allow = $Allow; Rights = [int64]$Rights } }
$okRules = @((New-AclRule 'S-1-5-32-544' 0x1F01FF), (New-AclRule 'S-1-5-18' 0x1F01FF), (New-AclRule 'S-1-5-32-545' 0x1200A9))
Test-Eq 'ACL conforme'                                   (Test-AclSafe $true  'S-1-5-32-544' $okRules) $true
Test-Eq 'ACL héritée de ProgramData'                     (Test-AclSafe $false 'S-1-5-32-544' $okRules) $false
Test-Eq 'ACL propriétaire utilisateur'                   (Test-AclSafe $true  'S-1-5-21-1-2-3-1001' $okRules) $false
Test-Eq 'ACL Utilisateurs création de fichiers (WD,AD)'  (Test-AclSafe $true  'S-1-5-18' ($okRules + (New-AclRule 'S-1-5-32-545' 0x116))) $false
Test-Eq 'ACL CREATOR OWNER GENERIC_ALL'                  (Test-AclSafe $true  'S-1-5-32-544' ($okRules + (New-AclRule 'S-1-3-0' 0x10000000))) $false
Test-Eq 'ACL GENERIC_READ seul accepté'                  (Test-AclSafe $true  'S-1-5-32-544' ($okRules + (New-AclRule 'S-1-5-11' ([int64][int]-2147483648)))) $true
Test-Eq 'ACL refus en écriture accepté'                  (Test-AclSafe $true  'S-1-5-32-544' ($okRules + (New-AclRule 'S-1-1-0' 0x1F01FF $false))) $true

# ---------- fenêtre Logiciels : intitulé de la 4e colonne
Import-SrcFunction 'Get-SoftColTitle'
Test-Eq 'Colonne Logiciels : historique'      (Get-SoftColTitle $true $true) 'RÉSULTAT'
Test-Eq 'Colonne Logiciels : mise à jour'     (Get-SoftColTitle $false $true) 'ÉTAT'
Test-Eq 'Colonne Logiciels : inventaire'      (Get-SoftColTitle $false $false) 'SOURCE'

# ---------- analyseur d'espace disque : catégorie (couleur) d'un élément, éclaircissement des couleurs
Import-SrcFunction 'Get-TreeCategory', 'Get-LightHex'
Test-Eq 'Espace : Windows'                    (Get-TreeCategory @('Windows') $true $false) 'Sys'
Test-Eq 'Espace : sous-dossier de Windows'    (Get-TreeCategory @('System32', 'Windows') $true $false) 'Sys'
Test-Eq 'Espace : pagefile.sys'               (Get-TreeCategory @('pagefile.sys') $false $false) 'Sys'
Test-Eq 'Espace : Program Files (x86)'        (Get-TreeCategory @('Program Files (x86)') $true $false) 'Prog'
Test-Eq 'Espace : profil utilisateur'         (Get-TreeCategory @('olivier', 'Users') $true $false) 'User'
Test-Eq 'Espace : Users\x\...\Windows'      (Get-TreeCategory @('Windows', 'Microsoft', 'Local', 'AppData', 'olivier', 'Users') $true $false) 'User'
Test-Eq 'Espace : Temp du profil'             (Get-TreeCategory @('Temp', 'Local', 'AppData', 'olivier', 'Users') $true $false) 'Recov'
Test-Eq 'Espace : dossier temp à la racine'   (Get-TreeCategory @('temp') $true $false) 'Recov'
Test-Eq 'Espace : autre dossier'              (Get-TreeCategory @('NTlite') $true $false) 'Data'
Test-Eq 'Espace : fichier'                    (Get-TreeCategory @('install.wim', 'NTlite') $false $false) 'File'
Test-Eq 'Espace : éléments regroupés'         (Get-TreeCategory @('12 autres éléments') $false $true) 'More'
Test-Eq 'Espace : non analysé'                (Get-TreeCategory @('Non analysé (fichiers système)') $false $true) 'Unk'
Test-Eq 'Couleur éclaircie 0 %'               (Get-LightHex '#5B6B82' 0) '#5B6B82'
Test-Eq 'Couleur éclaircie 100 %'             (Get-LightHex '#5B6B82' 1) '#FFFFFF'

# ---------- rapport d'intervention : tâches terminées, en cours et en attente
Import-SrcFunction 'Get-RunEvent'
$global:Sync = @{ Selected = @('DismRestore', 'Sfc', 'ChkBoot'); TaskIdx = 2; TaskPct = 37.6; TaskStart = [DateTime]::Today.AddHours(10); ChildName = 'SFC'; Cancel = $false; RunStart = [DateTime]::Today.AddHours(9)
    Labels = @{ DismRestore = 'Réparation DISM'; Sfc = 'Réparation SFC'; ChkBoot = 'CHKDSK' }
    TaskResults = @(@{ Id = 'DismRestore'; Label = 'Réparation DISM'; Start = [DateTime]::Today.AddHours(9); Err = 0; Warn = 0; Cancel = $false; Last = 'ok' }); WuInstalled = @(); SpaceGain = $null }
$re = @(Get-RunEvent -Live)
Test-Eq 'Rapport en direct : 3 lignes'           $re.Count 3
Test-Eq 'Rapport en direct : tâche terminée'     $re[0].Result 'terminé'
Test-Eq 'Rapport en direct : tâche en cours'     $re[1].Result 'en cours (37 %)'
Test-Eq 'Rapport en direct : tâche en attente'   $re[2].Result 'en attente'
Test-Eq 'Rapport final : tâches terminées seules' @(Get-RunEvent).Count 1

# ---------- bilan
# ---------- nom court du fabricant (ligne Constructeur des mises à jour constructeur)
$OemBrands = Get-SrcValue 'OemBrands'
Import-SrcFunction 'Get-OemBrand'
Test-Eq 'Marque : ASUSTeK'      (Get-OemBrand 'ASUSTeK COMPUTER INC.') 'ASUS'
Test-Eq 'Marque : MSI'          (Get-OemBrand 'Micro-Star International Co., Ltd.') 'MSI'
Test-Eq 'Marque : Gigabyte'     (Get-OemBrand 'Gigabyte Technology Co., Ltd.') 'Gigabyte'
Test-Eq 'Marque : HP'           (Get-OemBrand 'HP') 'HP'
Test-Eq 'Marque : Lenovo'       (Get-OemBrand 'LENOVO') 'Lenovo'
Test-Eq 'Marque : Dell'         (Get-OemBrand 'Dell Inc.') 'Dell'
Test-Eq 'Marque : inconnue'     (Get-OemBrand 'Contoso Computer Corporation') 'Contoso'

# ---------- libellé court des mises à jour Windows
Import-SrcFunction 'Get-WuShortTitle'
Test-Eq 'WU : Defender'  (Get-WuShortTitle @{ Title = "Mise à jour de la sélection disjointe pour Microsoft Defender Antivirus $([char]0x2013) 2267602 Ko (version 1.441.123.0) $([char]0x2013) Canal actuel (large)"; Size = 0 }) 'Microsoft Defender Antivirus (définitions)  ·  version 1.441.123.0'
Test-Eq 'WU : cumulative' (Get-WuShortTitle @{ Title = 'Mise à jour cumulative 2026-11 pour Windows 11 Version 25H2 pour les systèmes x64 (KB5070773)'; Size = 1GB; Done = $true }) 'Mise à jour cumulative 2026-11 pour Windows 11 Version 25H2'

$total = $script:Pass + $script:Fail.Count
if ($script:Fail.Count) {
    $script:Fail | ForEach-Object { Write-Host "  ÉCHEC  $_" -ForegroundColor Red }
    Write-Host ("{0}/{1} tests réussis" -f $script:Pass, $total) -ForegroundColor Red
    exit 1
}
Write-Host ("{0}/{0} tests réussis" -f $total) -ForegroundColor Green
exit 0
