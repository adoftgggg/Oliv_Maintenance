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
Import-SrcFunction Get-OemImportance
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
Test-Eq 'Constructeur : plus proposé'           (Get-OemItemText @{ State = 'skip'; Phase = 'plus proposé' }).Text 'déjà à jour (plus proposé)'

# ---------- journal filtrable
Import-SrcFunction Test-LogLine
$global:LogView = @{ Level = 'All'; Text = '' }
$le = '10:02:11 [ERROR] DISM : échec 0x800F081F'; $lw = '10:02:12 [WARN ] Redémarrage requis'; $li = '10:02:13 [INFO ] Analyse terminée'
Test-Eq 'Journal : tout'                       (@($le, $lw, $li | Where-Object { Test-LogLine $_ }).Count) 3
$LogView.Level = 'Warn'; Test-Eq 'Journal : avertissements + erreurs' (@($le, $lw, $li | Where-Object { Test-LogLine $_ }).Count) 2
$LogView.Level = 'Err';  Test-Eq 'Journal : erreurs seules'           (@($le, $lw, $li | Where-Object { Test-LogLine $_ }).Count) 1
$LogView.Level = 'All'; $LogView.Text = 'dism'; Test-Eq 'Journal : texte sans casse' (@($le, $lw, $li | Where-Object { Test-LogLine $_ }).Count) 1

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

# ---------- journal de session : tâches terminées seules, avec leur résultat, et espace libéré
Import-SrcFunction 'Get-RunEvent', 'Format-SizeUi'
$global:Sync = @{ Selected = @('DismRestore', 'Sfc', 'ChkBoot'); TaskIdx = 2; TaskPct = 37.6; TaskStart = [DateTime]::Today.AddHours(10); ChildName = 'SFC'; Cancel = $false; RunStart = [DateTime]::Today.AddHours(9)
    Labels = @{ DismRestore = 'Réparation DISM'; Sfc = 'Réparation SFC'; ChkBoot = 'CHKDSK' }
    TaskResults = @(@{ Id = 'DismRestore'; Label = 'Réparation DISM'; Start = [DateTime]::Today.AddHours(9); Err = 0; Warn = 0; Cancel = $false; Last = 'ok' }, @{ Id = 'Sfc'; Label = 'Réparation SFC'; Start = [DateTime]::Today.AddHours(10); Err = 2; Warn = 0; Cancel = $false; Last = '' }); WuInstalled = @(); SpaceGain = $null }
$re = @(Get-RunEvent)
Test-Eq 'Journal de session : tâches terminées seules' $re.Count 2
Test-Eq 'Journal de session : tâche réussie'     $re[0].Result 'terminé'
Test-Eq 'Journal de session : tâche en erreur'   ('{0}|{1}' -f $re[1].Result, $re[1].Level) '2 erreurs|error'
$global:Sync = $null

# ---------- liens (jonctions) : détectés et supprimés sans suivre leur cible (dossier de l'application, nettoyage)
Import-SrcFunction 'Test-PathLink', 'Remove-PathLink', 'Remove-DirLink', 'Test-CleanLinkPath'
$lk = Join-Path ([IO.Path]::GetTempPath()) ('olivm-test-' + [guid]::NewGuid().ToString('N'))
$lkT = Join-Path $lk 'cible'; $lkR = Join-Path $lk 'app'
[void][IO.Directory]::CreateDirectory((Join-Path $lkT 'sous')); [void][IO.Directory]::CreateDirectory((Join-Path $lkR 'reel'))
[IO.File]::WriteAllText((Join-Path $lkT 'garder.txt'), 'x')
& cmd.exe /d /c mklink /J (Join-Path $lkR 'lien') $lkT | Out-Null
& cmd.exe /d /c mklink /J (Join-Path $lkR 'reel\lien2') $lkT | Out-Null
try {
    Test-Eq 'Lien : jonction détectée'             (Test-PathLink (Join-Path $lkR 'lien')) $true
    Test-Eq 'Lien : dossier réel'                  (Test-PathLink (Join-Path $lkR 'reel')) $false
    Test-Eq 'Lien : chemin absent'                 (Test-PathLink (Join-Path $lkR 'absent')) $false
    Test-Eq 'Nettoyage : cible réelle acceptée'    (Test-CleanLinkPath (Join-Path $lkR 'reel')) $false
    Test-Eq 'Nettoyage : jonction refusée'         (Test-CleanLinkPath (Join-Path $lkR 'reel\lien2')) $true
    Test-Eq 'Nettoyage : dossier sous jonction'    (Test-CleanLinkPath (Join-Path $lkR 'lien\sous')) $true
    Test-Eq 'Liens : premier niveau seulement'     (Remove-DirLink $lkR) 1
    Test-Eq 'Liens : lien profond conservé'        (Test-PathLink (Join-Path $lkR 'reel\lien2')) $true
    Test-Eq 'Liens : toute profondeur'             (Remove-DirLink $lkR -Deep) 1
    Test-Eq 'Liens : cible intacte'                ([IO.File]::Exists((Join-Path $lkT 'garder.txt'))) $true
    & cmd.exe /d /c mklink /J (Join-Path $lk 'racine-lien') $lkT | Out-Null
    Remove-PathLink (Join-Path $lk 'racine-lien')
    Test-Eq 'Lien à la place du dossier : retiré'  ([IO.Directory]::Exists((Join-Path $lk 'racine-lien'))) $false
    Test-Eq 'Lien à la place du dossier : cible'   ([IO.File]::Exists((Join-Path $lkT 'garder.txt'))) $true
} finally { try { [void](Remove-DirLink $lk -Deep); [IO.Directory]::Delete($lk, $true) } catch { $null = $_ } }

