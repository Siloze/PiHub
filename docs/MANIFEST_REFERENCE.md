# 06 · Référence du manifeste et des handlers

[Manuel](README.md) · [Précédent : modding](EXTENSIONS.md) · [Suivant : recettes d’installation](CATALOG.md)

> L’interface PiHub parle de **moteurs**. Cette référence conserve `provider` lorsqu’il s’agit d’une valeur, d’une clé JSON, d’une fonction ou d’un chemin Python du contrat public.

Cette référence décrit le contrat lu par le code actuel. Consultez aussi le [schéma JSON](manifest.schema.json), le [schéma de `install`](catalog.schema.json) et les [manifestes livrés](../pihub-manager/integrations/).

## Emplacement et identité

```text
pihub-manager/integrations/<id>/manifest.json   intégration livrée
.pihub/integrations/<id>/manifest.json          intégration personnelle prioritaire
```

| Propriété | Type | Rôle |
| --- | --- | --- |
| `api_version` | entier | Version du contrat ; `1` actuellement. |
| `id` | chaîne | Identifiant stable : lettres ASCII, chiffres, tirets et underscores ; 1 à 80 caractères. |
| `kind` | chaîne | `provider` ou `agent`. |
| `name` | chaîne | Nom affiché. |
| `description` | chaîne | Présentation courte. |
| `icon` | chaîne | Nom d’un symbole système macOS utilisé par l’interface. |
| `color` | chaîne | Palette prévue : `violet`, `cyan`, `orange`, `mint`, `blue`. |

La découverte fournit des valeurs de présentation par défaut pour certains champs absents. Pour un dossier importable et lisible, renseignez explicitement l’identité complète.

Ne confondez pas `id` d’intégration et `id` d’instance. Une instance référence l’intégration par sa propriété `adapter`.

## Formulaire : fields

```json
{
  "fields": [
    {
      "key": "context",
      "label": "Contexte",
      "group": "Performance",
      "type": "slider",
      "default": "8192",
      "min": 1024,
      "max": 131072,
      "step": 1024
    }
  ]
}
```

Tous les champs possèdent `key`, `label`, `group`, `type` et `default`. **Les valeurs enregistrées dans `settings` sont des chaînes**, y compris les nombres et les booléens.

| Type | Interface et validation | Métadonnées utiles |
| --- | --- | --- |
| `text` | Saisie libre. | `default`. |
| `number` | Saisie avec validation numérique à l’enregistrement. | `min`, `max`. |
| `slider` | Curseur et valeur. | `min`, `max`, `step`. |
| `select` | Un choix dans une liste. | `options`, liste de chaînes. |
| `multi_select` | Plusieurs propositions et ajout libre. Valeur CSV. | `options`, `option_help`. |
| `toggle` | Interrupteur. | Valeurs `"true"` ou `"false"`. |
| `model` | Identifiant saisi ou choisi dans le catalogue. | Filtrage selon `model_format`. |
| `provider` | Sélection d’une instance de moteur. | Contrat `routing`. |
| `file` | Chemin et sélection de fichier. | Utilisé notamment pour l’exécutable. |
| `directory` | Chemin et sélection de dossier. | Utilisé notamment pour `project`. |

Les groupes organisent les sections du formulaire. `Intégration` et `Diagnostic` sont ajoutés par l’éditeur d’instance.

### Liste multi_select

```json
{
  "key": "tools",
  "label": "Outils actifs",
  "group": "Session",
  "type": "multi_select",
  "default": "read,write",
  "options": ["read", "write", "grep"],
  "option_help": {
    "read": "Lire un fichier",
    "write": "Écrire un fichier",
    "grep": "Rechercher dans les fichiers"
  }
}
```

Le résultat reste une chaîne comme `read,write,outil-personnel`. Le widget ne vérifie pas qu’un outil ajouté librement existe dans le runtime. Votre commande ou handler doit transmettre et interpréter cette valeur.

### Réglages reconnus par les helpers

| Clé conventionnelle | Utilisation |
| --- | --- |
| `executable` | Chemin personnalisé prioritaire pour cette instance. |
| `extra_args` | Tableau JSON de chaînes ajouté à la fin de la commande. |
| `project` | Dossier de travail des helpers d’agents ; la racine du projet par défaut. |
| `host`, `port` | Construction de l’endpoint et contrôle de port des moteurs communs. |
| `base_url` | URL explicite prioritaire sur host/port. |
| `key_env` | Nom d’une variable contenant le secret d’API. |

Déclarez dans `fields` chaque réglage que vos instances doivent enregistrer. Les réglages inconnus du manifeste sont refusés lors de la validation d’une instance.

## Programme, commande et environnement

