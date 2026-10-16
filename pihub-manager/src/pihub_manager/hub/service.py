"""Application service shared by the native UI and JSON CLI."""
import concurrent.futures
import json
import os
import subprocess
import time
from pathlib import Path
from . import runtime as rt
from .storage import ROOT, DATA, REGISTRY_ERRORS, config, defaults, locked, manifests, read, valid_id, write
from .integrations import Context, call, resolve, capabilities, PUBLIC_ACTIONS
from . import model_changes
from . import catalog
from . import telemetry
from .relations import model_bindings


from .configuration import expand, executable, env_for, values_for, build_command, endpoint, validate


def probe(item, registry, table):
    ctx = Context(item, config(), registry, table=table)
    try:
        if not resolve(ctx.manifest, 'status'):
            return unavailable_status(item['id'])
        return normalize_status(item['id'], call(ctx, 'status'))
    except Exception as error:
        return unavailable_status(item['id'], str(error))


def unavailable_status(identifier, error=''):
    return dict(id=identifier, state='unavailable', ready=False, managed=False, cpu=0, memory=0, pid=0, uptime='', latency=0, model='', error=error, endpoint='', models=[], details={})


def normalize_status(identifier, payload):
    if not isinstance(payload, dict):
        raise ValueError('Le handler status doit renvoyer un dictionnaire.')
    state = {**unavailable_status(identifier), **payload, 'id': identifier}
    gpu = state.get('gpu')
    if gpu is not None and (isinstance(gpu, bool) or not isinstance(gpu, (int, float)) or not __import__('math').isfinite(gpu) or not 0 <= gpu <= 100):
        state['gpu'] = None
    if 'state' not in payload:
        state['state'] = 'ready' if state['ready'] else 'stopped'
    return state


def model_catalog(current):
    cache_path = DATA / 'models-cache.json'
    cache = read(cache_path, {})
    roots = current.get('settings', {}).get('model_roots', str(ROOT / 'models'))
    if time.time() - cache.get('time', 0) < 60 and cache.get('roots') == roots:
        return unique_models(current.get('models', []) + cache.get('models', []))
    models = []
    for root in roots.splitlines():
        folder = Path(expand(root)).expanduser()
        hub = folder / 'huggingface/hub'
        if not hub.exists():
            hub = folder
        for repo in sorted(hub.glob('models--*')):
            name = repo.name.removeprefix('models--').replace('--', '/', 1)
            if any(k in name.lower() for k in ('dflash', '-splash')):
                continue
            snapshots = sorted((repo / 'snapshots').glob('*/config.json'))
            if snapshots:
                size = sum(p.stat().st_size for p in snapshots[-1].parent.glob('*.safetensors') if p.exists())
                models.append(dict(id=name, name=name.split('/')[-1], format='mlx', path=str(snapshots[-1].parent), size=size / 1024**3, source='discovered'))
        for gguf in folder.glob('**/*.gguf'):
            if not gguf.is_file():
                continue
            models.append(dict(id=str(gguf), name=gguf.stem, format='gguf', path=str(gguf), size=gguf.stat().st_size / 1024**3, source='discovered'))
    write(cache_path, dict(time=time.time(), roots=roots, models=models))
    return unique_models(current.get('models', []) + models)


def unique_models(models):
    result = {}
    for model in models:
        result.setdefault(model['id'], model)
    return list(result.values())


def snapshot():
    current, registry, table = config(), manifests(), rt.processes()
    providers = [p for p in current['providers'] if p['adapter'] in registry]
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        states = list(pool.map(lambda p: probe(p, registry, table), providers))
    agents = []
    integration_errors = []
    action_map = {}
    for item in providers + current['agents']:
        manifest = registry.get(item['adapter'])
        if not manifest:
            action_map[item['id']] = []
            continue
        actions, errors = capabilities(manifest)
        action_map[item['id']] = actions
        integration_errors.extend(item['name'] + ' · ' + error for error in errors)
    for item in current['agents']:
        try:
            manifest = registry.get(item['adapter'], {})
            agents.append(normalize_status(item['id'], call(Context(item, current, registry, table=table), 'status')) if resolve(manifest, 'status') else unavailable_status(item['id']))
        except Exception as error:
            agents.append(unavailable_status(item['id'], str(error)))
    availability = {p['id']: executable(p, registry[p['adapter']]) for p in providers + current['agents'] if p['adapter'] in registry}
    for item in providers + current['agents']:
        manifest = registry.get(item['adapter'], {})
        if manifest.get('handlers') and not manifest.get('executables'):
            availability[item['id']] = 'Intégration Python'
    changes = model_changes.plans(current, registry, {s['id']: s for s in states}, table)
    models = model_catalog(current)
    bindings = model_bindings(models, current, registry, {s['id']: s for s in states + agents})
    return dict(config=current, model_bindings=bindings, gpu=telemetry.gpu(), catalog=catalog.snapshot(current, registry, {s['id']: s for s in states + agents}), registry=list(registry.values()), registry_errors=list(REGISTRY_ERRORS) + integration_errors, capabilities=action_map, model_changes=changes, providers=states, agents=agents, models=models, availability=availability, events=read(DATA / 'events.json', []), root=str(ROOT), data=str(DATA), host=dict(name=socket_hostname(), cores=os.cpu_count() or 1, memory=physical_memory()), timestamp=time.time())


