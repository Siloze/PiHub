"""Local, versioned recipes; install workers never block monitoring."""
import copy
import json
import os
import re
import subprocess
import sys
import time
import uuid
from pathlib import Path
from .storage import ROOT, DATA, INTEGRATIONS, read, write, valid_id, config, manifests, defaults

CATALOG_ERRORS = []


def detect(entry, current, registry, states=None):
    """Presence is executable evidence, not just a PiHub installation receipt."""
    from .configuration import executable
    manifest = registry.get(entry['adapter'])
    if not manifest:
        return None
    items = [i for i in current['providers'] + current['agents'] if i['adapter'] == entry['adapter']]
    installed = read(DATA / 'installations.json', {}).get(entry['id'], {})
    receipt = [dict(settings={'executable': installed['executable']})] if installed.get('executable') else []
    for item in items + receipt + [dict(settings=defaults(manifest))]:
        path = executable(item, manifest)
        if path:
            return dict(executable=path, origin='pihub' if path == installed.get('executable') else 'external', instances=[i['id'] for i in items], version=installed.get('revision', '') if path == installed.get('executable') else '')
    if any((states or {}).get(i['id'], {}).get('ready') for i in items):
        return dict(executable='', origin='connected', instances=[i['id'] for i in items], version='')
    return None


def entries():
    result = {}
    CATALOG_ERRORS.clear()
    candidates = []
    for manifest in manifests().values():
        install = manifest.get('install', {})
        entry = dict(
            id=manifest['id'], adapter=manifest['id'], kind=manifest['kind'],
            name=manifest['name'], icon=manifest['icon'], color=manifest['color'],
            summary=manifest.get('description', ''), revision='local', repository='',
            verification='unverified', executable='', prerequisites=[], steps=[],
        )
        entry.update(install)
        entry.update(manifest=manifest, id=manifest['id'], adapter=manifest['id'], kind=manifest['kind'])
        candidates.append((Path(manifest['source']), entry))
    for path, entry in candidates:
        try:
            valid_id(entry['id'])
            valid_id(entry['adapter'])
            if entry.get('kind') not in ('agent', 'provider'):
                raise ValueError('kind doit être agent ou provider')
            for key in ('name', 'revision', 'summary', 'repository', 'icon', 'color', 'verification', 'executable'):
                if not isinstance(entry.get(key), str):
                    raise ValueError('Champ texte requis : ' + key)
            if not isinstance(entry.get('prerequisites'), list) or not all(isinstance(v, str) for v in entry['prerequisites']):
                raise ValueError('prerequisites doit être une liste de chaînes')
            if not isinstance(entry.get('steps'), list):
                raise ValueError('steps doit être une liste')
            for step in entry['steps']:
                if not isinstance(step, dict) or not isinstance(step.get('label'), str):
                    raise ValueError('Étape sans label')
                if step.get('download'):
                    if not isinstance(step['download'], str) or not step['download'].startswith('https://') or not re.fullmatch('[a-f0-9]{64}', step.get('sha256', '')):
                        raise ValueError('Téléchargement HTTPS + SHA-256 requis')
                elif not isinstance(step.get('argv'), list) or not step['argv'] or not all(isinstance(v, str) for v in step['argv']):
                    raise ValueError('Étape sans argv valide')
            entry['recipe_source'] = str(path)
            result[entry['id']] = entry
        except (ValueError, KeyError, TypeError) as error:
            CATALOG_ERRORS.append(path.name + ' : ' + str(error))
    return result


