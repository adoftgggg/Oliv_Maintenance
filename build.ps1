<#
.SYNOPSIS
    Assemble les sources de Oliv_Maintenance en un seul fichier livrable dist\Oliv_Maintenance.cmd et le contrôle.

.DESCRIPTION
    1. Concatène src\*.ps1 dans l'ordre alphabétique (préfixe numérique = ordre de chargement).
    2. Inscrit la version (fichier VERSION ou -Version) et la date de compilation (heure de Paris).
       Compile native\*.cs en une DLL embarquée compressée dans le script ($NativeDll, chargée en mémoire au démarrage).
    3. Contrôles bloquants : syntaxe PowerShell du script principal et de chaque script embarqué (here-strings),
       XAML bien formé, caractères interdits (BMP > U+07FF, U+2010-U+201F), absence de BOM.
       Analyse statique PSScriptAnalyzer (tools\PSScriptAnalyzerSettings.psd1) si le module est installé.
    4. Exécute les tests unitaires (tests\Run-Tests.ps1).
    5. Écrit dist\Oliv_Maintenance.cmd en UTF-8 sans BOM, fins de ligne CRLF.
    6. Compile le lanceur dist\Oliv_Maintenance_<version>.exe (launcher\Lanceur.cs, script embarqué compressé, manifeste
       requireAdministrator, icône, version). Windows PowerShell 5.1 uniquement : sous PowerShell 7, seule la syntaxe
       est contrôlée si le compilateur Mono (mcs) est présent.

.PARAMETER SkipTests
    N'exécute pas tests\Run-Tests.ps1 avant l'écriture du livrable (déconseillé).

.PARAMETER SkipLint
    N'exécute pas l'analyse statique PSScriptAnalyzer (tools\PSScriptAnalyzerSettings.psd1).

.PARAMETER Version
    Nouvelle version (0.x.y). Mise à jour du fichier VERSION avant l'assemblage.

.PARAMETER SignOnly
    Signe dist\Oliv_Maintenance_<version>.exe déjà construit (aucun assemblage, aucun test) : exe livré sans signature.

.PARAMETER CertThumbprint
    Empreinte du certificat de signature de code. Par défaut : certificat « Oliv » de signature de code le plus
    récent, avec clé privée, du magasin personnel de l'utilisateur (Cert:\CurrentUser\My) puis de l'ordinateur.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\build.ps1
    powershell -NoProfile -ExecutionPolicy Bypass -File .\build.ps1 -SignOnly
    powershell -NoProfile -ExecutionPolicy Bypass -File .\build.ps1 -Version 0.100.0
#>
[CmdletBinding()]
param([string]$Version, [switch]$SkipTests, [switch]$SkipLint, [switch]$SignOnly, [string]$CertThumbprint)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
$root = $PSScriptRoot
$utf8 = [Text.UTF8Encoding]::new($false)

