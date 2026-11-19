$AppClock = [Diagnostics.Stopwatch]::StartNew()
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
# Code natif (native\*.cs) : DLL compilée par build.ps1 et embarquée ici compressée (base64), chargée en mémoire au
# démarrage. Aucune compilation C# sur le poste (Add-Type : 0,5 à 1 s par bloc à la première ouverture après chaque mise à
# jour, l'application n'étant ouverte que quelques fois par an), aucun fichier DLL écrit ni relu sur le disque. Les types
# (_OlivM.*) sont visibles de tous les runspaces (même domaine d'application). Échec signalé par 02-journaux.ps1.
$NativeDll = '__NATIVE_DLL__'
function Import-NativeDll {
    if ($NativeDll.StartsWith('__')) { throw 'code natif absent : lancer la version construite par build.ps1' }
    $z = [IO.Compression.GZipStream]::new([IO.MemoryStream]::new([Convert]::FromBase64String($NativeDll)), [IO.Compression.CompressionMode]::Decompress)
    $ms = [IO.MemoryStream]::new()
    try { $z.CopyTo($ms) } finally { $z.Dispose() }
    [void][Reflection.Assembly]::Load($ms.ToArray())
}
$NativeErr = $null; try { Import-NativeDll } catch { $NativeErr = $_ }
# AppUserModelID propre au processus, posé avant toute fenêtre : la barre des tâches ne regroupe plus l'outil
# avec PowerShell et affiche l'icône de la fenêtre (logo Oliv_Maintenance) au lieu de celle de powershell.exe
try { [void][_OlivM.Shell]::SetCurrentProcessExplicitAppUserModelID('Oliv.Maintenance') } catch {}

