"""Portable paths, atomic configuration, and per-user extension registry."""
import copy
import fcntl
import json
import os
import re
import tempfile
from contextlib import contextmanager
from pathlib import Path

ROOT = Path(os.environ.get('PIHUB_ROOT', Path(__file__).resolve().parents[4])).resolve()
DATA = Path(os.environ.get('PIHUB_DATA', ROOT / '.pihub')).expanduser().resolve()
INTEGRATIONS = ROOT / 'pihub-manager' / 'integrations'
REGISTRY_ERRORS = []


def read(path, default=None):
    if not path.exists():
        return copy.deepcopy(default)
    return json.loads(path.read_text())


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temp = tempfile.mkstemp(dir=path.parent, prefix='.pihub-')
    try:
        with os.fdopen(fd, 'w') as stream:
            json.dump(value, stream, indent=2, ensure_ascii=False)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temp, path)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)


@contextmanager
def locked():
    DATA.mkdir(parents=True, exist_ok=True)
    with (DATA / 'hub.lock').open('a') as handle:
        fcntl.flock(handle, fcntl.LOCK_EX)
        yield


def valid_id(value):
    if not isinstance(value, str) or not re.fullmatch(r'[a-zA-Z0-9][a-zA-Z0-9_-]{0,79}', value):
        raise ValueError('Identifiant invalide (lettres, chiffres, tirets).')
    return value


def validate_manifest(item):
    """Validate the complete UI-facing contract before publishing any override."""
    if not isinstance(item, dict):
        raise ValueError('Le manifeste doit être un objet JSON.')
    if not isinstance(item.get('install', {}), dict):
        raise ValueError('install doit être un objet de recette d’installation.')
    valid_id(item.get('id'))
    if item.get('kind') not in ('provider', 'agent') or item.get('api_version', 1) != 1:
        raise ValueError('Type ou version de manifeste invalide.')
    for key in ('name', 'icon', 'color', 'description', 'model_field', 'health', 'model_format'):
        if key in item and (not isinstance(item[key], str) or '\x00' in item[key]):
            raise ValueError('Texte requis : ' + key)
    if 'name' in item and not item['name'].strip():
        raise ValueError('Le nom de l’intégration ne peut pas être vide.')
    for key in ('command', 'executables', 'modes', 'process_signatures', 'log_paths'):
        if not isinstance(item.get(key, []), list) or not all(isinstance(v, str) and '\x00' not in v for v in item.get(key, [])):
            raise ValueError('Liste de chaînes requise : ' + key)
    for key in ('handlers', 'env', 'action_labels', 'editor_hints', 'log_channels'):
        value = item.get(key, {})
        if not isinstance(value, dict) or not all(isinstance(k, str) and isinstance(v, str) and '\x00' not in k + v for k, v in value.items()):
            raise ValueError('Objet de chaînes requis : ' + key)
    for action, reference in item.get('handlers', {}).items():
        module, separator, function = reference.rpartition(':')
        if not action or not separator or not module or not function.isidentifier():
            raise ValueError('Handler invalide : ' + action)
    if 'routing' in item:
        routing = item['routing']
        if not isinstance(routing, dict) or not isinstance(routing.get('provider_field'), str):
            raise ValueError('routing.provider_field requis.')
        for key in ('model_field', 'unbound_value', 'unbound_label'):
            if key in routing and not isinstance(routing[key], str):
                raise ValueError('Champ de routage invalide : ' + key)
        if 'required' in routing and not isinstance(routing['required'], bool):
            raise ValueError('routing.required doit être booléen.')
    for key in ('external', 'multi_model'):
        if key in item and not isinstance(item[key], bool):
            raise ValueError('Booléen requis : ' + key)
    fields = item.get('fields', [])
    if not isinstance(fields, list):
        raise ValueError('fields doit être une liste.')
    keys = set()
    for field in fields:
        if not isinstance(field, dict) or not all(isinstance(field.get(k), str) for k in ('key', 'label', 'group', 'type', 'default')):
            raise ValueError('Champ de formulaire invalide.')
        if field['key'] in keys:
            raise ValueError('Clé de formulaire répétée : ' + field['key'])
        keys.add(field['key'])
        if 'options' in field and (not isinstance(field['options'], list) or not all(isinstance(v, str) for v in field['options'])):
            raise ValueError('Les choix de formulaire doivent être des chaînes.')
        if 'option_help' in field and (not isinstance(field['option_help'], dict) or not all(isinstance(k, str) and isinstance(v, str) for k, v in field['option_help'].items())):
            raise ValueError('L’aide des choix doit être un objet de chaînes.')
        for key in ('min', 'max', 'step'):
            if key in field and (isinstance(field[key], bool) or not isinstance(field[key], (int, float)) or not __import__('math').isfinite(field[key])):
                raise ValueError('Limite numérique invalide : ' + key)
        if field.get('min', 0) > field.get('max', 10000000) or field.get('step', 1) <= 0:
            raise ValueError('Bornes ou pas de formulaire invalides.')
    return item


def manifests():
    result = {}
    REGISTRY_ERRORS.clear()
    for folder, pattern in ((INTEGRATIONS, '*/manifest.json'), (DATA / 'integrations', '*/manifest.json')):
        for path in sorted(folder.glob(pattern)):
            try:
                item = read(path)
                validate_manifest(item)
                if item.get('api_version', 1) != 1:
                    raise ValueError('Version de contrat de handlers non prise en charge')
                valid_id(item['id'])
                if item.get('kind') not in ('provider', 'agent'):
                    raise ValueError('kind doit être provider ou agent')
                for key, fallback in (('name', item['id']), ('icon', 'puzzlepiece.extension'), ('color', 'violet'), ('description', 'Intégration personnalisée')):
                    item.setdefault(key, fallback)
                    if not isinstance(item.get(key), str):
                        raise ValueError('Champ texte requis : ' + key)
                item.setdefault('fields', [])
                item.setdefault('command', [])
                item.setdefault('executables', [])
                item.setdefault('handlers', {})
                if not isinstance(item['handlers'], dict) or not all(isinstance(k, str) and isinstance(v, str) for k, v in item['handlers'].items()):
                    raise ValueError('handlers doit associer chaque action à module:fonction')
                if not isinstance(item['command'], list) or not all(isinstance(v, str) for v in item['command']):
                    raise ValueError('command doit être une liste de chaînes')
                keys = set()
                for field in item['fields']:
                    for key in ('key', 'label', 'group', 'type', 'default'):
                        if not isinstance(field.get(key), str):
                            raise ValueError('Champ de formulaire invalide : ' + key)
                    if field['key'] in keys:
                        raise ValueError('Clé de formulaire répétée : ' + field['key'])
                    keys.add(field['key'])
                item['source'] = str(path)
                result[item['id']] = item
            except (ValueError, KeyError, TypeError) as error:
                REGISTRY_ERRORS.append(path.name + ' : ' + str(error))
    return result


def defaults(manifest):
    return {f['key']: str(f.get('default', '')) for f in manifest['fields']}


def config():
    current = read(DATA / 'config.json')
    if current is not None:
        return current
    # A distribution ships recipes, never pre-created instances or weights.
    return dict(version=2, providers=[], agents=[], models=[], settings={'refresh': '4', 'model_roots': str(ROOT / 'models')})