def snapshot(current=None, registry=None, states=None):
    jobs = []
    from .runtime import processes
    table = None
    for path in sorted((DATA / 'install-jobs').glob('*.json')):
        job = read(path, {})
        if job.get('state') in ('queued', 'running') and job.get('pid'):
            if table is None:
                table = processes()
            process = table.get(job['pid'], {})
            if process.get('identity') != job.get('identity') and time.time() - job.get('created', 0) > 5:
                job = read(path, job)
                if job['state'] in ('queued', 'running'):
                    # Snapshot is read-only: never overwrite a worker completing
                    # concurrently. A dead worker is still presented as failed.
                    job.update(state='failed', message='Installation interrompue. Consultez le journal puis réessayez.')
        jobs.append({k: v for k, v in job.items() if k not in ('recipe', 'definition')})
    installed = read(DATA / 'installations.json', {})
    current = config() if current is None else current
    registry = manifests() if registry is None else registry
    recipes = entries()
    detected = {key: presence for key, entry in recipes.items() if (presence := detect(entry, current, registry, states))}
    templates = {}
    for key, entry in recipes.items():
        path = DATA / 'integrations' / entry['adapter'] / 'manifest.json'
        available = entry['adapter'] in registry or bool(entry.get('manifest'))
        templates[key] = dict(
            available=available,
            source='personal' if path.exists() else 'bundled' if available else 'missing',
            instances=[i['id'] for i in current['providers'] + current['agents'] if i['adapter'] == entry['adapter']],
        )
    return {'entries': list(recipes.values()), 'errors': list(CATALOG_ERRORS), 'jobs': sorted(jobs, key=lambda j: j.get('created', 0), reverse=True)[:20], 'installed': installed, 'detected': detected, 'templates': templates}


def template(entry):
    # Custom catalogues can include an inline definition, not remote executable code.
    value = copy.deepcopy(entry.get('manifest') or read(INTEGRATIONS / entry['adapter'] / 'manifest.json'))
    if not value:
        raise ValueError('Template introuvable.')
    if value.get('id') != entry['adapter'] or value.get('kind') != entry['kind']:
        raise ValueError('Le template ne correspond pas à la recette.')
    value['compatibility'] = {'revision': entry['revision'], 'repository': entry.get('repository', ''), 'status': entry.get('verification', 'reference')}
    return value


def add_instance(entry, executable='', manifest_override=None):
    from .storage import config, defaults
    from .customization import save_manifest
    definition = manifest_override or template(entry)
    destination = DATA / 'integrations' / definition['id'] / 'manifest.json'
    # Never replace personal customizations when adding another instance.
    if destination.exists():
        definition = read(destination)
        # An installed bundle may require a new PYTHONPATH. Keep user env keys
        # except the explicitly runtime-bound keys declared by this recipe.
        if executable and entry.get('runtime_env'):
            for key in entry['runtime_env']:
                definition.setdefault('env', {})[key] = manifest_override['env'][key]
            save_manifest(definition)
    else:
        save_manifest(definition)
    current = config()
    if not executable:
        evidence = detect(entry, current, manifests())
        executable = evidence['executable'] if evidence else ''
    settings = defaults(definition)
    if executable:
        settings['executable'] = executable
    routing = definition.get('routing', {})
    if routing.get('provider_field') and routing.get('required'):
        settings[routing['provider_field']] = ''
    model_field = definition.get('model_field', 'model')
    if entry['kind'] == 'provider' and model_field in settings:
        settings[model_field] = ''
    # Avoid collisions between instances; leave actual OS checks to start().
    occupied = {p['settings'].get('port') for p in current['providers']}
    if settings.get('port'):
        port = int(settings['port'])
        while str(port) in occupied:
            port += 1
        settings['port'] = str(port)
    identifier = entry['adapter'] + '-' + uuid.uuid4().hex[:6]
    item = dict(id=identifier, adapter=definition['id'], name=definition['name'], settings=settings)
    current['providers' if entry['kind'] == 'provider' else 'agents'].append(item)
    write(DATA / 'config.json', current)
    return item


