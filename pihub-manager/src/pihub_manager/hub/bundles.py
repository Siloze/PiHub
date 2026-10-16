"""Portable integration folders: one manifest, handlers and optional assets."""
import copy
import shutil
from pathlib import Path
from .storage import DATA, manifests, valid_id, read, write, validate_manifest


def inspect_bundle(folder, expected_kind=None, expected_id=None):
    """Read and validate a portable folder without importing or executing it."""
    folder = Path(folder).expanduser().resolve()
    if not folder.is_dir():
        raise ValueError('Sélectionnez un dossier d’intégration existant.')
    source = folder / 'manifest.json'
    if not source.is_file() or source.is_symlink():
        raise ValueError('Le dossier doit contenir un fichier manifest.json à sa racine.')
    manifest = read(source)
    validate_manifest(manifest)
    identifier = valid_id(manifest['id'])
    existing = manifests().get(identifier)
    if existing and existing['kind'] != manifest['kind']:
        raise ValueError('Le type d’une intégration existante ne peut pas changer.')
    if expected_kind and manifest['kind'] != expected_kind:
        raise ValueError('Ce dossier contient un ' + manifest['kind'] + ', pas un ' + expected_kind + '.')
    if expected_id and identifier != expected_id:
        raise ValueError('Le manifeste a changé depuis sa sélection. Sélectionnez à nouveau le dossier.')
    for entry in folder.rglob('*'):
        if entry.is_symlink():
            raise ValueError('Les liens symboliques ne sont pas pris en charge dans un dossier d’intégration : ' + str(entry.relative_to(folder)))
    for reference in manifest.get('handlers', {}).values():
        module = reference.rpartition(':')[0]
        if module.endswith('.py'):
            handler = (folder / module).resolve()
            if Path(module).is_absolute() or not handler.is_relative_to(folder):
                raise ValueError('Les handlers doivent se trouver dans le dossier de l’intégration.')
            if not handler.is_file():
                raise ValueError('Fichier de handler introuvable : ' + module)
            try:
                compile(handler.read_bytes(), str(handler), 'exec')
            except SyntaxError as error:
                raise ValueError('Syntaxe Python invalide dans ' + module + ' : ' + str(error)) from error
    return manifest


def import_bundle(folder, replace=False, create_instance=False, definition=None, expected_kind=None, expected_id=None):
    manifest = inspect_bundle(folder, expected_kind=expected_kind, expected_id=expected_id)
    identifier = manifest['id']
    if definition is not None:
        validate_manifest(definition)
        if definition['id'] != identifier or definition['kind'] != manifest['kind']:
            raise ValueError('Le JSON modifié doit conserver l’identifiant et le type du dossier.')
        manifest = copy.deepcopy(definition)
    if identifier in manifests() and not replace:
        raise ValueError('Cette intégration existe déjà. Confirmez le remplacement.')
    manifest['source'] = str(Path(folder).expanduser().resolve() / 'manifest.json')
    from .customization import import_manifest
    result = import_manifest(manifest, create_instance=create_instance)
    result['message'] = 'Intégration importée dans l’Explorateur : ' + manifest.get('name', identifier)
    return result


def export_bundle(manifest):
    identifier = valid_id(manifest['id'])
    target = DATA / 'exports' / identifier
    source = Path(manifest['source']).parent if manifest.get('source') else None
    # Use a fresh export directory so removed files cannot reappear in a bundle.
    if target.exists():
        import time
        target = DATA / 'exports' / (identifier + '-' + str(time.time_ns()))
    target.mkdir(parents=True)
    if source and source.is_dir():
        if (source / 'manifest.json').is_file():
            shutil.copytree(source, target, dirs_exist_ok=True, ignore=shutil.ignore_patterns('__pycache__', '*.pyc'))
        else:
            for reference in manifest.get('handlers', {}).values():
                module = reference.rpartition(':')[0]
                if module.endswith('.py'):
                    handler = source / module
                    if handler.is_file():
                        shutil.copy2(handler, target / handler.name)
    value = copy.deepcopy(manifest)
    value.pop('source', None)
    write(target / 'manifest.json', value)
    return target