# ---------- Wi-Fi : noms que netsh interprète (« * » = tous les profils) refusés
Import-SrcFunction 'Test-WifiNameSafe'
Test-Eq 'Wi-Fi : nom ordinaire'               (Test-WifiNameSafe 'Livebox-1234') $true
Test-Eq 'Wi-Fi : nom accentué et espaces'     (Test-WifiNameSafe 'Café de la gare') $true
Test-Eq 'Wi-Fi : étoile refusée'              (Test-WifiNameSafe '*') $false
Test-Eq 'Wi-Fi : guillemet refusé'            (Test-WifiNameSafe 'a"b') $false
Test-Eq 'Wi-Fi : nom vide refusé'             (Test-WifiNameSafe ' ') $false

# ---------- entrée de désinstallation : clé du profil (HKCU) signalée, sa commande n'est pas lancée en administrateur
Import-SrcFunction 'Get-SoftArpKey'
function global:Get-SoftLocalId($App) { $App.Id }
function global:Open-RegKey([string]$Path) { if ($Path -like '*\Uninstall\Foo') { [pscustomobject]@{ P = $Path } } else { $null } }
Test-Eq 'Désinstallation : entrée HKCU'       (Get-SoftArpKey @{ Id = 'ARP\User\X64\Foo'; Name = 'Foo' }).User $true
Test-Eq 'Désinstallation : entrée HKLM'       (Get-SoftArpKey @{ Id = 'ARP\Machine\X64\Foo'; Name = 'Foo' }).User $false
Remove-Item function:global:Get-SoftLocalId, function:global:Open-RegKey

# ---------- exe stable : copié seulement si son empreinte est celle calculée par le lanceur
Import-SrcFunction 'Sync-StableExe'
function global:Write-FileLog([string]$Message, [string]$Level) { $null = $Message, $Level }
$sx = Join-Path ([IO.Path]::GetTempPath()) ('olivm-test-' + [guid]::NewGuid().ToString('N')); [void][IO.Directory]::CreateDirectory($sx)
$StableExe = Join-Path $sx 'stable.exe'; $AppDirSafe = $true; $curExe = Join-Path $sx 'telecharge.exe'
$oldExe = $env:_OLIVM_EXE; $oldSha = $env:_OLIVM_EXE_SHA256
try {
    [IO.File]::WriteAllText($curExe, 'version lancée'); $env:_OLIVM_EXE = $curExe
    $env:_OLIVM_EXE_SHA256 = (Get-FileHash -LiteralPath $curExe -Algorithm SHA256).Hash
    Test-Eq 'Exe stable : copie conforme'          (Sync-StableExe) $true
    Test-Eq 'Exe stable : contenu copié'           ([IO.File]::ReadAllText($StableExe)) 'version lancée'
    [IO.File]::WriteAllText($curExe, 'remplacé après le lancement')
    [void](Sync-StableExe)
    Test-Eq 'Exe stable : exe remplacé refusé'     ([IO.File]::ReadAllText($StableExe)) 'version lancée'
    Test-Eq 'Exe stable : aucun fichier temporaire' @(Get-ChildItem -LiteralPath $sx -Filter '*.tmp').Count 0
    $env:_OLIVM_EXE_SHA256 = ''; [IO.File]::Delete($StableExe)
    Test-Eq 'Exe stable : empreinte absente'       (Sync-StableExe) $false
} finally {
    $env:_OLIVM_EXE = $oldExe; $env:_OLIVM_EXE_SHA256 = $oldSha
    try { [IO.Directory]::Delete($sx, $true) } catch { $null = $_ }
}

# ---------- écriture atomique et lecture des fichiers d'état (version précédente .bak, fichier illisible jamais écrasé)
Import-SrcFunction 'Write-FileAtomic', 'Read-JsonState', 'Read-LastRunState', 'Get-LastRun', 'Save-LastRun'
$wf = Join-Path ([IO.Path]::GetTempPath()) ('olivm-test-' + [guid]::NewGuid().ToString('N')); [void][IO.Directory]::CreateDirectory($wf)
try {
    $af = Join-Path $wf 'etat.json'
    Write-FileAtomic $af 'un'
    Test-Eq 'Écriture atomique : création'         ([IO.File]::ReadAllText($af)) 'un'
    Write-FileAtomic $af 'deux'
    Test-Eq 'Écriture atomique : remplacement'     ([IO.File]::ReadAllText($af)) 'deux'
    Test-Eq 'Écriture atomique : version .bak'     ([IO.File]::ReadAllText("$af.bak")) 'un'
    Test-Eq 'Écriture atomique : pas de .tmp'      ([IO.File]::Exists("$af.tmp")) $false
    $nb = Join-Path $wf 'sans-bak.txt'; Write-FileAtomic $nb 'a' -NoBackup; Write-FileAtomic $nb 'b' -NoBackup
    Test-Eq 'Écriture atomique : -NoBackup'        ([IO.File]::Exists("$nb.bak")) $false
    Test-Eq 'Écriture atomique : encodage ANSI'    ([IO.File]::ReadAllText($nb, [Text.Encoding]::Default)) 'b'
    # lecture : absent, tableau JSON (piège 5.1 : un seul objet), fichier corrompu relu depuis .bak, aucun lisible
    $js = Join-Path $wf 'attente.json'
    $r0 = Read-JsonState $js 'test'
    Test-Eq 'État JSON : fichier absent (Ok)'      $r0.Ok $true
    Write-FileAtomic $js '[{"Key":"A"},{"Key":"B"}]'
    $r1 = Read-JsonState $js 'test'
    Test-Eq 'État JSON : tableau de 2 entrées'     @($r1.Data).Count 2
    Test-Eq 'État JSON : 2e entrée'                @($r1.Data)[1].Key 'B'
    Write-FileAtomic $js '[{"Key":"A"},{"Key":"B"},{"Key":"C"}]'
    [IO.File]::WriteAllText($js, '[{"Key":"A"},{"Ke')
    $r2 = Read-JsonState $js 'test'
    Test-Eq 'État JSON : corrompu, .bak relu'      ($r2.Ok -and @($r2.Data).Count -eq 2 -and $r2.From -like '*.bak') $true
    Test-Eq 'État JSON : copie .illisible'         ([IO.File]::Exists("$js.illisible")) $true
    [IO.File]::WriteAllText("$js.bak", '{oups')
    Test-Eq 'État JSON : rien de lisible'          (Read-JsonState $js 'test').Ok $false
    # dernières exécutions : fichier illisible jamais réécrit avec la seule nouvelle date
    $LastRunFile = Join-Path $wf 'dernieres-actions.json'
    Save-LastRun 'Optimize' 'ok'; Save-LastRun 'NetReset' 'ok'
    Test-Eq 'Derniers passages : 2 dates'          (Get-LastRun).Count 2
    [IO.File]::WriteAllText($LastRunFile, '{"Optimize":{"Ti'); [IO.File]::WriteAllText("$LastRunFile.bak", 'x')
    Save-LastRun 'TimeSync' 'ok'
    Test-Eq 'Derniers passages : illisible gardé'  ([IO.File]::ReadAllText($LastRunFile)) '{"Optimize":{"Ti'
} finally { try { [IO.Directory]::Delete($wf, $true) } catch { $null = $_ } }