| Propriété | Rôle |
| --- | --- |
| `executables` | Liste ordonnée de noms ou chemins de programmes candidats. |
| `command` | Tableau d’arguments ; le premier élément est généralement `{executable}`. |
| `env` | Variables d’environnement du runtime, valeurs sous forme de chaînes. |
| `flags` | Arguments ajoutés selon une valeur de réglage. |

L’exécutable personnalisé d’une instance remplace la liste de candidats. Les candidats acceptent les noms résolus dans `PATH`, des chemins et des motifs de fichiers. Leur expansion reconnaît `{root}` et `{home}`.

Pour exécuter un script inclus dans le dossier :

```json
{
  "executables": ["/usr/bin/python3"],
  "command": ["{executable}", "{bundle}/programme.py", "--port", "{port}"]
}
```

N’utilisez pas `{bundle}` comme candidat dans `executables` : sa résolution comme programme est distincte de l’expansion des arguments.

### Variables de la commande et de env

| Variable | Valeur |
| --- | --- |
| `{root}` | Racine du projet PiHub. |
| `{home}` | Home utilisateur. |
| `{bundle}` | Dossier du manifeste chargé. |
| `{executable}` | Programme effectivement résolu. |
| `{nom-de-champ}` | Valeur du champ correspondant après fusion des valeurs par défaut et des réglages. |

`{package}` est réservé au contexte d’installation, pas à une commande de runtime ordinaire.

Les commandes sont exécutées comme tableaux d’arguments. `&&`, les redirections et les substitutions shell ne sont pas interprétées comme un script. Si une opération exige un script, fournissez ce script et appelez son interpréteur explicitement.

Les accolades littérales d’un argument traité par le formatage Python doivent être échappées avec `{{` et `}}`.

### Flags conditionnels

```json
{
  "flags": {
    "offline": {"true": ["--offline"]},
    "mode": {"fast": ["--fast"], "normal": []}
  }
}
```

La valeur comparée est convertie en minuscules. `extra_args`, s’il est déclaré et renseigné, doit être un tableau JSON, par exemple `["--seed", "42"]`.

## Métadonnées de moteur (`provider` dans le contrat)

| Propriété | Usage |
| --- | --- |
| `model_format` | Filtre de catalogue : `mlx`, `gguf`, `ollama` ou `any`. Ce filtre n’est pas un test de compatibilité moteur. |
| `model_field` | Nom du réglage modèle ; `model` par défaut pour les opérations qui le consultent. |
| `requires_model` | Les helpers de démarrage exigent un modèle par défaut ; `false` lève cette exigence. |
| `health` | Route de santé utilisée par le helper HTTP. |
| `external` | Indique un endpoint externe à l’interface. |
| `multi_model` | Le planner peut considérer le modèle cible présent s’il figure dans `models`. |
| `process_signatures` | Fragments de commande pour aider le statut commun à identifier un runtime local. |
| `port_in_environment` | Option de détection pour certains runtimes dont le port n’est pas dans argv. |
| `server_key_env` | Variable dans laquelle le helper de démarrage peut transmettre la clé au serveur. |

Ces propriétés ne créent aucune action automatiquement. Les capacités viennent des handlers déclarés.

## Routage des agents

```json
{
  "routing": {
    "provider_field": "provider",
    "model_field": "model",
    "required": true,
    "unbound_value": "native",
    "unbound_label": "Compte natif"
  }
}
```

| Clé | Rôle |
| --- | --- |
| `provider_field` | Réglage contenant l’ID du moteur sélectionné. |
| `model_field` | Réglage modèle de l’agent. |
| `required` | Exige un moteur dans les helpers de résolution. |
| `unbound_value` / `unbound_label` | Choix permettant une configuration native lorsque l’intégration le prend en charge. |

Le handler de l’agent doit traduire le résultat en flags, variables, fichiers ou appels SDK réellement compris par son programme.

## Référencer les handlers

```json
{
  "handlers": {
    "status": "handler.py:status",
    "terminal": "handler.py:terminal",
    "inspect-config": "handler.py:inspect_config"
  },
  "action_labels": {"inspect-config": "Inspecter la configuration"}
}
```

Les références sont relatives au manifeste, sous la forme `fichier.py:fonction`. Les fonctions de helpers PiHub peuvent aussi être référencées par un nom de module installé. Les anciens modules spécifiques de compatibilité ont été retirés : utilisez les fichiers des dossiers ou les helpers communs.

Un handler peut importer un module voisin avec `from .helper import fonction`. Les modules sont mis en cache par chemin et date de modification du fichier principal dans le processus de backend.

### Signature commune

```python
def mon_action(ctx, request):
    return {"message": "Opération terminée"}
```

Une action publique renvoie un dictionnaire sérialisable en JSON. Le hook `command` est l’exception interne qui renvoie `(argv, environment, cwd)`.

