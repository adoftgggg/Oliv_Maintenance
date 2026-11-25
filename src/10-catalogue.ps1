$TaskLabels = @{
    RestorePoint = 'Création d''un point de restauration'
    WuReset     = 'Réinitialisation des composants Windows Update'
    WuInstall   = 'Installation des mises à jour Windows'
    NetReset    = 'Réinitialisation réseau (DNS, Winsock)'
    SpoolReset  = 'Purge et redémarrage du spouleur d''impression'
    TimeSync    = 'Synchronisation de l''heure'
    StoreReset  = 'Vidage du cache du Microsoft Store'
    GpForce     = 'Réapplication des stratégies de groupe (gpupdate)'
    NetCheck    = 'Diagnostic réseau'
    GpuReset    = 'Redémarrage du pilote graphique'
    Smart       = 'Rapport de santé des disques (SMART)'
    Optimize    = 'Optimisation du disque système'
    DismScan    = 'Analyse de l''image Windows (DISM)'
    DismRestore = 'Réparation de l''image Windows (DISM)'
    SfcVerify   = 'Vérification des fichiers système (SFC)'
    Sfc         = 'Réparation des fichiers système (SFC)'
    ChkBoot     = 'Vérification du disque au prochain démarrage (CHKDSK)'
    ChkState    = 'État du volume système (CHKDSK)'
    Clean       = 'Nettoyage'
    AppxRemove  = 'Suppression des applications préinstallées'
    SoftUpgrade = 'Mise à jour des logiciels'
    AppInstall  = 'Installation d''applications'
    Battery     = 'Rapport de batterie'
}