# ---------- fichier hosts : lecture impossible = erreur, jamais un contenu vide (réécriture avec la seule nouvelle entrée)
Import-SrcFunction 'Read-HostsFile'
$HostsFile = Join-Path ([IO.Path]::GetTempPath()) ('olivm-test-hosts-' + [guid]::NewGuid().ToString('N'))
Test-Eq 'Hosts : fichier absent = vide'       (Read-HostsFile) ''
[IO.File]::WriteAllText($HostsFile, "127.0.0.1`tnas.maison")
$lockFs = [IO.File]::Open($HostsFile, 'Open', 'ReadWrite', 'None')
try { $hr = 'lu'; try { [void](Read-HostsFile) } catch { $hr = 'erreur' }; Test-Eq 'Hosts : fichier verrouillé = erreur' $hr 'erreur' }
finally { $lockFs.Dispose(); [IO.File]::Delete($HostsFile) }

# ---------- analyseur d'espace disque : fichiers de démarrage protégés sur tout lecteur
Import-SrcFunction 'Test-TreeProtected'
Test-Eq 'Protégé : C:\bootmgr'                (Test-TreeProtected "$env:SystemDrive\bootmgr") $true
Test-Eq 'Protégé : BOOTNXT'                   (Test-TreeProtected "$env:SystemDrive\BOOTNXT") $true
Test-Eq 'Protégé : D:\EFI'                    (Test-TreeProtected 'D:\EFI') $true
Test-Eq 'Protégé : $WinREAgent'               (Test-TreeProtected "$env:SystemDrive\`$WinREAgent") $true
Test-Eq 'Non protégé : dossier de données'    (Test-TreeProtected 'D:\Photos\EFI') $false

# ---------- inventaire des logiciels relu du fichier (PSCustomObject) : réenregistré après une modification (B1)
Import-SrcFunction 'ConvertTo-StateTable', 'Save-SoftInventory'
$si = Join-Path ([IO.Path]::GetTempPath()) ('olivm-test-' + [guid]::NewGuid().ToString('N')); [void][IO.Directory]::CreateDirectory($si)
try {
    $SoftFile = Join-Path $si 'logiciels.json'
    $Sync = @{ WgResult = @{ Stamp = [DateTime]'2026-11-20 10:00'; Apps = @(@{ Id = 'A'; From = '1.0'; To = '2.0' }, @{ Id = 'B'; From = '3.0'; To = $null }) } }
    Save-SoftInventory
    Test-Eq 'Inventaire : enregistré (table)'      ([IO.File]::Exists($SoftFile)) $true
    # comme au démarrage (87c) : inventaire relu du fichier, puis logiciel A mis à jour et B désinstallé
    $Sync.WgResult = Get-Content -LiteralPath $SoftFile -Raw -Encoding UTF8 | ConvertFrom-Json
    Test-Eq 'Inventaire relu : objet, pas une table' ($Sync.WgResult -is [hashtable]) $false
    foreach ($a in @($Sync.WgResult.Apps | Where-Object { $_.Id -eq 'A' })) { $a.From = '2.0'; $a.To = $null }
    $Sync.WgResult.Apps = @($Sync.WgResult.Apps | Where-Object { $_.Id -ne 'B' })
    Save-SoftInventory
    $back = Get-Content -LiteralPath $SoftFile -Raw -Encoding UTF8 | ConvertFrom-Json
    Test-Eq 'Inventaire relu : réenregistré'       (@($back.Apps).Count) 1
    Test-Eq 'Inventaire relu : version reportée'   (@($back.Apps)[0].From) '2.0'
    Test-Eq 'Inventaire relu : date conservée'     ([DateTime]$back.Stamp).ToString('yyyy-MM-dd HH:mm') '2026-11-20 10:00'
    Test-Eq 'Table d''état : copie d''une table'    (ConvertTo-StateTable @{ X = 1 }).X 1
    Test-Eq 'Table d''état : objet vide'            (ConvertTo-StateTable $null).Count 0
} finally { $Sync = $null; try { [IO.Directory]::Delete($si, $true) } catch { $null = $_ } }

# ---------- minuteur : tâches de fond relevées aussi quand la fenêtre est réduite (B2)
Import-SrcFunction 'Test-BgJobTick'
Test-Eq 'Minuteur au repos : tâches relevées'  @(1..8 | Where-Object { $_ % 4 -eq 0 } | Where-Object { Test-BgJobTick $_ $true }).Count 2
Test-Eq 'Minuteur actif : 1 passage sur 4'     @(1..8 | Where-Object { Test-BgJobTick $_ $false }).Count 2