def socket_hostname():
    import socket
    return socket.gethostname().split('.')[0]


def physical_memory():
    try:
        return int(subprocess.check_output(['/usr/sbin/sysctl', '-n', 'hw.memsize'], text=True)) / 1024**3
    except Exception:
        return 0


def find_item(current, identifier):
    return next((p for p in current['providers'] + current['agents'] if p['id'] == identifier), None)


def provider_start(item, manifest):
    return call(Context(item, config(), {item['adapter']: manifest}), 'start')


def agent_command(item, registry, current, web=False):
    from .integrations import Context, call
    return call(Context(item, current, registry), 'command', {'mode': 'web' if web else 'terminal'})


def run_agent(identifier):
    current, registry = config(), manifests()
    item = find_item(current, identifier)
    if not item:
        raise ValueError('Agent inconnu.')
    argv, environment, cwd = agent_command(item, registry, current)
    model_context = json.loads(environment.get('PIHUB_MODEL_CONTEXT', '{}'))
    if not isinstance(model_context, dict):
        raise ValueError('PIHUB_MODEL_CONTEXT doit être un objet JSON.')
    ctx = Context(item, current, registry)
    if resolve(ctx.manifest, 'prepare'):
        call(ctx, 'prepare')
    # Track this stable terminal supervisor. Agents such as Pi rewrite their
    # process title during startup, including a brief empty title on macOS.
    child = subprocess.Popen(argv, env=environment, cwd=cwd)
    import signal
    def forward_stop(signum, frame):
        if child.poll() is None:
            child.terminate()
    signal.signal(signal.SIGTERM, forward_stop)
    signal.signal(signal.SIGINT, signal.SIG_IGN)
    table = rt.processes()
    runner_pid = os.getpid()
    if runner_pid in table:
        write(rt.record_path(identifier), dict(pid=runner_pid, identity=table[runner_pid]['identity'], started=time.time(), argv=argv, terminal=True, group=False, model_context=model_context))
    try:
        return child.wait()
    finally:
        record = read(rt.record_path(identifier), {})
        if record.get('pid') == runner_pid:
            rt.record_path(identifier).unlink(missing_ok=True)