def action(request):
    name = request['action']
    if name == 'catalog-cancel':
        import signal
        from .runtime import processes
        path = DATA / 'install-jobs' / (valid_id(request['id']) + '.json')
        job = read(path, {})
        if job.get('state') not in ('queued', 'running'):
            raise ValueError('Cette installation n’est plus active.')
        process = processes().get(job.get('pid'), {})
        if not job.get('identity') or process.get('identity') != job['identity']:
            raise ValueError('Processus non identifié ; actualisez le catalogue.')
        os.killpg(job['pid'], signal.SIGTERM)
        job.update(state='cancelled', message='Installation annulée ; fichiers partiels conservés pour diagnostic.')
        write(path, job)
        return {'message': job['message']}
    if name == 'catalog-log':
        identifier = valid_id(request['id'])
        path = DATA / 'install-jobs' / (identifier + '.log')
        return {'message': path.read_text(errors='replace')[-30000:] if path.exists() else 'Journal non disponible.'}
    entry = entries().get(request.get('id'))
    if not entry:
        raise ValueError('Recette inconnue.')
    if name == 'catalog-template':
        item = add_instance(entry)
        return {'message': 'Template ajouté, aucun runtime téléchargé.', 'instance_id': item['id']}
    if name == 'catalog-delete-installation':
        identifier = valid_id(request['id'])
        receipt = read(DATA / 'installations.json', {}).get(identifier)
        if not receipt:
            raise ValueError('Aucune installation PiHub à retirer.')
        current = config()
        ignored = set(request.get('ignore_instances', []))
        if any(i['adapter'] == entry['adapter'] and i['id'] not in ignored for i in current['providers'] + current['agents']):
            raise ValueError('Retirez d’abord les instances utilisant ce runtime.')
        package = Path(receipt.get('path', '')).resolve()
        expected = (DATA / 'packages').resolve()
        executable_path = Path(receipt.get('executable', '')).resolve()
        if package.parent != expected or not package.name.startswith(identifier + '-') or not executable_path.is_relative_to(package):
            raise ValueError('Le chemin de cette installation ne correspond pas au reçu PiHub.')
        if package.exists():
            import shutil
            shutil.rmtree(package)
        installed = read(DATA / 'installations.json', {})
        installed.pop(identifier, None)
        write(DATA / 'installations.json', installed)
        return {'message': 'Runtime PiHub retiré.'}
    if name == 'catalog-export':
        from .bundles import export_bundle
        path = export_bundle(template(entry))
        return {'message': str(path)}
    if name != 'catalog-install':
        raise ValueError('Action de catalogue inconnue.')
    if request.get('confirmed') is not True:
        raise ValueError('Confirmez les commandes et la source avant l’installation.')
    if not entry.get('steps'):
        raise ValueError('Cette intégration ne nécessite pas de runtime local.')
    revision = request.get('revision') or entry['revision']
    if not isinstance(revision, str) or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._/+\-]{0,119}', revision):
        raise ValueError('Révision invalide.')
    if revision != entry['revision']:
        if not entry.get('allow_revision'):
            raise ValueError('Cette recette exige sa version exacte.')
        if request.get('acknowledge_unverified') is not True:
            raise ValueError('Version hors référence : confirmez le risque de compatibilité.')
    for job in snapshot()['jobs']:
        if job.get('entry_id') == entry['id'] and job['state'] in ('queued', 'running'):
            raise ValueError('Une installation de cette intégration est déjà en cours.')
    identifier = entry['id'] + '-' + uuid.uuid4().hex[:10]
    job = dict(id=identifier, entry_id=entry['id'], name=entry['name'], revision=revision, state='queued', created=time.time(), progress=0, message='Préparation', recipe=entry, definition=template(entry))
    path = DATA / 'install-jobs' / (identifier + '.json')
    write(path, job)
    environment = dict(os.environ, PIHUB_ROOT=str(ROOT), PIHUB_DATA=str(DATA))
    environment['PYTHONPATH'] = os.pathsep.join(sys.path)
    log = path.with_suffix('.log').open('ab')
    try:
        process = subprocess.Popen([sys.executable, '-m', 'pihub_manager.hub.installer', identifier], stdin=subprocess.DEVNULL, stdout=log, stderr=log, env=environment, start_new_session=True)
        from .runtime import processes
        job.update(pid=process.pid, identity=processes().get(process.pid, {}).get('identity', ''))
        write(path, job)
        import threading
        threading.Thread(target=process.wait, daemon=True).start()
    finally:
        log.close()
    return {'message': 'Installation lancée en arrière-plan ; suivi dans le catalogue.'}