# ---------- SMART ATA : 32 bits de poids faible (0xFFFFFFFF vaut -1 sous Windows PowerShell 5.1) (B6)
Import-SrcFunction 'Get-SmartLow'
Test-Eq 'SMART : octets hauts ignorés'         (Get-SmartLow ([uint64]0x123400000064)) 100
Test-Eq 'SMART : valeur simple'                (Get-SmartLow 5) 5
Test-Eq 'SMART : 32 bits pleins'               (Get-SmartLow ([uint64]4294967295)) 4294967295
Test-Eq 'SMART : absent'                       ($null -eq (Get-SmartLow $null)) $true

# ---------- libellé des boutons de copie : genre et nombre (B7)
Import-SrcFunction 'Get-CopyDone'
Test-Eq 'Copie : les lignes'                   (Get-CopyDone 'Copier les lignes') 'Lignes copiées'
Test-Eq 'Copie : les 3 erreurs'                (Get-CopyDone 'Copier les 3 erreurs') 'Erreurs copiées'
Test-Eq 'Copie : le nom'                       (Get-CopyDone 'Copier le nom') 'Nom copié'
Test-Eq 'Copie : la version'                   (Get-CopyDone 'Copier la version') 'Version copiée'
Test-Eq 'Copie : l''adresse'                   (Get-CopyDone 'Copier l''adresse') 'Adresse copiée'
Test-Eq 'Copie : les identifiants'             (Get-CopyDone 'Copier les identifiants') 'Identifiants copiés'

# ---------- modules chargés seulement depuis Windows et Program Files, Windows en premier (S15)
Import-SrcFunction 'Get-SafeModulePath'
$mpIn = "C:\Users\bob\Documents\WindowsPowerShell\Modules;%ProgramFiles%\WindowsPowerShell\Modules;$env:windir\system32\WindowsPowerShell\v1.0\Modules;D:\Outils\Modules;"
Test-Eq 'Modules : dossiers réservés, ordre'    (Get-SafeModulePath $mpIn) "$env:windir\system32\WindowsPowerShell\v1.0\Modules;$env:ProgramFiles\WindowsPowerShell\Modules"
Test-Eq 'Modules : profil seul -> vide'         (Get-SafeModulePath 'C:\Users\bob\Documents\WindowsPowerShell\Modules') ''

# ---------- dossier d'installation lu dans HKCU : retenu seulement dans le profil (S17)
Import-SrcFunction 'Test-SoftDirInProfile'
$UserProfilePath = 'C:\Users\bob'
Test-Eq 'Profil : dossier du profil'           (Test-SoftDirInProfile 'C:\Users\bob\AppData\Local\Discord') $true
Test-Eq 'Profil : Program Files refusé'        (Test-SoftDirInProfile 'C:\Program Files\Antivirus') $false
Test-Eq 'Profil : autre profil au nom proche'  (Test-SoftDirInProfile 'C:\Users\bobby\Outil') $false
$UserProfilePath = $null

# ---------- pages web : adresses https seulement (S18)
Import-SrcFunction 'Open-WebPage'
foreach ($bad in 'file:///C:/Windows/System32/calc.exe', 'http://exemple.com', 'https://a b') {
    $wr = 'ouverte'; try { Open-WebPage $bad } catch { $wr = 'refusée' }; Test-Eq "Page web : $bad refusée" $wr 'refusée'
}

# ---------- objets nommés de l'instance : droits réservés aux Administrateurs et à SYSTEM (S12)
Import-SrcFunction 'New-AppSyncObject'
$snm = 'Local\olivm-test-' + [guid]::NewGuid().ToString('N')
$smx = New-AppSyncObject $snm; $sev = New-AppSyncObject ($snm + '-ev') -Signal
try {
    $sids = { param($o) (@($o.GetAccessControl().GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier]) | ForEach-Object { $_.IdentityReference.Value } | Sort-Object) -join ',') }
    Test-Eq 'Verrou d''instance : droits'          (& $sids $smx) 'S-1-5-18,S-1-5-32-544'
    Test-Eq 'Événement : droits'                  (& $sids $sev) 'S-1-5-18,S-1-5-32-544'
    Test-Eq 'Événement : type'                    ($sev -is [Threading.EventWaitHandle]) $true
} finally { $smx.Dispose(); $sev.Dispose() }

# ---------- relance administrateur du .cmd : script exécuté seulement s'il n'a pas changé ; chemin avec apostrophe
# typographique, espace et $ (S13, B38)
Import-SrcFunction 'Get-RelaunchCommand'
$rl = Join-Path ([IO.Path]::GetTempPath()) ('olivm-test-' + [guid]::NewGuid().ToString('N') + '\l' + [char]0x2019 + 'outil $x')
[void][IO.Directory]::CreateDirectory($rl)
try {
    $rlOut = Join-Path $rl 'sortie.txt'; $rlScript = Join-Path $rl 'Oliv_Maintenance.cmd'
    [IO.File]::WriteAllText($rlScript, ("[IO.File]::WriteAllText('{0}', 'exécuté ' + `$global:_OlivMScriptPath.Length)" -f ($rlOut -replace ("['" + [char]0x2019 + ']'), '$0$0')), [Text.UTF8Encoding]::new($false))
    $rlp = Start-Process -FilePath "$env:windir\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList (Get-RelaunchCommand $rlScript) -WindowStyle Hidden -PassThru -Wait
    Test-Eq 'Relance : script inchangé exécuté'    $(if ([IO.File]::Exists($rlOut)) { [IO.File]::ReadAllText($rlOut) } else { "absent (code $($rlp.ExitCode))" }) ('exécuté ' + $rlScript.Length)
} finally { try { [IO.Directory]::Delete((Split-Path $rl), $true) } catch { $null = $_ } }

