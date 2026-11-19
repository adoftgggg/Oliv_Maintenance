# Instance unique par session Windows : une nouvelle ouverture ramène la fenêtre déjà ouverte (éventuellement masquée
# dans la zone de notification) puis s'arrête. Attente de 4 s au plus : relance après réinitialisation, ancienne
# instance encore en cours de fermeture.
$AppMutex = [Threading.Mutex]::new($false, 'Local\Oliv_Maintenance')
$AppShowEvent = [Threading.EventWaitHandle]::new($false, [Threading.EventResetMode]::AutoReset, 'Local\Oliv_Maintenance_Afficher')
$owned = $false
try { $owned = $AppMutex.WaitOne(4000) } catch { $owned = ($_.Exception -is [Threading.AbandonedMutexException]) -or ($_.Exception.InnerException -is [Threading.AbandonedMutexException]) }
if (-not $owned) { [void]$AppShowEvent.Set(); [Environment]::Exit(0) }
$Build = [int](Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').CurrentBuild

function Get-InteractiveUserSid {
    try {
        $sess = (Get-Process -Id $PID).SessionId
        $ex = Get-Process -Name explorer -IncludeUserName -ErrorAction Stop | Where-Object { $_.SessionId -eq $sess -and $_.UserName } | Select-Object -First 1
        if ($ex) { return [Security.Principal.NTAccount]::new($ex.UserName).Translate([Security.Principal.SecurityIdentifier]).Value }
    } catch { Write-Ignored 'Utilisateur de la session (explorer.exe)' $_ }
    ([Security.Principal.WindowsIdentity]::GetCurrent()).User.Value
}
$UserSid     = Get-InteractiveUserSid
$UserSession = (Get-Process -Id $PID).SessionId
$UserName    = try { [Security.Principal.SecurityIdentifier]::new($UserSid).Translate([Security.Principal.NTAccount]).Value } catch { $UserSid }
$HkuSidOk    = $false
try { $k = [Microsoft.Win32.Registry]::Users.OpenSubKey($UserSid); if ($k) { $HkuSidOk = $true; $k.Close() } } catch {}
if (-not $HkuSidOk) { $UserName = "$env:USERDOMAIN\$env:USERNAME (repli HKCU)" }
$UserProfilePath = [Environment]::ExpandEnvironmentVariables("$((Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$UserSid" -ErrorAction SilentlyContinue).ProfileImagePath)")
if (-not $UserProfilePath) { $UserProfilePath = $env:USERPROFILE }
$BootTime = try { (Get-Process -Name wininit -ErrorAction Stop | Select-Object -First 1).StartTime } catch { [DateTime]::MinValue }

