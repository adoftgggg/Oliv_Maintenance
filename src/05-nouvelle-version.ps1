# ---------- Nouvelle version : application réinitialisée au premier lancement (comme Paramètres > Réinitialisation)
# Version du dernier lancement dans _etat\version.txt. Version différente, ou fichier absent alors que le dossier de
# l'application contient déjà des fichiers (version antérieure à ce suivi) : tout le dossier est vidé (paramètres,
# journaux, rapports, instantanés, résultats mémorisés) sauf le suivi des modifications en attente de redémarrage et
# ce fichier, réglages du compte (HKCU\Software\Oliv_Maintenance\Maintenance) supprimés. Réglages Windows appliqués non annulés.
# Placé après l'instance unique (03-contexte) : une 2e ouverture ne vide jamais le dossier d'une instance en cours.
$VersionFile = Join-Path (Get-LogPath 'Etat') 'version.txt'
$UpgradeNote = $null
try {
    $prev = $(if (Test-Path -LiteralPath $VersionFile) { [IO.File]::ReadAllText($VersionFile).Trim() } else { '' })
    $used = $prev -or @(Get-ChildItem -LiteralPath $LogDir -Recurse -File -Force -ErrorAction SilentlyContinue | Select-Object -First 1).Count -gt 0
    if ($prev -ne $AppVersion -and $used) {
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
        $UpgradeNote = 'Nouvelle version ({0} > {1}) : application réinitialisée (paramètres, historique et résultats mémorisés). Réglages Windows appliqués conservés.' -f $(if ($prev) { $prev } else { 'version antérieure' }), $AppVersion
    }
    [IO.File]::WriteAllText($VersionFile, $AppVersion)
} catch { Write-Ignored 'Réinitialisation après mise à jour' $_ }
