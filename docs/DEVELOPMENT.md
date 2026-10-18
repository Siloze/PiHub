# 09 · Développer, tester et publier

[Manuel](README.md) · [Précédent : architecture](ARCHITECTURE.md) · [Suivant : dépannage](TROUBLESHOOTING.md)

## Installer l’environnement de développement

Suivez le [chapitre installation](INSTALLATION.md). Le backend ne nécessite pas de venv ni de dépendance Python tierce.

```sh
make check
make test
make manager-build
```

Pour ouvrir puis recharger vos changements :

```sh
make manager-open
make manager-reload
```

## Choisir le bon emplacement pour une modification

| Changement | Emplacement |
| --- | --- |
| Ajouter un moteur ou un agent | `pihub-manager/integrations/<id>/`. Le manifeste conserve `kind: "provider"` pour un moteur. |
| Paramètre ou action spécifique | Manifeste et handler de cette intégration. |
| Type de contrôle générique | `HubField` dans `HubModels.swift`, rendu dans `HubEditors.swift`, validation et schéma. |
| Menu d’actions | `swift/IntegrationActions.swift`. |
| Éditeur de définition/import | `swift/ManifestEditor.swift`. |
| Explorateur | `swift/HubCatalog.swift` et `hub/catalog.py`. |
| Import/export de dossiers | `hub/bundles.py` et `hub/customization.py`. |
| Politique de modèle liée aux agents | Handler de l’agent ; planner générique dans `model_changes.py`. |
| Transport ou action de workspace | `hub/service.py` et `hub/__main__.py`. |
| Nouvelle mesure | `hub/telemetry.py` ou statut mesuré du handler. |

Un nouveau programme n’a normalement pas besoin d’une branche portant son nom dans le manager. Décrivez ses paramètres et déclarez ses hooks.

## Développer sans toucher à son workspace habituel

Les dossiers personnels de développement doivent être séparés si vous testez des imports, suppressions ou installations.

```sh
PIHUB_DATA="$PWD/.pihub-dev" \
  ./PiHubManager.app/Contents/MacOS/PiHubManager --window
```

Lancez un processus du manager qui reçoit réellement cet environnement. Une application déjà ouverte avec un autre environnement peut continuer à utiliser son ancien workspace.

Pour un test backend isolé, utilisez de préférence un dossier temporaire comme le fait la suite de tests. Ne pointez pas un test destructif vers vos données habituelles.

## API de gestion interne

Le frontend parle au backend via JSON. Depuis la racine :

```sh
printf '%s' '{"action":"snapshot"}' | \
  PYTHONPATH=pihub-manager/src /usr/bin/python3 -m pihub_manager.hub
```

Réponse :

```json
{
  "ok": true,
  "data": {}
}
```

Le contenu de `data` dépend de l’action. En cas d’erreur, `ok` vaut `false` et `error` contient le message. Les handlers ne doivent pas polluer la sortie standard du transport avec du texte de debug ; utilisez les journaux ou une exception exploitable.

Cette API sert à l’intégration et au diagnostic. Le parcours normal des opérations de moteurs, agents et modèles reste l’interface.

## Vérifier un plugin

Le contrôle des [exemples pédagogiques](examples/README.md) importe deux dossiers dans un workspace temporaire, démarre le serveur de démo, exécute l’agent une fois puis arrête le serveur :

```sh
PYTHONPATH=pihub-manager/src /usr/bin/python3 docs/examples/check_examples.py
```

Il n’ouvre pas Terminal ni l’application et ne télécharge pas de modèle.

La suite du projet couvre notamment les imports de dossiers, l’export réimportable, les installations de fixtures, les politiques de modèle, les ports et l’identité des processus. Elle utilise des dossiers temporaires et des programmes légers.

Pour un runtime réel, documentez séparément ce qui a été exercé : version exacte, prérequis, configuration et limites. Ne déduisez pas une certification de tous les moteurs du seul succès de `make test`.

## Contribuer une intégration

Un dossier de contribution doit contenir :

- un manifeste avec un ID stable, des valeurs par défaut raisonnables et des hooks réellement disponibles ;
- le code Python référencé et ses ressources ;
- une recette optionnelle précisément versionnée ;
- des indications sur les prérequis, le format des modèles et les limites ;
- une méthode de vérification reproductible.

Testez les chemins comportant des espaces, l’absence d’exécutable, une erreur de connexion et une tentative de lancement avec des réglages incomplets.

L’interface ne doit pas afficher un bouton prétendant une action que le runtime ne réalise pas. Préférez un hook absent ou un message précis à une opération factice.

## Préparer le dépôt GitHub

Sur une machine qui contient déjà des usages privés, créez d’abord :

```sh
make package-source
```

L’archive se trouve dans `.pihub/exports/PiHub-source.tar.gz`. Elle est composée à partir de la liste explicite dans `release.py` et inclut la documentation et ses exemples.

Décompressez-la dans un nouveau dossier destiné à la publication. Vérifiez sa liste de fichiers, puis initialisez votre dépôt depuis cette copie source.

À renseigner avant de publier :

1. Le nom du dépôt et son URL réelle dans vos annonces.
2. La licence du code dont vous êtes titulaire : aucune licence de projet n’est choisie automatiquement par le manager.
3. Les éventuelles mentions et licences des contributions intégrées.
4. Les versions réellement vérifiées et le périmètre de vos tests.

Les logiciels tiers conservent leurs licences. La présence d’une recette d’installation ne transfère pas leurs droits au projet PiHub.

## Ce qui ne doit pas accompagner les sources

`.pihub/`, les homes d’agents, les clés, les sessions, les caches, les poids et les installations de moteurs sont exclus de l’archive source. Vos dossiers locaux supplémentaires ne sont pas automatiquement une partie publiable du projet.

Un `.gitignore` ne retire pas des fichiers déjà suivis par Git. Relisez les fichiers effectivement ajoutés à un commit.

## Intégration continue

La configuration [CI](../.github/workflows/ci.yml) exécute les tests backend et une construction native sur macOS. Elle peut produire l’application comme artefact de build.

Les tests et la CI du manager n’installent pas l’ensemble des moteurs tiers ni leurs modèles.

[Suivant : dépannage →](TROUBLESHOOTING.md)
