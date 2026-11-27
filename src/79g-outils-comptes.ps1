# ================= Comptes locaux : type (administrateur / standard), compte Microsoft ou local, dernière connexion ;
# actions par le menu d'actions (3 points) de chaque compte. Garde-fous : jamais le dernier administrateur actif, ni le compte ciblé,
# ni le compte qui exécute l'application ; comptes système (DefaultAccount, WDAGUtilityAccount) masqués.
$AccScript = @'
$r = @{ Items = @() }
try {
    $adm = @{}
    try {
        $gn = ([Security.Principal.SecurityIdentifier]'S-1-5-32-544').Translate([Security.Principal.NTAccount]).Value.Split('\')[-1]
        $grp = [ADSI]"WinNT://$env:COMPUTERNAME/$gn,group"
        foreach ($m in @($grp.psbase.Invoke('Members'))) {
            try { $sid = [Security.Principal.SecurityIdentifier]::new([byte[]]$m.GetType().InvokeMember('objectSid', 'GetProperty', $null, $m, $null), 0); $adm[$sid.Value] = 1 } catch { $null = $_ }
        }
    } catch { $r.AdmError = $_.Exception.Message }
    # groupe illisible ou vide (un poste a toujours au moins un membre) : type des comptes inconnu, actions qui retirent des
    # droits ou un compte bloquées par l'interface (sinon le dernier administrateur pouvait être désactivé ou supprimé)
    if (-not $adm.Count -and -not $r.AdmError) { $r.AdmError = 'aucun membre lu' }
    foreach ($u in @(Get-LocalUser -ErrorAction Stop)) {
        $sid = "$($u.SID.Value)"; if ($sid -match '-(503|504)$') { continue }
        $r.Items += [pscustomobject]@{ Name = "$($u.Name)"; Full = "$($u.FullName)"; Desc = "$($u.Description)"; Enabled = [bool]$u.Enabled; Sid = $sid; Admin = $adm.ContainsKey($sid)
            Last = $u.LastLogon; Ms = "$($u.PrincipalSource)" -eq 'MicrosoftAccount'; Builtin = $sid -match '-(500|501)$'; PwdSet = $u.PasswordLastSet; NoExpire = -not $u.PasswordExpires }
    }
} catch { $r.Error = $_.Exception.Message }
$Sync.Acc = $r
'@
function Start-AccRead {
    if ($BgJobs.ContainsKey('Acc')) { return }
    $ToolsUI.AccBody.Children.Clear(); $t = New-Text 'Lecture des comptes...' 'Muted'; $t.Margin = New-Thickness 38 0 10 12; [void]$ToolsUI.AccBody.Children.Add($t)
    $Sync.Acc = $null; Start-BgJob 'Acc' $AccScript
}
$BgJobDone['Acc'] = { Update-AccCard $Sync.Acc }
$AccSelf = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
function Update-AccCard($R) {
    $b = $ToolsUI.AccBody; $b.Children.Clear()
    $items = @($(if ($R) { $R.Items }) | Sort-Object @{ E = { -not $_.Enabled } }, @{ E = { $_.Builtin } }, Name)
    if (-not $items.Count) { $t = New-Text $(if ($R -and $R.Error) { "Comptes illisibles : $($R.Error)" } else { 'Aucun compte local.' }) 'Muted'; $t.Margin = New-Thickness 38 0 10 12; [void]$b.Children.Add($t) }
    $ToolsUI.AccAdmins = @($items | Where-Object { $_.Admin -and $_.Enabled }).Count
    $ToolsUI.AccAdmUnknown = [bool]($R -and $R.AdmError)
    if ($ToolsUI.AccAdmUnknown) {
        $w = New-Text "Membres du groupe Administrateurs illisibles ($($R.AdmError)) : type des comptes inconnu, conversion en compte standard, désactivation et suppression bloquées. Actualiser pour relire."
        $w.TextWrapping = 'Wrap'; $w.Margin = New-Thickness 46 0 18 8; $w.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'WarnFgBrush'); [void]$b.Children.Add($w)
    }
    foreach ($a in $items) {
        $me = $a.Sid -in $UserSid, $AccSelf
        $sub = @($(if ($a.Admin) { 'Compte administrateur' } else { 'Compte utilisateur standard' }), $(if ($a.Ms) { 'compte Microsoft' } elseif ($a.Builtin) { 'compte intégré' } else { 'compte local' }),
            $(if ($a.Last) { 'connexion ' + (Format-TskDate $a.Last) } else { 'jamais connecté' }), $(if (-not $a.Enabled) { 'désactivé' }), $(if ($me) { 'compte en cours' })) | Where-Object { $_ }
        $mb = New-ToolIconButton 0xE712 'Actions' $a { param($s, $e) Show-AccMenu $s }
        $mb.LayoutTransform = [Windows.Media.RotateTransform]::new(90)
        $nm = $(if ($a.Full -and $a.Full -ne $a.Name) { '{0}  ({1})' -f $a.Full, $a.Name } else { $a.Name })
        $row = New-ToolRow $nm ($sub -join '  ·  ') @($mb) $(if ($a.Desc) { $a.Desc } else { $null })
        if (-not $a.Enabled) { $row.Main.Opacity = 0.55 }
        [void]$b.Children.Add($row.Row)
    }
    $btns = @((New-ToolButton 'Créer un compte' $null { New-LocalAccount } 'PrimaryBtn'), (New-ToolButton 'Paramètres des comptes' $null { Start-Process 'ms-settings:otherusers' }), (New-ToolButton 'Actualiser' $null { Start-AccRead }))
    [void]$b.Children.Add((New-ToolBar $btns))
}
function Show-AccMenu($Btn) {
    $a = $Btn.Tag; $me = $a.Sid -in $UserSid, $AccSelf; $lastAdm = ($a.Admin -and $a.Enabled -and $ToolsUI.AccAdmins -le 1) -or $ToolsUI.AccAdmUnknown
    $cm = [Windows.Controls.ContextMenu]::new()
    $add = { param([string]$T, [string]$Op, [bool]$On, [string]$Why)
        $mi = [Windows.Controls.MenuItem]::new(); $mi.Header = $T; $mi.Tag = @{ A = $a; Op = $Op }; $mi.IsEnabled = $On
        if (-not $On -and $Why) { $mi.ToolTip = $Why; [Windows.Controls.ToolTipService]::SetShowOnDisabled($mi, $true) }
        $mi.Add_Click({ param($s, $e) Invoke-AccAction $s.Tag.A $s.Tag.Op }); [void]$cm.Items.Add($mi) }
    $why = $(if ($me) { 'Compte en cours d''utilisation' } elseif ($ToolsUI.AccAdmUnknown) { 'Membres du groupe Administrateurs illisibles : action bloquée' } elseif ($lastAdm) { 'Dernier administrateur actif du PC' } else { '' })
    if ($a.Admin) { & $add 'Convertir en compte utilisateur standard' 'std' (-not $me -and -not $lastAdm -and -not ($a.Sid -match '-500$')) $why } else { & $add 'Convertir en compte administrateur' 'adm' $true '' }
    if ($a.Enabled) { & $add 'Désactiver le compte' 'off' (-not $me -and -not $lastAdm) $why } else { & $add 'Activer le compte' 'on' $true '' }
    & $add 'Changer le mot de passe...' 'pwd' (-not $a.Ms) 'Compte Microsoft : mot de passe à changer sur account.microsoft.com'
    [void]$cm.Items.Add([Windows.Controls.Separator]::new())
    & $add 'Supprimer le compte...' 'del' (-not $me -and -not $a.Builtin -and -not $lastAdm) $(if ($a.Builtin) { 'Compte intégré de Windows : à désactiver plutôt' } else { $why })
    $Btn.ContextMenu = $cm; $cm.PlacementTarget = $Btn; $cm.Placement = 'Bottom'; $cm.IsOpen = $true
}
# mot de passe saisi 2 fois (champs masqués) ; renvoie $null si annulé, mot de passe vide accepté (compte sans mot de passe)
function Read-AccPassword([string]$Message, $Extra) {
    $sp = [Windows.Controls.StackPanel]::new(); $pb = @()
    foreach ($l in 'Mot de passe', 'Confirmation') {
        $t = New-Text $l 'Muted'; $t.Margin = New-Thickness 0 6 0 4; [void]$sp.Children.Add($t)
        $p = [Windows.Controls.PasswordBox]::new(); $p.Padding = New-Thickness 8 6 8 6
        $p.SetResourceReference([Windows.Controls.Control]::BackgroundProperty, 'BgBrush'); $p.SetResourceReference([Windows.Controls.Control]::ForegroundProperty, 'FgBrush'); $p.SetResourceReference([Windows.Controls.Control]::BorderBrushProperty, 'LineBrush')
        [void]$sp.Children.Add($p); $pb += $p
    }
    if ($Extra) { foreach ($x in $Extra) { [void]$sp.Children.Add($x) } }
    while ($true) {
        $v = Show-Dialog $Message 'Question' @(@{ T = 'Annuler'; V = 'no'; C = $true }, @{ T = 'Valider'; V = 'ok'; K = 'OkBtn' }) $null $null 520 $sp { param($d, $bp) $d.Tag = $pb[0]; foreach ($c in $bp.Children) { $c.IsDefault = $c.Name -eq 'OkBtn' } }
        if ($sp.Parent) { $sp.Parent.Content = $null }
        if ($v -ne 'ok') { return $null }
        if ($pb[0].Password -ne $pb[1].Password) { Show-Info 'Les 2 saisies sont différentes.' 'Warn'; $pb[0].Clear(); $pb[1].Clear(); continue }
        return $pb[0].SecurePassword
    }
}
function Invoke-AccAction($A, [string]$Op) {
    $nm = $A.Name
    try {
        Import-Module Microsoft.PowerShell.LocalAccounts -ErrorAction SilentlyContinue
        switch ($Op) {
            'adm' { if (-not (Confirm-Action "Convertir « $nm » en compte administrateur ?`n`nCe compte pourra installer des logiciels et modifier tout le PC.")) { return }; Add-LocalGroupMember -SID 'S-1-5-32-544' -Member (Get-LocalUser -SID $A.Sid) -ErrorAction Stop; $v = 'converti en compte administrateur' }
            'std' { if (-not (Confirm-Action "Convertir « $nm » en compte utilisateur standard ?`n`nIl pourra toujours utiliser le PC et ses logiciels, mais plus installer de logiciel ni modifier les réglages de Windows sans les identifiants d'un administrateur.")) { return }
                    Add-LocalGroupMember -SID 'S-1-5-32-545' -Member (Get-LocalUser -SID $A.Sid) -ErrorAction SilentlyContinue
                    Remove-LocalGroupMember -SID 'S-1-5-32-544' -Member (Get-LocalUser -SID $A.Sid) -ErrorAction Stop; $v = 'converti en compte utilisateur standard' }
            'off' { if (-not (Confirm-Action "Désactiver le compte « $nm » ?`n`nPlus aucune ouverture de session possible avec ce compte ; ses fichiers sont conservés. Réactivable ici.")) { return }; Disable-LocalUser -SID $A.Sid -ErrorAction Stop; $v = 'désactivé' }
            'on' { if ($A.Builtin -and -not (Confirm-Action "Activer le compte intégré « $nm » ?`n`n" + $(if ($A.Sid -match '-500$') { 'Compte administrateur intégré : définir un mot de passe solide ensuite, il est souvent ciblé.' } else { 'Compte Invité : accès sans mot de passe au PC.' }))) { return }; Enable-LocalUser -SID $A.Sid -ErrorAction Stop; $v = 'activé' }
            'pwd' { $p = Read-AccPassword "Nouveau mot de passe de « $nm »`n`nLaisser vide pour retirer le mot de passe. Attention : les fichiers chiffrés (EFS) et mots de passe enregistrés par Windows pour ce compte deviennent illisibles." $null
                    if ($null -eq $p) { return }; Set-LocalUser -SID $A.Sid -Password $p -ErrorAction Stop; $v = 'mot de passe changé' }
            # dossier réel du profil (ProfileList du SID : compte Microsoft, profil sur un autre disque...), C:\Users\<nom> supposé avant
            'del' { $pf = [Environment]::ExpandEnvironmentVariables("$(Get-RegValue "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$($A.Sid)" 'ProfileImagePath')")
                    $pt = $(if ($pf) { "son dossier $pf reste sur le disque (à supprimer ensuite à la main si inutile)" } else { 'aucun dossier de profil (jamais connecté)' })
                    if ((Show-Dialog "Supprimer le compte « $nm » ?`n`nLe compte est supprimé ; $pt." 'Warn' @(@{ T = 'Annuler'; V = $false; C = $true }, @{ T = 'Supprimer'; V = $true; S = 'WarnBtn' })) -ne $true) { return }
                    Remove-LocalUser -SID $A.Sid -ErrorAction Stop; $v = 'supprimé' }
        }
        Write-UiLog "Compte « $nm » : $v." 'OK'; Add-SessionEvent 'Réglages' "Compte $nm" $v 'ok'
    } catch { Write-UiLog "Compte « $nm » : $($_.Exception.Message)" 'ERROR'; Show-Info "Action impossible sur le compte « $nm ».`n`n$($_.Exception.Message)" 'Error' }
    Start-AccRead
}
function New-LocalAccount {
    $n = Read-ToolInput "Créer un compte local`n`nNom d'ouverture de session : 20 caractères au plus, sans / \ [ ] : ; | = , + * ? < > `" @. Mot de passe demandé ensuite (facultatif)." @(@{ L = 'Nom du compte'; V = '' }, @{ L = 'Nom complet (facultatif)'; V = '' }) 'Suivant' 560
    if (-not $n) { return }
    $name = "$($n[0])".Trim(); $full = "$($n[1])".Trim()
    if (-not $name -or $name.Length -gt 20 -or $name -match '[/\\\[\]:;|=,+*?<>"@]' -or $name.Trim('.') -eq '') { Show-Info 'Nom de compte invalide.' 'Warn'; return }
    $ck = [Windows.Controls.CheckBox]::new(); $ck.Content = 'Administrateur du PC'; $ck.Margin = New-Thickness 0 12 0 0; $ck.SetResourceReference([Windows.Controls.Control]::ForegroundProperty, 'FgBrush')
    $p = Read-AccPassword "Mot de passe du compte « $name »`n`nLaisser vide pour un compte sans mot de passe (déconseillé pour un administrateur)." @($ck)
    if ($null -eq $p) { return }
    try {
        Import-Module Microsoft.PowerShell.LocalAccounts -ErrorAction SilentlyContinue
        $prm = @{ Name = $name; ErrorAction = 'Stop' }; if ($full) { $prm.FullName = $full }
        if ($p.Length) { $prm.Password = $p; $prm.PasswordNeverExpires = $true } else { $prm.NoPassword = $true }
        $u = New-LocalUser @prm
        Add-LocalGroupMember -SID 'S-1-5-32-545' -Member $u -ErrorAction Stop
        if ($ck.IsChecked) { Add-LocalGroupMember -SID 'S-1-5-32-544' -Member $u -ErrorAction Stop }
        Write-UiLog ('Compte local « {0} » créé ({1}).' -f $name, $(if ($ck.IsChecked) { 'administrateur' } else { 'standard' })) 'OK'; Add-SessionEvent 'Réglages' "Compte $name" 'créé' 'ok'
    } catch { Write-UiLog "Création du compte « $name » : $($_.Exception.Message)" 'ERROR'; Show-Info "Création impossible.`n`n$($_.Exception.Message)" 'Error' }
    Start-AccRead
}

