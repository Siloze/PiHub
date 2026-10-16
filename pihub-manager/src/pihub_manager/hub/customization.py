"""Editable integration definitions. Shipped templates remain untouched."""
import copy
import uuid
import shutil
from pathlib import Path
from .storage import DATA, config, defaults, manifests, read, valid_id, write, validate_manifest


def save_manifest(value):
    if not isinstance(value, dict):
        raise ValueError('Le manifeste doit être un objet JSON.')
    item = copy.deepcopy(value)
    validate_manifest(item)
    identifier = valid_id(item.get('id'))
    for key, fallback in (('name', identifier), ('icon', 'puzzlepiece.extension'), ('color', 'violet'), ('description', 'Intégration personnalisée')):
        item.setdefault(key, fallback)
    hooks = item.get('handlers', {})
    previous = manifests().get(identifier)
    if previous and previous['kind'] != item['kind']:
        raise ValueError('Le type d’une intégration ne peut pas changer.')
    # Moving an override must not change relative Python file resolution.
    source = Path(item.get('source') or (previous or {}).get('source', DATA / 'integrations' / identifier / 'manifest.json'))
    origin = source.parent
    destination = DATA / 'integrations' / identifier / 'manifest.json'
    if previous and 'install' not in item and 'install' in previous:
        item['install'] = copy.deepcopy(previous['install'])
    if source.name == 'manifest.json' and origin.resolve() != destination.parent.resolve() and origin.is_dir():
        if destination.exists():
            from time import time_ns
            shutil.copytree(destination.parent, DATA / 'backups' / (identifier + '-bundle-' + str(time_ns())))
        shutil.copytree(origin, destination.parent, dirs_exist_ok=True, ignore=shutil.ignore_patterns('manifest.json', '__pycache__', '*.pyc'))
    for action, ref in hooks.items():
        module, sep, function = ref.rpartition(':')
        if module.endswith('.py'):
            handler = (origin / module).resolve()
            relative = Path(module).name if Path(module).is_absolute() else module
            if '..' in Path(relative).parts:
                raise ValueError('Le handler doit se trouver dans le dossier de l’intégration.')
            target = destination.parent / relative
            if handler.is_file() and handler != target.resolve():
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(handler, target)
            hooks[action] = relative + sep + function
    item.pop('source', None)
    if destination.exists():
        from time import time_ns
        write(DATA / 'backups' / (identifier + '-' + str(time_ns()) + '.json'), read(destination))
    write(destination, item)
    return {'message': 'Intégration enregistrée : ' + str(destination)}


def import_manifest(value, create_instance=False):
    """Import a JSON definition and optionally create its first local instance."""
    result = save_manifest(value)
    if not create_instance:
        return result
    definition = manifests()[value['id']]
    current = config()
    settings = defaults(definition)
    routing = definition.get('routing', {})
    if routing.get('provider_field') and routing.get('required'):
        settings[routing['provider_field']] = ''
    model_field = definition.get('model_field', 'model')
    if definition['kind'] == 'provider' and model_field in settings:
        settings[model_field] = ''
    if definition['kind'] == 'provider' and settings.get('port'):
        occupied = {item['settings'].get('port') for item in current['providers']}
        port = int(settings['port'])
        while str(port) in occupied and port < 65535:
            port += 1
        if str(port) in occupied:
            raise ValueError('Aucun port libre entre le port par défaut et 65535.')
        settings['port'] = str(port)
    identifier = value['id'][:68] + '-' + uuid.uuid4().hex[:8]
    item = dict(id=identifier, adapter=value['id'], name=definition['name'], settings=settings)
    group = 'providers' if value['kind'] == 'provider' else 'agents'
    current[group].append(item)
    write(DATA / 'config.json', current)
    result.update(message='JSON importé et instance créée : ' + item['name'], instance_id=identifier)
    return result
