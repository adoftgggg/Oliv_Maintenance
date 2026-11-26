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

# ---------- nom court du fabricant (ligne Constructeur des mises à jour constructeur)
$OemBrands = Get-SrcValue 'OemBrands'

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