def action(request):
    name = request.get('action', 'snapshot')
    if name == 'snapshot':
        return snapshot()
    with locked():
        current, registry = config(), manifests()
        identifier = request.get('id', '')
        item = find_item(current, identifier)
        if name == 'bundle-validate':
            from .bundles import inspect_bundle
            manifest = inspect_bundle(request['path'], expected_kind=request.get('expected_kind'), expected_id=request.get('expected_id'))
            return {'message': 'Dossier valide : ' + manifest.get('name', manifest['id'])}
        if name == 'bundle-import':
            from .bundles import import_bundle
            return import_bundle(request['path'], replace=request.get('replace') is True, create_instance=request.get('create_instance') is True, definition=request.get('manifest'), expected_kind=request.get('expected_kind'), expected_id=request.get('expected_id'))
        if name == 'bundle-export':
            from .bundles import export_bundle
            manifest = registry.get(identifier)
            if not manifest:
                raise ValueError('Intégration introuvable.')
            return {'message': str(export_bundle(manifest))}
        if name.startswith('catalog-'):
            return catalog.action(request)
        if name == 'manifest-save':
            from .customization import save_manifest
            return save_manifest(request['manifest'])
        if name == 'manifest-import':
            from .customization import import_manifest
            return import_manifest(request['manifest'], create_instance=request.get('create_instance') is True)
        if name == 'manifest-reset':
            valid_id(identifier)
            path = DATA / 'integrations' / identifier / 'manifest.json'
            if not (ROOT / 'pihub-manager/integrations' / identifier / 'manifest.json').exists():
                raise ValueError('Aucun template livré pour cette intégration.')
            if path.exists():
                import shutil
                backup = DATA / 'backups' / (identifier + '-bundle-' + str(time.time_ns()))
                backup.parent.mkdir(parents=True, exist_ok=True)
                shutil.move(str(path.parent), str(backup))
            return {'message': 'Template d’origine restauré ; copie personnelle sauvegardée dans backups/.'}
        if name == 'save':
            incoming = request['item']
            item = find_item(current, incoming['id'])
            manifest = registry[incoming['adapter']]
            validate(incoming, manifest)
            incoming['settings'] = {**defaults(manifest), **incoming['settings']}
            group = 'providers' if manifest['kind'] == 'provider' else 'agents'
            if item and item['adapter'] != incoming['adapter']:
                raise ValueError('Le type d’une instance existante ne peut pas changer.')
            if manifest['kind'] == 'provider' and 'port' in incoming['settings']:
                for other in current['providers']:
                    if other['id'] != incoming['id'] and other['settings'].get('port') == incoming['settings']['port'] and other['settings'].get('host') == incoming['settings'].get('host'):
                        raise ValueError('Ce port est déjà attribué à une autre instance PiHub.')
            current[group] = [p for p in current[group] if p['id'] != incoming['id']] + [incoming]
            write(DATA / 'config.json', current)
            if manifest['kind'] == 'provider':
                model_changes.remember(item, incoming, current, registry)
            rt.event('Configuration', incoming['name'], 'Réglages enregistrés ; redémarrer pour appliquer au processus actif.')
            onboarding = None
            if item is None and resolve(manifest, 'after_install'):
                try:
                    guide = call(Context(incoming, current, registry), 'after_install')
                    if isinstance(guide, dict) and all(isinstance(guide.get(key), str) for key in ('title', 'message')) and isinstance(guide.get('steps'), list) and all(isinstance(step, str) for step in guide['steps']):
                        action = guide.get('action')
                        if action is not None and (not isinstance(action, str) or action in {'status', 'command', 'prepare', 'model_change', 'after_install'} or not resolve(manifest, action)):
                            action = None
                        onboarding = dict(title=guide['title'], message=guide['message'], steps=guide['steps'])
                        if action:
                            onboarding['action'] = action
                            onboarding['action_label'] = guide.get('action_label') if isinstance(guide.get('action_label'), str) else action
                except Exception as error:
                    # The instance has already been saved; an optional guide
                    # must never turn a successful save into a reported failure.
                    rt.event('Guide de démarrage indisponible', incoming['name'], str(error))
            if onboarding:
                return dict(message='Configuration enregistrée.', onboarding=onboarding)
        elif name == 'dismiss-model-change':
            model_changes.dismiss(identifier)
        elif name == 'apply-model-change':
            pending = snapshot()['model_changes']
            plan = next((p for p in pending if p['id'] == identifier), None)
            if not plan:
                raise ValueError('Cette proposition a changé. Actualisez le hub.')
            return model_changes.apply(current, registry, plan, request)
        elif name == 'delete':
            if rt.owned(identifier, rt.processes()) or rt.owned(identifier + '-web', rt.processes()):
                raise ValueError('Arrêtez cette instance avant de la supprimer.')
            if not item:
                raise ValueError('Instance introuvable.')
            siblings = [p for p in current['providers'] + current['agents'] if p['adapter'] == item['adapter'] and p['id'] != identifier]
            if request.get('remove_runtime'):
                if siblings:
                    raise ValueError('Le runtime est partagé avec une autre instance ; supprimez d’abord les autres instances.')
                recipe = next((value for value in catalog.entries().values() if value['adapter'] == item['adapter']), None)
                if not recipe:
                    raise ValueError('Aucune recette catalogue ne permet d’identifier ce runtime.')
                receipt = read(DATA / 'installations.json', {}).get(recipe['id'])
                if not receipt:
                    raise ValueError('Ce runtime n’a pas été installé par PiHub.')
                catalog.action({'action': 'catalog-delete-installation', 'id': recipe['id'], 'ignore_instances': [identifier]})
            if request.get('remove_manifest') and not siblings:
                path = DATA / 'integrations' / item['adapter'] / 'manifest.json'
                if path.exists():
                    import shutil
                    backup = DATA / 'backups' / (item['adapter'] + '-removed-' + str(time.time_ns()))
                    backup.parent.mkdir(parents=True, exist_ok=True)
                    shutil.move(str(path.parent), str(backup))
            for group in ('providers', 'agents'):
                current[group] = [p for p in current[group] if p['id'] != identifier]
            for agent in current['agents']:
                routing = registry.get(agent['adapter'], {}).get('routing', {})
                field = routing.get('provider_field')
                if field and agent['settings'].get(field) == identifier:
                    agent['settings'][field] = routing.get('unbound_value', '')
            write(DATA / 'config.json', current)
            rt.event('Suppression', identifier, 'Instance retirée ; options de nettoyage appliquées.')
        elif name in PUBLIC_ACTIONS or (item and name in registry.get(item['adapter'], {}).get('handlers', {}) and name not in {'status', 'command', 'prepare', 'model_change', 'after_install'}):
            if not item:
                raise ValueError('Instance introuvable.')
            result = call(Context(item, current, registry), name, request)
            rt.event(name, item['name'])
            return result or {'message': 'Opération terminée.'}
        elif name == 'model-save':
            model = request['model']
            if not model.get('id') or not model.get('name') or model.get('format') not in ('mlx', 'gguf', 'ollama', 'api'):
                raise ValueError('Modèle : nom, identifiant et format requis.')
            current['models'] = [m for m in current['models'] if m['id'] != model['id']] + [model]
            write(DATA / 'config.json', current)
        elif name == 'model-delete':
            current['models'] = [m for m in current['models'] if m['id'] != identifier]
            write(DATA / 'config.json', current)
        elif name == 'rescan':
            (DATA / 'models-cache.json').unlink(missing_ok=True)
        elif name == 'settings':
            current['settings'].update(request['settings'])
            write(DATA / 'config.json', current)
        elif name == 'export':
            path = DATA / 'exports' / ('pihub-' + time.strftime('%Y%m%d-%H%M%S') + '.json')
            portable = json.loads(json.dumps(current).replace(str(ROOT), '{root}'))
            write(path, portable)
            return dict(message=str(path))
        elif name == 'import':
            incoming = request['config']
            if incoming.get('version') != 2:
                raise ValueError('Configuration PiHub version 2 requise.')
            if not isinstance(incoming.get('settings'), dict) or not isinstance(incoming.get('models'), list):
                raise ValueError('Sections settings et models requises.')
            for model in incoming['models']:
                if not all(isinstance(model.get(k), str) for k in ('id', 'name', 'format', 'path', 'source')) or not isinstance(model.get('size'), (int, float)):
                    raise ValueError('Entrée de catalogue invalide.')
            if not all(isinstance(k, str) and isinstance(v, str) for k, v in incoming['settings'].items()):
                raise ValueError('Réglages globaux invalides.')
            identifiers = set()
            ports = set()
            for kind, group in (('provider', 'providers'), ('agent', 'agents')):
                for instance in incoming[group]:
                    manifest = registry[instance['adapter']]
                    if manifest['kind'] != kind or instance['id'] in identifiers:
                        raise ValueError('Identifiant répété ou type d’instance incorrect.')
                    validate(instance, manifest)
                    identifiers.add(instance['id'])
                    port = (instance['settings'].get('host'), instance['settings'].get('port'))
                    if kind == 'provider' and port[1]:
                        if port in ports:
                            raise ValueError('Port répété dans l’import.')
                        ports.add(port)
            for group in ('providers', 'agents'):
                for instance in current[group]:
                    if rt.owned(instance['id'], rt.processes()) or rt.owned(instance['id'] + '-web', rt.processes()):
                        raise ValueError('Arrêtez les instances gérées avant de remplacer la configuration.')
            write(DATA / 'backups' / ('config-' + str(time.time_ns()) + '.json'), current)
            write(DATA / 'config.json', incoming)
            rt.event('Import', 'Configuration', 'Ancienne configuration sauvegardée dans backups/.')
        elif name == 'reveal':
            target = {'root': ROOT, 'data': DATA, 'extensions': DATA / 'integrations', 'logs': DATA / 'logs'}.get(identifier)
            if target is None:
                raise ValueError('Destination inconnue.')
            target.mkdir(parents=True, exist_ok=True)
            rt.reveal(target)
        else:
            raise ValueError('Action inconnue : ' + name)
    return dict(message='Opération terminée.')
