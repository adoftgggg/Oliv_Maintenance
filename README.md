# Oliv_Maintenance – sources

## Lancer l'application en une commande

Dans PowerShell (Windows 10 / 11, sans droits administrateur pour la commande ; Windows demande l'autorisation au lancement) :

```powershell
irm https://raw.githubusercontent.com/adoftgggg/Oliv_Maintenance/main/lancer.ps1 | iex
```

Le script `lancer.ps1` lit la dernière version publiée, télécharge l'exe dans le dossier Téléchargements sous le nom
`Oliv_Maintenance.exe`, vérifie son empreinte SHA-256 par rapport à celle de la publication (fichier rejeté sinon),
puis le lance. Téléchargement manuel : https://github.com/adoftgggg/Oliv_Maintenance/releases/latest

Outil de maintenance Windows (PowerShell 5.1 + WPF) livré en un seul fichier `Oliv_Maintenance.cmd`
(polyglotte CMD / PowerShell). Le livrable est **assemblé** à partir des sources de `src\` : on ne modifie jamais
le `.cmd` à la main.

## Arborescence

```
lancer.ps1           lancement en une commande (irm ... | iex) : dernière version publiée, SHA-256 vérifié
build.ps1            assemblage + contrôles + tests -> dist\Oliv_Maintenance.cmd et dist\Oliv_Maintenance_<version>.exe
VERSION              version courante (x.y.z)
src\NN-nom.ps1       sources, concaténées dans l'ordre du préfixe NN
launcher\Lanceur.cs  lanceur exe (C# 5) : script embarqué compressé, manifeste requireAdministrator
native\*.cs          code natif (C# 5) : compilé en une DLL embarquée dans le script, chargée en mémoire
tests\Run-Tests.ps1  tests unitaires (sans dépendance, Pester non requis)
tools\               certificat interne de signature de code (création, installation sur les postes)
dist\                livrable généré (non versionné)
```

## Construire

Windows PowerShell 5.1, sans droits administrateur :

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\build.ps1                    # version du fichier VERSION
powershell -NoProfile -ExecutionPolicy Bypass -File .\build.ps1 -Version 0.100.1   # nouvelle version
```

Résultat attendu : `NN/NN tests réussis` puis une ligne verte avec la version, le nombre de sources et le chemin du
livrable. Toute erreur bloque l'écriture du livrable (rien n'est produit à moitié).

Contrôles faits à chaque construction :

- syntaxe PowerShell du script principal **et** de chaque script embarqué (here-strings `@'…'@` exécutés dans les runspaces) ;
- XAML bien formé ;
- caractères interdits : tout caractère BMP au-delà de U+07FF (3 octets en UTF-8) et U+2010–U+201F
  (Invoke-Expression relit le fichier ; ces caractères s'écrivent en `[char]0x…` dans le code) ;
- sources en UTF-8 **sans BOM** ; livrable en UTF-8 sans BOM, fins de ligne CRLF ;
- `[math]::Min` / `[math]::Max` avec un entier littéral et une valeur décimale : refusés (PowerShell choisit alors la
  surcharge Int32 : `[math]::Max(0, 3.7)` vaut 4, `[math]::Min(1, 0.3)` vaut 0, au-delà de 2 Go la conversion échoue).
  Écrire `[math]::Max([double]0, $x)`.
- analyse statique **PSScriptAnalyzer** (règles et exclusions justifiées dans `tools\PSScriptAnalyzerSettings.psd1`),
  bloquante si le module est installé : verbes approuvés, noms au singulier, casse des commandes, pas d'alias, chaînes
  constantes entre apostrophes, comparaisons à `$null` du bon côté… Activation (PowerShell, utilisateur standard,
  accès à PowerShell Gallery) : `Install-Module PSScriptAnalyzer -Scope CurrentUser`, puis vérifier avec
  `Get-Module -ListAvailable PSScriptAnalyzer`. `-SkipLint` pour s'en passer ponctuellement.

## Lanceur Oliv_Maintenance_<version>.exe

Produit par `build.ps1` sous Windows PowerShell 5.1 (compilateur C# du .NET Framework 4.x, aucune installation). Hors
Windows, il est produit si Mono (`mcs`) et `x86_64-w64-mingw32-windres` sont présents ; sinon seule la syntaxe est contrôlée.

Au lancement : élévation UAC (manifeste), mise en conformité des droits de `C:\ProgramData\Oliv_Maintenance` (voir ci-dessous),
écriture du script dans `C:\ProgramData\Oliv_Maintenance\App\Oliv_Maintenance.ps1` (dossier vidé à chaque lancement), puis
exécution par `powershell.exe` 64 bits en STA sans console, comme le `.cmd`. Le `.cmd` reste utilisable tel quel.

### Signature de l'exe (certificat interne Oliv)

Une seule fois, sur le poste de construction (Windows PowerShell 5.1, sans droits admin) :
`powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\New-CertificatSignature.ps1`. Résultat : certificat dans
`Cert:\CurrentUser\My`, `Oliv_Maintenance_SignatureCode.cer` (public) et `Oliv_Maintenance_SignatureCode.pfx` (clé privée : coffre de mots de
passe puis suppression du disque ; jamais versionné, voir `.gitignore`).

Postes clients : `tools\Install-CertificatSignature.ps1` + `Oliv_Maintenance_SignatureCode.cer` en administrateur, ou par GPO
(Configuration ordinateur > Stratégies > Paramètres Windows > Paramètres de sécurité > Stratégies de clés publiques :
« Autorités de certification racines de confiance » et « Éditeurs approuvés »).

Signature : automatique à chaque `build.ps1` sous Windows si le certificat est présent ; exe construit ailleurs :
`.\build.ps1 -SignOnly`. Horodatage DigiCert (signature valable après l'expiration du certificat), contrôle `Valid` bloquant.
Vérification (PowerShell) : `Get-AuthenticodeSignature .\dist\Oliv_Maintenance_<version>.exe | Format-List Status, SignerCertificate`.

## Droits de C:\ProgramData\Oliv_Maintenance

Hérités de ProgramData, ils laissent tout utilisateur standard créer des fichiers dans les sous-dossiers. Le lanceur et
l'application (`Protect-AppDir`, `src\00-entree.ps1`) les remplacent : héritage coupé, propriétaire Administrateurs,
Administrateurs et SYSTEM en contrôle total, Utilisateurs en lecture et exécution ; sous-dossiers remis en héritage seul,
ancien cache de code natif supprimé. Contrôle à chaque ouverture (quelques millisecondes), correction une seule fois par
poste. Si la correction échoue : le lanceur refuse de démarrer, l'application le signale dans le Journal (WARN).

Vérification (CMD, sans droits administrateur) : `icacls C:\ProgramData\Oliv_Maintenance` doit afficher uniquement
`BUILTIN\Administrateurs:(OI)(CI)(F)`, `AUTORITE NT\Système:(OI)(CI)(F)` et `BUILTIN\Utilisateurs:(OI)(CI)(RX)`.

## Tests

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-Tests.ps1
```

Les fonctions testées sont extraites de `src\` par leur nom (y compris dans les scripts embarqués) et chargées
seules : aucune fenêtre, aucune modification du poste. Code de sortie 0 = tout passe.
Toute fonction de calcul ajoutée (comparaison, format, analyse de texte) doit avoir ses cas dans ce fichier.

## Organisation des sources

Le script est exécuté d'un bloc, dans l'ordre des fichiers. Une fonction peut être définie n'importe où avant son
**premier appel au chargement** ; le code exécuté directement (hors fonctions) doit rester après ce dont il dépend.

| Fichiers | Rôle |
|---|---|
| `00`–`04` | entrée polyglotte, élévation, code natif C# mis en cache, journaux, contexte utilisateur, registre / GPO |
| `10`–`11` | catalogue des réglages et des tâches, moteur de nettoyage |
| `20` | script des tâches longues (runspace « worker ») |
| `30`–`32` | XAML principal, chargement de la fenêtre, briques d'interface (cartes, lignes, boutons, jauges) |
| `40` | réglages : lecture / écriture, mise en attente, applications au démarrage |
| `49`–`53` | tâches d'arrière-plan, collecte d'informations, Windows Update, constructeur, diagnostic |
| `60`–`63` | placement / zoom des fenêtres, animations, boîtes de dialogue, notifications Windows de fin de tâche |
| `70`–`74` | pages : Accueil (moniteur d'activité, stockage), Nettoyage, Réparation, pages chargées à la demande, filtre du Journal |
| `80`–`89` | navigation, Paramètres, espace disque, exécution des tâches, mise en page adaptative, recherche globale, événements et raccourcis clavier, logiciels, rapport d'intervention |
| `90`–`99` | minuteur principal, fermeture / réinitialisation, démarrage |

Fonctionnement à l'exécution :

- **Runspaces** (`49-arriere-plan.ps1`) : chaque collecte ou tâche s'exécute dans son propre runspace, partagé avec
  l'interface par la table synchronisée `$sync`. Des runspaces de réserve sont ouverts à l'avance hors fil d'interface
  (4 au démarrage, 2 ensuite) : une collecte démarre sans les 100 à 300 ms d'ouverture. Relancer une collecte de même clé
  arrête et libère la précédente ; à la fin, l'état « en cours » est remis à zéro par `$BgJobDone`.
- **Minuteur** (`90-minuteur.ps1`, 250 ms) : seul point de passage des runspaces vers l'affichage, en étapes
  indépendantes (`Invoke-TickStep`) : une étape en erreur n'arrête pas les suivantes et son erreur est journalisée une
  seule fois (niveau WARN, préfixe « Rafraîchissement »).
- **Code natif** (`native\*.cs`, chargé par `01-natif.ps1`) : compilé par `build.ps1` (CodeDom sous Windows, mcs sous
  Mono) en une DLL embarquée compressée dans le script (`$NativeDll`) et chargée en mémoire au démarrage. Aucune
  compilation C# sur le poste (l'application n'étant ouverte que quelques fois par an, chaque ouverture était une première
  ouverture après mise à jour), aucun fichier DLL sur le disque. Les tests vérifient que chaque type `[_OlivM.*]` utilisé
  par les sources existe dans la DLL.
- **Erreurs non bloquantes** : `Write-Ignored 'Sujet' $_` (interface et runspaces) journalise en WARN une seule fois par
  sujet et par message, au lieu d'un `catch {}` muet. Les `catch {}` restants sont volontaires : libération de ressources,
  sources d'information facultatives (WMI absent sur l'édition, pas de batterie), valeur de repli prévue.
- **Démarrage** : détections matérielles des réglages, applications installées, navigateurs et éléments absents du nettoyage lus en arrière-plan ; rien de bloquant avant l'affichage de la fenêtre.
- **Réactivité et légèreté** : aucune attente sur le fil d'interface (pas de `Start-Sleep`, de requête WMI / Appx ni
  d'arrêt synchrone de runspace dans un gestionnaire : minuteur ou runspace) ; les rafraîchissements périodiques ne
  réécrivent que ce qui a changé (signatures : Accueil, avancement constructeur comme Windows Update) ; fenêtre réduite :
  minuteur principal à 1 passage par seconde ; collecte des volumes toutes les 5 s sur l'Accueil, 30 s ailleurs ;
  runspaces de réserve limités (3 au démarrage, 1 ensuite).
- **Journal** (`74-journal.ps1`) : compteurs mis à jour à chaque ligne reçue (aucune relecture complète par tick),
  affichage différé tant que l'onglet n'est pas visible, 3 000 lignes affichées au plus (fichier journal complet).

## Conventions

- Fonctions : `Verbe-Nom` avec un verbe approuvé (`Get-Verb`) et un nom **au singulier**, même quand elles renvoient
  une liste (`Get-SoftUpdate`, `Add-SoftRow`) ; préfixe de domaine dans le nom (`Soft`, `Tree`, `Wu`, `Oem`, `Clean`,
  `Log`, `Info`…). Affichage d'une zone : `Show-…` (construction) / `Update-…` (rafraîchissement).
- Variables : état partagé de niveau script en **PascalCase** (`$Sync`, `$Ui`, `$Window`, `$Timer`, `$SoftUI`…),
  paramètres de fonction en PascalCase, variables locales en minuscules (`$i`, `$row`, `$tg`) ; gestionnaires
  d'événements WPF : `param($s, $e)`.
- Une instruction par ligne pour les suites d'instructions longues ; les instructions courtes et liées peuvent rester
  sur une ligne, séparées par `;`.
- Erreurs non bloquantes : `Write-Ignored 'Sujet' $_` (journal, une seule fois par sujet) ; `catch {}` vide réservé aux
  libérations de ressources et aux lectures facultatives qui ont une valeur par défaut.
- PowerShell 5.1 uniquement (pas de syntaxe PowerShell 7) ; variables insensibles à la casse : ne jamais réutiliser
  `$A` / `$a` dans une même fonction.
- `@()` autour de tout résultat dont on lit `.Count`.
- Interface : polices 20 (titre de page) / 16 (titre de carte) / 15 (titre de dialogue) / 14 / 13 (texte) / 12 / 11 ;
  lignes de 40 px ; boutons de dialogue : actions à gauche (gris, rouge si irréversible), annulation à droite en bleu.
- Animations : `Start-Transition` uniquement (opacité + transformation, jamais de hauteur animée) ; les minuteurs
  sautent leur passage pendant un effet (`Test-AnimBusy`).
- Avancement des recherches : étapes réelles publiées par `Set-JobStep` dans le script d'arrière-plan, jamais
  d'estimation au temps.
- Libellés en français, vocabulaire « application » (pas « outil ») dans l'interface.

## Raccourcis clavier

Ctrl+1 à Ctrl+5 : onglets · F5 : actualiser la page affichée · Ctrl+Entrée : appliquer la sélection · Ctrl+F : recherche globale ·
Ctrl+molette, Ctrl+ / Ctrl- / Ctrl+0 : taille de l'interface, ou du texte du Journal quand la souris est sur la zone
du journal · Échap : fermer la recherche, vider un filtre.
