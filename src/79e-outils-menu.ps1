# ================= Menu clic droit de l'Explorateur : entrées ajoutées par les logiciels (éditeur autre que Microsoft)
# Extensions COM (shellex\ContextMenuHandlers) masquées par la liste Shell Extensions\Blocked (tout l'Explorateur) ;
# commandes simples (shell\<verbe>) masquées par la valeur LegacyDisable. Windows 11 : entrées du menu « Afficher plus
# d'options » ; les entrées des applications empaquetées (MSIX) n'y figurent pas.
$CtxScript = @'
$r = @{ Items = @() }
$locs = [ordered]@{ '*' = 'fichiers'; 'AllFilesystemObjects' = 'fichiers et dossiers'; 'Directory' = 'dossiers'; 'Folder' = 'dossiers'; 'Directory\Background' = 'fond de dossier'; 'DesktopBackground' = 'Bureau'; 'Drive' = 'lecteurs' }
$roots = @('HKLM:\SOFTWARE\Classes'); if ($Sync.CtxSid) { $roots += "Registry::HKEY_USERS\$($Sync.CtxSid)\Software\Classes" }
$blocked = @{}; try { $bk = Get-Item -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked' -ErrorAction Stop; foreach ($n in $bk.GetValueNames()) { $blocked[$n.ToUpper()] = 1 } } catch { $null = $_ }
$co = @{}
function Get-Co([string]$F) {
    if (-not $F) { return '' }; $F = [Environment]::ExpandEnvironmentVariables($F.Trim('"'))
    if (-not $co.ContainsKey($F)) { $c = ''; try { if (Test-Path -LiteralPath $F) { $c = "$([Diagnostics.FileVersionInfo]::GetVersionInfo($F).CompanyName)".Trim() } } catch { $null = $_ }; $co[$F] = $c }
    $co[$F]
}
function Get-Ind([string]$S) { if ($S -like '@*') { try { $v = [_OlivM.Shell]::Indirect($S); if ($v) { return $v } } catch { $null = $_ } }; $S }
$h = @{}; $v = @{}
foreach ($root in $roots) {
    foreach ($loc in $locs.Keys) {
        # extensions COM
        $hk = "$root\$loc\shellex\ContextMenuHandlers"
        if (Test-Path -LiteralPath $hk) {
            foreach ($k in @(Get-ChildItem -LiteralPath $hk -ErrorAction SilentlyContinue)) {
                $id = "$($k.GetValue(''))"; if ($id -notmatch '^\{[0-9A-Fa-f\-]{36}\}$') { $id = $k.PSChildName }
                if ($id -notmatch '^\{[0-9A-Fa-f\-]{36}\}$') { continue }
                $id = $id.ToUpper()
                if (-not $h.ContainsKey($id)) {
                    $nm = ''; $dll = ''
                    foreach ($cr in $roots) { if (-not $nm) { $nm = "$((Get-ItemProperty -LiteralPath "$cr\CLSID\$id" -ErrorAction SilentlyContinue).'(default)')" }; if (-not $dll) { $dll = "$((Get-ItemProperty -LiteralPath "$cr\CLSID\$id\InprocServer32" -ErrorAction SilentlyContinue).'(default)')" } }
                    $c = Get-Co $dll
                    $h[$id] = [pscustomobject]@{ Kind = 'ext'; Id = $id; Name = $(if ($nm) { $nm } else { $k.PSChildName }); Handler = $k.PSChildName; File = $dll; Co = $c; Ms = $c -match '^Microsoft'; Off = $blocked.ContainsKey($id); Where = [Collections.Generic.List[string]]::new(); Keys = @() }
                }
                if (-not $h[$id].Where.Contains($locs[$loc])) { $h[$id].Where.Add($locs[$loc]) }
            }
        }
        # commandes simples
        $sk = "$root\$loc\shell"
        if (Test-Path -LiteralPath $sk) {
            foreach ($k in @(Get-ChildItem -LiteralPath $sk -ErrorAction SilentlyContinue)) {
                $cmd = "$((Get-ItemProperty -LiteralPath "$($k.PSPath)\command" -ErrorAction SilentlyContinue).'(default)')"
                if (-not $cmd) { continue }
                $exe = $(if ($cmd -match '^\s*"([^"]+)"') { $Matches[1] } elseif ($cmd -match '^\s*(\S+)') { $Matches[1] } else { '' })
                $c = Get-Co $exe; if ($c -match '^Microsoft' -or $exe -match '(?i)\\(cmd|powershell|explorer|rundll32|regsvr32|msiexec)\.exe$') { continue }
                $p = Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction SilentlyContinue
                $lb = "$($p.MUIVerb)"; if (-not $lb) { $lb = "$($p.'(default)')" }; if (-not $lb) { $lb = $k.PSChildName }
                $key = "$($k.PSChildName)|$exe"
                if (-not $v.ContainsKey($key)) { $v[$key] = [pscustomobject]@{ Kind = 'verb'; Id = $key; Name = ((Get-Ind $lb) -replace '&', ''); Handler = $k.PSChildName; File = $exe; Co = $c; Ms = $false; Off = $false; Where = [Collections.Generic.List[string]]::new(); Keys = @() } }
                $v[$key].Keys += $k.PSPath
                if ($null -ne $p.LegacyDisable) { $v[$key].Off = $true }
                if (-not $v[$key].Where.Contains($locs[$loc])) { $v[$key].Where.Add($locs[$loc]) }
            }
        }
    }
}
$r.Items = @(@($h.Values | Where-Object { -not $_.Ms }) + @($v.Values)) | Sort-Object Name
$Sync.Ctx = $r
'@
function Start-CtxRead {
    if ($BgJobs.ContainsKey('Ctx')) { return }
    $ToolsUI.CtxBody.Children.Clear(); $t = New-Text 'Lecture des entrées du menu...' 'Muted'; $t.Margin = New-Thickness 38 0 10 12; [void]$ToolsUI.CtxBody.Children.Add($t)
    $Sync.CtxSid = $(if ($HkuSidOk) { $UserSid } else { $null }); $Sync.Ctx = $null
    Start-BgJob 'Ctx' $CtxScript
}
$BgJobDone['Ctx'] = { Update-CtxCard $Sync.Ctx }
function Update-CtxCard($R) {
    $b = $ToolsUI.CtxBody; $b.Children.Clear()
    $items = @($(if ($R) { $R.Items }))
    if (-not $items.Count) { $t = New-Text 'Aucune entrée ajoutée par un logiciel.' 'Muted'; $t.Margin = New-Thickness 38 0 10 12; [void]$b.Children.Add($t) }
    foreach ($it in $items) {
        $tg = New-ToolButton $(if ($it.Off) { 'Afficher' } else { 'Masquer' }) $it { param($s, $e) Switch-CtxEntry $s.Tag }
        $tg.Width = 90; $tg.Margin = New-Thickness 4 0 0 0
        $sub = '{0}  ·  {1}' -f $(if ($it.Co) { $it.Co } else { 'éditeur inconnu' }), ($it.Where -join ', ')
        $row = New-ToolRow $it.Name $sub @($tg) ('{0}{1}' -f $(if ($it.File) { 'Fichier : ' + $it.File } else { '' }), $(if ($it.Kind -eq 'ext') { "`nExtension $($it.Handler) $($it.Id)" } else { "`nCommande « $($it.Handler) »" }))
        if ($it.Off) { $row.Main.Opacity = 0.55; $row.Sub.Text = 'masquée  ·  ' + $sub }
        [void]$b.Children.Add($row.Row)
    }
    $btns = @((New-ToolButton 'Redémarrer l''Explorateur' $null { Restart-Explorer }), (New-ToolButton 'Actualiser' $null { Start-CtxRead }))
    [void]$b.Children.Add((New-ToolBar $btns))
}
function Switch-CtxEntry($It) {
    try {
        if ($It.Kind -eq 'ext') {
            $k = Open-RegKey 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked' $true $true
            try { if ($It.Off) { $k.DeleteValue($It.Id, $false) } else { $k.SetValue($It.Id, $It.Name, [Microsoft.Win32.RegistryValueKind]::String) } } finally { $k.Close() }
        } else {
            foreach ($p in $It.Keys) { if ($It.Off) { Remove-ItemProperty -LiteralPath $p -Name 'LegacyDisable' -ErrorAction SilentlyContinue } else { Set-ItemProperty -LiteralPath $p -Name 'LegacyDisable' -Value '' -Type String -ErrorAction Stop } }
        }
        $It.Off = -not $It.Off
        Write-UiLog ('Menu clic droit : « {0} » {1} (effectif après redémarrage de l''Explorateur).' -f $It.Name, $(if ($It.Off) { 'masquée' } else { 'réaffichée' })) 'OK'
    } catch { Write-UiLog "Menu clic droit : $($_.Exception.Message)" 'ERROR'; Show-Info "Modification impossible.`n`n$($_.Exception.Message)" 'Error' }
    Update-CtxCard $Sync.Ctx
}
function Restart-Explorer {
    if (-not (Confirm-Action "Redémarrer l'Explorateur Windows ?`n`nLa barre des tâches et les fenêtres de l'Explorateur se ferment quelques secondes ; les autres programmes restent ouverts.")) { return }
    try { Get-Process -Name explorer -ErrorAction Stop | Stop-Process -Force -ErrorAction Stop } catch { Write-Ignored 'Arrêt de l''Explorateur' $_ }
    # relancé automatiquement par Windows en principe ; sinon lancé dans la session (lancement par l'interface de l'utilisateur)
    $t = [Windows.Threading.DispatcherTimer]::new(); $t.Interval = [TimeSpan]::FromSeconds(3)
    $t.Add_Tick({ param($s, $e) $s.Stop(); if (-not (Get-Process -Name explorer -ErrorAction SilentlyContinue)) { Start-Process (Join-Path $env:windir 'explorer.exe') } })
    $t.Start(); Write-UiLog 'Explorateur Windows redémarré.' 'APP'
}