# ---------- versions portables : copie vers le profil refusée à travers une jonction (S10)
Import-SrcFunction 'Test-PortLink', 'Copy-PortTree'
$pt = Join-Path ([IO.Path]::GetTempPath()) ('olivm-test-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory((Join-Path $pt 'prepare\app')); [void][IO.Directory]::CreateDirectory((Join-Path $pt 'ailleurs')); [void][IO.Directory]::CreateDirectory((Join-Path $pt 'profil'))
[IO.File]::WriteAllText((Join-Path $pt 'prepare\app\outil.exe'), 'x')
& cmd.exe /d /c mklink /J (Join-Path $pt 'profil\piege') (Join-Path $pt 'ailleurs') | Out-Null
try {
    Copy-PortTree (Join-Path $pt 'prepare') (Join-Path $pt 'profil\Outil')
    Test-Eq 'Portable : copie dans le profil'      ([IO.File]::Exists((Join-Path $pt 'profil\Outil\app\outil.exe'))) $true
    $pr = 'copiée'; try { Copy-PortTree (Join-Path $pt 'prepare') (Join-Path $pt 'profil\piege\Outil') } catch { $pr = 'refusée' }
    Test-Eq 'Portable : jonction refusée'          $pr 'refusée'
    Test-Eq 'Portable : rien écrit à travers'      @(Get-ChildItem -LiteralPath (Join-Path $pt 'ailleurs')).Count 0
} finally { try { [IO.Directory]::Delete((Join-Path $pt 'profil\piege'), $false); [IO.Directory]::Delete($pt, $true) } catch { $null = $_ } }

# ---------- stratégie locale : Registry.pol relu à l'identique ; sauvegardes jamais écrasées, origine jamais purgée (D8)
Import-SrcFunction 'Read-PolFile', 'ConvertTo-PolData', 'Write-PolFile', 'Backup-LocalPolicy'
$gp = Join-Path ([IO.Path]::GetTempPath()) ('olivm-test-' + [guid]::NewGuid().ToString('N')); [void][IO.Directory]::CreateDirectory($gp)
function global:Get-LogPath([string]$Cat) { $null = $Cat; $gpLog }
$gpLog = $gp
try {
    $pol = Join-Path $gp 'Registry.pol'; $ini = Join-Path $gp 'gpt.ini'
    $l1 = [Collections.Generic.List[object]]::new(); $l1.Add([pscustomobject]@{ Key = 'Software\Policies\Test'; Name = 'Valeur'; Type = 4; Data = [BitConverter]::GetBytes([int]1) })
    Write-PolFile $pol $l1
    $l2 = [Collections.Generic.List[object]]::new(@($l1)); $l2.Add([pscustomobject]@{ Key = 'Software\Policies\Test'; Name = 'Texte'; Type = 1; Data = [Text.Encoding]::Unicode.GetBytes('abc' + [char]0) })
    Write-PolFile $pol $l2
    $rb = Read-PolFile $pol
    Test-Eq 'Registry.pol : relu après remplacement' $rb.Count 2
    Test-Eq 'Registry.pol : 2e valeur'             ([Text.Encoding]::Unicode.GetString($rb[1].Data).TrimEnd([char]0)) 'abc'
    Test-Eq 'Registry.pol : pas de fichier temporaire' @(Get-ChildItem -LiteralPath $gp -Filter '*.tmp').Count 0
    [IO.File]::WriteAllText($ini, "[General]`r`nVersion=1`r`n")
    $orig = [Convert]::ToBase64String([IO.File]::ReadAllBytes($pol))
    [void](Backup-LocalPolicy $pol $ini)
    Write-PolFile $pol $l1
    [void](Backup-LocalPolicy $pol $ini)
    $bk = Join-Path $gp 'gpo-sauvegarde'
    Test-Eq 'Sauvegarde GPO : 2 copies datées'      @(Get-ChildItem -LiteralPath $bk -Filter 'Registry_2*.pol').Count 2
    Test-Eq 'Sauvegarde GPO : origine conservée'    ([Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $bk 'Registry_origine.pol')))) $orig
    for ($n = 0; $n -lt 23; $n++) { [void](Backup-LocalPolicy $pol $ini) }
    Test-Eq 'Sauvegarde GPO : 20 copies datées'     @(Get-ChildItem -LiteralPath $bk -Filter 'Registry_2*.pol').Count 20
    Test-Eq 'Sauvegarde GPO : origine jamais purgée' ([IO.File]::Exists((Join-Path $bk 'Registry_origine.pol')) -and [IO.File]::Exists((Join-Path $bk 'gpt_origine.ini'))) $true
} finally { Remove-Item function:global:Get-LogPath; try { [IO.Directory]::Delete($gp, $true) } catch { $null = $_ } }

# ---------- instantanés de réglages : 30 gardés par compte (D9)
Import-SrcFunction 'Get-SnapshotPurge'
$snaps = @(1..35 | ForEach-Object { [pscustomobject]@{ Name = ('2026{0:D4}.json' -f $_); Path = "a$_"; Sid = 'S-A' } }) + @(1..5 | ForEach-Object { [pscustomobject]@{ Name = ('2025{0:D4}.json' -f $_); Path = "b$_"; Sid = 'S-B' } }) + @([pscustomobject]@{ Name = '2020.json'; Path = 'x'; Sid = $null })
$purge = @(Get-SnapshotPurge $snaps 30)
Test-Eq 'Instantanés : 5 plus anciens de A'      $purge.Count 5
Test-Eq 'Instantanés : B et illisible gardés'    @($purge | Where-Object { $_.Sid -ne 'S-A' }).Count 0
Test-Eq 'Instantanés : plus ancien de A purgé'   (@($purge | Sort-Object Name)[0].Path) 'a1'

