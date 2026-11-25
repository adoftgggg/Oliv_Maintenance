# ---------- Nouvelle version : mise à jour sans perte, réinitialisation seulement à la 1re installation suivie
# Version du dernier lancement dans _etat\version.txt.
# - Fichier présent, version différente (mise à jour, ou retour à une version antérieure) : tout est conservé
#   (paramètres, journaux, historique, résultats mémorisés), simple mention dans le journal.
# - Fichier absent : recréé, rien n'est effacé.
# Placé après l'instance unique (03-contexte) : une 2e ouverture ne vide jamais le dossier d'une instance en cours.
$VersionFile = Join-Path (Get-LogPath 'Etat') 'version.txt'
$UpgradeNote = $null
try {
    $prev = $(if (Test-Path -LiteralPath $VersionFile) { [IO.File]::ReadAllText($VersionFile).Trim() } else { '' })
    $used = $prev -or @(Get-ChildItem -LiteralPath $LogDir -Recurse -File -Force -ErrorAction SilentlyContinue | Select-Object -First 1).Count -gt 0
    # suivi absent alors que le dossier contient des fichiers : plus d'effacement (il supprimait aussi la copie d'origine du
    # fichier hosts, la liste des services désactivés et les sauvegardes de stratégie dès que version.txt manquait)
    if (-not $prev -and $used) { $UpgradeNote = "Suivi de version recréé ($AppVersion) : paramètres, historique et sauvegardes conservés." }
    elseif ($prev -and $prev -ne $AppVersion) { $UpgradeNote = 'Mise à jour {0} > {1} : paramètres, historique et résultats mémorisés conservés.' -f $prev, $AppVersion }
    [IO.File]::WriteAllText($VersionFile, $AppVersion)
} catch { Write-Ignored 'Réinitialisation après mise à jour' $_ }
