# 10 · Dépannage

[Manuel](README.md) · [Précédent : développement](DEVELOPMENT.md) · [Accueil](../README.md)

## Par où commencer

1. Identifiez l’instance et l’opération en cause.
2. Ouvrez **Configurer → Diagnostic**.
3. Consultez l’exécutable détecté, la commande et les journaux.
4. Si le problème est une installation, utilisez le journal du job dans l’Explorateur.
5. Pour un état global, lancez `make manager-status`.

Les logs peuvent contenir des chemins locaux ou du contenu de session. Relisez-les avant de les joindre à une issue.

## Installation et interface

| Symptôme | Vérification ou action |
| --- | --- |
| `swiftc` introuvable | Installer les outils Apple, attendre la fin, puis `make check`. |
| Mauvaise architecture | Le build actuel cible Apple Silicon `arm64`. |
| L’application n’apparaît pas comme fenêtre | Elle s’ouvre dans la barre des menus. Cliquer sur son icône ou utiliser `open PiHubManager.app --args --window`. |
| Mes changements Swift ne sont pas visibles | Reconstruire et relancer avec `make manager-reload`. |
| Le backend embarqué semble ancien | Reconstruire l’application : les sources Python sont copiées pendant le build. |
| Projet déplacé, intégrations absentes | Garder l’application à côté du projet ou vérifier `PIHUB_ROOT`. |
| Workspace vide au premier lancement | Comportement attendu : ajouter les premières instances dans l’Explorateur. |

## Importer un dossier

| Symptôme | Vérification ou action |
| --- | --- |
| L’intégration n’apparaît pas | Vérifier `.pihub/integrations/<id>/manifest.json` et la validité du JSON. |
| Dossier reconnu comme archive sans contenu | Décompresser et sélectionner le dossier qui contient directement `manifest.json`. |
| Erreur de handler | Vérifier le fichier relatif et le nom de fonction après `:`. |
| Import Python voisin en échec | Utiliser un import relatif, par exemple `from .helper import fonction`. |
| Une intégration livrée a changé de comportement | Chercher une copie personnelle portant le même `id`. |
| Une action n’a pas de bouton | Vérifier sa déclaration dans `handlers`, sa fonction et les éventuelles métadonnées `primary_actions`. |

Les erreurs de définition et de capacité apparaissent aussi dans les sections `registry_errors` et `catalog.errors` du diagnostic JSON.

## Exécutable, lancement et arrêt

**« Runtime absent »** : choisir le programme dans **Avancé → Chemin de l’exécutable**, vérifier ses permissions ou installer le runtime depuis l’Explorateur.

Le champ doit contenir un programme comme `/chemin/bin/serveur`, pas `serveur --port 18100`. Les arguments appartiennent à la commande du manifeste ou au tableau JSON `extra_args`.

**« Port déjà utilisé »** : contrôler le port de toutes les instances et celui des programmes lancés à l’extérieur. Deux configurations enregistrées avec un port identique peuvent se heurter, même si leurs noms diffèrent.

**Le programme quitte immédiatement** : lire le journal. Un interpréteur valide peut échouer à charger un module ou recevoir un flag non pris en charge par sa version.

**La relance d’un processus externe n’est pas proposée** : l’intégration ne sait peut-être pas identifier précisément le processus. Utiliser son propre outil de cycle de vie au lieu d’essayer de forcer la propriété du PID.

**Le provider continue après fermeture du manager** : quitter l’interface n’est pas un arrêt de tous les runtimes. L’arrêter via son instance si souhaité.

## API et authentification

**HTTP 404** : contrôler l’URL de base et le chemin attendu. Un serveur peut exposer `/v1/models` sans accepter l’API de génération utilisée par l’agent, ou l’inverse.

**Variable de clé introuvable** : le champ contient le nom de variable, et le processus PiHub doit la recevoir dans son environnement. Une app déjà ouverte depuis Finder n’hérite pas automatiquement d’un nouvel `export` dans Terminal.

**API prête mais agent en échec** : contrôler le protocole, le modèle, les outils et le format des réponses. Le statut de santé n’est pas un test complet de conversation.

## Modèles

| Symptôme | Vérification |
| --- | --- |
| Mon GGUF n’apparaît pas | Dossiers de scan, extension, rescan, ou ajout manuel de son chemin. |
| Mon dossier MLX n’est pas découvert | Le scanner reconnaît surtout la structure de cache Hugging Face documentée ; ajouter une référence manuelle si nécessaire. |
| Modèle introuvable côté API | Utiliser l’identifiant exact attendu par le serveur, pas uniquement le nom d’affichage PiHub. |
| Modèle incompatible | Vérifier format, architecture et prise en charge du runtime. |
| Le modèle actif reste ancien | Enregistrer ne suffit pas : charger ou relancer le provider puis appliquer la proposition aux agents. |
| Un agent ne suit pas le provider | Vérifier si son champ modèle est fixé explicitement. |
| Mémoire insuffisante | Ajuster le modèle et les paramètres dans le moteur ; PiHub ne rend pas les allocations illimitées. |

## Hermes et Pi

**Gateway Hermes** : lancer l’action dédiée dans les diagnostics de l’instance PiHub. Le gateway hôte partagé est piloté depuis son profil propriétaire ; lancer directement une commande gateway sous un profil nommé peut être refusé par Hermes. Vérifier aussi les plateformes configurées et le journal `gateway.error.log` du home Hermes.

**Dashboard Hermes en démarrage** : le premier usage peut construire le frontend. Lire son journal avant de relancer.

**Le tutoriel ne s’ouvre pas** : le hook `after_install` n’est actuellement appelé que lorsque `save` crée une nouvelle instance. Il n’est pas un callback universel d’installation. Une instance déjà créée doit accéder aux actions par son interface.

**Outil Pi ajouté mais indisponible** : le nom saisi n’installe pas une extension ou un serveur MCP. Vérifier ce que le runtime Pi charge réellement.

## Rassembler un rapport utile

Indiquez la version de macOS, l’architecture, l’intégration, sa révision, le nom de l’action, le message exact et les extraits de logs nécessaires.

Pour une intégration personnelle, joignez un exemple minimal du manifeste et du handler sans clés ni sessions. Précisez si le runtime vient de l’Explorateur ou d’une installation extérieure.

Les modèles de [bug](../.github/ISSUE_TEMPLATE/bug_report.md) et de [proposition d’intégration](../.github/ISSUE_TEMPLATE/integration.md) sont disponibles dans le dépôt.

[Retour au manuel →](README.md)