| Attribut de ctx | Contenu |
| --- | --- |
| `item` | Instance courante : id, adapter, name, settings. |
| `manifest` | Définition chargée, incluant le chemin de localisation `source`. |
| `current` | Configuration du workspace. |
| `registry` | Définitions résolues par ID d’intégration. |
| `root` / `data` | Racine du projet et dossier privé. |
| `runtime` | Helpers HTTP, processus, logs, Terminal et ouverture de fichiers. |
| `table` | Snapshot de processus, quand il a été fourni. |
| `provider()` | Moteur lié via le contrat de routage. |
| `call(action, request)` | Appel d’un autre hook déclaré. |
| `with_item(item)` | Contexte dérivé avec une copie d’instance. |

Les secrets peuvent se trouver dans l’environnement. Évitez de retourner ou journaliser cet environnement entier.

## Hooks internes

| Hook | Contrat |
| --- | --- |
| `status` | Statut en lecture seule ; dictionnaire complet ou partiel. |
| `command` | Commande de session terminal : argv, environnement, cwd. |
| `prepare` | Préparation avant lancement supervisé et certains chemins de relance. |
| `model_change` | Politique de réaction au changement de modèle du moteur. |
| `after_install` | Guide optionnel lors de la création d’instance par save. |

Ces hooks sont retirés des menus publics et ne sont pas des actions directes de l’API de gestion.

Le nom `after_install` ne désigne pas actuellement une notification universelle de fin de job d’installation. Voir sa [sémantique et ses limites](EXTENSIONS.md#proposer-un-guide-de-premier-démarrage).

## Actions publiques conventionnelles

| Action | Usage habituel |
| --- | --- |
| `start`, `stop`, `restart` | Cycle de vie. |
| `terminal`, `web`, `stop-web` | Interfaces de session. |
| `preview`, `test`, `adopt` | Commande, disponibilité API, prise en charge. |
| `logs` | Lecture d’un journal. |
| `load`, `unload` | Chargement et libération d’un modèle lorsque le programme le permet. |
| `set_model` | Action propre à l’intégration pour préparer ou appliquer un modèle. |
| Autre nom | Action personnalisée affichée par le menu générique. |

Déclarer une action sans fonction résoluble produit une erreur de capacité. Déclarer seulement une commande ne crée pas les actions de cycle de vie.

## Forme d’un statut

```python
return {
    "state": "ready",
    "ready": True,
    "managed": False,
    "model": "modele-reel",
    "models": ["modele-reel"],
    "endpoint": "http://127.0.0.1:18100/v1",
    "pid": 0,
    "error": "",
}
```

Les valeurs manquantes sont normalisées par le backend. `cpu` est un pourcentage observé, `memory` une RSS en MiB et `gpu` une mesure facultative de 0 à 100, ou absente. Les valeurs de repli ne constituent pas une mesure du runtime.

`ready` indique la disponibilité annoncée ; `managed` indique le contrôle de processus par PiHub. Un endpoint peut être prêt et externe.

## Politique de changement de modèle

```python
def model_change(ctx, request):
    return {
        "action": "restart",
        "reason": "Cet agent lit son modèle au lancement.",
    }
```

La politique est consultée en lecture seule avec le modèle cible et des informations sur le moteur. Son action doit elle-même être déclarée et disponible.

Le planner ne met pas à jour les agents ayant un modèle fixe. Il attend la disponibilité du modèle cible côté moteur avant d’autoriser l’application aux agents sélectionnés. Une action de mise à jour reçoit notamment le modèle cible ; elle doit réellement respecter la promesse qu’elle annonce.

## Présentation et journaux

| Métadonnée | Rôle |
| --- | --- |
| `action_labels` | Libellés d’actions. |
| `editor_hints` | Texte d’aide par nom de groupe de paramètres. |
| `log_channels` | Suffixe de journal par canal, par exemple `{"web": "-web"}`. |
| `log_paths` | Fichiers de repli pour le helper de logs. |
| `modes` | Métadonnée des modes proposés, par exemple terminal/web. |
| `primary_actions` | Retire certaines actions du menu secondaire lorsque l’interface possède déjà un contrôle dédié. |

N’utilisez pas `primary_actions` pour une action personnalisée qui n’a pas de rendu dédié : cette clé ne crée pas un bouton générique à elle seule.

## Installation et propriétés internes

Le bloc `install` est décrit dans le [chapitre suivant](CATALOG.md).

`source` est injecté au chargement pour résoudre les fichiers. Il n’a pas à être codé en dur dans votre manifeste partagé. `compatibility` peut être ajouté par le catalogue comme métadonnée de référence ; la recette opérationnelle reste dans `install`.

Le parseur conserve les propriétés additionnelles. Cela permet une évolution du contrat, sans garantir qu’une propriété inconnue ait un effet sur l’interface ou le runtime.

[Suivant : recettes d’installation →](CATALOG.md)
