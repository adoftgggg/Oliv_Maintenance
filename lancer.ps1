# Oliv_Maintenance : téléchargement et lancement de la dernière version publiée, en une commande PowerShell
#   irm https://raw.githubusercontent.com/adoftgggg/Oliv_Maintenance/main/lancer.ps1 | iex
# Dernière publication lue sur GitHub, exe téléchargé dans le dossier Téléchargements sous le nom Oliv_Maintenance.exe,
# empreinte SHA-256 vérifiée par rapport à celle publiée (fichier rejeté sinon), puis lancé (Windows demande l'élévation).
& {
    $ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue'
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $repo = 'adoftgggg/Oliv_Maintenance'
    try {
        Write-Host 'Oliv_Maintenance : recherche de la dernière version publiée...' -ForegroundColor Cyan
        $r = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest" -Headers @{ 'User-Agent' = 'Oliv_Maintenance'; 'Accept' = 'application/vnd.github+json' } -UseBasicParsing -TimeoutSec 20
        $v = "$($r.tag_name)" -replace '^[vV]', ''
        $sha = $(if ("$($r.body)" -match '(?i)SHA-?256\W+([0-9a-f]{64})') { $Matches[1].ToUpper() } else { $null })
        if (-not $sha) { throw 'empreinte SHA-256 absente de la publication : téléchargement refusé.' }
        $url = $(if ("$($r.body)" -match '(https://raw\.githubusercontent\.com/\S+?\.exe)') { $Matches[1] } else { "https://raw.githubusercontent.com/$repo/binaires/Oliv_Maintenance_$v.exe" })
        # dossier Téléchargements réel de l'utilisateur (déplacé ou redirigé compris), sinon dossier temporaire
        $dir = $null; try { $dir = (New-Object -ComObject Shell.Application).NameSpace('shell:Downloads').Self.Path } catch { $dir = $null }
        if (-not $dir -or -not (Test-Path -LiteralPath $dir)) { $dir = Join-Path $env:USERPROFILE 'Downloads' }
        if (-not (Test-Path -LiteralPath $dir)) { $dir = $env:TEMP }
        $dst = Join-Path $dir 'Oliv_Maintenance.exe'; $tmp = "$dst.part"
        Write-Host "Téléchargement de la version $v..." -ForegroundColor Cyan
        Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing -TimeoutSec 120
        if ((Get-FileHash -LiteralPath $tmp -Algorithm SHA256).Hash -ne $sha) { Remove-Item -LiteralPath $tmp -Force; throw 'empreinte SHA-256 différente de celle publiée : fichier rejeté.' }
        # exe déjà ouvert (application en cours) : nouvelle version gardée à côté sous un nom daté
        try { Move-Item -LiteralPath $tmp -Destination $dst -Force }
        catch { $dst = Join-Path $dir ('Oliv_Maintenance_{0}.exe' -f $v); Move-Item -LiteralPath $tmp -Destination $dst -Force }
        Write-Host "Version $v vérifiée (SHA-256) : $dst" -ForegroundColor Green
        Write-Host 'Lancement (Windows demande l''autorisation administrateur)...' -ForegroundColor Cyan
        Start-Process -FilePath $dst
    } catch {
        Write-Host "Oliv_Maintenance : $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Téléchargement manuel : https://github.com/$repo/releases/latest" -ForegroundColor Yellow
    }
}