# ---------- fichier hosts : repère de fin absent, entrées personnelles qui suivent gardées (D10)
Import-SrcFunction 'Split-HostsContent'
$HostsMarkA = Get-SrcValue 'HostsMarkA'; $HostsMarkB = Get-SrcValue 'HostsMarkB'
$hx = @('# mon fichier', '192.168.1.5 imprimante', $HostsMarkA, '127.0.0.1 localhost', '0.0.0.0 pub1.exemple', '# section', '0.0.0.0 pub2.exemple', '', '# mon NAS', '192.168.1.20 nas.maison', '0.0.0.0 bloque-moi.fr') -join "`r`n"
$hs = Split-HostsContent $hx
Test-Eq 'Hosts sans repère de fin : bloc'        $hs.Block.Count 5
Test-Eq 'Hosts sans repère de fin : NAS gardé'   ($hs.Own -match 'nas\.maison' -and $hs.Own -match '# mon NAS' -and $hs.Own -match 'bloque-moi' -and $hs.Own -match 'imprimante') $true
$hs2 = Split-HostsContent (@('192.168.1.5 imprimante', $HostsMarkA, '0.0.0.0 a', $HostsMarkB, '10.0.0.1 nas') -join "`r`n")
Test-Eq 'Hosts avec repère de fin : bloc'        $hs2.Block.Count 3
Test-Eq 'Hosts avec repère de fin : entrées'     $hs2.Own "192.168.1.5 imprimante`r`n10.0.0.1 nas"

# ---------- variables d'environnement : liste seulement si chaque élément est un chemin (D12)
Import-SrcFunction 'Test-EnvList'
Test-Eq 'Variable : Path'                        (Test-EnvList @{ Name = 'Path'; Value = 'C:\Windows' }) $true
Test-Eq 'Variable : liste de dossiers'           (Test-EnvList @{ Name = 'LIB'; Value = 'C:\a;%ProgramFiles%\b;\\srv\c' }) $true
Test-Eq 'Variable : chaîne de connexion'         (Test-EnvList @{ Name = 'CNX'; Value = 'Server=x;Database=y' }) $false
Test-Eq 'Variable : « ; » final gardé'           (Test-EnvList @{ Name = 'LIB'; Value = 'C:\a;C:\b;' }) $false

# ---------- sauvegarde .reg d'une entrée de démarrage : tout type de valeur (D17)
Import-SrcFunction 'ConvertTo-RegExportLine'
Test-Eq '.reg : texte échappé'                   (ConvertTo-RegExportLine 'App' 'String' 'C:\x\"a"') '"App"="C:\\x\\\"a\""'
Test-Eq '.reg : DWORD'                           (ConvertTo-RegExportLine 'N' 'DWord' 255) '"N"=dword:000000ff'
Test-Eq '.reg : binaire (StartupApproved)'       (ConvertTo-RegExportLine 'App' 'Binary' ([byte[]](3, 0, 0x1f))) '"App"=hex:03,00,1f'
Test-Eq '.reg : texte extensible'                (ConvertTo-RegExportLine 'E' 'ExpandString' '%a%') '"E"=hex(2):25,00,61,00,25,00,00,00'
Test-Eq '.reg : multi-chaîne'                    (ConvertTo-RegExportLine 'M' 'MultiString' @('a', 'b')) '"M"=hex(7):61,00,00,00,62,00,00,00,00,00'

# ---------- anciens points de restauration : seuls les clichés des points de restauration (D19)
Import-SrcFunction 'Select-RestoreShadow'
$t0 = [DateTime]'2026-11-20 10:00'
$shd = @([pscustomobject]@{ ID = 'pr1'; InstallDate = $t0.AddSeconds(20) }, [pscustomobject]@{ ID = 'sauvegarde'; InstallDate = $t0.AddHours(3) }, [pscustomobject]@{ ID = 'pr2'; InstallDate = $t0.AddDays(1) })
Test-Eq 'Points : clichés des points seulement'  ((@(Select-RestoreShadow $shd @($t0, $t0.AddDays(1).AddMinutes(2))) | ForEach-Object { $_.ID }) -join ',') 'pr1,pr2'
Test-Eq 'Points : aucun point = rien'            @(Select-RestoreShadow $shd @()).Count 0

# ---------- filtres de recherche : texte tapé pris tel quel, sans motif (B8)
Import-SrcFunction 'Test-TextHas'
Test-Eq 'Filtre : crochet ouvrant'               (Test-TextHas 'Outil [x64]' '[x6') $true
Test-Eq 'Filtre : casse ignorée'                 (Test-TextHas 'Mozilla Firefox' 'FIRE') $true
Test-Eq 'Filtre : * non joker'                   (Test-TextHas 'Firefox' 'F*x') $false

# ---------- ligne de commande winget : arguments avec espace entre guillemets (B9)
Import-SrcFunction 'Join-ProcessArg'
Test-Eq 'Arguments : override entre guillemets'  (Join-ProcessArg @('install', '--override', '--quiet --force', '')) 'install --override "--quiet --force" ""'