# ---------- signature Authenticode de l'exe (certificat de signature de code Oliv, voir tools\New-CertificatSignature.ps1)
# Horodatage DigiCert : la signature reste valide après l'expiration du certificat. Contrôle : Status Valid attendu (racine
# du certificat présente dans les autorités de confiance du poste de construction).
function Invoke-ExeSigning([string]$Path) {
    if ($PSVersionTable.PSEdition -eq 'Core' -or -not (Get-Command Set-AuthenticodeSignature -ErrorAction SilentlyContinue)) {
        Write-Host 'Signature : non disponible ici (Windows PowerShell 5.1 requis) : lancer .\build.ps1 -SignOnly sous Windows.' -ForegroundColor Yellow; return
    }
    $cert = $null
    if ($CertThumbprint) { $cert = @(Get-ChildItem Cert:\CurrentUser\My, Cert:\LocalMachine\My | Where-Object { $_.Thumbprint -eq ($CertThumbprint -replace '\s', '') }) | Select-Object -First 1 }
    else {
        $cert = @(Get-ChildItem Cert:\CurrentUser\My, Cert:\LocalMachine\My -CodeSigningCert -ErrorAction SilentlyContinue |
            Where-Object { $_.Subject -like '*Oliv*' -and $_.HasPrivateKey -and $_.NotAfter -gt (Get-Date) } | Sort-Object NotAfter -Descending) | Select-Object -First 1
    }
    if (-not $cert) { Write-Host 'Signature : aucun certificat de signature de code Oliv trouvé, exe NON signé (voir tools\New-CertificatSignature.ps1).' -ForegroundColor Yellow; return }
    $r = Set-AuthenticodeSignature -FilePath $Path -Certificate $cert -HashAlgorithm SHA256 -TimestampServer 'http://timestamp.digicert.com' -ErrorAction Stop
    if ($r.Status -ne 'Valid') { $r = Set-AuthenticodeSignature -FilePath $Path -Certificate $cert -HashAlgorithm SHA256 -ErrorAction Stop; Write-Host 'Signature : horodatage DigiCert injoignable, signature sans horodatage (invalide à l''expiration du certificat).' -ForegroundColor Yellow }
    $v = Get-AuthenticodeSignature -FilePath $Path
    if ($v.Status -ne 'Valid') { throw "Signature de $Path : état $($v.Status) - $($v.StatusMessage)" }
    Write-Host ('Signature : {0} signé par {1} (empreinte {2}, expire le {3:dd/MM/yyyy}){4}' -f (Split-Path $Path -Leaf), $cert.GetNameInfo('SimpleName', $false), $cert.Thumbprint, $cert.NotAfter, $(if ($v.TimeStamperCertificate) { ', horodaté' } else { '' })) -ForegroundColor Green
}
if ($SignOnly) {
    $exe = Join-Path (Join-Path $root 'dist') ('Oliv_Maintenance_{0}.exe' -f [IO.File]::ReadAllText((Join-Path $root 'VERSION')).Trim())
    if (-not (Test-Path -LiteralPath $exe)) { throw "$exe introuvable : construire d'abord" }
    Invoke-ExeSigning $exe
    return
}

# ---------- version et date
$verFile = Join-Path $root 'VERSION'
if ($Version) {
    if ($Version -notmatch '^0\.\d+\.\d+$') { throw "Version invalide : $Version (format attendu 0.x.y)" }
    [IO.File]::WriteAllText($verFile, $Version + "`n", $utf8)
}
$ver = [IO.File]::ReadAllText($verFile, $utf8).Trim()
try { $tz = [TimeZoneInfo]::FindSystemTimeZoneById('Romance Standard Time') } catch { $tz = [TimeZoneInfo]::FindSystemTimeZoneById('Europe/Paris') }
$stamp = [TimeZoneInfo]::ConvertTimeFromUtc([DateTime]::UtcNow, $tz).ToString('yyyy-MM-dd HH:mm')

