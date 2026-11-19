# ---------- Nouvelle version : mise à jour sans perte, réinitialisation seulement à la 1re installation suivie
# Version du dernier lancement dans _etat\version.txt.
# - Fichier présent, version différente (mise à jour, ou retour à une version antérieure) : tout est conservé
#   (paramètres, journaux, historique, résultats mémorisés), simple mention dans le journal.
# - Fichier absent alors que le dossier de l'application contient déjà des fichiers (restes d'une version antérieure à
#   ce suivi) : dossier vidé (comme Paramètres > Réinitialisation) sauf le suivi des modifications en attente de
#   redémarrage, réglages du compte (HKCU\Software\Oliv_Maintenance\Maintenance) supprimés. Réglages Windows non annulés.
# Placé après l'instance unique (03-contexte) : une 2e ouverture ne vide jamais le dossier d'une instance en cours.
$VersionFile = Join-Path (Get-LogPath 'Etat') 'version.txt'
$UpgradeNote = $null
try {
    $prev = $(if (Test-Path -LiteralPath $VersionFile) { [IO.File]::ReadAllText($VersionFile).Trim() } else { '' })
    $used = $prev -or @(Get-ChildItem -LiteralPath $LogDir -Recurse -File -Force -ErrorAction SilentlyContinue | Select-Object -First 1).Count -gt 0
    if (-not $prev -and $used) {
        $keep = @($VersionFile, (Join-Path (Get-LogPath 'Etat') 'en-attente.json'))
        foreach ($x in @(Get-ChildItem -LiteralPath $LogDir -Recurse -Force -File -ErrorAction SilentlyContinue)) {
            if ($x.FullName -in $keep) { continue }
            try { $x.Delete() } catch { Write-Ignored 'Réinitialisation après mise à jour' $_ }
        }
        foreach ($d in @(Get-ChildItem -LiteralPath $LogDir -Recurse -Force -Directory -ErrorAction SilentlyContinue | Sort-Object { $_.FullName.Length } -Descending)) {
            if (-not @(Get-ChildItem -LiteralPath $d.FullName -Force -ErrorAction SilentlyContinue).Count) { try { $d.Delete() } catch {} }
        }
        try { $k = Open-RegKey 'HKCU\Software\Oliv_Maintenance' $true; if ($k) { try { $k.DeleteSubKeyTree('Maintenance', $false) } finally { $k.Close() } } } catch { Write-Ignored 'Réinitialisation après mise à jour (réglages du compte)' $_ }
        foreach ($d in $LogCats.Values) { [void][IO.Directory]::CreateDirectory((Join-Path $LogDir $d)) }
        $UpgradeNote = "Première installation de la version $AppVersion : restes d'une version antérieure effacés (paramètres, historique). Réglages Windows appliqués conservés."
    }
    elseif ($prev -and $prev -ne $AppVersion) { $UpgradeNote = 'Mise à jour {0} > {1} : paramètres, historique et résultats mémorisés conservés.' -f $prev, $AppVersion }
    [IO.File]::WriteAllText($VersionFile, $AppVersion)
} catch { Write-Ignored 'Réinitialisation après mise à jour' $_ }