# ---------- analyse de disque : chemin long d'un partage réseau (B12)
if ('_OlivM.DirScan' -as [type]) {
    Test-Eq 'Chemin long : lecteur'              ([_OlivM.DirScan]::LongPath('C:\Dossier\')) '\\?\C:\Dossier\'
    Test-Eq 'Chemin long : partage réseau'       ([_OlivM.DirScan]::LongPath('\\serveur\partage\')) '\\?\UNC\serveur\partage\'
    Test-Eq 'Chemin long : déjà préfixé'         ([_OlivM.DirScan]::LongPath('\\?\D:\x\')) '\\?\D:\x\'
}

# ---------- réglages : valeur lue à l'avance utilisée seulement pendant la construction des lignes (B13) ; DNS inconnu (B15)
Import-SrcFunction 'Get-TweakState', 'Set-DnsProvider'
$Sync = @{ TwCache = [hashtable]::Synchronized(@{ X = $true }) }
$twx = [pscustomobject]@{ Id = 'X'; Get = { $false } }
$TwUseCache = $false
Test-Eq 'Réglage : relecture hors construction'  (Get-TweakState $twx) $false
$TwUseCache = $true
Test-Eq 'Réglage : valeur lue à l''avance'       (Get-TweakState $twx) $true
$TwUseCache = $false; $Sync = $null
$DnsProviders = [ordered]@{ AdGuard = @{ V4 = @('94.140.14.14') } }
$dr = 'accepté'; try { Set-DnsProvider 'Ancien' } catch { $dr = 'refusé' }
Test-Eq 'DNS : fournisseur inconnu refusé'       $dr 'refusé'

# ---------- antivirus : couleur sur les seuls antivirus actifs de date connue (B21, B22)
Import-SrcFunction 'Get-AvWorstAge'
$now = [DateTime]::Now
Test-Eq 'Antivirus : tiers sans date ignoré'     ([int](Get-AvWorstAge @(@{ Date = $null; Passive = $false }, @{ Date = $now.AddDays(-1); Passive = $false }))) 1
Test-Eq 'Antivirus : Defender passif ignoré'     ([int](Get-AvWorstAge @(@{ Date = $now.AddDays(-30); Passive = $true }, @{ Date = $now.AddHours(-2); Passive = $false }))) 0
Test-Eq 'Antivirus : aucune date connue'         ($null -eq (Get-AvWorstAge @(@{ Date = $null; Passive = $false }))) $true

# ---------- claviers : dernier clavier de la langue principale jamais proposé au retrait (B24)
Import-SrcFunction 'Test-KeyboardRemovable'
Test-Eq 'Clavier : dernier de la langue principale' (Test-KeyboardRemovable 0 1 2) $false
Test-Eq 'Clavier : 2e clavier de la principale'  (Test-KeyboardRemovable 0 2 2) $true
Test-Eq 'Clavier : clavier d''une autre langue'   (Test-KeyboardRemovable 1 1 2) $true
Test-Eq 'Clavier : seul clavier du poste'        (Test-KeyboardRemovable 1 1 1) $false

# ---------- licence : Windows activé retenu avant un complément non activé (B27)
Import-SrcFunction 'Select-WinLicense'
$lic = Select-WinLicense @([pscustomobject]@{ Name = 'ESU'; LicenseStatus = 0; LicenseIsAddon = $true }, [pscustomobject]@{ Name = 'Windows'; LicenseStatus = 1; LicenseIsAddon = $false })
Test-Eq 'Licence : Windows activé retenu'        $lic.Name 'Windows'
$lic2 = Select-WinLicense @([pscustomobject]@{ Name = 'Notif'; LicenseStatus = 5; LicenseIsAddon = $false }, [pscustomobject]@{ Name = 'Activé'; LicenseStatus = 1; LicenseIsAddon = $false })
Test-Eq 'Licence : activé avant notification'    $lic2.Name 'Activé'

# ---------- moniteur : arborescence et PID réutilisé (B28)
Import-SrcFunction 'Get-MonDescendant', 'Test-MonSameProc'
$tree = @(@{ Pid = 10; Parent = 1 }, @{ Pid = 20; Parent = 10 }, @{ Pid = 30; Parent = 20 }, @{ Pid = 40; Parent = 1 })
Test-Eq 'Arborescence : descendants'             ((@(Get-MonDescendant 10 $tree) | Sort-Object) -join ',') '20,30'
$me = Get-Process -Id $PID
Test-Eq 'PID : même processus'                   (Test-MonSameProc $PID $me.StartTime.ToFileTime()) $true
Test-Eq 'PID : réutilisé (autre heure)'          (Test-MonSameProc $PID ($me.StartTime.AddMinutes(-5).ToFileTime())) $false
Test-Eq 'PID : heure inconnue'                   (Test-MonSameProc $PID 0) $true

# ---------- recherche globale : caractères hors du plan de base (emoji) sans erreur, positions conservées (B32)
Import-SrcFunction 'Get-FlatText'
$emo = 'Été ' + [char]::ConvertFromUtf32(0x1F600) + ' Démo'
$fl = 'erreur'; try { $fl = Get-FlatText $emo } catch { $fl = 'erreur' }
Test-Eq 'Recherche : emoji sans erreur'          ($fl.Length -eq $emo.Length -and $fl.StartsWith('ete ') -and $fl.EndsWith(' demo')) $true

# ---------- détail SFC : lignes de l'exécution en cours seulement (B42)
Import-SrcFunction 'Select-SfcLine'
$cbs = @('2026-11-20 09:00:00, Info CSI 00000001 [SR] ancienne exécution', '2026-11-26 14:00:03, Info CSI 00000002 [SR] Verifying', 'ligne sans date [SR]', '2026-11-26 14:05:00, Info CSI 00000003 [SR] Repaired')
Test-Eq 'SFC : lignes depuis le lancement'       (@(Select-SfcLine $cbs ([DateTime]'2026-11-26 14:00:05')).Count) 2

# ---------- nettoyage : crochets d'un nom de profil pris tels quels (B43)
Import-SrcFunction 'ConvertTo-CleanPattern', 'Resolve-CleanTarget'
Test-Eq 'Motif : chemin sans joker'              ($null -eq (ConvertTo-CleanPattern 'C:\Users\Jean[1]\AppData\Local\Temp')) $true
Test-Eq 'Motif : partie fixe échappée'           (ConvertTo-CleanPattern 'C:\Users\Jean[1]\User Data\*\Cache') 'C:\Users\Jean`[1`]\User Data\*\Cache'
$cp = Join-Path ([IO.Path]::GetTempPath()) ('olivm-test-' + [guid]::NewGuid().ToString('N') + '\Jean[1]')
[void][IO.Directory]::CreateDirectory((Join-Path $cp 'Temp')); [void][IO.Directory]::CreateDirectory((Join-Path $cp 'Data\Profil 1\Cache'))
try {
    Test-Eq 'Nettoyage : profil à crochets'      @(Resolve-CleanTarget @{ Paths = @("D:$cp\Temp") }).Count 1
    Test-Eq 'Nettoyage : crochets et joker'      @(Resolve-CleanTarget @{ Paths = @("D:$cp\Data\*\Cache") }).Count 1
} finally { try { [IO.Directory]::Delete((Split-Path $cp), $true) } catch { $null = $_ } }

# ---------- historiques (JSON Lines) lus par paquets, ligne corrompue ignorée, ordre conservé ; cache des logiciels (P5, P6)
Import-SrcFunction 'Read-JsonLine', 'Get-SoftHistory'
$jl = Join-Path ([IO.Path]::GetTempPath()) ('olivm-test-' + [guid]::NewGuid().ToString('N') + '.jsonl')
try {
    $rows = @(1..1200 | ForEach-Object { '{"N":' + $_ + ',"Date":"2026-11-' + ('{0:D2}' -f (1 + $_ % 28)) + 'T10:00:00"}' })
    [IO.File]::WriteAllLines($jl, [string[]]($rows[0..599] + @('{"N":') + $rows[600..1199]), [Text.UTF8Encoding]::new($false))
    $rd = @(Read-JsonLine $jl 'test')
    Test-Eq 'JSON Lines : 1200 entrées lues'       $rd.Count 1200
    Test-Eq 'JSON Lines : ordre conservé'          ('{0},{1}' -f $rd[0].N, $rd[1199].N) '1,1200'
    $SoftHistFile = $jl; $SoftHistCache = @{ Stamp = ''; Rows = @() }
    Test-Eq 'Historique logiciels : lu'            @(Get-SoftHistory).Count 1200
    $stamp1 = $SoftHistCache.Stamp
    [void](Get-SoftHistory)
    Test-Eq 'Historique logiciels : cache réutilisé' $SoftHistCache.Stamp $stamp1
    [IO.File]::AppendAllText($jl, '{"N":1201,"Date":"2026-12-15T10:00:00"}' + "`r`n")
    Test-Eq 'Historique logiciels : relu si modifié' @(Get-SoftHistory).Count 1201
    Test-Eq 'Historique logiciels : plus récent en tête' @(Get-SoftHistory)[0].N 1201
} finally { try { [IO.File]::Delete($jl) } catch { $null = $_ } }

# ---------- imprimante par défaut : nom échappé dans la requête WQL (P10)
Import-SrcFunction 'ConvertTo-WqlString'
Test-Eq 'WQL : apostrophe et barre oblique'      (ConvertTo-WqlString "\\srv\HP d'accueil") "\\\\srv\\HP d\'accueil"

# ---------- attente sans figer la fenêtre : délai respecté (P4)
Add-Type -AssemblyName WindowsBase
Import-SrcFunction 'Wait-UiDelay'
$sw = [Diagnostics.Stopwatch]::StartNew(); Wait-UiDelay 200; $sw.Stop()
Test-Eq 'Attente : 200 ms au moins'              ($sw.ElapsedMilliseconds -ge 190 -and $sw.ElapsedMilliseconds -lt 2000) $true

# ---------- rangement des journaux : dossiers de l'arborescence actuelle jamais supprimés (P14)
Import-SrcFunction 'Get-LogPath', 'Move-OldLog'
$LogDir = Join-Path ([IO.Path]::GetTempPath()) ('olivm-test-' + [guid]::NewGuid().ToString('N'))
$LogCats = [ordered]@{ Restauration = 'Systeme\Point de restauration'; Demarrage = 'Systeme\Applications au demarrage'; Etat = '_etat'; Depannage = 'Maintenance\Depannage' }
foreach ($d in @($LogCats.Values) + @('Reglages\vide')) { [void][IO.Directory]::CreateDirectory((Join-Path $LogDir $d)) }
try {
    Move-OldLog
    Test-Eq 'Journaux : dossier actuel gardé'      ([IO.Directory]::Exists((Join-Path $LogDir 'Systeme\Point de restauration'))) $true
    Test-Eq 'Journaux : ancien dossier vide retiré' ([IO.Directory]::Exists((Join-Path $LogDir 'Reglages'))) $false
} finally { try { [IO.Directory]::Delete($LogDir, $true) } catch { $null = $_ } }

# ---------- groupes de réglages : chacun a son icône de carte (I5)
$GroupInfo = Get-SrcValue 'GroupInfo'
$grpSrc = [IO.File]::ReadAllText((Join-Path $root 'src\10-catalogue.ps1'), $utf8)
$grpMiss = @([regex]::Matches($grpSrc, "Group='([^']+)'") | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique | Where-Object { -not $GroupInfo.ContainsKey($_) })
Test-Eq 'Groupes de réglages : icône'            ($grpMiss -join ', ') ''

# ---------- choix du réglage : écriture refusée = $false, rien d'affiché comme pris (I1)
Import-SrcFunction 'Set-AffichageValue'
function global:Open-RegKey { throw 'accès refusé' }
function global:Show-Info { $null = $args }
function global:Write-UiLog { $null = $args }
Test-Eq 'Choix enregistré : échec signalé'       (Set-AffichageValue 'Test' 1) $false
Remove-Item function:global:Open-RegKey, function:global:Show-Info, function:global:Write-UiLog

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