# ---------- assemblage
$files = @(Get-ChildItem -LiteralPath (Join-Path $root 'src') -Filter '*.ps1' -File | Sort-Object Name)
if (-not $files.Count) { throw 'Aucune source dans src\' }
$sb = [Text.StringBuilder]::new()
foreach ($f in $files) {
    $raw = [IO.File]::ReadAllBytes($f.FullName)
    if ($raw.Length -ge 3 -and $raw[0] -eq 0xEF -and $raw[1] -eq 0xBB -and $raw[2] -eq 0xBF) { throw "$($f.Name) : BOM interdit (UTF-8 sans BOM attendu)" }
    $t = $utf8.GetString($raw).Replace("`r`n", "`n")
    if (-not $t.EndsWith("`n")) { $t += "`n" }
    [void]$sb.Append($t)
}
$code = $sb.ToString().TrimEnd("`n")
$code = [regex]::Replace($code, "(?m)^\`$AppVersion = '[^']*'", "`$AppVersion = '$ver'")
$code = [regex]::Replace($code, "(?m)^\`$BuildDate  = '[^']*'", "`$BuildDate  = '$stamp'")

# ---------- code natif (native\*.cs) : une DLL compilée ici, embarquée compressée dans le script ($NativeDll, 01-natif.ps1)
# et chargée en mémoire au démarrage : plus aucune compilation C# sur le poste (0,5 à 1 s par bloc à chaque première
# ouverture après une mise à jour), aucun fichier DLL écrit sur le disque.
$obj = Join-Path (Join-Path $root 'dist') 'obj'
[void][IO.Directory]::CreateDirectory($obj)
$natSrc = @(Get-ChildItem -LiteralPath (Join-Path $root 'native') -Filter '*.cs' -File | Sort-Object Name)
if (-not $natSrc.Count) { throw 'Aucune source dans native\' }
$natDll = Join-Path $obj 'olivm_natif.dll'
if (Test-Path -LiteralPath $natDll) { Remove-Item -LiteralPath $natDll -Force }
if ($PSVersionTable.PSEdition -ne 'Core') {
    $cp = [CodeDom.Compiler.CompilerParameters]::new()
    $cp.GenerateExecutable = $false; $cp.GenerateInMemory = $false; $cp.OutputAssembly = $natDll
    foreach ($r in 'System.dll', 'System.Core.dll') { [void]$cp.ReferencedAssemblies.Add($r) }
    $cp.CompilerOptions = '/target:library /optimize+'
    $res = [Microsoft.CSharp.CSharpCodeProvider]::new().CompileAssemblyFromSource($cp, [string[]]@($natSrc | ForEach-Object { [IO.File]::ReadAllText($_.FullName, $utf8) }))
    $errs = @($res.Errors | Where-Object { -not $_.IsWarning })
    if ($errs.Count) { $errs | ForEach-Object { Write-Host "  Code natif ligne $($_.Line) : $($_.ErrorText)" -ForegroundColor Red }; throw 'Compilation du code natif en échec : livrable non produit.' }
} else {
    $mcs = Get-Command mcs -ErrorAction SilentlyContinue
    if (-not $mcs) { throw 'Code natif : compilateur C# introuvable (Windows PowerShell 5.1 ou Mono mcs requis)' }
    # assemblys de référence du .NET Framework 4.8 fournis avec Mono (4.8-api) : le mscorlib de Mono contient des méthodes
    # absentes du .NET Framework (ex. String.Split(Char, StringSplitOptions)) ; compilé contre lui, le code natif levait
    # MissingMethodException sur les postes (0.114.8, recherche globale). Compilation contre la surface réelle de Windows.
    $api = '/usr/lib/mono/4.8-api'
    $refs = $(if (Test-Path -LiteralPath (Join-Path $api 'mscorlib.dll')) { @('-nostdlib', "-r:$api/mscorlib.dll", "-r:$api/System.dll", "-r:$api/System.Core.dll") } else { throw "Code natif : assemblys de référence .NET Framework 4.8 introuvables ($api)" })
    $o = & $mcs.Source -nologo -langversion:5 -optimize+ -target:library -nowarn:169,649 ("-out:$natDll") @refs @($natSrc | ForEach-Object { $_.FullName }) 2>&1
    if ($LASTEXITCODE -ne 0) { $o | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }; throw 'Compilation du code natif en échec : livrable non produit.' }
}
$nb = [IO.File]::ReadAllBytes($natDll)
$nms = [IO.MemoryStream]::new()
$nz = [IO.Compression.GZipStream]::new($nms, [IO.Compression.CompressionMode]::Compress); $nz.Write($nb, 0, $nb.Length); $nz.Dispose()
if (-not $code.Contains("'__NATIVE_DLL__'")) { throw 'Emplacement $NativeDll introuvable dans src\01-natif.ps1' }
$code = $code.Replace("'__NATIVE_DLL__'", "'" + [Convert]::ToBase64String($nms.ToArray()) + "'")
$natKo = $nb.Length / 1KB

# ---------- contrôles
$errors = [Collections.Generic.List[string]]::new()
$tok = $null; $perr = $null
$ast = [System.Management.Automation.Language.Parser]::ParseInput($code, [ref]$tok, [ref]$perr)
foreach ($e in $perr) { $errors.Add("Syntaxe (script principal) ligne $($e.Extent.StartLineNumber) : $($e.Message)") }
# scripts embarqués : here-strings entre apostrophes = code PowerShell (runspaces) ou XAML (commence par <)
$here = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.StringConstantExpressionAst] -and $n.StringConstantType -eq 'SingleQuotedHereString' }, $true)
$nPs = 0; $nXml = 0
foreach ($h in $here) {
    $v = $h.Value
    if ($v.TrimStart().StartsWith('<')) {
        $nXml++
        try { [void][xml]$v } catch { $errors.Add("XAML ligne $($h.Extent.StartLineNumber) : $($_.Exception.Message)") }
    } else {
        $nPs++
        $e2 = $null; [void][System.Management.Automation.Language.Parser]::ParseInput($v, [ref]$null, [ref]$e2)
        foreach ($e in $e2) { $errors.Add("Syntaxe (script embarqué ligne $($h.Extent.StartLineNumber)) +$($e.Extent.StartLineNumber) : $($e.Message)") }
    }
}
# caractères interdits : 3 octets en UTF-8 (lecture incertaine par Invoke-Expression selon la page de codes) et guillemets typographiques
$bad = @{}
foreach ($ch in $code.ToCharArray()) { $c = [int]$ch; if (($c -gt 0x7FF -and $c -lt 0xD800) -or ($c -ge 0xE000 -and $c -le 0xFFFF) -or ($c -ge 0x2010 -and $c -le 0x201F)) { $bad[('U+{0:X4}' -f $c)] = 1 } }
if ($bad.Count) { $errors.Add('Caractères interdits : ' + (@($bad.Keys | Sort-Object) -join ', ')) }
# édition personnelle (dépôt public) : aucune mention de l'édition professionnelle ni de ses outils dans le script ni dans
# aucun fichier texte du projet (sources, lanceur, outils, tests, README)
$perso = '(?i)4\s?sys|dat{2}o'
foreach ($chk in @(@('script', $code), @('lanceur', [IO.File]::ReadAllText((Join-Path $root 'launcher\Lanceur.cs'), $utf8)))) {
    if ($chk[1] -match $perso) { $errors.Add("Édition personnelle : mention « $($Matches[0]) » trouvée dans le $($chk[0]) (interdit).") }
}
foreach ($f in @(Get-ChildItem -LiteralPath $root -Recurse -File -Include *.ps1, *.psd1, *.md, *.cs, *.txt, *.rc, *.json, *.xml | Where-Object { $_.FullName -notmatch '[\\/](dist|\.git)[\\/]' })) {
    if ([IO.File]::ReadAllText($f.FullName) -match $perso) { $errors.Add("Édition personnelle : mention « $($Matches[0]) » dans $($f.FullName.Substring($root.Length + 1)) (interdit).") }
}
# [math]::Min / Max avec un entier littéral et une valeur décimale : PowerShell choisit la surcharge Int32 (3,7 -> 4,
# 0,3 -> 0, au-delà de 2 Go : exception). Littéral à typer ([double]0) sauf si l'autre argument est un entier explicite.
$ln = 0
foreach ($l in ($code -split "`n")) {
    $ln++
    foreach ($m in [regex]::Matches($l, '\[math\]::(Min|Max)\(\d+(?:KB|MB|GB)?, *([^;]{0,40})')) {
        if ($m.Groups[2].Value -notmatch '^(\[int\]|\[long\]|\$[\w.]+\.(Count|Length)\b|\[Environment\]::ProcessorCount|\$Steps\b)') { $errors.Add("Ligne $ln : $($m.Value.Trim()) - typer le littéral ([double]) pour éviter la surcharge Int32") }
    }
}

