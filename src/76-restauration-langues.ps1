# ---------- Points de restauration : revenir à un point existant (Système, barre « Point de restauration »)
# Liste des points (Get-ComputerRestorePoint, du plus récent au plus ancien, 15 au plus) dans un menu sous le bouton,
# confirmation, puis SystemRestore.Restore (WMI root\default) et redémarrage : Windows restaure au démarrage.
$Ui.RestoreBack.Add_Click({ Show-RestorePointMenu $Ui.RestoreBack })
function Show-RestorePointMenu($Btn) {
    $pts = @()
    try { $pts = @(Get-ComputerRestorePoint -ErrorAction Stop | Sort-Object SequenceNumber -Descending | Select-Object -First 15) }
    catch { Show-Info ('Points de restauration illisibles : {0}' -f $_.Exception.Message) 'Error'; return }
    if (-not $pts.Count) { Show-Info 'Aucun point de restauration sur ce poste : bouton Créer pour en faire un.'; return }
    $cm = [Windows.Controls.ContextMenu]::new()
    foreach ($p in $pts) {
        $d = [Management.ManagementDateTimeConverter]::ToDateTime($p.CreationTime)
        $mi = [Windows.Controls.MenuItem]::new(); $mi.Header = '{0:dd/MM/yyyy HH:mm}  ·  {1}' -f $d, $p.Description
        $mi.Tag = @{ Seq = [uint32]$p.SequenceNumber; Date = $d; Desc = "$($p.Description)" }
        $mi.Add_Click({ param($s, $e) Restore-ToPoint $s.Tag }); [void]$cm.Items.Add($mi)
    }
    $cm.PlacementTarget = $Btn; $cm.Placement = 'Bottom'; $cm.IsOpen = $true
}
function Restore-ToPoint($P) {
    if ($Sync.Running) { Show-Info 'Une tâche est en cours : restaurer une fois terminée.'; return }
    $msg = "Restaurer le système au point du {0:dd/MM/yyyy à HH:mm} ?`n`n« {1} »`n`nLes programmes, pilotes, mises à jour et réglages système modifiés depuis sont annulés. Les documents, photos et fichiers personnels ne sont pas touchés.`n`nLe poste redémarre dans 10 secondes pour lancer la restauration : enregistrer le travail en cours avant de confirmer." -f $P.Date, $P.Desc
    if ((Show-Dialog $msg 'Warn' @(@{ T = 'Annuler'; V = $false; D = $true; C = $true }, @{ T = 'Restaurer et redémarrer'; V = $true; S = 'WarnBtn' })) -ne $true) { return }
    try {
        $r = Invoke-CimMethod -Namespace 'root/default' -ClassName SystemRestore -MethodName Restore -Arguments @{ SequenceNumber = $P.Seq } -ErrorAction Stop
        if ([int]$r.ReturnValue -ne 0) { throw ('SystemRestore.Restore a renvoyé {0}' -f $r.ReturnValue) }
        Write-UiLog ('Restauration système vers le point du {0:dd/MM/yyyy HH:mm} ({1}) : redémarrage dans 10 s.' -f $P.Date, $P.Desc) 'WARN'
        & "$env:windir\System32\shutdown.exe" /r /t 10 /c 'Oliv_Maintenance : restauration du système au redémarrage' | Out-Null
    } catch { Write-UiLog "Restauration système impossible : $($_.Exception.Message)" 'ERROR'; Show-Info "Restauration impossible : $($_.Exception.Message)" 'Error' }
}

