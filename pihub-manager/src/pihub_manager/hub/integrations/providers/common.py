"""Reusable HTTP/CLI provider hooks, explicitly opted into by manifests."""
import os
from .. import Context
from ... import runtime as rt
from ...storage import ROOT, DATA, read, write
from ...configuration import endpoint, build_command, values_for
import time


def http_status(ctx, request):
    item, registry = ctx.item, ctx.registry
    table = ctx.table or rt.processes()
    manifest = registry[item['adapter']]
    result = dict(id=item['id'], state='stopped', ready=False, managed=False, cpu=0.0, memory=0.0, pid=0, uptime='', latency=0.0, model='', error='', endpoint=endpoint(item), models=[], details={})
    record = rt.owned(item['id'], table)
    if record:
        rows = rt.family(record['pid'], table)
        result.update(state='loading', managed=True, pid=record['pid'], cpu=sum(r['cpu'] for r in rows), memory=sum(r['memory'] for r in rows), uptime=table[record['pid']]['uptime'])
    key = item['settings'].get('key_env', '')
    url = result['endpoint']
    health = manifest.get('health', '')
    start = time.monotonic()
    try:
        data = rt.http(url[:-3] + health if health else url + '/models', key)
        result.update(ready=data.get('ready', True), state='ready' if data.get('ready', True) else 'loading', latency=(time.monotonic() - start) * 1000)
        result['details'] = data
        catalog = data if 'data' in data else rt.http(url + '/models', key)
        result['models'] = [m['id'] for m in catalog.get('data', []) if isinstance(m, dict) and 'id' in m]
        if not result['model'] and result['models']:
            result['model'] = result['models'][0]
    except Exception as error:
        result['error'] = str(error)
        if record:
            result['state'] = 'loading'
        elif rt.record_path(item['id']).exists():
            result['state'] = 'failed'
    # Associate external listeners with exact port and a known runtime signature, read-only.
    if result['state'] in ('ready', 'loading') and not record and 'port' in item['settings']:
        port = str(item['settings']['port'])
        rows = [row for row in table.values() if any(token in row['command'] for token in manifest.get('process_signatures', [])) and (f'--port {port}' in row['command'] or manifest.get('port_in_environment', False))]
        if rows:
            row = rows[0]
            family = rt.family(row['pid'], table)
            result.update(pid=row['pid'], cpu=sum(r['cpu'] for r in family), memory=sum(r['memory'] for r in family), uptime=row['uptime'])
    return result



def start(ctx, request):
    values = values_for(ctx.item, ctx.manifest)
    model_field = ctx.manifest.get('model_field', 'model')
    if model_field in values and not values[model_field] and ctx.manifest.get('requires_model', True):
        raise ValueError('Choisissez un modèle avant de démarrer.')
    rt.port_free(values.get('host', '127.0.0.1'), values['port'])
    argv, environment, values = build_command(ctx.item, ctx.manifest)
    key_env = values.get('key_env', '')
    if key_env:
        if not os.environ.get(key_env):
            raise ValueError('Variable de clé API non définie : ' + key_env)
        server_key = ctx.manifest.get('server_key_env')
        if server_key:
            environment[server_key] = os.environ[key_env]
    pid = rt.spawn(ctx.item['id'], argv, environment)
    path = rt.record_path(ctx.item['id'])
    record = read(path, {})
    record['model_context'] = {'model': values.get(model_field, ''), 'endpoint': endpoint(ctx.item)}
    write(path, record)
    return {'message': 'Démarrage demandé.', 'pid': pid}


def stop(ctx, request):
    rt.stop(ctx.item['id'])
    values = values_for(ctx.item, ctx.manifest)
    if values.get('port'):
        rt.wait_port_free(values.get('host', '127.0.0.1'), values['port'])
    return {'message': 'Processus arrêté.'}


def restart(ctx, request):
    if not rt.owned(ctx.item['id'], rt.processes()):
        if not request.get('confirm_external'):
            raise ValueError('Ce moteur est externe à PiHub. Confirmez d’abord la prise en charge temporaire avant de tenter sa relance.')
        # Only adopt a process the provider's own status handler positively identified
        # by its API port and process signature. The caller has explicitly confirmed
        # that PiHub may signal that PID; unrelated processes are never searched/killed.
        ctx.call('adopt')
    ctx.call('stop')
    return ctx.call('start')


def test(ctx, request):
    state = ctx.call('status')
    if not state['ready']:
        raise ValueError(state.get('error') or 'Le moteur n’est pas prêt.')
    return {'message': 'API disponible.'}


def preview(ctx, request):
    import shlex
    return {'message': shlex.join(build_command(ctx.item, ctx.manifest)[0])}


def adopt(ctx, request):
    state = ctx.call('status')
    table = rt.processes()
    row = table.get(state.get('pid'))
    if not row or not state['ready']:
        raise ValueError('Aucun processus local actif identifié.')
    write(rt.record_path(ctx.item['id']), dict(pid=row['pid'], identity=row['identity'], started=time.time(), argv=[], group=False))
    return {'message': 'Processus local pris en charge.'}