# analyse statique (PSScriptAnalyzer, règles et exclusions justifiées dans tools\PSScriptAnalyzerSettings.psd1) : verbes
# approuvés, noms au singulier, casse des commandes, alias, comparaisons à $null, chaînes constantes... Bloquante si le
# module est présent ; sinon signalée (Install-Module PSScriptAnalyzer -Scope CurrentUser pour l'activer).
if (-not $SkipLint) {
    if (Get-Module -ListAvailable -Name PSScriptAnalyzer) {
        Import-Module PSScriptAnalyzer
        # contenu passé lu en UTF-8 (-ScriptDefinition) : avec -Path, Windows PowerShell 5.1 lit les sources sans BOM en
        # ANSI (« à » final devenait « Ã » + espace insécable : fausse alerte d'espace en fin de ligne)
        $set = Join-Path (Join-Path $root 'tools') 'PSScriptAnalyzerSettings.psd1'
        # PSScriptAnalyzer lève parfois une NullReferenceException interne (cache des commandes) : une nouvelle tentative
        $lintRun = { param($Code) try { @(Invoke-ScriptAnalyzer -ScriptDefinition $Code -Settings $set -ErrorAction Stop) } catch { @(Invoke-ScriptAnalyzer -ScriptDefinition $Code -Settings $set -ErrorAction Stop) } }
        foreach ($f in $files) {
            foreach ($l in @(& $lintRun ([IO.File]::ReadAllText($f.FullName, $utf8)))) {
                if ($f.Name -eq '00-entree.ps1' -and $l.RuleName -in 'PSAvoidUsingWriteHost', 'PSAvoidGlobalVars', 'PSAvoidUsingInvokeExpression') { continue }
                $errors.Add(('Analyse statique {0}:{1} [{2}] {3}' -f $f.Name, $l.Line, $l.RuleName, $l.Message))
            }
            # scripts embarqués (here-strings de code exécutés dans les runspaces) : mêmes règles
            $fa = [Management.Automation.Language.Parser]::ParseInput([IO.File]::ReadAllText($f.FullName, $utf8), [ref]$null, [ref]$null)
            foreach ($h in $fa.FindAll({ param($n) $n -is [Management.Automation.Language.StringConstantExpressionAst] -and "$($n.StringConstantType)" -eq 'SingleQuotedHereString' }, $true)) {
                if ($h.Value.TrimStart().StartsWith('<')) { continue }
                foreach ($l in @(& $lintRun $h.Value)) {
                    $errors.Add(('Analyse statique {0}:{1} (script embarqué) [{2}] {3}' -f $f.Name, ($h.Extent.StartLineNumber + $l.Line), $l.RuleName, $l.Message))
                }
            }
        }
    } else { Write-Host '  Analyse statique ignorée : module PSScriptAnalyzer absent.' -ForegroundColor Yellow }
    # verbes approuvés seulement depuis PowerShell 6 (Build, Deploy) : refusés par l'analyse sous Windows PowerShell 5.1
    foreach ($m in [regex]::Matches($code, '(?im)^\s*function\s+((Build|Deploy)-[\w-]+)')) { $errors.Add("Verbe non approuvé sous Windows PowerShell 5.1 : $($m.Groups[1].Value)") }
}