# ---------- Langues et claviers du compte (Personnalisation) : retrait des langues et dispositions de clavier en trop
# Get / Set-WinUserLanguageList (compte qui exécute l'application) ; nom des claviers : Keyboard Layouts\<KLID>\Layout Text.
# La 1re langue (langue d'affichage préférée) et le dernier clavier restant ne peuvent pas être retirés.
$LangUI = @{}
# Set-WinUserLanguageList agit sur le compte qui exécute l'application : élevée avec un autre compte administrateur que celui
# de la session, la modification partait sur ce compte-là sans le dire ; refusée dans ce cas
function Test-LangSameUser {
    if ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -eq $UserSid) { return $true }
    Show-Info ("Langues et claviers : modification impossible pour $UserName.`n`nL'application tourne sous le compte administrateur $env:USERDOMAIN\$env:USERNAME, et Windows n'applique ce réglage qu'au compte qui le fait. À changer depuis la session de $UserName, dans Paramètres > Heure et langue.") 'Warn'
    $false
}
function Get-KeyboardName([string]$Tip) {
    $klid = ($Tip -split ':')[-1]
    if ($klid -match '^\{') { return 'méthode de saisie' }
    Get-KlidName $klid
}
# nom d'un clavier dans la langue de Windows (Layout Display Name, chaîne indirecte), sinon nom anglais (Layout Text)
function Get-KlidName([string]$Klid) {
    $k = "HKLM\SYSTEM\CurrentControlSet\Control\Keyboard Layouts\$Klid"
    $n = $null; $dn = "$(Get-RegValue $k 'Layout Display Name')"
    if ($dn) { try { $n = [_OlivM.Shell]::Indirect($dn) } catch { $n = $null } }
    if (-not $n) { $n = "$(Get-RegValue $k 'Layout Text')" }
    $(if ($n) { $n } else { "clavier $Klid" })
}
function New-LangCard {
    $c = New-Card 'Langues et claviers' '' ([string][char]0xE775)
    $LangUI.Body = [Windows.Controls.StackPanel]::new(); $LangUI.Body.Margin = New-Thickness 38 0 10 8
    [void]$c.Body.Children.Add($LangUI.Body)
    [void]$Ui.PersoLeft.Children.Add($c.Card)
    Update-LangCard
}
function Update-LangCard {
    $b = $LangUI.Body; if (-not $b) { return }
    $b.Children.Clear()
    $list = $null
    try { $list = Get-WinUserLanguageList -ErrorAction Stop } catch { $t = New-Text "Langues illisibles : $($_.Exception.Message)" 'Muted'; [void]$b.Children.Add($t); return }
    $nKb = 0; foreach ($l in $list) { $nKb += @($l.InputMethodTips).Count }
    $i = 0
    foreach ($l in $list) {
        $g = [Windows.Controls.Grid]::new(); $g.Margin = New-Thickness 8 6 8 2
        foreach ($w in '*', 'Auto') { $cd = [Windows.Controls.ColumnDefinition]::new(); $cd.Width = $(if ($w -eq '*') { [Windows.GridLength]::new(1, 'Star') } else { [Windows.GridLength]::Auto }); [void]$g.ColumnDefinitions.Add($cd) }
        $n = New-Text ('{0}{1}' -f $(if ($l.Autonym) { $l.Autonym } else { $l.LanguageTag }), $(if ($i -eq 0) { '  ·  langue principale' } else { '' })); $n.FontWeight = [Windows.FontWeights]::SemiBold; $n.VerticalAlignment = 'Center'
        [void]$g.Children.Add($n)
        if ($i -eq 0) {
            # ajout d'un clavier : sur la ligne de la langue principale, à côté de ses claviers
            $ab = New-Button 'Ajouter un clavier'; $ab.Height = 30; $ab.Padding = New-Thickness 10 0 10 0
            $ab.Add_Click({ param($s, $e) Show-AddKeyboardMenu $s })
            [Windows.Controls.Grid]::SetColumn($ab, 1); [void]$g.Children.Add($ab)
        }
        if ($i -gt 0) {
            $rb = New-Button 'Retirer la langue'; $rb.Height = 30; $rb.Padding = New-Thickness 10 0 10 0; $rb.Tag = "$($l.LanguageTag)"
            $rb.Add_Click({ param($s, $e) Remove-UserLanguage "$($s.Tag)" $null })
            [Windows.Controls.Grid]::SetColumn($rb, 1); [void]$g.Children.Add($rb)
        }
        [void]$b.Children.Add($g)
        foreach ($tip in @($l.InputMethodTips)) {
            $kg = [Windows.Controls.Grid]::new(); $kg.Margin = New-Thickness 28 1 8 1
            foreach ($w in '*', 'Auto') { $cd = [Windows.Controls.ColumnDefinition]::new(); $cd.Width = $(if ($w -eq '*') { [Windows.GridLength]::new(1, 'Star') } else { [Windows.GridLength]::Auto }); [void]$kg.ColumnDefinitions.Add($cd) }
            $kt = New-Text ('Clavier  ' + (Get-KeyboardName $tip)) 'Muted'; $kt.VerticalAlignment = 'Center'; $kt.ToolTip = $tip
            [void]$kg.Children.Add($kt)
            if ($nKb -gt 1) {
                $kb = [Windows.Controls.Button]::new(); $kb.Style = $Window.FindResource('IconBtn'); $kb.Content = [string][char]0xE711; $kb.Width = 28; $kb.Height = 24
                $kb.ToolTip = 'Retirer ce clavier'; $kb.Tag = @{ L = "$($l.LanguageTag)"; T = "$tip" }
                $kb.Add_Click({ param($s, $e) Remove-UserLanguage $s.Tag.L $s.Tag.T })
                [Windows.Controls.Grid]::SetColumn($kb, 1); [void]$kg.Children.Add($kb)
            }
            [void]$b.Children.Add($kg)
        }
        $i++
    }
    try { Add-OfficeLangSection $b } catch { Write-Ignored 'Langues d''Office' $_ }
}
# ---------- Langues d'Office (Click-to-Run : Microsoft 365, Office 2019 / 2021 / 2024)
# Langues installées : ProductReleaseIDs\<configuration active>\<produit>\<langue> (registre Click-to-Run), complétées par
# les entrées de désinstallation (« productstoremove=<produit>.16_<langue>_x-none »). Langue d'affichage d'Office
# en cours (voir Get-OfficeUiLang) jamais proposée au retrait. Retrait par l'outil de déploiement d'Office (setup.exe, CDN
# Microsoft, signature vérifiée) : <Remove><Product ID><Language ID/></Product></Remove>, sans interface, Office fermé.
$OfficeC2R = 'HKLM\SOFTWARE\Microsoft\Office\ClickToRun'
function Get-OfficeLang {
    $h = [ordered]@{}
    $add = { param($P, $L) $L = $L.ToLower(); if (-not $h.Contains($L)) { $h[$L] = [Collections.Generic.List[string]]::new() }; if (-not $h[$L].Contains($P)) { $h[$L].Add($P) } }
    $k = Open-RegKey "$OfficeC2R\ProductReleaseIDs"
    if ($k) {
        try {
            $act = "$($k.GetValue('ActiveConfiguration'))"
            foreach ($cfg in @($(if ($act) { $act } else { $k.GetSubKeyNames() }))) {
                $ck = $k.OpenSubKey($cfg); if (-not $ck) { continue }
                try {
                    foreach ($pn in $ck.GetSubKeyNames()) {
                        $pk = $ck.OpenSubKey($pn); if (-not $pk) { continue }
                        try { foreach ($ln in $pk.GetSubKeyNames()) { if ($ln -match '^[a-z]{2,3}-[a-z]{2,4}$' -and $ln -ne 'x-none') { & $add ($pn -replace '\.\d+$', '') $ln } } } finally { $pk.Close() }
                    }
                } finally { $ck.Close() }
            }
        } finally { $k.Close() }
    }
    foreach ($root in 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall') {
        $k = Open-RegKey $root; if (-not $k) { continue }
        try {
            foreach ($n in $k.GetSubKeyNames()) {
                $sk = $k.OpenSubKey($n); if (-not $sk) { continue }
                $u = ''; try { $u = "$($sk.GetValue('UninstallString'))" } finally { $sk.Close() }
                if ($u -notmatch '(?i)OfficeClickToRun\.exe' -or $u -notmatch '(?i)productstoremove=(\S+)') { continue }
                foreach ($x in ($Matches[1] -split '\|')) { if ($x -match '^([A-Za-z0-9]+)\.\d+_([A-Za-z]{2,3}-[A-Za-z]{2,4})_') { & $add $Matches[1] $Matches[2] } }
            }
        } finally { $k.Close() }
    }
    $h
}
# langue d'affichage d'Office pour l'utilisateur ciblé : choix fait dans Office (Options > Langue, enregistré dans
# HKCU\Software\Microsoft\Office\16.0\Common\LanguageResources : UILanguageTag, FollowSystemUI), sinon langue de Windows
# si Office l'a, sinon langue d'installation (ClickToRun\Configuration\ClientCulture)
$OfficeLangRes = 'HKCU\Software\Microsoft\Office\16.0\Common\LanguageResources'
function Get-OfficeUiLang($Langs) {
    $t = "$(Get-RegValue $OfficeLangRes 'UILanguageTag')".ToLower(); $f = "$(Get-RegValue $OfficeLangRes 'FollowSystemUI')"
    if ($t -and $f -ne 'On' -and $Langs.Contains($t)) { return $t }
    $w = "$((Get-UICulture).Name)".ToLower(); if ($Langs.Contains($w)) { return $w }
    "$(Get-RegValue "$OfficeC2R\Configuration" 'ClientCulture')".ToLower()
}
function Set-OfficeUiLang([string]$Lang) {
    try {
        Set-RegValue $OfficeLangRes 'UILanguageTag' $Lang 'String'; Set-RegValue $OfficeLangRes 'FollowSystemUI' 'Off' 'String'
        Write-UiLog "Office : langue d'affichage $Lang (effective à la réouverture des applications Office)." 'OK'
        Add-SessionEvent 'Réglages' 'Langue d''affichage d''Office' $Lang 'ok'
    } catch { Write-UiLog "Office : langue d'affichage - $($_.Exception.Message)" 'ERROR'; Show-Info "Changement impossible : $($_.Exception.Message)" 'Error' }
    Update-LangCard
}
function Get-CultureName([string]$Tag) { try { [Globalization.CultureInfo]::GetCultureInfo($Tag).NativeName } catch { $Tag } }
function Add-OfficeLangSection($B) {
    $langs = Get-OfficeLang; if (-not $langs.Count) { return }
    $ui = Get-OfficeUiLang $langs
    $h = New-Text 'Office'; $h.FontWeight = [Windows.FontWeights]::SemiBold; $h.Margin = New-Thickness 8 14 8 2
    [void]$B.Children.Add($h)
    foreach ($l in $langs.Keys) {
        # une ligne encadrée par langue, surlignée au survol (boutons compris) : on voit à quelle langue s'appliquent les boutons
        $row = [Windows.Controls.Border]::new(); $row.Style = $Window.FindResource('SvcRow'); $row.Padding = New-Thickness 10 4 6 4; $row.Margin = New-Thickness 20 2 8 2
        $g = [Windows.Controls.Grid]::new(); $row.Child = $g
        foreach ($w in '*', 'Auto') { $cd = [Windows.Controls.ColumnDefinition]::new(); $cd.Width = $(if ($w -eq '*') { [Windows.GridLength]::new(1, 'Star') } else { [Windows.GridLength]::Auto }); [void]$g.ColumnDefinitions.Add($cd) }
        $isUi = $l -eq $ui
        $t = New-Text ('{0}  ({1})' -f (Get-CultureName $l), $l); $t.VerticalAlignment = 'Center'; $t.TextWrapping = 'Wrap'
        if ($isUi) { $t.Inlines.Add([Windows.Documents.Run]::new('  ·  langue d''affichage d''Office')); $t.FontWeight = [Windows.FontWeights]::SemiBold; $t.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'AccentBrush') }
        $t.ToolTip = 'Produits : ' + ($langs[$l] -join ', ')
        [void]$g.Children.Add($t)
        if (-not $isUi) {
            # autre langue : passage en langue d'affichage, ou retrait (jamais la langue d'affichage en cours)
            $bp = [Windows.Controls.StackPanel]::new(); $bp.Orientation = 'Horizontal'
            $db = New-Button ('Afficher Office en ' + ((Get-CultureName $l) -replace '\s*\(.*$', '')); $db.Height = 30; $db.Padding = New-Thickness 10 0 10 0; $db.Tag = $l; $db.IsEnabled = -not $LangUI.OffBusy
            $db.Add_Click({ param($s, $e) Set-OfficeUiLang "$($s.Tag)" })
            [void]$bp.Children.Add($db)
            $rb = New-Button $(if ($LangUI.OffBusy -eq $l) { 'Retrait en cours...' } else { 'Retirer cette langue' }); $rb.Height = 30; $rb.Padding = New-Thickness 10 0 10 0; $rb.Margin = New-Thickness 0 0 0 0
            $rb.Tag = @{ L = $l; P = @($langs[$l]) }; $rb.IsEnabled = -not $LangUI.OffBusy
            $rb.Add_Click({ param($s, $e) Remove-OfficeLang $s.Tag.L $s.Tag.P })
            [void]$bp.Children.Add($rb)
            $db.Margin = New-Thickness 0 0 6 0
            [Windows.Controls.Grid]::SetColumn($bp, 1); [void]$g.Children.Add($bp)
        }
        [void]$B.Children.Add($row)
    }
    $LangUI.OffState = New-Text '' 'Muted'; $LangUI.OffState.Margin = New-Thickness 28 4 8 0; $LangUI.OffState.FontSize = 12; $LangUI.OffState.TextWrapping = 'Wrap'
    $LangUI.OffState.Visibility = $(if ($LangUI.OffBusy) { 'Visible' } else { 'Collapsed' })
    [void]$B.Children.Add($LangUI.OffState)
}
$OfficeLangScript = @'
$p = $Sync.OffLangReq; $st = $Sync.OffLang
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $dir = Join-Path $env:TEMP 'Oliv_Maintenance_ODT'; [void][IO.Directory]::CreateDirectory($dir)
    $exe = Join-Path $dir 'setup.exe'; $cfg = Join-Path $dir 'retrait-langue.xml'
    $st.Phase = 'téléchargement de l''outil de déploiement d''Office'
    (New-Object Net.WebClient).DownloadFile('https://officecdn.microsoft.com/pr/wsus/setup.exe', $exe)
    $sig = Get-AuthenticodeSignature -LiteralPath $exe
    if ("$($sig.Status)" -ne 'Valid' -or "$($sig.SignerCertificate.Subject)" -notmatch 'O=Microsoft Corporation') { throw "signature de setup.exe non valide ($($sig.Status))" }
    $x = '<Configuration><Remove All="FALSE">' + (($p.Products | ForEach-Object { '<Product ID="{0}"><Language ID="{1}"/></Product>' -f $_, $p.Lang }) -join '') + '</Remove><Display Level="None" AcceptEULA="TRUE"/><Property Name="FORCEAPPSHUTDOWN" Value="TRUE"/></Configuration>'
    [IO.File]::WriteAllText($cfg, $x, [Text.UTF8Encoding]::new($false))
    $st.Phase = 'retrait de la langue (applications Office fermées)'
    $pr = Start-Process -FilePath $exe -ArgumentList @('/configure', ('"{0}"' -f $cfg)) -WorkingDirectory $dir -WindowStyle Hidden -Wait -PassThru
    $st.Code = $pr.ExitCode; $st.Ok = $pr.ExitCode -eq 0
    if (-not $st.Ok) { $st.Msg = 'code de retour {0} (0x{0:X8}) ; journal : %TEMP% du compte administrateur, fichiers <PC>-<date>.log' -f $pr.ExitCode }
} catch { $st.Ok = $false; $st.Msg = $_.Exception.Message }
'@
function Remove-OfficeLang([string]$Lang, [string[]]$Products) {
    if ($LangUI.OffBusy) { return }
    $n = Get-CultureName $Lang
    if (-not (Confirm-Action ("Retirer la langue « $n » ($Lang) d'Office ?`n`nProduits : " + ($Products -join ', ') + ".`n`nWord, Excel, Outlook et les autres applications Office ouvertes sont fermées (travail non enregistré perdu). Plusieurs minutes. Rajout possible depuis le site Microsoft 365 (packs de langue)."))) { return }
    $LangUI.OffBusy = $Lang; $LangUI.OffT0 = [DateTime]::Now
    $Sync.OffLangReq = @{ Lang = $Lang; Products = $Products }; $Sync.OffLang = [hashtable]::Synchronized(@{ Phase = 'préparation'; Ok = $false; Msg = ''; Code = $null })
    Write-UiLog "Office : retrait de la langue $Lang ($($Products -join ', '))." 'APP'
    Update-LangCard
    Start-BgJob 'OffLang' $OfficeLangScript
    if (-not $LangUI.OffTimer) {
        $LangUI.OffTimer = [Windows.Threading.DispatcherTimer]::new(); $LangUI.OffTimer.Interval = [TimeSpan]::FromSeconds(1)
        $LangUI.OffTimer.Add_Tick({ if ($LangUI.OffState -and $Sync.OffLang) { $LangUI.OffState.Text = '{0} : {1}  ·  {2:mm\:ss}' -f $LangUI.OffBusy, $Sync.OffLang.Phase, ([DateTime]::Now - $LangUI.OffT0) } })
    }
    $LangUI.OffTimer.Start()
}
$BgJobDone['OffLang'] = {
    if ($LangUI.OffTimer) { $LangUI.OffTimer.Stop() }
    $l = $LangUI.OffBusy; $LangUI.OffBusy = $null; $st = $Sync.OffLang
    if ($st -and $st.Ok) {
        Write-UiLog "Office : langue $l retirée." 'OK'; Add-SessionEvent 'Réglages' 'Langue d''Office' "$l retirée" 'ok'
    } else {
        $m = $(if ($st -and $st.Msg) { $st.Msg } else { 'tâche interrompue' })
        Write-UiLog "Office : retrait de la langue $l en échec - $m" 'ERROR'; Add-SessionEvent 'Réglages' 'Langue d''Office' "échec : $m" 'error'
        Show-Info "Retrait de la langue $l d'Office impossible.`n`n$m" 'Error'
    }
    Update-LangCard
}
# Tip absent : toute la langue retirée ; sinon un clavier (langue retirée avec son dernier clavier)
function Remove-UserLanguage([string]$Tag, $Tip) {
    if (-not (Test-LangSameUser)) { return }
    try {
        $list = Get-WinUserLanguageList -ErrorAction Stop
        $l = @($list | Where-Object { $_.LanguageTag -eq $Tag })[0]; if (-not $l) { return }
        $what = $(if ($Tip) { 'le clavier « {0} »' -f (Get-KeyboardName $Tip) } else { 'la langue « {0} » et ses claviers' -f $l.Autonym })
        if (-not (Confirm-Action "Retirer $what ?`n`nSe rajoute à tout moment dans Paramètres > Heure et langue.")) { return }
        if ($Tip) { [void]$l.InputMethodTips.Remove($Tip); if (-not $l.InputMethodTips.Count) { [void]$list.Remove($l) } }
        else { [void]$list.Remove($l) }
        Set-WinUserLanguageList -LanguageList $list -Force -ErrorAction Stop
        Write-UiLog "Langues et claviers : $what retiré(e)." 'OK'
        Add-SessionEvent 'Réglages' 'Langues et claviers' "$what retiré(e)" 'ok'
    } catch { Write-UiLog "Langues et claviers : $($_.Exception.Message)" 'ERROR' }
    Update-LangCard
}

