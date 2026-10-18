# Contribuer à PiHub

[Accueil](README.md) · [Manuel](docs/README.md) · [Développement](docs/DEVELOPMENT.md)

Merci de proposer des améliorations qui restent compréhensibles, vérifiables et simples à distribuer.

## Préparer le projet

```sh
make check
make test
make manager-build
```

Le manager cible macOS 13+ sur Apple Silicon. Le backend utilise Python 3.9+ et sa bibliothèque standard. Les moteurs et agents tiers ont leurs propres prérequis.

## Ajouter une intégration

Une contribution moteur/agent est un dossier (le contrat JSON conserve `kind: "provider"`) :

```text
pihub-manager/integrations/mon-integration/
├── manifest.json
├── handler.py
└── ...ressources éventuelles...
```

Le manifeste décrit les champs, la commande, les hooks et le bloc d’installation optionnel. Les instances et données personnelles restent dans `.pihub/`.

Commencez par le [guide de modding](docs/EXTENSIONS.md), la [référence du manifeste](docs/MANIFEST_REFERENCE.md) et les [exemples importables](docs/examples/README.md).

Précisez dans votre contribution :

- le programme pris en charge et ses versions de référence ;
- les prérequis de machine et de runtime ;
- les formats de modèles et protocoles réellement acceptés ;
- les actions implémentées et les limites connues ;
- la vérification réalisée et les étapes pour la reproduire.

N’annoncez pas de changement de modèle à chaud si votre action écrit seulement un fichier destiné au prochain lancement. Ne proposez pas une action de cycle de vie qui n’a pas d’implémentation réelle.

## Recettes et code Python

Utilisez une version précise, un commit ou une archive à empreinte vérifiée. Le champ informatif `commit` ne remplace pas des étapes qui récupèrent réellement la référence voulue.

Évitez les chemins de compte codés en dur. Les paramètres variables doivent venir du manifeste ou du contexte. Les commandes sont des tableaux d’arguments ; les scripts d’installation doivent être fournis et fonctionner sans interaction.

Les opérations de suivi doivent être courtes et ne pas modifier l’état du runtime. Les arrêts doivent cibler des processus identifiés, jamais tous les programmes portant un nom.

## Vérifier avant une proposition de changement

- Exécuter les contrôles appropriés à la modification.
- Tester les erreurs utiles : programme absent, port occupé, API inaccessible et paramètres incomplets.
- Pour une intégration, exporter le dossier puis réimporter cet export dans un workspace isolé.
- Mettre à jour les pages du manuel concernées.
- Décrire le problème, le comportement obtenu et le périmètre réel de vérification.

Le [guide développement](docs/DEVELOPMENT.md) précise les emplacements des composants, la CI et les conventions du backend.

## Signaler un problème

Le modèle de [rapport de bug](.github/ISSUE_TEMPLATE/bug_report.md) et celui de [proposition d’intégration](.github/ISSUE_TEMPLATE/integration.md) indiquent les informations utiles.

Incluez la version de macOS, l’intégration, la version de son runtime, l’action concernée et les logs nécessaires. Retirez les secrets et le contenu privé des sessions.

## Préparer des sources à publier

`make package-source` prépare une archive à partir des sources autorisées. Les poids, installations, sessions et données locales ne font pas partie d’une contribution.

Choisissez et documentez la licence applicable avant publication. Les logiciels tiers et les contributions intégrées conservent leurs propres conditions de licence.
