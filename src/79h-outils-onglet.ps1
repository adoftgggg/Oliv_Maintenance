# ================= construction de l'onglet
function New-ToolsCard([string]$Title, [string]$Desc, [int]$Glyph, $Column) {
    $c = New-Card $Title $Desc ([string][char]$Glyph)
    $body = [Windows.Controls.StackPanel]::new(); [void]$c.Body.Children.Add($body)
    [void]$Column.Children.Add($c.Card)
    $body
}
function New-ToolsPage {
    $ToolsUI.Built = $true
    $ToolsUI.LicBody = New-ToolsCard 'Licence Windows' 'Activation, type de licence et clé d''origine du PC' 0xE8D7 $Ui.ToolsLeft
    $ToolsUI.WifiBody = New-ToolsCard 'Réseaux Wi-Fi enregistrés' 'Mots de passe des réseaux déjà utilisés sur ce PC' 0xE701 $Ui.ToolsLeft
    $ToolsUI.HostsBody = New-ToolsCard 'Fichier hosts' 'Noms locaux et sites bloqués à la main ; blocage des pubs et traqueurs par le DNS AdGuard' 0xE774 $Ui.ToolsLeft
    $ToolsUI.AccBody = New-ToolsCard 'Comptes locaux' 'Comptes du PC, administrateurs, activation, mots de passe' 0xE716 $Ui.ToolsRight
    $ToolsUI.CtxBody = New-ToolsCard 'Menu clic droit de l''Explorateur' 'Entrées ajoutées par les logiciels (Windows 11 : « Afficher plus d''options »)' 0xE8A4 $Ui.ToolsRight
    $ToolsUI.EnvBody = New-ToolsCard 'Variables d''environnement' 'PATH et autres variables, de l''utilisateur et du système' 0xE943 $Ui.ToolsRight
    Update-ToolsPage
}
function Update-ToolsPage {
    if (-not $ToolsUI.Built) { return }
    Start-LicRead $null; Start-WifiRead; Update-HostsCard; Start-AccRead; Start-CtxRead; Update-EnvCard
}

