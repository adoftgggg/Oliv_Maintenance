$OemFile = Join-Path (Get-LogPath 'Etat') 'constructeur.json'

# journal des 3 runspaces constructeur (recherche, installation de l'outil, installation des mises à jour) : interface et
# fichier $Sync.OemLog ; ajouté en tête de chaque script par Start-OemJob
$OemLogLib = @'
function Write-TaskLog([string]$Message, [string]$Level = 'INFO') {
    $line = '{0} [{1,-5}] {2}' -f (Get-Date -Format 'HH:mm:ss'), $Level, $Message
    $Sync.Queue.Enqueue($line)
    try { [IO.File]::AppendAllText($Sync.OemLog, $line + [Environment]::NewLine, [Text.Encoding]::UTF8) }
    catch {
        if (-not $Sync.OemLogErr) {
            $Sync.OemLogErr = $true
            $Sync.Queue.Enqueue(('{0} [WARN ] Écriture du journal constructeur impossible ({1}) : {2}' -f (Get-Date -Format 'HH:mm:ss'), $Sync.OemLog, $_.Exception.Message))
        }
    }
}
'@
function Start-OemJob([string]$Key, [string]$Script) { Start-BgJob $Key ($OemLogLib + "`n" + $Script) }

# Recherche des mises à jour constructeur : runspace d'arrière-plan indépendant des autres tâches (journal Systeme dédié)
$OemScript = @'
# progression publiée par les commandes (Install-Module, modules constructeur) conservée dans le flux Progress, lu par l'interface
$ProgressPreference = 'Continue'
function Invoke-Native([string]$FilePath, [string[]]$ArgumentList) {
    Write-TaskLog ('> {0} {1}' -f $FilePath, ($ArgumentList -join ' ')) 'CMD'
    $p = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -WindowStyle Hidden -PassThru
    $Sync.OemChildPid = $p.Id
    try { $p.WaitForExit() } finally { $Sync.OemChildPid = $null }
    Write-TaskLog "Code retour : $($p.ExitCode)"
    $p.ExitCode
}
& {

    $bios = Get-ItemProperty 'HKLM:\HARDWARE\DESCRIPTION\System\BIOS' -ErrorAction SilentlyContinue
    $man = "$($bios.SystemManufacturer)".Trim()
    $res = @{ Time = [DateTime]::Now.ToString('o'); Vendor = $man; Model = (@("$($bios.SystemFamily)".Trim(), "$($bios.SystemProductName)".Trim()) | Where-Object { $_ -and $_ -notmatch '^(?i)(to be filled.*|default string|system (product name|version|family|manufacturer|serial number)|not (specified|applicable|available)|none|n/?a|oem|o\.e\.m\.?|unknown|invalid|empty|x+|0+|[\s.\-_0]*)$' } | Select-Object -Unique) -join ' · '; Tool = ''; Items = @(); Error = $null }
    # pilotes proposés par Windows Update (« Mises à jour facultatives > Mises à jour de pilotes » dans Paramètres) :
    # recherche en ligne sur les serveurs Microsoft (hors WSUS), identifiants « wu:<UpdateID> » installables à l'unité
    # outil du constructeur absent (Dell Command | Update, HP Image Assistant) : installé automatiquement par winget avant
    # l'analyse (paquets winget-pkgs Dell.CommandUpdate.Universal et HP.ImageAssistant, vérifiés le 24/11/2026)
    function Install-OemTool([string]$Id, [string]$Name) {
        try {
            Set-JobStep 'Oem' 1 4 "installation de $Name (winget)"
            $wg = Find-Winget; if (-not $wg) { throw 'winget introuvable.' }
            Write-TaskLog "$Name absent : installation automatique par winget ($Id)."
            $p = Start-Process -FilePath $wg -ArgumentList @('install', '-e', '--id', $Id, '--silent', '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity') -WindowStyle Hidden -Wait -PassThru
            Write-TaskLog ('{0} : code retour winget {1}' -f $Name, $p.ExitCode) $(if ($p.ExitCode -eq 0) { 'OK' } else { 'ERROR' })
            $p.ExitCode -eq 0
        } catch { Write-TaskLog "Installation de $Name : $($_.Exception.Message)" 'ERROR'; $false }
    }
    function Get-WuDriverItem([int]$Step, [int]$Steps) {
        Write-TaskLog 'Pilotes proposés par Windows Update (mises à jour facultatives, serveurs Microsoft)...'
        Set-JobStep 'Oem' $Step $Steps 'recherche des pilotes Windows Update'
        $sess = New-Object -ComObject Microsoft.Update.Session; $sess.ClientApplicationID = 'Oliv_Maintenance'
        $srch = $sess.CreateUpdateSearcher(); $srch.ServerSelection = 2; $srch.Online = $true
        $r = $srch.Search("IsInstalled=0 and IsHidden=0 and Type='Driver'")
        $n = [math]::Max(1, $r.Updates.Count); $i = 0
        @(foreach ($u in $r.Updates) {
            $i++; Set-JobStep 'Oem' ($Step + 1) $Steps "analyse de $($r.Updates.Count) $(Get-Plural $r.Updates.Count 'pilote' 'pilotes') Windows Update" (100 * $i / $n)
            $dv = ''; try { $dv = '{0:dd/MM/yyyy}' -f $u.DriverVerDate } catch {}
            @{ Id = "wu:$($u.Identity.UpdateID)"; Source = 'WU'; Unattended = $true; Title = "$($u.Title)"; Version = ''; Category = ("$($u.DriverClass)  ·  $($u.DriverProvider)").Trim(' ', [char]0xB7); Severity = ''; Size = "$([long]$u.MaxDownloadSize)"; Date = $dv }
        })
    }
    $dir = Join-Path $Sync.LogRoot '_etat\constructeur'
    try {
        if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue }
        [void](New-Item -ItemType Directory -Path $dir -Force)
    } catch { Write-Ignored 'Préparation du dossier constructeur' $_ }
    Write-TaskLog "Constructeur : $man - modèle : $($res.Model)"
    try {
        switch -Regex ($man) {
            'Lenovo' {
                $res.Tool = 'Lenovo.Client.Update (Get-LnvUpdate)'
                # étapes : module, catalogue Lenovo, pilotes Windows Update, analyse des pilotes
                Set-JobStep 'Oem' 1 4 'module Lenovo.Client.Update'
                [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
                if (-not (Get-Module -ListAvailable -Name Lenovo.Client.Update)) {
                    Write-TaskLog 'Module Lenovo.Client.Update absent : installation depuis PowerShell Gallery (AllUsers).'
                    if (-not (Get-PackageProvider -ListAvailable -Name NuGet -ErrorAction SilentlyContinue | Where-Object { $_.Version -ge [version]'2.8.5.201' })) {
                        [void](Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers -ErrorAction Stop)
                    }
                    Install-Module -Name Lenovo.Client.Update -Repository PSGallery -Scope AllUsers -Force -ErrorAction Stop
                }
                Import-Module Lenovo.Client.Update -ErrorAction Stop
                Write-TaskLog ('Lenovo.Client.Update {0} : recherche des pilotes, BIOS et firmware applicables (plusieurs minutes possibles)...' -f (Get-Module Lenovo.Client.Update).Version)
                Set-JobStep 'Oem' 2 4 'catalogue Lenovo (pilotes, BIOS, firmware)'
                $pk = @(Get-LnvUpdate -ScratchDirectory $dir -ErrorAction Stop)
                $Sync.OemPkgs = $pk
                $res.Items = @($pk | ForEach-Object {
                    @{ Id = "$($_.PackageID)"; Unattended = [bool]$_.Installer.Unattended; Title = "$($_.Title)"; Version = "$($_.Version)"; Category = "$($_.Category)"; Severity = "$($_.Severity)"; Size = "$($_.FileSize)"; Date = "$($_.ReleaseDate)" } })
            }
            '^Dell' {
                Set-JobStep 'Oem' 1 4 'outil Dell Command | Update'
                $findDcu = { @("$env:ProgramFiles\Dell\CommandUpdate\dcu-cli.exe", "${env:ProgramFiles(x86)}\Dell\CommandUpdate\dcu-cli.exe") | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1 }
                $dcu = & $findDcu
                # outil absent : installé tout seul (winget), puis recherche poursuivie
                if (-not $dcu -and (Install-OemTool 'Dell.CommandUpdate.Universal' 'Dell Command | Update')) { $dcu = & $findDcu }
                if (-not $dcu) {
                    $res.ToolMissing = 'Dell.CommandUpdate.Universal'
                    $res.ToolName = 'Dell Command | Update'
                    throw 'Dell Command | Update absent (dcu-cli.exe introuvable).'
                }
                $res.Tool = 'Dell Command | Update (dcu-cli /scan)'
                Set-JobStep 'Oem' 2 4 'analyse Dell Command | Update'
                $rc = Invoke-Native $dcu @('/scan', "-report=$dir\DCUApplicableUpdates.xml")
                if ($rc -eq 500) { Write-TaskLog 'Dell Command | Update : aucune mise à jour applicable.' 'OK' }
                elseif ($rc -ne 0) { throw "dcu-cli /scan : code retour $rc" }
                else {
                    $xf = Get-ChildItem -LiteralPath $dir -Filter '*.xml' -File -Recurse -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
                    if ($xf) {
                        [xml]$xd = Get-Content -LiteralPath $xf.FullName -Raw
                        $res.Items = @($xd.SelectNodes('//update') | ForEach-Object {
                            @{ Title = "$($_.name)"; Version = "$($_.version)"; Category = "$($_.category) $($_.type)".Trim(); Severity = "$($_.urgency)"; Size = "$($_.bytes)"; Date = "$($_.date)" } })
                    }
                }
            }
            '^(HP|Hewlett)' {
                Set-JobStep 'Oem' 1 4 'outil HP Image Assistant'
                $findHp = {
                $hpia = @("$env:ProgramFiles\HP\HPIA\HPImageAssistant.exe", "${env:ProgramFiles(x86)}\HP\HPIA\HPImageAssistant.exe", "$env:SystemDrive\HPIA\HPImageAssistant.exe") | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
                if (-not $hpia) {
                    foreach ($wd in "$env:ProgramFiles\WinGet\Packages", "$env:LOCALAPPDATA\Microsoft\WinGet\Packages") {
                        if (-not $hpia -and (Test-Path -LiteralPath $wd)) { $hpia = Get-ChildItem -LiteralPath $wd -Directory -Filter 'HP.ImageAssistant*' -ErrorAction SilentlyContinue | ForEach-Object { Get-ChildItem -LiteralPath $_.FullName -Filter 'HPImageAssistant.exe' -File -Recurse -Depth 3 -ErrorAction SilentlyContinue } | Select-Object -First 1 -ExpandProperty FullName }
                    }
                }
                if (-not $hpia -and (Test-Path -LiteralPath "$env:SystemDrive\SWSetup")) { $hpia = Get-ChildItem -LiteralPath "$env:SystemDrive\SWSetup" -Filter 'HPImageAssistant.exe' -File -Recurse -Depth 2 -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName }
                $hpia
                }
                $hpia = & $findHp
                if (-not $hpia -and (Install-OemTool 'HP.ImageAssistant' 'HP Image Assistant')) { $hpia = & $findHp }
                if (-not $hpia) {
                    $res.ToolMissing = 'HP.ImageAssistant'
                    $res.ToolName = 'HP Image Assistant'
                    throw 'HP Image Assistant absent (HPImageAssistant.exe introuvable).'
                }
                $res.Tool = 'HP Image Assistant (/Operation:Analyze /Action:List)'
                Set-JobStep 'Oem' 2 4 'analyse HP Image Assistant'
                $rc = Invoke-Native $hpia @('/Operation:Analyze', '/Action:List', '/Category:All', '/Selection:All', '/Silent', "/ReportFolder:$dir")
                # codes de retour : guide utilisateur HP Image Assistant, tableau 7-1
                $hpErr = @{ 4096 = 'modèle non pris en charge par HP Image Assistant'; 4097 = 'paramètres invalides'; 4098 = 'pas de connexion Internet'
                            4102 = 'TLS 1.2 ou supérieur requis'; 4103 = 'requête incomplète vers le serveur HP'; 8192 = 'échec de l''opération'
                            8196 = 'échec du téléchargement de la liste des modèles pris en charge'; 8197 = 'échec du téléchargement de la base HP'
                            16384 = 'fichier de référence illisible'; 16385 = 'fichier de référence invalide' }
                if ($rc -eq 256) { Write-TaskLog 'HP Image Assistant : aucune recommandation.' 'OK' }
                elseif ($rc -ne 0 -and $rc -ne 4104) { throw ('HP Image Assistant : code retour {0}{1}' -f $rc, $(if ($hpErr.ContainsKey([int]$rc)) { ' (' + $hpErr[[int]$rc] + ')' } else { '' })) }
                else {
                    # 4104 : HP ne publie pas de référence pour cette version de Windows sur ce modèle, analyse faite avec la
                    # référence générique du modèle (rapport produit quand même, recommandations possiblement incomplètes)
                    if ($rc -eq 4104) { Write-TaskLog 'HP Image Assistant : pas de référence HP pour cette version de Windows sur ce modèle (code 4104), analyse faite avec la référence générique du modèle : liste possiblement incomplète.' 'WARN'; $res.Note = 'référence HP générique : version de Windows non suivie par HP pour ce modèle' }
                    $jf = Get-ChildItem -LiteralPath $dir -Filter '*.json' -File -Recurse -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
                    if ($jf) {
                        $j = Get-Content -LiteralPath $jf.FullName -Raw | ConvertFrom-Json
                        $res.Items = @(@($j.HPIA.Recommendations) | Where-Object { $_ } | ForEach-Object {
                            @{ Title = "$($_.Name)"; Version = "$($_.ReferenceVersion)"; Category = "$($_.Category)"; Severity = "$($_.RecommendationValue)"; Size = ''; Date = '' } })
                    } else { Write-TaskLog "Rapport HP Image Assistant : $dir" 'WARN' }
                }
            }
            default {
                # ASUS, MSI, Gigabyte et autres : pas d'outil constructeur en ligne de commande, pilotes publiés sur Windows Update
                $res.Tool = 'Windows Update (pilotes)'
                $res.Items = @(Get-WuDriverItem 1 2)
                $res.WuDone = $true
            }
        }
        # Lenovo, Dell, HP : pilotes Windows Update ajoutés aux paquets de l'outil constructeur ; un échec ici ne retire pas ces derniers
        if (-not $res.WuDone -and -not $Sync.OemCancelled) {
            foreach ($x in @($res.Items)) { if (-not $x.Source) { $x.Source = 'OEM' } }
            try { $res.Items = @($res.Items) + @(Get-WuDriverItem 3 4); $res.Tool += ' + Windows Update (pilotes)' }
            catch { $res.WuError = $_.Exception.Message; Write-TaskLog "Pilotes Windows Update : $($res.WuError)" 'WARN' }
        }
        Write-TaskLog ('{0} {1}.' -f @($res.Items).Count, (Get-Plural (@($res.Items).Count) 'mise à jour constructeur disponible' 'mises à jour constructeur disponibles')) $(if (@($res.Items).Count) { 'WARN' } else { 'OK' })
        foreach ($x in $res.Items) { Write-TaskLog ('  {0} {1} [{2}] {3}' -f $x.Title, $x.Version, $x.Category, $x.Severity) }
    } catch { $res.Error = $_.Exception.Message; Write-TaskLog "Mises à jour constructeur : $($res.Error)" 'ERROR' }
    if ($Sync.OemCancelled) { return }
    $Sync.OemResult = $res
    try { ConvertTo-Json -InputObject $res -Depth 4 | Set-Content -LiteralPath (Join-Path $Sync.LogRoot '_etat\constructeur.json') -Encoding UTF8 } catch { Write-Ignored 'Enregistrement de la recherche constructeur' $_ }
}
'@
$OemInstallScript = @'
$ProgressPreference = 'SilentlyContinue'
# État par mise à jour publié pour la carte ($Sync.OemRun.Items[Id]) : State = wait | run | ok | fail | skip,
# Phase / Pct pendant l'opération (téléchargement et installation Windows Update : progression réelle de l'agent),
# Code = HRESULT (Windows Update) ou code de retour (outil constructeur)
function Set-OemItem([string]$Id, [hashtable]$V) { $it = $Sync.OemRun.Items[$Id]; if ($it) { foreach ($k in $V.Keys) { $it[$k] = $V[$k] } } }
# avancement global : chaque mise à jour pèse le même poids ; fraction de la mise à jour en cours (0-1)
function Set-OemPct([double]$Frac) { $n = [math]::Max(1, [int]$Sync.OemRun.Count); $Sync.OemRun.Pct = [int][math]::Min([double]99, 100 * (([int]$Sync.OemRun.Done) + [math]::Max([double]0, [math]::Min([double]1, $Frac))) / $n) }
# sélection mixte possible : pilotes Windows Update (« wu:<UpdateID> ») puis paquets de l'outil constructeur (Lenovo)
$ids   = @($Sync.OemInstallIds)
$wuIds = @($ids | Where-Object { "$_" -like 'wu:*' })
$oemIds = @($ids | Where-Object { "$_" -notlike 'wu:*' })
$Sync.OemRun = [hashtable]::Synchronized(@{ Count = $ids.Count; Done = 0; Pct = 0; Step = 'préparation'; Items = [hashtable]::Synchronized(@{}) })
foreach ($x in @($Sync.OemResult.Items | Where-Object { $ids -contains "$($_.Id)" })) { $Sync.OemRun.Items["$($x.Id)"] = [hashtable]::Synchronized(@{ Name = "$($x.Title)"; State = 'wait'; Phase = ''; Pct = -1; Code = 0 }) }
if ($wuIds.Count) {
    try {
        $sess = New-Object -ComObject Microsoft.Update.Session; $sess.ClientApplicationID = 'Oliv_Maintenance'
        $srch = $sess.CreateUpdateSearcher(); $srch.ServerSelection = 2; $srch.Online = $true
        $Sync.OemInstStatus = 'recherche des pilotes sélectionnés'; $Sync.OemRun.Step = 'recherche des pilotes sélectionnés sur Windows Update'
        $coll = New-Object -ComObject Microsoft.Update.UpdateColl; $collIds = [Collections.Generic.List[string]]::new()
        foreach ($u in $srch.Search("IsInstalled=0 and Type='Driver'").Updates) {
            $k = "wu:$($u.Identity.UpdateID)"
            if ($wuIds -contains $k) { if (-not $u.EulaAccepted) { $u.AcceptEula() }; [void]$coll.Add($u); $collIds.Add($k) }
        }
        foreach ($k in $wuIds) {
            if (-not $collIds.Contains($k)) { Set-OemItem $k @{ State = 'skip'; Phase = 'plus proposé' }; $Sync.OemRun.Done++ }
        }
        if ($coll.Count -eq 0) { Write-TaskLog 'Aucun des pilotes sélectionnés n''est encore proposé par Windows Update.' 'WARN' }
        else {
            $n = $coll.Count; $base = [int]$Sync.OemRun.Done
            # téléchargement puis installation en tâche asynchrone : GetProgress() donne la mise à jour en cours et son pourcentage
            foreach ($phase in 'téléchargement', 'installation') {
                $Sync.OemRun.Step = "$phase de $n $(Get-Plural $n 'pilote' 'pilotes') Windows Update"; $Sync.OemInstStatus = $Sync.OemRun.Step; Write-TaskLog $Sync.OemInstStatus
                if ($phase -eq 'téléchargement') { $op = $sess.CreateUpdateDownloader() } else { $op = $sess.CreateUpdateInstaller() }
                $op.Updates = $coll
                $job = $null; try { $job = $(if ($phase -eq 'téléchargement') { $op.BeginDownload($null, $null, $null) } else { $op.BeginInstall($null, $null, $null) }) } catch {}
                if ($job) {
                    while (-not $job.IsCompleted) {
                        try {
                            $pg = $job.GetProgress(); $ci = [int]$pg.CurrentUpdateIndex
                            for ($i = 0; $i -lt $n; $i++) {
                                $k = $collIds[$i]
                                if ($i -lt $ci) {
                                    if ($phase -eq 'téléchargement') { Set-OemItem $k @{ State = 'run'; Phase = 'téléchargé'; Pct = -1 } }
                                }
                                elseif ($i -eq $ci) { Set-OemItem $k @{ State = 'run'; Phase = $phase; Pct = [int]$pg.CurrentUpdatePercentComplete } }
                            }
                            # avancement : téléchargement = 1re moitié, installation = 2de moitié de la part des pilotes
                            $off = $(if ($phase -eq 'téléchargement') { 0 } else { 0.5 })
                            $Sync.OemRun.Pct = [int][math]::Min([double]99, 100 * ($base + $n * ($off + 0.5 * [int]$pg.PercentComplete / 100)) / [math]::Max(1, [int]$Sync.OemRun.Count))
                        } catch {}
                        Start-Sleep -Milliseconds 400
                    }
                    $res = $(if ($phase -eq 'téléchargement') { $op.EndDownload($job) } else { $op.EndInstall($job) })
                } else { $res = $(if ($phase -eq 'téléchargement') { $op.Download() } else { $op.Install() }) }
                if ($phase -eq 'installation') {
                    $rc = @{ 2 = 'installé'; 3 = 'installé avec erreurs'; 4 = 'échec'; 5 = 'annulé' }
                    for ($i = 0; $i -lt $n; $i++) {
                        $ur = $res.GetUpdateResult($i); $k = $collIds[$i]; $hr = [int64]$ur.HResult; if ($hr -lt 0) { $hr += 4294967296 }
                        if ([int]$ur.ResultCode -in 2, 3) {
                            $Sync.OemOkCount = 1 + [int]$Sync.OemOkCount
                            Set-OemItem $k @{ State = 'ok'; Phase = ''; Pct = 100 }
                        }
                        else { Set-OemItem $k @{ State = 'fail'; Code = $hr } }
                        $Sync.OemRun.Done++
                        Write-TaskLog ('{0} : {1} (0x{2:X8})' -f $coll.Item($i).Title, $(if ($rc.ContainsKey([int]$ur.ResultCode)) { $rc[[int]$ur.ResultCode] } else { "code $($ur.ResultCode)" }), $hr) $(if ([int]$ur.ResultCode -eq 2) { 'OK' } else { 'ERROR' })
                    }
                    if ($res.RebootRequired) { $Sync.OemReboot = $true }
                } elseif ($res.ResultCode -notin 2, 3) {
                    # téléchargement en échec : pilotes non téléchargés marqués en échec, installation des autres tentée quand même
                    for ($i = 0; $i -lt $n; $i++) {
                        try {
                            $ur = $res.GetUpdateResult($i)
                            if ([int]$ur.ResultCode -notin 2, 3) {
                                $hr = [int64]$ur.HResult
                                if ($hr -lt 0) { $hr += 4294967296 }
                                Set-OemItem $collIds[$i] @{ State = 'fail'; Code = $hr; Phase = 'téléchargement' }
                            }
                        } catch { Write-Ignored 'Résultat d''installation constructeur' $_ }
                    }
                    Write-TaskLog ('Téléchargement des pilotes : code {0} (0x{1:X8})' -f $res.ResultCode, $res.HResult) 'WARN'
                }
            }
        }
    } catch {
        Write-TaskLog "Installation des pilotes Windows Update : $($_.Exception.Message)" 'ERROR'
        foreach ($k in $wuIds) {
            if ($Sync.OemRun.Items[$k].State -in 'wait', 'run') {
                Set-OemItem $k @{ State = 'fail'; Phase = $_.Exception.Message }
                $Sync.OemRun.Done++
            }
        }
    }
}
if ($oemIds.Count) {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $Sync.OemRun.Step = 'chargement du module Lenovo.Client.Update'
        Import-Module Lenovo.Client.Update -ErrorAction Stop
        $pk = @($Sync.OemPkgs | Where-Object { $oemIds -contains "$($_.PackageID)" })
        if ($pk.Count -lt $oemIds.Count) {
            Write-TaskLog 'Paquets de la dernière recherche non disponibles en mémoire : nouvelle détection Get-LnvUpdate.'
            $Sync.OemRun.Step = 'nouvelle détection des paquets Lenovo'
            $dir = Join-Path $Sync.LogRoot '_etat\constructeur'
            $pk = @(Get-LnvUpdate -ScratchDirectory $dir -ErrorAction Stop | Where-Object { $oemIds -contains "$($_.PackageID)" })
        }
        foreach ($k in $oemIds) {
            if (-not @($pk | Where-Object { "$($_.PackageID)" -eq $k }).Count) {
                Set-OemItem $k @{ State = 'skip'; Phase = 'plus applicable' }
                $Sync.OemRun.Done++
            }
        }
        $i = 0
        foreach ($x in $pk) {
            $i++; $k = "$($x.PackageID)"; $Sync.OemInstStatus = '{0}/{1} : {2}' -f $i, $pk.Count, $x.Title
            $Sync.OemRun.Step = 'paquet Lenovo {0}/{1}' -f $i, $pk.Count
            # l'outil Lenovo télécharge puis installe sans publier de progression : étape seule, pas de pourcentage inventé
            Set-OemItem $k @{ State = 'run'; Phase = 'téléchargement et installation'; Pct = -1 }; Set-OemPct 0
            Write-TaskLog ('Installation {0} (version {1}, {2})' -f $Sync.OemInstStatus, $x.Version, $x.PackageID)
            try {
                # BIOS / UEFI / firmware : BitLocker suspendu jusqu'au prochain redémarrage (reprise automatique ensuite), sinon
                # la mise à jour du micrologiciel change les mesures du TPM et le poste demande la clé de récupération au démarrage
                if ("$($x.Title) $($x.Category)" -match '(?i)bios|uefi|firmware|micrologiciel|\bME\b|management engine|thunderbolt|tpm' -and (Get-Command Get-BitLockerVolume -ErrorAction SilentlyContinue)) {
                    try {
                        $bl = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction Stop
                        if ("$($bl.ProtectionStatus)" -eq 'On') { Suspend-BitLocker -MountPoint $env:SystemDrive -RebootCount 1 -ErrorAction Stop | Out-Null; Write-TaskLog ('BitLocker suspendu jusqu''au prochain redémarrage ({0}) : mise à jour du micrologiciel.' -f $env:SystemDrive) 'WARN' }
                    } catch { Write-TaskLog ('BitLocker : suspension impossible avant {0} ({1}) - mise à jour non lancée, la clé de récupération serait demandée au démarrage.' -f $x.Title, $_.Exception.Message) 'ERROR'; Set-OemItem $k @{ State = 'fail'; Phase = 'BitLocker non suspendu' }; $Sync.OemRun.Done++; continue }
                }
                $r = Install-LnvUpdate -Package $x -SaveBIOSUpdateInfoToRegistry -ErrorAction Stop
                Write-TaskLog ('{0} : {1} (code {2}, action {3}){4}' -f $x.Title, $(if ($r.Success) { 'installé' } else { 'échec' }), $r.ExitCode, $r.PendingAction, $(if ($r.FailureReason) { " - $($r.FailureReason)" } else { '' })) $(if ($r.Success) { 'OK' } else { 'ERROR' })
                if ($r.Success) {
                    $Sync.OemOkCount = 1 + [int]$Sync.OemOkCount
                    Set-OemItem $k @{ State = 'ok'; Phase = $(if ("$($r.PendingAction)" -match 'REBOOT|SHUTDOWN') { 'redémarrage requis' } else { '' }); Pct = 100 }
                }
                else { Set-OemItem $k @{ State = 'fail'; Code = [int64]$r.ExitCode; Phase = "$($r.FailureReason)" } }
                if ("$($r.PendingAction)" -match 'REBOOT|SHUTDOWN') { $Sync.OemReboot = $true }
            } catch {
                Write-TaskLog "$($x.Title) : $($_.Exception.Message)" 'ERROR'
                Set-OemItem $k @{ State = 'fail'; Phase = $_.Exception.Message }
            }
            $Sync.OemRun.Done++; Set-OemPct 0
        }
        if (-not $pk.Count) { Write-TaskLog 'Aucune des mises à jour constructeur sélectionnées n''est encore applicable.' 'WARN' }
    } catch {
        Write-TaskLog "Installation des mises à jour constructeur : $($_.Exception.Message)" 'ERROR'
        foreach ($k in $oemIds) {
            if ($Sync.OemRun.Items[$k].State -in 'wait', 'run') {
                Set-OemItem $k @{ State = 'fail'; Phase = $_.Exception.Message }
                $Sync.OemRun.Done++
            }
        }
    }
}
$Sync.OemRun.Pct = 100; $Sync.OemRun.Step = 'terminé'
'@
function Start-OemInstall([string[]]$Ids) {
    Close-BgJob
    if ($Sync.OemRunning -or $Sync.OemInstalling -or $BgJobs.ContainsKey('OemInst')) { return }
    $Sync.OemInstalling = $true
    $Sync.OemRun = $null
    $Sync.OemReboot = $false
    $Sync.OemOkCount = 0
    $Sync.OemInstallIds = $Ids
    $Sync.OemInstStatus = 'préparation'
    $Sync.OemStart = [DateTime]::Now
    $Sync.LogRoot = $LogDir
    $d = Get-LogPath 'AccueilOem'; try { [void](New-Item -ItemType Directory -Path $d -Force) } catch { Write-Ignored 'Dossier des journaux constructeur' $_ }
    $Sync.OemLog = Join-Path $d ('{0}_{1:yyyyMMdd-HHmmss}_constructeur-installation.log' -f $env:COMPUTERNAME, (Get-Date))
    Write-UiLog ('Installation de {0} {1}.' -f $Ids.Count, (Get-Plural $Ids.Count 'mise à jour constructeur' 'mises à jour constructeur'))
    Start-OemJob 'OemInst' $OemInstallScript
    Show-OemResult
}
function Stop-OemScan {
    if (-not $Sync.OemRunning) { return }
    $Sync.OemCancelled = $true
    $j = $BgJobs['Oem']; if ($j) { try { [void]$j.PS.BeginStop($null, $null) } catch {} }
    if ($Sync.OemChildPid) { & "$env:windir\System32\taskkill.exe" /PID $Sync.OemChildPid /T /F 2>&1 | Out-Null }
    Write-UiLog 'Recherche des mises à jour constructeur annulée : dernier résultat conservé.' 'WARN'
    try { [IO.File]::AppendAllText($Sync.OemLog, ('{0:HH:mm:ss} [WARN ] Recherche annulée par l''utilisateur.' -f (Get-Date)) + [Environment]::NewLine, [Text.Encoding]::UTF8) } catch {}
    $InfoUI.OemCancelBtn.IsEnabled = $false
}
$OemToolScript = @'
$ProgressPreference = 'SilentlyContinue'
$Sync.OemToolOk = $false
try {
    $wg = Find-Winget
    if (-not $wg) { throw 'winget introuvable (Programme d''installation d''application / App Installer absent).' }
    $a = @('install', '-e', '--id', $Sync.OemToolId, '--silent', '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity')
    Write-TaskLog ('> winget {0}' -f ($a -join ' ')) 'CMD'
    $psi = [Diagnostics.ProcessStartInfo]::new($wg, ($a -join ' ')); $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true; $psi.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
    $p = [Diagnostics.Process]::Start($psi)
    while ($null -ne ($l = $p.StandardOutput.ReadLine())) {
        $t = ($l -replace '[\u2580-\u259F\u2500-\u257F]', '').Trim()
        if ($t -and $t -notmatch '^[-\\|/]$' -and $t -notmatch '^\d+([.,]\d+)?\s*(KB|MB|GB|Ko|Mo|Go)\s*/') { Write-TaskLog $t }
    }
    $p.WaitForExit()
    Write-TaskLog "Code retour winget : $($p.ExitCode)" $(if ($p.ExitCode -eq 0) { 'OK' } else { 'ERROR' })
    $Sync.OemToolOk = $p.ExitCode -eq 0
} catch { Write-TaskLog "Installation de $($Sync.OemToolName) : $($_.Exception.Message)" 'ERROR' }
'@
function Start-OemToolInstall {
    $r = $Sync.OemResult
    if (-not $r.ToolMissing) { return }
    Close-BgJob
    if ($Sync.OemRunning -or $Sync.OemInstalling -or $BgJobs.ContainsKey('OemTool')) { return }
    if (-not (Confirm-Action ("Installer $($r.ToolName) sur ce poste ?`n`nInstallation silencieuse par winget (paquet $($r.ToolMissing)), puis nouvelle recherche des mises à jour constructeur."))) {
        return
    }
    $Sync.OemInstalling = $true
    $Sync.OemToolId = "$($r.ToolMissing)"
    $Sync.OemToolName = "$($r.ToolName)"
    $Sync.OemInstStatus = "installation de $($r.ToolName)"
    $Sync.OemStart = [DateTime]::Now
    $d = Get-LogPath 'AccueilOem'; try { [void](New-Item -ItemType Directory -Path $d -Force) } catch { Write-Ignored 'Dossier des journaux constructeur' $_ }
    $Sync.OemLog = Join-Path $d ('{0}_{1:yyyyMMdd-HHmmss}_constructeur-outil.log' -f $env:COMPUTERNAME, (Get-Date))
    Write-UiLog "Installation de $($r.ToolName) par winget."
    Start-OemJob 'OemTool' $OemToolScript
    Show-OemResult
}
function Start-OemScan([bool]$Auto = $false) {
    Close-BgJob
    if ($Sync.OemRunning -or $Sync.OemInstalling -or $BgJobs.ContainsKey('Oem')) { return }
    if ($Sync.Running -and -not $Auto) { return }
    $Sync.OemRunning = $true
    $Sync.OemCancelled = $false
    $Sync.OemStep = $null
    $Sync.OemAuto = $Auto
    $Sync.OemStart = [DateTime]::Now
    $Sync.LogRoot = $LogDir
    $d = Get-LogPath 'AccueilOem'; try { [void](New-Item -ItemType Directory -Path $d -Force) } catch { Write-Ignored 'Dossier des journaux constructeur' $_ }
    $Sync.OemLog = Join-Path $d ('{0}_{1:yyyyMMdd-HHmmss}_constructeur.log' -f $env:COMPUTERNAME, (Get-Date))
    Write-UiLog $(if ($Auto) { 'Recherche automatique des mises à jour constructeur (dernière recherche de plus de 7 jours).' } else { 'Recherche des mises à jour constructeur.' })
    Start-OemJob 'Oem' $OemScript
    Show-OemResult
}
# identifiants installables (paquet Lenovo ou pilote Windows Update) : cochés, sinon tous
function Get-OemInstallId {
    $all = @($Sync.OemResult.Items | Where-Object { $_ -and $_.Id } | ForEach-Object { "$($_.Id)" })
    $chk = @($all | Where-Object { $InfoUI.OemSel -and $InfoUI.OemSel[$_] })
    if ($chk.Count) { return $chk }
    $all
}
function Update-OemInstallButton {
    if (-not $InfoUI.OemInstBtn) { return }
    $all = @($Sync.OemResult.Items | Where-Object { $_ -and $_.Id })
    $chk = @($all | Where-Object { $InfoUI.OemSel -and $InfoUI.OemSel["$($_.Id)"] }).Count
    $InfoUI.OemInstBtn.Content = Get-InstallLabel $all.Count $chk
    $InfoUI.OemInstBtn.IsEnabled = $all.Count -gt 0 -and -not $Sync.OemRunning -and -not $Sync.OemInstalling -and -not $Sync.Running
}
# texte et couleur d'état d'une mise à jour constructeur en cours d'installation (mêmes règles que les logiciels)
function Get-OemItemText($It) {
    switch ("$($It.State)") {
        'wait' { @{ Text = 'en attente'; Brush = 'MutedBrush' } }
        'run'  {
            $ph = $(if ($It.Phase) { "$($It.Phase)" } else { 'préparation' })
            @{ Text = $(if ($It.Pct -gt 0 -and $ph -in 'téléchargement', 'installation') { "$ph $($It.Pct) %" } else { "$ph..." }); Brush = 'AccentBrush' }
        }
        'ok'   { @{ Text = $(if ($It.Phase) { "installé, $($It.Phase)" } else { 'installé' }); Brush = 'OkFgBrush' } }
        'fail' {
            $c = [int64]$It.Code
            @{ Text = $(if ($c) { 'échec (0x{0:X8})' -f $(if ($c -lt 0) { $c + 4294967296 } else { $c }) } else { 'échec' }); Brush = 'ErrFgBrush' }
        }
        'skip' { @{ Text = $(if ($It.Phase) { 'déjà à jour (' + "$($It.Phase)" + ')' } else { 'non installé' }); Brush = $(if ($It.Phase) { 'OkFgBrush' } else { 'WarnFgBrush' }) } }
        default { $null }
    }
}
# une ligne par mise à jour sélectionnée : titre à gauche, état à droite (détail de l'échec en info-bulle)
function Add-OemRunRow($Panel, $Run) {
    foreach ($k in @($Run.Items.Keys | Sort-Object { $Run.Items[$_].Name })) {
        $it = $Run.Items[$k]; $x = Get-OemItemText $it; if (-not $x) { continue }
        $v = Add-KV $Panel $it.Name $x.Text $x.Brush
        $v.Parent.Children[0].ToolTip = $it.Name
        if ($it.State -eq 'fail' -and $it.Phase) { $v.ToolTip = "$($it.Phase)" }
    }
}
# signature de l'état des mises à jour en cours d'installation : la liste n'est reconstruite que si elle change
function Get-OemRunSig { $run = $Sync.OemRun; if (-not $run) { return '' }; (@($run.Items.Keys | Sort-Object | ForEach-Object {
    $i = $run.Items[$_]
    '{0}:{1}:{2}:{3}' -f $_, $i.State, $i.Phase, $i.Pct
}) -join '|') + "|$([bool]$Sync.AutoReboot)" }
# Nom court du fabricant : « ASUSTeK COMPUTER INC. » > ASUS, « Micro-Star International Co., Ltd. » > MSI, « LENOVO » > Lenovo...
# Inconnu : formes juridiques et mots génériques retirés (Inc., Corporation, Co., Ltd., Computer, Technology...).
$OemBrands = [ordered]@{
    '(?i)^asus' = 'ASUS'; '(?i)micro-?star|^msi\b' = 'MSI'; '(?i)gigabyte' = 'Gigabyte'; '(?i)asrock' = 'ASRock'
    '(?i)hewlett|^hp\b' = 'HP'; '(?i)^dell' = 'Dell'; '(?i)^lenovo' = 'Lenovo'; '(?i)^acer' = 'Acer'; '(?i)^microsoft' = 'Microsoft'
    '(?i)fujitsu' = 'Fujitsu'; '(?i)dynabook' = 'Dynabook'; '(?i)toshiba' = 'Toshiba'; '(?i)samsung' = 'Samsung'
    '(?i)supermicro|super micro' = 'Supermicro'; '(?i)biostar' = 'Biostar'; '(?i)^intel' = 'Intel'; '(?i)medion' = 'Medion'
    '(?i)panasonic' = 'Panasonic'; '(?i)getac' = 'Getac'; '(?i)huawei' = 'Huawei'; '(?i)^apple' = 'Apple'; '(?i)^nzxt' = 'NZXT'
}
function Get-OemBrand([string]$Name) {
    $n = $Name.Trim(); if (-not $n) { return '' }
    foreach ($k in $OemBrands.Keys) { if ($n -match $k) { return $OemBrands[$k] } }
    ($n -replace '(?i)[,.]?\s*\b(inc|corp(oration)?|co|ltd|limited|gmbh|s\.?a\.?s?|computer|technology|international|electronics)\b\.?', '').Trim(' ', ',', '.')
}
# Ligne « Constructeur » : marque  ·  modèle  ·  n° de série. Modèle : nom commercial (famille chez Lenovo, dont le
# nom de produit est le type machine) ; PC assemblé (valeurs système par défaut) : marque et modèle de la carte mère.
# N° de série lu par la collecte de l'accueil (première valeur réelle : BIOS, produit, châssis, carte mère).
function Get-OemIdentity($Bios) {
    $ok = { param($v) $v = "$v".Trim(); if ($v -and $v -notmatch $SmbJunk) { $v } else { '' } }
    $man = & $ok $Bios.SystemManufacturer; $mod = & $ok $Bios.SystemProductName
    if ($man -match '(?i)^lenovo') { $fam = & $ok $Bios.SystemVersion; if (-not $fam) { $fam = & $ok $Bios.SystemFamily }; if ($fam) { $mod = $fam } }
    if (-not $man -or -not $mod) { $bm = & $ok $Bios.BaseBoardManufacturer; $bp = & $ok $Bios.BaseBoardProduct; if ($bm -or $bp) { $man = $bm; $mod = $bp } }
    $br = Get-OemBrand $man
    # « HP EliteBook 840 G8 » : marque non répétée devant le modèle
    if ($br -and $mod) { $mod = ($mod -replace ('^(?i)' + [regex]::Escape($br) + '\s+'), '') }
    $parts = @(@($br, $mod) | Where-Object { $_ })
    $S = $Sync.InfoSlow
    if ($S -and $S.Serial -and "$($S.SerialSrc)" -ne 'aucun') { $parts += 'n° de série ' + ("$($S.Serial)" -replace '\s+\(.*\)$', '') }
    $InfoUI.OemSerialShown = [bool]($S -and $S.Serial)
    $(if ($parts.Count) { $parts -join '  ·  ' } else { 'non renseigné par le fabricant' })
}
function Show-OemResult {
    if (-not $InfoUI.OemPanel) { return }
    # recherche ou installation en cours, sans changement d'état : seule la ligne d'avancement est mise à jour (même
    # principe que Update-WuProgress), au lieu de reconstruire la carte chaque seconde
    $live = $InfoUI.OemLive
    if ($live -and $InfoUI.OemPanel.Children.Contains($live.G.Text)) {
        if ($live.Mode -eq 'scan' -and $Sync.OemRunning -and -not $Sync.OemInstalling -and $live.Cancel -eq [bool]$Sync.OemCancelled) {
            $pg = Get-JobProgress 'Oem' 'Oem'
            $live.G.Text.Text = '{0}{1}  ·  {2:mm\:ss}' -f (Format-Pct $pg.Pct), $pg.Text, ([DateTime]::Now - $Sync.OemStart); $live.G.Bar.Value = $pg.Pct
            return
        }
        if ($live.Mode -eq 'inst' -and $Sync.OemInstalling -and $Sync.OemRun -and $live.Sig -eq (Get-OemRunSig)) {
            $run = $Sync.OemRun
            $live.G.Text.Text = 'Installation  ·  {0}{1}  ·  {2:mm\:ss}' -f (Format-Pct $run.Pct), $run.Step, ([DateTime]::Now - $Sync.OemStart)
            $live.G.Bar.Value = [math]::Max(0, [int]$run.Pct)
            return
        }
    }
    $InfoUI.OemLive = $null
    Update-AllSearchButton
    if (-not $InfoUI.OemSel) { $InfoUI.OemSel = @{} }
    $p = $InfoUI.OemPanel; $p.Children.Clear()
    $bios = Get-ItemProperty 'HKLM:\HARDWARE\DESCRIPTION\System\BIOS' -ErrorAction SilentlyContinue
    # constructeur, modèle et n° de série : déjà dans la carte Matériel, non répétés ici
    $r = $Sync.OemResult
    $InfoUI.OemAge.Text = ''
    $InfoUI.OemRunShown = [bool]($Sync.OemRunning -or $Sync.OemInstalling)
    $InfoUI.OemInstBtn.Visibility = 'Collapsed'; $InfoUI.OemToolBtn.Visibility = 'Collapsed'
    if ($Sync.OemInstalling) {
        # avancement global (mises à jour terminées + progression réelle de celle en cours) puis état de chaque mise à jour
        $run = $Sync.OemRun
        if ($run) {
            $g = Add-ProgressLine $p ('Installation  ·  {0}{1}  ·  {2:mm\:ss}' -f (Format-Pct $run.Pct), $run.Step, ([DateTime]::Now - $Sync.OemStart))
            $g.Bar.Value = [math]::Max(0, [int]$run.Pct)
            $InfoUI.OemLive = @{ Mode = 'inst'; G = $g; Sig = (Get-OemRunSig) }
            Add-OemRunRow $p $run
            $ar = [Windows.Controls.CheckBox]::new()
            $ar.Style = $Window.FindResource('TaskCheck')
            $ar.Content = 'Redémarrer à la fin si nécessaire'
            $ar.Margin = New-Thickness 46 6 10 0
            $ar.IsChecked = [bool]$Sync.AutoReboot; $ar.ToolTip = $Ui.AutoReboot.ToolTip
            $ar.Add_Click({ param($s, $e) $Sync.AutoReboot = [bool]$s.IsChecked; $Ui.AutoReboot.IsChecked = $Sync.AutoReboot })
            [void]$p.Children.Add($ar)
        } else { [void](Add-KV $p 'Installation' ('{0}  ·  {1:mm\:ss}' -f $Sync.OemInstStatus, ([DateTime]::Now - $Sync.OemStart))) }
        $InfoUI.OemBtn.IsEnabled = $false; return
    }
    $InfoUI.OemCancelBtn.Visibility = $(if ($Sync.OemRunning) { 'Visible' } else { 'Collapsed' })
    $InfoUI.OemBtn.Visibility = $(if ($Sync.OemRunning) { 'Collapsed' } else { 'Visible' })
    if ($Sync.OemRunning) {
        $InfoUI.OemCancelBtn.IsEnabled = -not $Sync.OemCancelled
        $pg = Get-JobProgress 'Oem' 'Oem'
        $g = Add-ProgressLine $p ('{0}{1}  ·  {2:mm\:ss}' -f (Format-Pct $pg.Pct), $pg.Text, ([DateTime]::Now - $Sync.OemStart)); $g.Bar.Value = $pg.Pct
        $InfoUI.OemLive = @{ Mode = 'scan'; G = $g; Cancel = [bool]$Sync.OemCancelled }
        # résultat précédent affiché en attendant le nouveau
        if ($r -and -not $r.Error) {
            $pi = @($r.Items | Where-Object { $_ })
            $age = try { Format-Age ([DateTime]::Parse("$($r.Time)", [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)) } catch { '' }
            $t = New-Text ('Résultat précédent ({0}) : {1}' -f $age, $(if ($pi.Count) { '{0} {1}' -f $pi.Count, (Get-Plural $pi.Count 'mise à jour disponible' 'mises à jour disponibles') } else { 'aucune mise à jour disponible' })) 'Muted'
            $t.Margin = New-Thickness 46 2 10 2; [void]$p.Children.Add($t)
            foreach ($x in ($pi | Select-Object -First 4)) {
                $v = Add-KV $p $(if ($x.Category) { $x.Category } else { 'Mise à jour' }) $x.Title 'MutedBrush'
                $v.FontWeight = [Windows.FontWeights]::Normal
            }
        }
        $InfoUI.OemBtn.IsEnabled = $false; return
    }
    $InfoUI.OemBtn.IsEnabled = -not $Sync.Running
    Update-AllSearchButton
    if (-not $r) { Add-StateLine $p 'Aucune recherche effectuée' 'MutedBrush'; return }
    try {
        $t = [DateTime]::Parse("$($r.Time)", [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
        $InfoUI.OemAge.Text = 'dernière recherche : ' + (Format-Age $t)
        $InfoUI.OemAge.ToolTip = "$($r.Tool)  ·  {0:dd/MM/yyyy HH:mm:ss}" -f $t
    } catch {}
    if ($r.Error) {
        Add-StateLine $p $r.Error 'ErrFgBrush'
        if ($r.ToolMissing) { $InfoUI.OemToolBtn.Content = "Installer $($r.ToolName)"; $InfoUI.OemToolBtn.Visibility = 'Visible' }
        return
    }
    # bilan de la dernière installation (jusqu'à la prochaine) : une ligne, détail par mise à jour en info-bulle
    if ($Sync.OemRun -and $Sync.OemRun.Step -eq 'terminé') {
        $its = @($Sync.OemRun.Items.Values)
        $nOk = @($its | Where-Object { $_.State -eq 'ok' }).Count
        $nKo = @($its | Where-Object { $_.State -eq 'fail' }).Count
        $nSk = @($its | Where-Object { $_.State -eq 'skip' }).Count
        $parts = @()
        if ($nOk) { $parts += '{0} {1}' -f $nOk, (Get-Plural $nOk 'installée' 'installées') }
        if ($nKo) { $parts += '{0} en échec' -f $nKo }
        # « skip » = paquet plus proposé à la nouvelle détection juste avant l'installation : déjà installé entre-temps (Windows
        # Update, Lenovo Vantage...) ou devenu inutile ; ce n'est pas un échec
        if ($nSk) { $parts += '{0} déjà à jour (plus proposée{1} par le constructeur)' -f $nSk, $(if ($nSk -gt 1) { 's' } else { '' }) }
        $v = Add-KV $p 'Dernière installation' ($parts -join ', ') $(if ($nKo) { 'ErrFgBrush' } else { 'OkFgBrush' })
        $v.ToolTip = (@($its | Sort-Object { $_.Name } | ForEach-Object { '{0} : {1}' -f $_.Name, (Get-OemItemText $_).Text }) -join "`n")
    }
    # analyse du constructeur faite avec une référence partielle (HP : version de Windows non suivie pour ce modèle)
    if ($r.Note) { $v = Add-KV $p 'Remarque' "$($r.Note)" 'WarnFgBrush'; $v.ToolTip = 'Liste des mises à jour possiblement incomplète : HP ne publie plus de référence pour cette version de Windows sur ce modèle.' }
    $items = @($r.Items | Where-Object { $_ })
    if (-not $items.Count) { Add-StateLine $p 'Aucune mise à jour disponible' 'OkFgBrush'; return }
    $sel = @($items | Where-Object { $_.Id })
    Add-StateLine $p ('{0} {1}{2}' -f $items.Count, (Get-Plural $items.Count 'mise à jour disponible' 'mises à jour disponibles'), $(if ($sel.Count) { '' } else { '  ·  installation sélective non proposée par l''outil du constructeur' })) 'WarnFgBrush'
    foreach ($k in @($InfoUI.OemSel.Keys)) { if (-not ($sel | Where-Object { $_.Id -eq $k })) { $InfoUI.OemSel.Remove($k) } }
    $list = [Windows.Controls.StackPanel]::new(); $list.Margin = New-Thickness 38 0 10 0; [void]$p.Children.Add($list)
    $more = [Windows.Controls.StackPanel]::new(); $more.Margin = New-Thickness 38 0 10 0; $idx = 0
    $InfoUI.OemChecks = [Collections.ArrayList]::new()
    # 2 origines (outil du constructeur + Windows Update) : intertitre discret avant chaque groupe
    $mixed = @($items | Where-Object { $_.Source -eq 'WU' }).Count -gt 0 -and @($items | Where-Object { $_.Source -ne 'WU' }).Count -gt 0
    $lastSrc = $null
    foreach ($x in $items) {
        $dst = $(if ($idx -lt $ListMax) { $list } else { $more }); $idx++
        $src = $(if ($x.Source -eq 'WU') { 'WU' } else { 'OEM' })
        if ($mixed -and $src -ne $lastSrc) {
            $h = New-Text $(if ($src -eq 'WU') { 'Pilotes Windows Update (mises à jour facultatives)' } else { ('Outil {0}' -f [Globalization.CultureInfo]::CurrentCulture.TextInfo.ToTitleCase("$($r.Vendor)".ToLower())).Trim() }) 'Muted'
            $h.FontSize = 12; $h.Margin = New-Thickness 8 $(if ($lastSrc) { 8 } else { 2 }) 8 2; [void]$dst.Children.Add($h)
            $lastSrc = $src
        }
        $d = @()
        if ($x.Category) { $d += $x.Category }
        if ($x.Version) { $d += "version $($x.Version)" }
        if ($x.Date) { $d += $x.Date }
        if ($x.Severity) { $d += $x.Severity }
        if ("$($x.Size)" -match '^\d+$' -and [double]$x.Size -gt 0) { $d += Format-SizeUi ([double]$x.Size) }
        if ($x.Id -and -not $x.Unattended) { $d += 'installation interactive (fenêtre à valider)' }
        # importance (même règle que le rapport d'intervention, 89-rapport.ps1) en tête de l'info-bulle
        $imp = Get-OemImportance $x
        $tip = "{0}`nImportance : {1} ({2})`n{3}" -f $x.Title, $imp.Label.ToLower(), $imp.Basis, ($d -join '  ·  ')
        if ($x.Id) {
            $cb = New-HoverCheck $dst ('{0}{1}' -f $x.Title, $(if ($x.Unattended) { '' } else { '  (interactive)' })) $tip {
                foreach ($c in $InfoUI.OemChecks) { $InfoUI.OemSel[$c.Tag] = [bool]$c.IsChecked }
                Update-OemInstallButton
            }
            $cb.Tag = $x.Id; $cb.IsChecked = [bool]$InfoUI.OemSel[$x.Id]; [void]$InfoUI.OemChecks.Add($cb)
        } else {
            # non installable à l'unité (Dell, HP) : ligne d'information dans la même liste, pour garder l'ordre des groupes
            $v = Add-KV $dst $(if ($x.Category) { $x.Category } else { 'Mise à jour' }) $x.Title
            $v.ToolTip = $tip
            $v.Parent.Parent.Margin = New-Thickness 0 0 0 0
        }
    }
    Add-FoldMore $p $more $items.Count 'Oem'
    if ($sel.Count) { $InfoUI.OemInstBtn.Visibility = 'Visible' }
    Update-OemInstallButton
}