if ($errors.Count) {
    $errors | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    throw "$($errors.Count) erreur(s) : livrable non produit."
}

# ---------- tests unitaires (processus séparé : les fonctions chargées n'interfèrent pas avec l'assemblage)
if (-not $SkipTests) {
    $exe = (Get-Process -Id $PID).Path
    & $exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path (Join-Path $root 'tests') 'Run-Tests.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'Tests en échec : livrable non produit.' }
}

# ---------- écriture
$dist = Join-Path $root 'dist'
[void][IO.Directory]::CreateDirectory($dist)
$out = Join-Path $dist 'Oliv_Maintenance.cmd'
[IO.File]::WriteAllText($out, $code.Replace("`n", "`r`n") + "`r`n", $utf8)
$size = (Get-Item -LiteralPath $out).Length
Write-Host ('Oliv_Maintenance {0} ({1}) : {2} sources, {3} scripts embarqués, {4} XAML, code natif {5} fichiers C# ({6:N0} Ko), {7:N0} Ko -> {8}' -f $ver, $stamp, $files.Count, $nPs, $nXml, $natSrc.Count, $natKo, ($size / 1KB), $out) -ForegroundColor Green

# ---------- lanceur Oliv_Maintenance.exe (launcher\Lanceur.cs)
# Compilateur C# du .NET Framework 4.x (CodeDom) : disponible uniquement sous Windows PowerShell 5.1. Ailleurs, l'exe n'est
# pas produit ; si le compilateur Mono (mcs) est présent, la syntaxe du lanceur est tout de même contrôlée.
$cs = [IO.File]::ReadAllText((Join-Path (Join-Path $root 'launcher') 'Lanceur.cs'), $utf8).Replace('__VERSION4__', "$ver.0").Replace('__VERSION__', $ver)
$gz = Join-Path $obj 'app.ps1.gz'
$ms = [IO.File]::Create($gz)
try { $z = [IO.Compression.GZipStream]::new($ms, [IO.Compression.CompressionMode]::Compress); $b = $utf8.GetBytes($code.Replace("`n", "`r`n") + "`r`n"); $z.Write($b, 0, $b.Length); $z.Dispose() } finally { $ms.Dispose() }