# version affichée de Windows (24H2, 25H2...) : version cible proposée (bloquer le poste sur sa version actuelle)
$WinDisplayVer = "$((Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue).DisplayVersion)"
$CDM = 'HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
$ADV = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
$Tweaks = @(
    [pscustomobject]@{ Id='FastStartup'; Need='Hibernate'; Def=$true; Page='Perf'; Group='Performances et alimentation'; MinBuild=0; Effect='R'
        Label='Démarrage rapide'
        Desc='Accélère le démarrage en mettant le noyau en veille prolongée à l''arrêt. Désactivé : arrêt complet à chaque extinction, plus fiable pour les mises à jour et les pilotes.'
        Tip='HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power\HiberbootEnabled (+ powercfg /hibernate on si nécessaire).'
        Get={ ((Get-RegValue 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'HiberbootEnabled') -eq 1) -and ((Get-RegValue 'HKLM\SYSTEM\CurrentControlSet\Control\Power' 'HibernateEnabled') -ne 0) }
        Set={ param($on)
              if ($on) {
                  & "$env:windir\System32\powercfg.exe" /hibernate on | Out-Null
                  Set-RegValue 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'HiberbootEnabled' 1
              }
              else     { Set-RegValue 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'HiberbootEnabled' 0 } } }
    [pscustomobject]@{ Id='Hibernate'; Need='Hibernate'; Def=$true; Page='Perf'; Group='Performances et alimentation'; MinBuild=0; Effect='I'
        Label='Mise en veille prolongée'
        Desc='Fichier hiberfil.sys (taille proche de la RAM). Désactiver le supprime et coupe aussi le démarrage rapide.'
        Tip='powercfg /hibernate on|off'
        Get={ (Get-RegValue 'HKLM\SYSTEM\CurrentControlSet\Control\Power' 'HibernateEnabled') -eq 1 }
        Set={ param($on) & "$env:windir\System32\powercfg.exe" /hibernate $(if ($on) { 'on' } else { 'off' }) | Out-Null } }
    [pscustomobject]@{ Id='BackgroundApps'; Page='Perf'; Group='Performances et alimentation'; MinBuild=0; Effect='L'
        Label='Applications en arrière-plan'
        Desc='Autorise les applications du Microsoft Store à tourner fenêtre fermée. Sans effet sur les logiciels classiques (Win32).'
        Tip='HKLM\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy\LetAppsRunInBackground = 2 + HKCU BackgroundAccessApplications\GlobalUserDisabled = 1.'
        Reg=@(
            @{ P='HKLM\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy'; N='LetAppsRunInBackground'; T='DWord'; On=$null; Off=2; D=0 }
            @{ P='HKCU\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications'; N='GlobalUserDisabled'; T='DWord'; On=0; Off=1; D=0 }) }
    [pscustomobject]@{ Id='SearchIndex'; Def=$true; Page='Perf'; Group='Performances et alimentation'; MinBuild=0; Effect='I'
        Label='Indexation de la recherche'
        Desc='Service Windows Search. Désactivé : moins d''accès disque, mais recherche Windows et Outlook beaucoup plus lentes.'
        Tip='WSearch : Automatique (différé) + démarré / Désactivé + arrêté.'
        Get={ $s = Get-Service -Name WSearch -ErrorAction SilentlyContinue; [bool]($s -and "$($s.StartType)" -ne 'Disabled') }
        Set={ param($on)
              if ($on) {
                  & "$env:windir\System32\sc.exe" config WSearch start= delayed-auto | Out-Null
                  Start-Service -Name WSearch -ErrorAction SilentlyContinue
              }
              else     { Stop-Service -Name WSearch -Force -ErrorAction SilentlyContinue; Set-Service -Name WSearch -StartupType Disabled } } }
    [pscustomobject]@{ Id='DeliveryOpt'; Page='Perf'; Group='Performances et alimentation'; MinBuild=0; Effect='I'
        Label='Partage des mises à jour entre postes (Optimisation de distribution)'
        Desc='Télécharge et envoie des morceaux de mises à jour vers d''autres postes. Désactivé : téléchargement direct depuis Microsoft / WSUS uniquement.'
        Tip='HKLM\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization\DODownloadMode = 0 / supprimée. Redémarrage de DoSvc. Écrasé par GPO de domaine.'
        Reg=@( @{ P='HKLM\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization'; N='DODownloadMode'; T='DWord'; On=$null; Off=0; D=1 })
        PostSet={ Restart-Service -Name DoSvc -Force -ErrorAction SilentlyContinue } }

    [pscustomobject]@{ Id='PowerPlan'; Need='ClassicPower'; Def='Balanced'; Page='Perf'; Group='Performances et alimentation'; MinBuild=0; Effect='I'; Kind='Choice'
        Label='Plan d''alimentation'
        Desc='Performances élevées / optimales : processeur maintenu à haute fréquence, consommation et chauffe plus fortes. Masqué sur les postes en veille moderne (S0), où Windows ne prévoit que le plan Équilibré.'
        Tip='powercfg /setactive. Plan absent du poste : recréé depuis le modèle Windows (powercfg /duplicatescheme 8c5e7fda-... ou e9a42b02-...).'
        Options=@( @{ L='Équilibré'; V='Balanced' }, @{ L='Performances élevées'; V='High' }, @{ L='Performances optimales'; V='Ultimate' }, @{ L='Autre plan'; V='Other'; H=$true })
        GetV={ Get-PowerPlanKey }
        SetV={ param($v) Set-PowerPlan "$v" } }
    [pscustomobject]@{ Id='VisualFx'; Page='Perf'; Group='Performances et alimentation'; MinBuild=0; Effect='L'
        Label='Effets visuels (animations, ombres, lissage)'
        Desc='Désactivé : réglage « Ajuster afin d''obtenir les meilleures performances » de Windows, interface plus sèche mais plus réactive sur un PC modeste. Polices toujours lissées.'
        Tip='HKCU\...\Explorer\VisualEffects\VisualFXSetting : 0 choix de Windows, 2 performances (3 = personnalisé). Désactivé : UserPreferencesMask 90 12 03 80 10 00 00 00, MinAnimate 0, TaskbarAnimations 0, FontSmoothing 2 conservé.'
        Get={ (Get-RegValue 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' 'VisualFXSetting') -ne 2 }
        Set={ param($on)
              Set-RegValue 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' 'VisualFXSetting' $(if ($on) { 0 } else { 2 })
              Set-RegValue 'HKCU\Control Panel\Desktop' 'UserPreferencesMask' ([byte[]]$(if ($on) { 0x9E, 0x1E, 0x07, 0x80, 0x12, 0, 0, 0 } else { 0x90, 0x12, 0x03, 0x80, 0x10, 0, 0, 0 })) 'Binary'
              Set-RegValue 'HKCU\Control Panel\Desktop\WindowMetrics' 'MinAnimate' $(if ($on) { '1' } else { '0' }) 'String'
              Set-RegValue "$ADV" 'TaskbarAnimations' $(if ($on) { 1 } else { 0 })
              Set-RegValue 'HKCU\Control Panel\Desktop' 'FontSmoothing' '2' 'String' }
        DefGet={ $true } }
    [pscustomobject]@{ Id='Hags'; Need='Hags'; Page='Perf'; Group='Performances et alimentation'; MinBuild=19041; Effect='R'
        Label='Planification GPU accélérée par le matériel'
        Desc='La carte graphique gère elle-même sa file de travail. Gain variable selon le pilote et le jeu. Carte et pilote compatibles uniquement (WDDM 2.7 et suivants).'
        Tip='HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\HwSchMode : 2 activé, 1 désactivé, absent = choix du pilote.'
        Get={ $v = Get-RegValue 'HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode'; if ($null -eq $v) { ([_OlivM.Gpu]::HwSch() -band 4) -ne 0 } else { [int]$v -eq 2 } }
        Set={ param($on) Set-RegValue 'HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode' $(if ($on) { 2 } else { 1 }) }
        DefGet={ ([_OlivM.Gpu]::HwSch() -band 4) -ne 0 } }
    [pscustomobject]@{ Id='WebSearch'; Page='Perso'; Group='Menu démarrer'; MinBuild=0; Effect='E'
        Label='Résultats web (Bing) dans la recherche'
        Desc='Mélange des résultats Internet aux résultats locaux dans la recherche du menu Démarrer.'
        Tip='HKCU\Software\Policies\Microsoft\Windows\Explorer\DisableSearchBoxSuggestions = 1 + Search\BingSearchEnabled = 0.'
        Reg=@(
            @{ P='HKCU\Software\Policies\Microsoft\Windows\Explorer'; N='DisableSearchBoxSuggestions'; T='DWord'; On=$null; Off=1; D=0 }
            @{ P='HKCU\Software\Microsoft\Windows\CurrentVersion\Search'; N='BingSearchEnabled'; T='DWord'; On=$null; Off=0; D=1 }) }
    [pscustomobject]@{ Id='StoreSuggest'; Page='Perso'; Group='Menu démarrer'; MinBuild=26200; Effect='E'
        Label='Suggestions du Microsoft Store dans la recherche'
        Desc='Applications du Store proposées dans les résultats de la recherche Windows (Windows 11 26H2 et suivants).'
        Tip='HKCU\Software\Microsoft\Windows\CurrentVersion\SearchSettings\IsStoreSuggestionsEnabled : 1 affichées (défaut), 0 masquées.'
        Reg=@( @{ P='HKCU\Software\Microsoft\Windows\CurrentVersion\SearchSettings'; N='IsStoreSuggestionsEnabled'; T='DWord'; On=1; Off=0; D=1 }) }
    [pscustomobject]@{ Id='StartReco'; Page='Perso'; Group='Menu démarrer'; MinBuild=22621; Effect='E'
        Label='Recommandations (astuces, raccourcis, nouvelles applications)'
        Desc='Suggestions promotionnelles dans la section « Recommandé » du menu Démarrer.'
        Tip='Explorer\Advanced\Start_IrisRecommendations (Windows 11 22H2+).'
        Reg=@( @{ P=$ADV; N='Start_IrisRecommendations'; T='DWord'; On=1; Off=0; D=1 }) }
    [pscustomobject]@{ Id='SilentApps'; Page='Perso'; Group='Menu démarrer'; MinBuild=0; Effect='I'
        Label='Installation automatique d''applications suggérées'
        Desc='Windows installe de lui-même des applications et jeux sponsorisés (Candy Crush, etc.).'
        Tip='ContentDeliveryManager : SilentInstalledAppsEnabled, PreInstalledAppsEnabled, OemPreInstalledAppsEnabled, SubscribedContent-338388Enabled.'
        Reg=@(
            @{ P=$CDM; N='SilentInstalledAppsEnabled'; T='DWord'; On=1; Off=0; D=1 }
            @{ P=$CDM; N='PreInstalledAppsEnabled'; T='DWord'; On=1; Off=0; D=1 }
            @{ P=$CDM; N='OemPreInstalledAppsEnabled'; T='DWord'; On=1; Off=0; D=1 }
            @{ P=$CDM; N='SubscribedContent-338388Enabled'; T='DWord'; On=1; Off=0; D=1 }) }
    [pscustomobject]@{ Id='AccountNotif'; Page='Perso'; Group='Menu démarrer'; MinBuild=22621; Effect='E'
        Label='Notifications liées au compte Microsoft'
        Desc='Pastilles sur l''icône du compte dans le menu Démarrer (sauvegarde, OneDrive...).'
        Tip='Explorer\Advanced\Start_AccountNotifications (Windows 11 22H2+).'
        Reg=@( @{ P=$ADV; N='Start_AccountNotifications'; T='DWord'; On=1; Off=0; D=1 }) }
    [pscustomobject]@{ Id='HibernateMenu'; Need='Hibernate'; Page='Perso'; Group='Menu démarrer'; MinBuild=0; Effect='I'
        Label='« Mettre en veille prolongée » dans le menu Marche/Arrêt'
        Desc='Ajoute l''option au menu. Nécessite la mise en veille prolongée active (onglet Système).'
        Tip='HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FlyoutMenuSettings\ShowHibernateOption.'
        Reg=@( @{ P='HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FlyoutMenuSettings'; N='ShowHibernateOption'; T='DWord'; On=1; Off=0; D=0 }) }
    [pscustomobject]@{ Id='TrackDocs'; Page='Perso'; Group='Menu démarrer'; MinBuild=0; Effect='E'
        Label='Fichiers récents'
        Desc='Affiche les derniers fichiers ouverts dans Démarrer, l''Explorateur et les listes de raccourcis.'
        Tip='Explorer\Advanced\Start_TrackDocs.'
        Reg=@( @{ P=$ADV; N='Start_TrackDocs'; T='DWord'; On=1; Off=0; D=1 }) }

    [pscustomobject]@{ Id='TaskbarAlign'; Page='Perso'; Group='Barre des tâches'; MinBuild=22000; Effect='E'; Kind='Choice'
        Label='Alignement des icônes'
        Desc='Position des icônes dans la barre des tâches.'
        Tip='Explorer\Advanced\TaskbarAl : 0 gauche, 1 centre.'
        Options=@( @{ L='Gauche'; V=0 }, @{ L='Centre'; V=1 })
        Reg=@( @{ P=$ADV; N='TaskbarAl'; T='DWord'; D=1 }) }
    [pscustomobject]@{ Id='SearchMode'; Page='Perso'; Group='Barre des tâches'; MinBuild=0; Effect='E'; Kind='Choice'
        Label='Recherche'
        Desc='Affichage de la recherche dans la barre des tâches.'
        Tip='Search\SearchboxTaskbarMode : 0 masquée, 1 icône, 2 zone de recherche.'
        Options=@( @{ L='Masquée'; V=0 }, @{ L='Icône'; V=1 }, @{ L='Zone'; V=2 })
        Reg=@( @{ P='HKCU\Software\Microsoft\Windows\CurrentVersion\Search'; N='SearchboxTaskbarMode'; T='DWord'; D=1 }) }
    [pscustomobject]@{ Id='BatteryPct'; Page='Perso'; Group='Barre des tâches'; MinBuild=26100; Effect='E'; Need='Laptop'
        Label='Pourcentage de batterie'
        Desc='Affiche le pourcentage à côté de l''icône de batterie (Windows 11 24H2 / 25H2 build 7019 et suivants). Postes portables uniquement.'
        Tip='Explorer\Advanced\IsBatteryPercentageEnabled : 1 affiché, 0 masqué (défaut).'
        Reg=@( @{ P=$ADV; N='IsBatteryPercentageEnabled'; T='DWord'; On=1; Off=0; D=0 }) }
    [pscustomobject]@{ Id='TaskView'; Page='Perso'; Group='Barre des tâches'; MinBuild=0; Effect='E'
        Label='Bouton Vue des tâches'
        Desc='Bouton d''accès aux bureaux virtuels et fenêtres ouvertes.'
        Tip='Explorer\Advanced\ShowTaskViewButton.'
        Reg=@( @{ P=$ADV; N='ShowTaskViewButton'; T='DWord'; On=1; Off=0; D=1 }) }
    [pscustomobject]@{ Id='Widgets'; Need='Widgets'; Page='Perso'; Group='Barre des tâches'; MinBuild=22000; Effect='E'
        Label='Widgets (météo, actualités)'
        Desc='Désactivé : widgets coupés pour tous les utilisateurs du poste.'
        Tip='HKLM\SOFTWARE\Policies\Microsoft\Dsh\AllowNewsAndInterests = 0 (TaskbarDa protégée sur les builds récentes).'
        Reg=@( @{ P='HKLM\SOFTWARE\Policies\Microsoft\Dsh'; N='AllowNewsAndInterests'; T='DWord'; On=$null; Off=0; D=1 }) }
    [pscustomobject]@{ Id='EndTask'; Page='Perso'; Group='Barre des tâches'; MinBuild=22631; Effect='E'
        Label='« Fin de tâche » au clic droit'
        Desc='Ferme de force une application bloquée depuis son icône, sans passer par le Gestionnaire des tâches.'
        Tip='Explorer\Advanced\TaskbarDeveloperSettings\TaskbarEndTask (Windows 11 23H2+).'
        Reg=@( @{ P="$ADV\TaskbarDeveloperSettings"; N='TaskbarEndTask'; T='DWord'; On=1; Off=0; D=0 }) }

    [pscustomobject]@{ Id='MousePrecision'; Page='Perso'; Group='Explorateur, souris et presse-papiers'; MinBuild=0; Effect='I'
        Label='Améliorer la précision du pointeur'
        Desc='Accélération de la souris : le pointeur va plus loin quand la souris bouge vite. Désactivé : déplacement proportionnel au geste, souvent préféré en jeu et en dessin.'
        Tip='HKCU\Control Panel\Mouse : MouseSpeed 1 / 0, MouseThreshold1 6 / 0, MouseThreshold2 10 / 0 (défauts de Windows : 1, 6, 10). Appliqué tout de suite à la session (SystemParametersInfo).'
        Reg=@(
            @{ P='HKCU\Control Panel\Mouse'; N='MouseSpeed'; T='String'; On='1'; Off='0'; D='1' }
            @{ P='HKCU\Control Panel\Mouse'; N='MouseThreshold1'; T='String'; On='6'; Off='0'; D='6' }
            @{ P='HKCU\Control Panel\Mouse'; N='MouseThreshold2'; T='String'; On='10'; Off='0'; D='10' })
        PostSet={ $on = "$(Get-RegValue 'HKCU\Control Panel\Mouse' 'MouseSpeed')" -eq '1'; [void][_OlivM.Mouse]::Apply($(if ($on) { 6 } else { 0 }), $(if ($on) { 10 } else { 0 }), $(if ($on) { 1 } else { 0 })) } }
    [pscustomobject]@{ Id='ClipHistory'; Page='Perso'; Group='Explorateur, souris et presse-papiers'; MinBuild=17763; Effect='I'
        Label='Historique du presse-papiers'
        Desc='Garde les derniers éléments copiés, rappelés avec Windows + V. Sans effet si une stratégie l''interdit.'
        Tip='HKCU\Software\Microsoft\Clipboard\EnableClipboardHistory : 1 activé, 0 désactivé (défaut). Stratégie HKLM\SOFTWARE\Policies\Microsoft\Windows\System\AllowClipboardHistory = 0 : interdit pour tous les comptes.'
        Reg=@( @{ P='HKCU\Software\Microsoft\Clipboard'; N='EnableClipboardHistory'; T='DWord'; On=1; Off=0; D=0 }) }

    [pscustomobject]@{ Id='LaunchTo'; Page='Perso'; Group='Explorateur, souris et presse-papiers'; MinBuild=0; Effect='I'; Kind='Choice'
        Label='Ouvrir l''Explorateur sur'
        Desc='Dossier affiché à l''ouverture d''une nouvelle fenêtre (Accueil = Accès rapide sous Windows 10).'
        Tip='Explorer\Advanced\LaunchTo : 2 Accueil / Accès rapide, 1 Ce PC.'
        Options=@( @{ L='Accueil'; V=2 }, @{ L='Ce PC'; V=1 })
        Reg=@( @{ P=$ADV; N='LaunchTo'; T='DWord'; D=2 }) }
    [pscustomobject]@{ Id='FileExt'; Page='Perso'; Group='Explorateur, souris et presse-papiers'; MinBuild=0; Effect='E'
        Label='Afficher les extensions de fichiers'
        Desc='Affiche .pdf, .exe, .docx... Évite de confondre « facture.pdf.exe » avec un PDF.'
        Tip='Explorer\Advanced\HideFileExt = 0.'
        Reg=@( @{ P=$ADV; N='HideFileExt'; T='DWord'; On=0; Off=1; D=1 }) }
    [pscustomobject]@{ Id='Hidden'; Page='Perso'; Group='Explorateur, souris et presse-papiers'; MinBuild=0; Effect='E'
        Label='Afficher les fichiers cachés'
        Desc='Affiche les fichiers et dossiers marqués « caché » (AppData, etc.).'
        Tip='Explorer\Advanced\Hidden = 1 (affichés) / 2 (masqués).'
        Reg=@( @{ P=$ADV; N='Hidden'; T='DWord'; On=1; Off=2; D=2 }) }
    [pscustomobject]@{ Id='ClassicMenu'; Page='Perso'; Group='Explorateur, souris et presse-papiers'; MinBuild=22000; Effect='E'
        Label='Menu clic droit complet (style Windows 10)'
        Desc='Affiche directement toutes les options, sans passer par « Afficher plus d''options ».'
        Tip='HKCU\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32 (défaut vide).'
        Reg=@( @{ P='HKCU\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32'; T='Key'; KillPath='HKCU\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}' }) }
    [pscustomobject]@{ Id='SyncAds'; Page='Perso'; Group='Explorateur, souris et presse-papiers'; MinBuild=0; Effect='E'
        Label='Bandeaux publicitaires OneDrive / Microsoft 365'
        Desc='Messages promotionnels affichés en haut des fenêtres de l''Explorateur.'
        Tip='Explorer\Advanced\ShowSyncProviderNotifications.'
        Reg=@( @{ P=$ADV; N='ShowSyncProviderNotifications'; T='DWord'; On=1; Off=0; D=1 }) }
    [pscustomobject]@{ Id='LongPaths'; Page='Perso'; Group='Explorateur, souris et presse-papiers'; MinBuild=0; Effect='R'
        Label='Chemins de plus de 260 caractères'
        Desc='Lève la limite historique de longueur des chemins pour les applications compatibles.'
        Tip='HKLM\SYSTEM\CurrentControlSet\Control\FileSystem\LongPathsEnabled (applications longPathAware uniquement).'
        Reg=@( @{ P='HKLM\SYSTEM\CurrentControlSet\Control\FileSystem'; N='LongPathsEnabled'; T='DWord'; On=1; Off=0; D=0 }) }

    [pscustomobject]@{ Id='SettingsAgent'; Need='CopilotPlus'; Page='Perso'; Group='Intelligence artificielle'; MinBuild=26100; Effect='P'
        Label='Expérience de recherche agentique'
        Desc='Agent IA de la recherche des Paramètres (langage naturel). Désactivé : recherche indexée et sémantique uniquement. Stratégie honorée sur Entreprise / Éducation, non prise en charge sur Pro.'
        Tip='HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsAI\DisableSettingsAgent = 1 (Policy CSP WindowsAI).'
        Reg=@( @{ P='HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsAI'; N='DisableSettingsAgent'; T='DWord'; On=$null; Off=1; D=0 }) }
    [pscustomobject]@{ Id='Recall'; Need='CopilotPlus'; Page='Perso'; Group='Intelligence artificielle'; MinBuild=26100; Effect='R'
        Label='Recall'
        Desc='PC Copilot+ uniquement. Désactivé : composant Recall indisponible et enregistrement des captures coupé pour tous les utilisateurs.'
        Tip='HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsAI : AllowRecallEnablement = 0, DisableAIDataAnalysis = 1 (24H2 KB5055627+).'
        Reg=@( @{ P='HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsAI'; N='AllowRecallEnablement'; T='DWord'; On=$null; Off=0; D=1 }
               @{ P='HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsAI'; N='DisableAIDataAnalysis'; T='DWord'; On=$null; Off=1; D=0 }) }
    [pscustomobject]@{ Id='ClickToDo'; Need='CopilotPlus'; Page='Perso'; Group='Intelligence artificielle'; MinBuild=26100; Effect='L'
        Label='Click to Do'
        Desc='Actions IA sur le contenu affiché (Win + clic, Win + Q). PC Copilot+ uniquement.'
        Tip='HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsAI\DisableClickToDo = 1.'
        Reg=@( @{ P='HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsAI'; N='DisableClickToDo'; T='DWord'; On=$null; Off=1; D=0 }) }
    [pscustomobject]@{ Id='NotepadAI'; Need='Notepad'; Page='Perso'; Group='Intelligence artificielle'; MinBuild=22621; Effect='I'
        Label='Outils d''écriture du Bloc-notes'
        Desc='Réécrire, Résumer, Écrire (Copilot). Désactivé : toutes les fonctions IA du Bloc-notes masquées, effectif à la réouverture du Bloc-notes (11.2503.16.0+).'
        Tip='HKLM\SOFTWARE\Policies\WindowsNotepad\DisableAIFeatures = 1 (stratégie DisableAIFeaturesInNotepad).'
        Reg=@( @{ P='HKLM\SOFTWARE\Policies\WindowsNotepad'; N='DisableAIFeatures'; T='DWord'; On=$null; Off=1; D=0 }) }
    [pscustomobject]@{ Id='PaintAI'; Need='Paint'; Page='Perso'; Group='Intelligence artificielle'; MinBuild=22621; Effect='I'
        Label='Fonctions IA de Paint'
        Desc='Image Creator, Cocreator et remplissage génératif. Désactivé : les 3 fonctions masquées dans Paint (Windows 11 22H2 / 24H2 à jour).'
        Tip='HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Paint : DisableImageCreator, DisableCocreator, DisableGenerativeFill = 1 (stratégie WindowsAI documentée par Microsoft).'
        Get={ $p = 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Paint'; -not (@('DisableImageCreator', 'DisableCocreator', 'DisableGenerativeFill') | Where-Object { [int](Get-RegValue $p $_) -eq 1 }).Count }
        Set={ param($on) $p = 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Paint'; foreach ($n in 'DisableImageCreator', 'DisableCocreator', 'DisableGenerativeFill') { Set-RegValue $p $n $(if ($on) { $null } else { 1 }) } }
        DefGet={ $true } }
    [pscustomobject]@{ Id='EdgeSidebar'; Page='Perso'; Group='Intelligence artificielle'; MinBuild=0; Effect='A'
        Label='Copilot et barre latérale d''Edge'
        Desc='Barre latérale de Microsoft Edge, dont le bouton Copilot. Désactivé : barre et bouton retirés pour tous les comptes.'
        Tip='HKLM\SOFTWARE\Policies\Microsoft\Edge\HubsSidebarEnabled = 0 (stratégie Edge). Pris en compte au prochain lancement d''Edge.'
        Reg=@( @{ P='HKLM\SOFTWARE\Policies\Microsoft\Edge'; N='HubsSidebarEnabled'; T='DWord'; On=$null; Off=0; D=1 }) }
    [pscustomobject]@{ Id='Location'; Page='Secu'; Group='Confidentialité'; MinBuild=0; Effect='I'
        Label='Localisation'
        Desc='Accès à la position du poste pour Windows et les applications (Cartes, Météo, fuseau horaire automatique...).'
        Tip='HKLM\...\CapabilityAccessManager\ConsentStore\location\Value = Allow / Deny (niveau machine).'
        Reg=@( @{ P='HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location'; N='Value'; T='String'; On='Allow'; Off='Deny'; D='Allow' }) }
    [pscustomobject]@{ Id='Telemetry'; Page='Secu'; Group='Confidentialité'; MinBuild=0; Effect='R'
        Label='Données de diagnostic Windows (télémétrie système)'
        Desc='Données de fonctionnement de tout le système envoyées à Microsoft par le service DiagTrack. Désactivé : niveau minimal autorisé par l''édition.'
        Tip='HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection\AllowTelemetry = 0 (0 effectif en Entreprise / Éducation / Serveur, sinon traité comme 1).'
        Reg=@( @{ P='HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; N='AllowTelemetry'; T='DWord'; On=$null; Off=0; D=3 }) }
    [pscustomobject]@{ Id='AppTelemetry'; Page='Secu'; Group='Confidentialité'; MinBuild=0; Effect='R'
        Label='Télémétrie de compatibilité des applications'
        Desc='Moteur séparé qui suit l''usage de certains composants Windows par les applications, pour le suivi de compatibilité.'
        Tip='HKLM\SOFTWARE\Policies\Microsoft\Windows\AppCompat\AITEnable = 0.'
        Reg=@( @{ P='HKLM\SOFTWARE\Policies\Microsoft\Windows\AppCompat'; N='AITEnable'; T='DWord'; On=$null; Off=0; D=1 }) }
    [pscustomobject]@{ Id='CEIP'; Page='Secu'; Group='Confidentialité'; MinBuild=0; Effect='R'
        Label='Programme d''amélioration de l''expérience utilisateur'
        Desc='Ancien programme de collecte (CEIP / SQM). Le couper coupe aussi la télémétrie de compatibilité.'
        Tip='HKLM\SOFTWARE\Policies\Microsoft\SQMClient\Windows\CEIPEnable = 0.'
        Reg=@( @{ P='HKLM\SOFTWARE\Policies\Microsoft\SQMClient\Windows'; N='CEIPEnable'; T='DWord'; On=$null; Off=0; D=1 }) }
    [pscustomobject]@{ Id='ActivityHistory'; Page='Secu'; Group='Confidentialité'; MinBuild=0; Effect='R'
        Label='Historique des activités'
        Desc='Enregistrement et envoi des applications et fichiers utilisés (ancienne chronologie Windows).'
        Tip='HKLM\SOFTWARE\Policies\Microsoft\Windows\System : PublishUserActivities, UploadUserActivities, EnableActivityFeed = 0.'
        Reg=@(
            @{ P='HKLM\SOFTWARE\Policies\Microsoft\Windows\System'; N='PublishUserActivities'; T='DWord'; On=$null; Off=0; D=1 }
            @{ P='HKLM\SOFTWARE\Policies\Microsoft\Windows\System'; N='UploadUserActivities'; T='DWord'; On=$null; Off=0; D=1 }
            @{ P='HKLM\SOFTWARE\Policies\Microsoft\Windows\System'; N='EnableActivityFeed'; T='DWord'; On=$null; Off=0; D=1 }) }
    [pscustomobject]@{ Id='TrackProgs'; Page='Secu'; Group='Confidentialité'; MinBuild=0; Effect='E'
        Label='Suivi des applications lancées'
        Desc='Mémorise les applications utilisées pour « Les plus utilisées » et la recherche.'
        Tip='Explorer\Advanced\Start_TrackProgs.'
        Reg=@( @{ P=$ADV; N='Start_TrackProgs'; T='DWord'; On=1; Off=0; D=1 }) }
    [pscustomobject]@{ Id='Inking'; Page='Secu'; Group='Confidentialité'; MinBuild=0; Effect='L'
        Label='Envoi des données de saisie à Microsoft'
        Desc='Envoi de données de frappe et d''écriture manuscrite pour améliorer la reconnaissance.'
        Tip='HKCU\Software\Microsoft\Input\TIPC\Enabled.'
        Reg=@( @{ P='HKCU\Software\Microsoft\Input\TIPC'; N='Enabled'; T='DWord'; On=1; Off=0; D=1 }) }
    [pscustomobject]@{ Id='InkPerso'; Page='Secu'; Group='Confidentialité'; MinBuild=0; Effect='L'
        Label='Dictionnaire personnel de saisie'
        Desc='Apprentissage local des mots et contacts de l''utilisateur pour les suggestions de frappe.'
        Tip='InputPersonalization\RestrictImplicitInkCollection / RestrictImplicitTextCollection = 1, TrainedDataStore\HarvestContacts = 0, Personalization\Settings\AcceptedPrivacyPolicy = 0.'
        Reg=@(
            @{ P='HKCU\Software\Microsoft\InputPersonalization'; N='RestrictImplicitInkCollection'; T='DWord'; On=0; Off=1; D=0 }
            @{ P='HKCU\Software\Microsoft\InputPersonalization'; N='RestrictImplicitTextCollection'; T='DWord'; On=0; Off=1; D=0 }
            @{ P='HKCU\Software\Microsoft\InputPersonalization\TrainedDataStore'; N='HarvestContacts'; T='DWord'; On=1; Off=0; D=1 }
            @{ P='HKCU\Software\Microsoft\Personalization\Settings'; N='AcceptedPrivacyPolicy'; T='DWord'; On=1; Off=0; D=1 }) }
    [pscustomobject]@{ Id='ErrorReports'; Page='Secu'; Group='Confidentialité'; MinBuild=0; Effect='I'
        Label='Rapports d''erreurs Windows'
        Desc='Envoi des rapports de plantage à Microsoft. Utile au diagnostic : à laisser actif.'
        Tip='HKLM\SOFTWARE\Microsoft\Windows\Windows Error Reporting\Disabled = 1.'
        Reg=@( @{ P='HKLM\SOFTWARE\Microsoft\Windows\Windows Error Reporting'; N='Disabled'; T='DWord'; On=0; Off=1; D=0 }) }
    [pscustomobject]@{ Id='LockCamera'; Need='Camera'; Page='Secu'; Group='Confidentialité'; MinBuild=0; Effect='I'
        Label='Caméra sur l''écran de verrouillage'
        Desc='Accès à l''appareil photo sans déverrouiller le poste.'
        Tip='HKLM\SOFTWARE\Policies\Microsoft\Windows\Personalization\NoLockScreenCamera = 1.'
        Reg=@( @{ P='HKLM\SOFTWARE\Policies\Microsoft\Windows\Personalization'; N='NoLockScreenCamera'; T='DWord'; On=$null; Off=1; D=0 }) }
    [pscustomobject]@{ Id='CameraOSD'; Need='Camera'; Page='Secu'; Group='Confidentialité'; MinBuild=0; Effect='R'
        Label='Indicateur à l''écran quand la caméra s''allume'
        Desc='Affiche une notification visuelle à chaque activation / arrêt de la webcam.'
        Tip='HKLM\SOFTWARE\Microsoft\OEM\Device\Capture\NoPhysicalCameraLED = 1.'
        Reg=@( @{ P='HKLM\SOFTWARE\Microsoft\OEM\Device\Capture'; N='NoPhysicalCameraLED'; T='DWord'; On=1; Off=$null; D=0 }) }
    [pscustomobject]@{ Id='OnlineSpeech'; Page='Secu'; Group='Confidentialité'; MinBuild=0; Effect='I'
        Label='Reconnaissance vocale en ligne'
        Desc='Envoi de la voix aux serveurs Microsoft pour la dictée et les commandes vocales.'
        Tip='HKCU\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy\HasAccepted.'
        Reg=@( @{ P='HKCU\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy'; N='HasAccepted'; T='DWord'; On=1; Off=0; D=0 }) }

    [pscustomobject]@{ Id='Tailored'; Page='Secu'; Group='Publicités et suggestions'; MinBuild=0; Effect='I'
        Label='Expériences personnalisées'
        Desc='Conseils et offres basés sur les données de diagnostic.'
        Tip='HKCU\...\Privacy\TailoredExperiencesWithDiagnosticDataEnabled.'
        Reg=@( @{ P='HKCU\Software\Microsoft\Windows\CurrentVersion\Privacy'; N='TailoredExperiencesWithDiagnosticDataEnabled'; T='DWord'; On=1; Off=0; D=1 }) }
    [pscustomobject]@{ Id='AdId'; Page='Secu'; Group='Publicités et suggestions'; MinBuild=0; Effect='I'
        Label='Identifiant de publicité'
        Desc='Identifiant unique utilisé par les applications pour cibler les publicités.'
        Tip='HKCU\...\AdvertisingInfo\Enabled.'
        Reg=@( @{ P='HKCU\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo'; N='Enabled'; T='DWord'; On=1; Off=0; D=1 }) }
    [pscustomobject]@{ Id='SettingsSuggest'; Page='Secu'; Group='Publicités et suggestions'; MinBuild=0; Effect='P'
        Label='Contenu suggéré dans les Paramètres'
        Desc='Suggestions et promotions affichées dans l''application Paramètres.'
        Tip='ContentDeliveryManager\SubscribedContent-338393Enabled, -353694Enabled, -353696Enabled.'
        Reg=@(
            @{ P=$CDM; N='SubscribedContent-338393Enabled'; T='DWord'; On=1; Off=0; D=1 }
            @{ P=$CDM; N='SubscribedContent-353694Enabled'; T='DWord'; On=1; Off=0; D=1 }
            @{ P=$CDM; N='SubscribedContent-353696Enabled'; T='DWord'; On=1; Off=0; D=1 }) }
    [pscustomobject]@{ Id='SettingsHome'; Def=$true; Page='Secu'; Group='Publicités et suggestions'; MinBuild=22631; Effect='P'
        Label='Page d''accueil de l''application Paramètres'
        Desc='Page « Accueil » avec cartes Microsoft 365, OneDrive, Game Pass...'
        Tip='HKLM\...\Policies\Explorer\SettingsPageVisibility : ajout de « home » à hide: (pages existantes conservées).'
        Get={
            $v = "$(Get-RegValue 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' 'SettingsPageVisibility')"
            -not ($v -match '^hide:(.*;)?home(;|$)')
        }
        Set={ param($on)
              $p = 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'
              $v = "$(Get-RegValue $p 'SettingsPageVisibility')"
              if ($v -and $v -notmatch '^hide:') { throw "SettingsPageVisibility est en mode showonly ($v) : modification manuelle requise." }
              $items = @()
              if ($v) { $items = @(($v -replace '^hide:', '') -split ';' | Where-Object { $_ -and $_ -ne 'home' }) }
              if (-not $on) { $items += 'home' }
              if ($items.Count) {
                  Set-RegValue $p 'SettingsPageVisibility' ('hide:' + ($items -join ';')) 'String'
              } else {
                  Set-RegValue $p 'SettingsPageVisibility' $null
              } } }
    [pscustomobject]@{ Id='SuggestNotif'; Page='Secu'; Group='Publicités et suggestions'; MinBuild=0; Effect='I'
        Label='Notifications suggérées'
        Desc='Notifications proposant des fonctions ou services Microsoft.'
        Tip='HKCU\...\Notifications\Settings\Windows.SystemToast.Suggested\Enabled.'
        Reg=@( @{ P='HKCU\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings\Windows.SystemToast.Suggested'; N='Enabled'; T='DWord'; On=1; Off=0; D=1 }) }
    [pscustomobject]@{ Id='LockTips'; Page='Secu'; Group='Publicités et suggestions'; MinBuild=0; Effect='I'
        Label='Astuces et anecdotes sur l''écran de verrouillage'
        Desc='Textes et liens promotionnels affichés sur l''écran de verrouillage.'
        Tip='ContentDeliveryManager\RotatingLockScreenOverlayEnabled + SubscribedContent-338387Enabled.'
        Reg=@(
            @{ P=$CDM; N='RotatingLockScreenOverlayEnabled'; T='DWord'; On=1; Off=0; D=1 }
            @{ P=$CDM; N='SubscribedContent-338387Enabled'; T='DWord'; On=1; Off=0; D=1 }) }
    [pscustomobject]@{ Id='Tips'; Page='Secu'; Group='Publicités et suggestions'; MinBuild=0; Effect='I'
        Label='Astuces et suggestions pour Windows'
        Desc='Notifications de conseils d''utilisation.'
        Tip='ContentDeliveryManager\SubscribedContent-338389Enabled + SoftLandingEnabled.'
        Reg=@(
            @{ P=$CDM; N='SubscribedContent-338389Enabled'; T='DWord'; On=1; Off=0; D=1 }
            @{ P=$CDM; N='SoftLandingEnabled'; T='DWord'; On=1; Off=0; D=1 }) }
    [pscustomobject]@{ Id='Welcome'; Page='Secu'; Group='Publicités et suggestions'; MinBuild=0; Effect='I'
        Label='Écran d''accueil après les mises à jour'
        Desc='Présentation des nouveautés affichée après certaines mises à jour.'
        Tip='ContentDeliveryManager\SubscribedContent-310093Enabled.'
        Reg=@( @{ P=$CDM; N='SubscribedContent-310093Enabled'; T='DWord'; On=1; Off=0; D=1 }) }
    [pscustomobject]@{ Id='Scoobe'; Page='Secu'; Group='Publicités et suggestions'; MinBuild=0; Effect='I'
        Label='« Terminer la configuration de votre appareil »'
        Desc='Écran proposant Microsoft 365, OneDrive, Game Pass... à l''ouverture de session.'
        Tip='HKCU\...\UserProfileEngagement\ScoobeSystemSettingEnabled.'
        Reg=@( @{ P='HKCU\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement'; N='ScoobeSystemSettingEnabled'; T='DWord'; On=1; Off=0; D=1 }) }
    [pscustomobject]@{ Id='GameModeWin'; Page='Perf'; Group='Performances et alimentation'; MinBuild=0; Effect='I'
        Label='Mode jeu de Windows'
        Desc='Windows donne la priorité au jeu au premier plan et suspend certaines tâches de fond (mises à jour, notifications) pendant la partie.'
        Tip='HKCU\Software\Microsoft\GameBar\AutoGameModeEnabled : 1 activé (défaut), 0 désactivé.'
        Reg=@( @{ P='HKCU\Software\Microsoft\GameBar'; N='AutoGameModeEnabled'; T='DWord'; On=1; Off=0; D=1 }) }
    [pscustomobject]@{ Id='DnsProvider'; Def='Auto'; Page='Secu'; Group='Sécurité'; MinBuild=0; Effect='I'; Kind='Choice'
        Label='Serveurs DNS'
        Desc='Appliqué à toutes les cartes réseau actives (Ethernet, Wi-Fi), IPv4 et IPv6. Windows 11 : requêtes chiffrées (DNS over HTTPS) quand le fournisseur le permet, repli en clair si le chiffrement échoue. Automatique = DNS donnés par la box ou le routeur.'
        Tip='Set-DnsClientServerAddress (Reset = automatique), cache DNS vidé. Chiffrement : modèle DoH du fournisseur avec AutoUpgrade (Set / Add-DnsClientDohServerAddress). Cloudflare 1.1.1.1, Google 8.8.8.8, AdGuard 94.140.14.14 (blocage des publicités).'
        Options=@( @{ L='Automatique'; V='Auto' }, @{ L='Cloudflare'; V='Cloudflare' }, @{ L='Google'; V='Google' }, @{ L='AdGuard'; V='AdGuard' }, @{ L='Autres serveurs'; V='Other'; H=$true })
        GetV={ Get-DnsProvider }
        SetV={ param($v) Set-DnsProvider "$v" } }
    [pscustomobject]@{ Id='Smb1'; Def=$false; Page='Secu'; Group='Sécurité'; MinBuild=0; Effect='I'
        Label='SMBv1 (ancien protocole de partage)'
        Desc='Protocole de 1984 exploité par WannaCry. Recommandé : désactivé (seuls de très vieux NAS ou imprimantes en ont besoin).'
        Tip='Set-SmbServerConfiguration -EnableSMB1Protocol (serveur SMB du poste).'
        Get={ [bool](Get-SmbServerConfiguration -ErrorAction Stop).EnableSMB1Protocol }
        Set={ param($on) Set-SmbServerConfiguration -EnableSMB1Protocol $on -Force -Confirm:$false -ErrorAction Stop } }
    [pscustomobject]@{ Id='Llmnr'; Page='Secu'; Group='Sécurité'; MinBuild=0; Effect='I'
        Label='LLMNR (résolution de noms locale)'
        Desc='Permet à un appareil du réseau de se faire passer pour un autre et de capter des identifiants. Recommandé : désactivé (DNS suffit).'
        Tip='HKLM\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient\EnableMulticast = 0.'
        Reg=@( @{ P='HKLM\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient'; N='EnableMulticast'; T='DWord'; On=$null; Off=0; D=1 }) }
    [pscustomobject]@{ Id='NetBios'; Def=$true; Page='Secu'; Group='Sécurité'; MinBuild=0; Effect='R'
        Label='NetBIOS sur TCP/IP'
        Desc='Ancienne résolution de noms, même risque que LLMNR. Recommandé : désactivé (sauf vieux partages réseau accédés par nom NetBIOS).'
        Tip='HKLM\SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces\Tcpip_{carte}\NetbiosOptions : 2 désactivé, 0 selon le DHCP (défaut).'
        Get={ $k = Open-RegKey 'HKLM\SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces'; $off = $true; $n = 0
              if ($k) { try { foreach ($i in $k.GetSubKeyNames()) { $n++; if ([int](Get-RegValue "HKLM\SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces\$i" 'NetbiosOptions') -ne 2) { $off = $false } } } finally { $k.Close() } }
              -not ($off -and $n) }
        Set={ param($on) $k = Open-RegKey 'HKLM\SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces'
              if ($k) { try { foreach ($i in $k.GetSubKeyNames()) { Set-RegValue "HKLM\SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces\$i" 'NetbiosOptions' $(if ($on) { 0 } else { 2 }) } } finally { $k.Close() } } } }
    [pscustomobject]@{ Id='WDigest'; Page='Secu'; Group='Sécurité'; MinBuild=0; Effect='R'
        Label='WDigest (mots de passe en clair en mémoire)'
        Desc='Garde le mot de passe de session lisible en mémoire, récupérable par un logiciel malveillant. Recommandé : désactivé (défaut de Windows 10 / 11).'
        Tip='HKLM\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest\UseLogonCredential : 0 / absent désactivé, 1 activé.'
        Reg=@( @{ P='HKLM\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest'; N='UseLogonCredential'; T='DWord'; On=1; Off=0; D=0 }) }
    [pscustomobject]@{ Id='AutoRun'; Page='Secu'; Group='Sécurité'; MinBuild=0; Effect='E'
        Label='Exécution automatique des supports (AutoRun)'
        Desc='Lancement automatique depuis clés USB, CD et lecteurs réseau, vecteur classique de virus. Recommandé : désactivé.'
        Tip='HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer\NoDriveTypeAutoRun = 255 (tous les lecteurs).'
        Reg=@( @{ P='HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'; N='NoDriveTypeAutoRun'; T='DWord'; On=$null; Off=255; D=145 }) }
    [pscustomobject]@{ Id='UacLevel'; Def='Default'; Page='Secu'; Group='Sécurité'; MinBuild=0; Effect='I'; Kind='Choice'
        Label='Contrôle de compte d''utilisateur (UAC)'
        Desc='Toujours avertir : confirmation aussi quand Windows modifie lui-même ses paramètres. Par défaut : confirmation pour les programmes seulement.'
        Tip='HKLM\...\Policies\System : ConsentPromptBehaviorAdmin 2 (toujours) / 5 (défaut), PromptOnSecureDesktop 1.'
        Options=@( @{ L='Par défaut'; V='Default' }, @{ L='Toujours avertir'; V='Always' }, @{ L='Réduit'; V='Other'; H=$true })
        GetV={ $p = 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'; $c = Get-RegValue $p 'ConsentPromptBehaviorAdmin'; $sd = Get-RegValue $p 'PromptOnSecureDesktop'
               if ([int]$c -eq 2 -and $sd -ne 0) { 'Always' } elseif (($null -eq $c -or [int]$c -eq 5) -and $sd -ne 0) { 'Default' } else { 'Other' } }
        SetV={ param($v) $p = 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
               if ("$v" -in 'Default', 'Always') { Set-RegValue $p 'ConsentPromptBehaviorAdmin' $(if ("$v" -eq 'Always') { 2 } else { 5 }); Set-RegValue $p 'PromptOnSecureDesktop' 1; Set-RegValue $p 'EnableLUA' 1 } } }
    [pscustomobject]@{ Id='Firewall'; Def=$true; Page='Secu'; Group='Sécurité'; MinBuild=0; Effect='I'
        Label='Pare-feu Windows (tous les profils)'
        Desc='Domaine, privé et public. Recommandé : activé (sauf pare-feu d''un autre antivirus, qui le désactive lui-même).'
        Tip='Get / Set-NetFirewallProfile -All -Enabled.'
        Get={ @(Get-NetFirewallProfile -ErrorAction Stop | Where-Object { -not $_.Enabled }).Count -eq 0 }
        Set={ param($on) Set-NetFirewallProfile -All -Enabled $(if ($on) { 'True' } else { 'False' }) -ErrorAction Stop } }
    [pscustomobject]@{ Id='DefPua'; Need='Defender'; Def=$false; Page='Secu'; Group='Sécurité'; MinBuild=0; Effect='I'
        Label='Defender : applications potentiellement indésirables'
        Desc='Bloque les logiciels publicitaires, mineurs de cryptomonnaie et installeurs piégés. Recommandé : activé.'
        Tip='Set-MpPreference -PUAProtection Enabled / Disabled.'
        Get={ [int](Get-MpPreference -ErrorAction Stop).PUAProtection -eq 1 }
        Set={ param($on) Set-MpPreference -PUAProtection $(if ($on) { 'Enabled' } else { 'Disabled' }) -ErrorAction Stop } }
    [pscustomobject]@{ Id='DefNet'; Need='Defender'; Def=$false; Page='Secu'; Group='Sécurité'; MinBuild=0; Effect='I'
        Label='Defender : protection réseau'
        Desc='Bloque l''accès aux sites d''hameçonnage et de logiciels malveillants depuis toutes les applications, pas seulement Edge. Recommandé : activé.'
        Tip='Set-MpPreference -EnableNetworkProtection Enabled / Disabled.'
        Get={ [int](Get-MpPreference -ErrorAction Stop).EnableNetworkProtection -eq 1 }
        Set={ param($on) Set-MpPreference -EnableNetworkProtection $(if ($on) { 'Enabled' } else { 'Disabled' }) -ErrorAction Stop } }
    [pscustomobject]@{ Id='DefCfa'; Need='Defender'; Def=$false; Page='Secu'; Group='Sécurité'; MinBuild=0; Effect='I'
        Label='Defender : dispositif d''accès contrôlé aux dossiers'
        Desc='Anti-rançongiciel : seuls les programmes reconnus peuvent modifier Documents, Images, Vidéos, Musique, Bureau. Peut bloquer un jeu ou un logiciel peu connu (autorisation dans Sécurité Windows > Protection contre les rançongiciels).'
        Tip='Set-MpPreference -EnableControlledFolderAccess Enabled / Disabled.'
        Get={ [int](Get-MpPreference -ErrorAction Stop).EnableControlledFolderAccess -eq 1 }
        Set={ param($on) Set-MpPreference -EnableControlledFolderAccess $(if ($on) { 'Enabled' } else { 'Disabled' }) -ErrorAction Stop } }
    [pscustomobject]@{ Id='Wsh'; Page='Secu'; Group='Sécurité'; MinBuild=0; Effect='I'
        Label='Windows Script Host (scripts .vbs, .js)'
        Desc='Exécute les scripts VBScript et JScript, vecteur fréquent de pièces jointes piégées. Recommandé : désactivé, sauf logiciel ou script d''entreprise qui en dépend.'
        Tip='HKLM\SOFTWARE\Microsoft\Windows Script Host\Settings\Enabled : 0 désactivé, absent / 1 activé.'
        Reg=@( @{ P='HKLM\SOFTWARE\Microsoft\Windows Script Host\Settings'; N='Enabled'; T='DWord'; On=$null; Off=0; D=1 }) }
    [pscustomobject]@{ Id='PsLog'; Def=$false; Page='Secu'; Group='Sécurité'; MinBuild=0; Effect='I'
        Label='Journal des scripts PowerShell'
        Desc='Enregistre le contenu de chaque script PowerShell exécuté dans l''Observateur d''événements (Microsoft-Windows-PowerShell/Operational, événement 4104) : trace utile après une infection.'
        Tip='HKLM\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging\EnableScriptBlockLogging = 1.'
        Reg=@( @{ P='HKLM\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging'; N='EnableScriptBlockLogging'; T='DWord'; On=1; Off=$null; D=0 }) }
    [pscustomobject]@{ Id='LsaPpl'; Page='Secu'; Group='Sécurité'; MinBuild=0; Effect='R'
        Label='Protection LSA'
        Desc='Empêche les programmes de lire les secrets d''ouverture de session (outils du type Mimikatz). Recommandé : activé. Peut bloquer d''anciens pilotes de lecteurs de cartes ou de sécurité.'
        Tip='HKLM\SYSTEM\CurrentControlSet\Control\Lsa\RunAsPPL : 2 activé sans verrou UEFI (Windows 11 22H2+, posé par l''outil), 1 activé avec verrou UEFI (Windows 10), 0 / absent désactivé.'
        Get={ [int](Get-RegValue 'HKLM\SYSTEM\CurrentControlSet\Control\Lsa' 'RunAsPPL') -in 1, 2 }
        # activé en 2 (sans verrou UEFI, Windows 11 22H2 et suivants) : en 1, la protection est aussi gravée dans une variable
        # UEFI et la désactiver ensuite par le registre ne suffit plus (outil de désactivation Microsoft requis)
        Set={ param($on) $lp = 'HKLM\SYSTEM\CurrentControlSet\Control\Lsa'; $was = Get-RegValue $lp 'RunAsPPL'
              Set-RegValue $lp 'RunAsPPL' $(if ($on) { if ($Build -ge 22621) { 2 } else { 1 } } else { 0 })
              if (-not $on -and [int]$was -eq 1) { Write-UiLog 'Protection LSA : elle avait été activée avec verrou UEFI (RunAsPPL = 1) ; si elle reste active après redémarrage, la désactivation demande l''outil LSA Protected Process Opt-out de Microsoft.' 'WARN' } }
        DefGet={ $false } }
    [pscustomobject]@{ Id='Rdp'; Need='NotHome'; Def=$false; Page='Secu'; Group='Sécurité'; MinBuild=0; Effect='I'
        Label='Bureau à distance (connexions entrantes)'
        Desc='Permet de prendre la main sur ce PC depuis un autre. Recommandé : désactivé si inutilisé (cible fréquente d''attaques).'
        Tip='HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server\fDenyTSConnections : 1 désactivé, 0 activé.'
        Reg=@( @{ P='HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server'; N='fDenyTSConnections'; T='DWord'; On=0; Off=1; D=1 }) }
    [pscustomobject]@{ Id='SmbSign'; Need='OldSmb'; Def=$false; Page='Secu'; Group='Sécurité'; MinBuild=0; Effect='R'
        Label='Signature SMB obligatoire'
        Desc='Chaque échange de partage de fichiers est signé : empêche l''interception et la modification en route (attaque par relais). Exigée par défaut depuis Windows 11 24H2. Recommandé : activé ; d''anciens NAS ou accès invité peuvent ne plus répondre.'
        Tip='HKLM\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters et LanmanServer\Parameters : RequireSecuritySignature = 1 / 0.'
        Reg=@( @{ P='HKLM\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters'; N='RequireSecuritySignature'; T='DWord'; On=1; Off=0; D=0 }
               @{ P='HKLM\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters'; N='RequireSecuritySignature'; T='DWord'; On=1; Off=0; D=0 }) }
    [pscustomobject]@{ Id='AdminShares'; Page='Secu'; Group='Sécurité'; MinBuild=0; Effect='R'
        Label='Partages administratifs (C$, ADMIN$)'
        Desc='Accès réseau à tout le disque pour un compte administrateur. Inutiles sur un PC personnel. Recommandé : désactivé.'
        Tip='HKLM\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters\AutoShareWks = 0 (désactivé) / absent (défaut).'
        Reg=@( @{ P='HKLM\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters'; N='AutoShareWks'; T='DWord'; On=$null; Off=0; D=1 }) }
    [pscustomobject]@{ Id='WuPolicy'; Need='NotHome'; Def='Default'; Page='Perf'; Group='Windows Update'; MinBuild=0; Effect='I'; Kind='Choice'
        Label='Mises à jour de Windows'
        Desc='Sécurité uniquement : nouvelles versions de Windows reportées de 365 jours, correctifs de sécurité installés 4 jours après leur sortie. Désactivées : plus aucune installation automatique (recherche manuelle toujours possible), déconseillé dans la durée.'
        Tip='HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate : DeferFeatureUpdates = 1, DeferFeatureUpdatesPeriodInDays = 365, DeferQualityUpdates = 1, DeferQualityUpdatesPeriodInDays = 4 ; ...\WindowsUpdate\AU\NoAutoUpdate = 1 (désactivées). Stratégie de domaine ou Intune prioritaire.'
        Options=@( @{ L='Par défaut'; V='Default' }, @{ L='Sécurité uniquement'; V='Secu' }, @{ L='Désactivées'; V='Off' }, @{ L='Réglage personnalisé'; V='Other'; H=$true })
        GetV={ $p = 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
               if ((Get-RegValue "$p\AU" 'NoAutoUpdate') -eq 1) { return 'Off' }
               $f = Get-RegValue $p 'DeferFeatureUpdates'; $q = Get-RegValue $p 'DeferQualityUpdates'
               if ($null -eq $f -and $null -eq $q) { return 'Default' }
               if ($f -eq 1 -and $q -eq 1 -and (Get-RegValue $p 'DeferFeatureUpdatesPeriodInDays') -eq 365 -and (Get-RegValue $p 'DeferQualityUpdatesPeriodInDays') -eq 4) { 'Secu' } else { 'Other' } }
        SetV={ param($v)
               $p = 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
               foreach ($n in 'DeferFeatureUpdates', 'DeferFeatureUpdatesPeriodInDays', 'DeferQualityUpdates', 'DeferQualityUpdatesPeriodInDays') { Set-RegValue $p $n $null }
               Set-RegValue "$p\AU" 'NoAutoUpdate' $null
               if ("$v" -eq 'Secu') { Set-RegValue $p 'DeferFeatureUpdates' 1; Set-RegValue $p 'DeferFeatureUpdatesPeriodInDays' 365; Set-RegValue $p 'DeferQualityUpdates' 1; Set-RegValue $p 'DeferQualityUpdatesPeriodInDays' 4 }
               elseif ("$v" -eq 'Off') { Set-RegValue "$p\AU" 'NoAutoUpdate' 1 } } }
    [pscustomobject]@{ Id='TargetRelease'; Need='TargetRelease'; Def='None'; Page='Perf'; Group='Windows Update'; MinBuild=22000; Effect='I'; Kind='Choice'
        Label='Version de Windows 11'
        Desc='Version actuelle : le poste reste sur sa version de Windows 11, les mises à jour de sécurité continuent, la version suivante n''est pas installée. Éditions Professionnel, Entreprise et Éducation.'
        Tip='HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate : TargetReleaseVersion = 1, ProductVersion = Windows 11, TargetReleaseVersionInfo = version. Pris en compte à la prochaine recherche Windows Update. Stratégie de domaine ou Intune prioritaire.'
        Options=@( @{ L='Non bloquée'; V='None' }, @{ L="Version actuelle ($WinDisplayVer)"; V="$WinDisplayVer" })
        GetV={ $p = 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'; $i = "$(Get-RegValue $p 'TargetReleaseVersionInfo')"; if ((Get-RegValue $p 'TargetReleaseVersion') -eq 1 -and $i) { $i } else { 'None' } }
        SetV={ param($v)
               $p = 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
               if ("$v" -eq 'None') { foreach ($n in 'TargetReleaseVersion', 'ProductVersion', 'TargetReleaseVersionInfo') { Set-RegValue $p $n $null } }
               else { Set-RegValue $p 'ProductVersion' 'Windows 11' 'String'; Set-RegValue $p 'TargetReleaseVersionInfo' "$v" 'String'; Set-RegValue $p 'TargetReleaseVersion' 1 } } }
)

$GroupInfo = @{
    'Performances et alimentation' = @{ Glyph=[string][char]0xE7E8; Desc='Démarrage, veille prolongée, applications en arrière-plan, indexation, partage des mises à jour' }
    'Menu démarrer'                = @{ Glyph=[string][char]0xE8A9; Desc='Résultats web, recommandations, suggestions et fichiers récents' }
    'Barre des tâches'             = @{ Glyph=[string][char]0xE7C4; Desc='Alignement, recherche, boutons et widgets' }
    'Souris et presse-papiers'     = @{ Glyph=[string][char]0xE962; Desc='Précision du pointeur, historique des éléments copiés (Windows + V)' }
    'Réseau'                       = @{ Glyph=[string][char]0xE968; Desc='Serveurs DNS des cartes réseau' }
    'Sécurité'                     = @{ Glyph=[string][char]0xE72E; Desc='Durcissement : protocoles anciens, UAC, pare-feu, Defender, LSA' }
    'Windows Update'               = @{ Glyph=[string][char]0xE895; Desc='Report ou arrêt des mises à jour, version de Windows 11 maintenue sur le poste' }
    'Explorateur de fichiers'      = @{ Glyph=[string][char]0xE8B7; Desc='Dossier d''ouverture, extensions, fichiers cachés, menu clic droit' }
    'Confidentialité'              = @{ Glyph=[string][char]0xE72E; Desc='Données envoyées à Microsoft sur l''utilisation du poste' }
    'Intelligence artificielle'    = @{ Glyph=[string][char]0xE945; Desc='Recherche agentique, Recall, Click to Do, Bloc-notes, Paint, Edge' }
    'Publicités et suggestions'    = @{ Glyph=[string][char]0xE789; Desc='Contenus promotionnels et suggestions de nouvelles fonctions' }
}

$EffectInfo = @{
    # Idle : texte de la pastille sous l'intitulé « Prend effet » (moment où le réglage s'applique réellement)
    I = @{ Idle = 'Immédiatement';                  Pending = $null;                       Bar = $false }
    P = @{ Idle = 'Après relance des Paramètres';   Pending = $null;                       Bar = $false }
    A = @{ Idle = 'À la relance du logiciel';       Pending = $null;                       Bar = $false }
    E = @{ Idle = 'Après relance de l''Explorateur'; Pending = 'Redémarrer l''Explorateur'; Bar = $true }
    L = @{ Idle = 'Après déconnexion';              Pending = 'Déconnexion requise';       Bar = $true }
    R = @{ Idle = 'Après redémarrage';              Pending = 'Redémarrage requis';        Bar = $true }
    N = @{ Idle = 'À la prochaine session';         Pending = 'Déconnexion';               Bar = $false }
}

$AppxCatalog = @(
    @{ N='Clipchamp.Clipchamp'; L='Clipchamp' }
    @{ N='Microsoft.BingNews'; L='Actualités' }
    @{ N='Microsoft.BingWeather'; L='Météo' }
    @{ N='Microsoft.BingSearch'; L='Recherche Bing' }
    @{ N='Microsoft.Copilot'; L='Copilot' }
    @{ N='Microsoft.GetHelp'; L='Obtenir de l''aide' }
    @{ N='Microsoft.Getstarted'; L='Astuces' }
    @{ N='Microsoft.MicrosoftOfficeHub'; L='Microsoft 365 (Office)' }
    @{ N='Microsoft.MicrosoftSolitaireCollection'; L='Solitaire Collection' }
    @{ N='Microsoft.People'; L='Contacts' }
    @{ N='Microsoft.PowerAutomateDesktop'; L='Power Automate' }
    @{ N='Microsoft.Todos'; L='Microsoft To Do' }
    @{ N='MSTeams'; L='Teams (nouveau, perso / pro)'; C=$true }
    @{ N='MicrosoftTeams'; L='Teams (personnel)' }
    @{ N='Microsoft.WindowsFeedbackHub'; L='Hub de commentaires' }
    @{ N='Microsoft.WindowsMaps'; L='Cartes' }
    @{ N='Microsoft.ZuneMusic'; L='Lecteur multimédia' }
    @{ N='Microsoft.ZuneVideo'; L='Films et TV' }
    @{ N='Microsoft.YourPhone'; L='Mobile connecté' }
    @{ N='Microsoft.OutlookForWindows'; L='Outlook (nouveau)'; C=$true }
    @{ N='Microsoft.549981C3F5F10'; L='Cortana' }
    @{ N='MicrosoftCorporationII.MicrosoftFamily'; L='Microsoft Family' }
    @{ N='MicrosoftCorporationII.QuickAssist'; L='Assistance rapide'; C=$true }
    @{ N='Microsoft.Windows.DevHome'; L='Dev Home' }
    @{ N='Microsoft.MixedReality.Portal'; L='Portail de réalité mixte' }
    @{ N='Microsoft.SkypeApp'; L='Skype' }
    @{ N='Microsoft.GamingApp'; L='Xbox'; C=$true }
    @{ N='Microsoft.XboxGamingOverlay'; L='Xbox Game Bar'; C=$true }
    @{ N='Microsoft.XboxSpeechToTextOverlay'; L='Xbox - transcription vocale' }
    @{ N='Microsoft.Xbox.TCUI'; L='Xbox TCUI'; C=$true }
)

