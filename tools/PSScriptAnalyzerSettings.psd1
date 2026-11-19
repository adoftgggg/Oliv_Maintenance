# Règles d'analyse statique (PSScriptAnalyzer) appliquées par build.ps1 aux sources (src\*.ps1).
# Règles par défaut de PSScriptAnalyzer, plus la casse des commandes et les chaînes constantes entre apostrophes.
# Exclusions justifiées par l'architecture de l'application :
#   PSUseShouldProcessForStateChangingFunctions : application graphique, chaque action est confirmée par une boîte de
#       dialogue ; -WhatIf / -Confirm n'ont pas de sens pour des fonctions appelées par l'interface.
#   PSUseBOMForUnicodeEncodedFile : les sources sont assemblées en un seul .cmd UTF-8 sans BOM (BOM interdit par build.ps1).
#   PSUseDeclaredVarsMoreThanAssignments : variables partagées entre fichiers assemblés (fausses alertes par fichier).
#   PSReviewUnusedParameter : gestionnaires d'événements WPF, signature imposée param($s, $e).
#   PSAvoidUsingEmptyCatchBlock : catch vide réservé aux libérations de ressources et aux lectures facultatives avec valeur
#       par défaut ; toute autre erreur passe par Write-Ignored (journal, une fois par sujet).
#   PSAvoidUsingPositionalParameters : fonctions internes appelées par position (information).
# Le lanceur 00-entree.ps1 (bloc de démarrage du .cmd, avant l'interface) peut seul utiliser Write-Host, une variable
# globale et Invoke-Expression : filtré dans build.ps1.
@{
    Severity     = @('Error', 'Warning', 'Information')
    ExcludeRules = @(
        'PSUseShouldProcessForStateChangingFunctions'
        'PSUseBOMForUnicodeEncodedFile'
        'PSUseDeclaredVarsMoreThanAssignments'
        'PSReviewUnusedParameter'
        'PSAvoidUsingEmptyCatchBlock'
        'PSAvoidUsingPositionalParameters'
    )
    Rules        = @{
        PSUseCorrectCasing                        = @{ Enable = $true }
        PSAvoidUsingDoubleQuotesForConstantString = @{ Enable = $true }
    }
}