$m = [regex]::Match($code, "(?m)^\`$LogoIcoB64\s*=\s*'([A-Za-z0-9+/=]+)'")
if (-not $m.Success) { throw 'Icône $LogoIcoB64 introuvable dans les sources' }
$ico = Join-Path $obj 'olivm.ico'
[IO.File]::WriteAllBytes($ico, [Convert]::FromBase64String($m.Groups[1].Value))
$manifest = Join-Path $obj 'app.manifest'
[IO.File]::WriteAllText($manifest, @"
<?xml version="1.0" encoding="utf-8" standalone="yes"?>
<assembly manifestVersion="1.0" xmlns="urn:schemas-microsoft-com:asm.v1">
  <assemblyIdentity version="$ver.0" name="Oliv_Maintenance.Maintenance" type="win32"/>
  <trustInfo xmlns="urn:schemas-microsoft-com:asm.v2">
    <security>
      <requestedPrivileges xmlns="urn:schemas-microsoft-com:asm.v3">
        <requestedExecutionLevel level="requireAdministrator" uiAccess="false"/>
      </requestedPrivileges>
    </security>
  </trustInfo>
  <compatibility xmlns="urn:schemas-microsoft-com:compatibility.v1">
    <application>
      <supportedOS Id="{8e0f7a12-bfb3-4fe8-b9a5-48fd50a15a9a}"/>
    </application>
  </compatibility>
</assembly>
"@, $utf8)
# nom versionné (Oliv_Maintenance_0.x.y.exe) : versions précédentes du lanceur retirées de dist
$exeOut = Join-Path $dist "Oliv_Maintenance_$ver.exe"
Get-ChildItem -LiteralPath $dist -Filter 'Oliv_Maintenance*.exe' -File -ErrorAction SilentlyContinue | Where-Object { $_.FullName -ne $exeOut } | Remove-Item -Force -ErrorAction SilentlyContinue
if ($PSVersionTable.PSEdition -ne 'Core') {
    $cp = [CodeDom.Compiler.CompilerParameters]::new()
    $cp.GenerateExecutable = $true
    $cp.GenerateInMemory = $false
    $cp.OutputAssembly = $exeOut
    $cp.TreatWarningsAsErrors = $false
    [void]$cp.ReferencedAssemblies.Add('System.dll')
    [void]$cp.EmbeddedResources.Add($gz)
    $cp.CompilerOptions = '/target:winexe /platform:anycpu /optimize+ /win32icon:"{0}" /win32manifest:"{1}"' -f $ico, $manifest
    $res = [Microsoft.CSharp.CSharpCodeProvider]::new().CompileAssemblyFromSource($cp, $cs)
    $errs = @($res.Errors | Where-Object { -not $_.IsWarning })
    if ($errs.Count) { $errs | ForEach-Object { Write-Host "  Lanceur ligne $($_.Line) : $($_.ErrorText)" -ForegroundColor Red }; throw 'Compilation du lanceur en échec : Oliv_Maintenance.exe non produit.' }
    Write-Host ('Lanceur {0} : {1:N0} Ko -> {2}' -f $ver, ((Get-Item -LiteralPath $exeOut).Length / 1KB), $exeOut) -ForegroundColor Green
    Invoke-ExeSigning $exeOut
} else {
    if (Test-Path -LiteralPath $exeOut) { Remove-Item -LiteralPath $exeOut -Force }
    $mcs = Get-Command mcs -ErrorAction SilentlyContinue
    $windres = Get-Command x86_64-w64-mingw32-windres -ErrorAction SilentlyContinue
    if ($mcs -and $windres) {
        # hors Windows (Mono + binutils MinGW) : icône, manifeste et version en ressource Win32 compilée par windres
        $v = ($ver + '.0').Replace('.', ',')
        [IO.File]::WriteAllText((Join-Path $obj 'app.rc'), @"
1 ICON "olivm.ico"
1 24 "app.manifest"
1 VERSIONINFO
FILEVERSION $v
PRODUCTVERSION $v
BEGIN
  BLOCK "StringFileInfo"
  BEGIN
    BLOCK "040C04B0"
    BEGIN
      VALUE "CompanyName", "Oliv"
      VALUE "FileDescription", "Oliv_Maintenance"
      VALUE "FileVersion", "$ver"
      VALUE "InternalName", "Oliv_Maintenance"
      VALUE "LegalCopyright", "Oliv"
      VALUE "OriginalFilename", "Oliv_Maintenance_$ver.exe"
      VALUE "ProductName", "Oliv_Maintenance"
      VALUE "ProductVersion", "$ver"
    END
  END
  BLOCK "VarFileInfo"
  BEGIN
    VALUE "Translation", 0x040C, 1200
  END
END
"@, [Text.UTF8Encoding]::new($false))
        Push-Location $obj
        try {
            $o = & $windres.Source -O res -i app.rc -o app.res 2>&1
            if ($LASTEXITCODE -ne 0) { $o | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }; throw 'Lanceur : ressources Win32 en échec.' }
            $src = Join-Path $obj 'Lanceur.cs'; [IO.File]::WriteAllText($src, $cs, $utf8)
            $api = '/usr/lib/mono/4.8-api'
            $o = & $mcs.Source -nologo -langversion:5 -optimize+ -platform:anycpu -target:winexe ("-out:$exeOut") ("-resource:$gz,app.ps1.gz") -win32res:app.res -nostdlib "-r:$api/mscorlib.dll" "-r:$api/System.dll" $src 2>&1
            if ($LASTEXITCODE -ne 0) { $o | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }; throw 'Compilation du lanceur en échec : Oliv_Maintenance.exe non produit.' }
        } finally { Pop-Location }
        Write-Host ('Lanceur {0} (Mono) : {1:N0} Ko -> {2} (à signer sous Windows : .\build.ps1 -SignOnly)' -f $ver, ((Get-Item -LiteralPath $exeOut).Length / 1KB), $exeOut) -ForegroundColor Green
    } elseif ($mcs) {
        $src = Join-Path $obj 'Lanceur.cs'; [IO.File]::WriteAllText($src, $cs, $utf8)
        $o = & $mcs.Source -nologo -langversion:5 -target:winexe -out:(Join-Path $obj 'controle.exe') ("-resource:$gz,app.ps1.gz") ("-win32icon:$ico") -r:System.dll $src 2>&1
        if ($LASTEXITCODE -ne 0) { $o | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }; throw 'Lanceur : erreurs de syntaxe C#.' }
        Write-Host 'Lanceur : syntaxe C# 5 contrôlée (mcs). Oliv_Maintenance.exe à produire sous Windows PowerShell 5.1.' -ForegroundColor Yellow
    } else {
        Write-Host 'Oliv_Maintenance.exe non produit : construire sous Windows PowerShell 5.1.' -ForegroundColor Yellow
    }
}