# Ajout d'un clavier : courants en tête, puis tous les claviers de Windows (Keyboard Layouts) dans un sous-menu.
# Langue déduite de l'identifiant du clavier (mot de poids faible = LCID : 0000080C > fr-BE), entrée « LCID:KLID ».
# Français : un seul AZERTY proposé en tête (le traditionnel, celui de Windows par défaut) ; l'AZERTY « Standard » (norme
# AFNOR 2019, accents et symboles réorganisés) reste dans « Tous les claviers »
$KbCommon = @('0000040C', '0002040C', '0000080C', '0000100C', '00001009', '00011009', '00000409', '00020409', '00000809', '00000407', '0000040A', '00000410', '00000816', '00000413')
# claviers canadiens : rattachés au français du Canada (leur identifiant porte la langue anglaise du Canada, 1009)
$KbLang = @{ '00001009' = 0x0C0C; '00011009' = 0x0C0C }
function Get-KlidEntry([string]$Klid) {
    try {
        $lcid = $(if ($KbLang.ContainsKey($Klid.ToUpper())) { $KbLang[$Klid.ToUpper()] } else { [Convert]::ToInt32($Klid.Substring($Klid.Length - 4), 16) })
        $ci = [Globalization.CultureInfo]::GetCultureInfo($lcid)
        if (-not $ci.Name) { return $null }
        @{ Klid = $Klid.ToUpper(); Tag = $ci.Name; Tip = ('{0:X4}:{1}' -f $lcid, $Klid.ToUpper()); Name = (Get-KlidName $Klid); Lang = $ci.DisplayName }
    } catch { $null }
}
function Show-AddKeyboardMenu($Btn) {
    $cm = [Windows.Controls.ContextMenu]::new()
    $all = @()
    $k = Open-RegKey 'HKLM\SYSTEM\CurrentControlSet\Control\Keyboard Layouts'
    if ($k) { try { $all = @($k.GetSubKeyNames() | Where-Object { $_ -match '^[0-9A-Fa-f]{8}$' }) } finally { $k.Close() } }
    # claviers déjà présents (toutes langues) : grisés, non sélectionnables
    $have = @{}
    try { foreach ($l in (Get-WinUserLanguageList -ErrorAction Stop)) { foreach ($t in @($l.InputMethodTips)) { $have[("$t" -split ':')[-1].ToUpper()] = 1 } } } catch { Write-Ignored 'Langues et claviers' $_ }
    $mk = { param($E)
        $mi = [Windows.Controls.MenuItem]::new(); $mi.Tag = $E
        if ($have.ContainsKey($E.Klid)) { $mi.Header = '{0}  ({1})  ·  déjà installé' -f $E.Name, $E.Lang; $mi.IsEnabled = $false }
        else { $mi.Header = '{0}  ({1})' -f $E.Name, $E.Lang; $mi.Add_Click({ param($s, $ev) Add-UserKeyboard $s.Tag }) }
        $mi }
    foreach ($kl in $KbCommon) { if ($all -contains $kl) { $en = Get-KlidEntry $kl; if ($en) { [void]$cm.Items.Add((& $mk $en)) } } }
    [void]$cm.Items.Add([Windows.Controls.Separator]::new())
    $sub = [Windows.Controls.MenuItem]::new(); $sub.Header = 'Tous les claviers'
    foreach ($en in @($all | ForEach-Object { Get-KlidEntry $_ } | Where-Object { $_ } | Sort-Object { $_.Name })) { [void]$sub.Items.Add((& $mk $en)) }
    [void]$cm.Items.Add($sub)
    $cm.PlacementTarget = $Btn; $cm.Placement = 'Bottom'; $cm.MaxHeight = 560; $cm.IsOpen = $true
}
function Add-UserKeyboard($E) {
    if (-not (Test-LangSameUser)) { return }
    try {
        $list = Get-WinUserLanguageList -ErrorAction Stop
        $l = @($list | Where-Object { $_.LanguageTag -eq $E.Tag })[0]
        if ($l -and @($l.InputMethodTips) -contains $E.Tip) { Show-Info "Le clavier « $($E.Name) » est déjà présent."; return }
        if ($l) { $l.InputMethodTips.Add($E.Tip) }
        else {
            $nl = (New-WinUserLanguageList -Language $E.Tag -ErrorAction Stop)[0]
            $nl.InputMethodTips.Clear(); $nl.InputMethodTips.Add($E.Tip); $list.Add($nl)
        }
        Set-WinUserLanguageList -LanguageList $list -Force -ErrorAction Stop
        Write-UiLog ('Langues et claviers : clavier « {0} » ajouté ({1}).' -f $E.Name, $E.Lang) 'OK'
        Add-SessionEvent 'Réglages' 'Langues et claviers' "clavier $($E.Name) ajouté" 'ok'
    } catch { Write-UiLog "Langues et claviers : $($_.Exception.Message)" 'ERROR'; Show-Info "Ajout du clavier impossible : $($_.Exception.Message)" 'Error' }
    Update-LangCard
}
