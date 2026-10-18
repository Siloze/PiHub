"""Opt-in agent helpers. Independent plugins can implement every hook themselves."""
import copy
import json
import os
import shlex
import time
from pathlib import Path
from .. import Context, resolve
from ...configuration import build_command, endpoint, expand
from ...storage import read, write


def resolved(ctx, request=None):
    request = request or {}
    item = copy.deepcopy(ctx.item)
    settings = item['settings']
    provider = ctx.provider()
    routing = ctx.manifest.get('routing', {})
    model_field = routing.get('model_field', 'model')
    if provider:
        state = Context(provider, ctx.current, ctx.registry).call('status')
        if not state.get('ready'):
            raise ValueError('Le moteur sélectionné doit être prêt avant de lancer l’agent.')
        configured = provider['settings'].get('model', '') if ctx.registry[provider['adapter']].get('multi_model') else ''
        settings[model_field] = request.get('model') or settings.get(model_field) or configured or state.get('model') or provider['settings'].get('model', '')
    elif routing.get('required'):
        raise ValueError('Sélectionnez un moteur PiHub.')
    return ctx.with_item(item), provider


def launch_base(ctx):
    argv, environment, values = build_command(ctx.item, ctx.manifest)
    cwd = Path(expand(ctx.item['settings'].get('project') or str(ctx.root))).expanduser()
    if not cwd.is_dir():
        raise ValueError('Le dossier de travail n’existe pas.')
    provider = ctx.provider()
    model_field = ctx.manifest.get('routing', {}).get('model_field', 'model')
    environment['PIHUB_MODEL_CONTEXT'] = json.dumps({'provider': provider['id'] if provider else '', 'model': ctx.item['settings'].get(model_field, ''), 'endpoint': endpoint(provider) if provider else ''})
    return argv, environment, cwd, values


def command(ctx, request):
    ctx, _ = resolved(ctx, request)
    argv, environment, cwd, _ = launch_base(ctx)
    return argv, environment, cwd


def start(ctx, request):
    if ctx.runtime.owned(ctx.item['id'], ctx.runtime.processes()):
        raise ValueError('Une session est déjà active pour cette instance.')
    ctx.call('command')  # preflight before creating a Terminal window
    ctx.runtime.terminal(ctx.item['id'])
    return {'message': 'Session ouverte dans Terminal.'}


def stop(ctx, request):
    stopped = False
    stopped_web = False
    for identifier in (ctx.item['id'], ctx.item['id'] + '-web'):
        if ctx.runtime.owned(identifier, ctx.runtime.processes()):
            ctx.runtime.stop(identifier)
            stopped = True
            stopped_web = stopped_web or identifier.endswith('-web')
    if stopped_web:
        wait_web_port(ctx)
    if not stopped:
        raise ValueError('Aucune session gérée active.')
    return {'message': 'Sessions arrêtées.'}


def restart(ctx, request):
    table = ctx.runtime.processes()
    modes = [mode for mode, identifier in (('terminal', ctx.item['id']), ('web', ctx.item['id'] + '-web')) if ctx.runtime.owned(identifier, table)]
    # Persist integration-specific settings before stopping the current session.
    # Hermes, for example, stores its provider/model inside the named profile;
    # command-line environment overrides alone do not update that profile.
    if resolve(ctx.manifest, 'prepare'):
        ctx.call('prepare', request)
    # Validate configuration and handlers before stopping anything.
    ctx.call('command')
    for mode in modes:
        if not resolve(ctx.manifest, mode):
            raise ValueError('Handler de relance absent : ' + mode)
    if not modes:
        pid = external_pid(ctx, table)
        if not pid or not request.get('confirm_external'):
            raise ValueError('Aucune session PiHub gérée. Une session externe ne peut être relancée qu’après confirmation et si son exécutable exact est détecté.')
        row = table[pid]
        write(ctx.runtime.record_path(ctx.item['id']), dict(
            pid=pid, identity=row['identity'], started=time.time(), argv=[], group=False,
            model_context={'model': request.get('model', ''), 'provider': request.get('provider_id', '')},
        ))
        modes = ['terminal']
    stop(ctx, request)
    for mode in modes:
        ctx.call(mode, {'open_browser': False})
    return {'message': 'Relance demandée avec le modèle actif du moteur.'}


def external_pid(ctx, table=None):
    """Find only a process whose command starts with this instance's exact custom executable."""
    configured = ctx.item.get('settings', {}).get('executable', '').strip()
    if not configured:
        return None
    try:
        target = str(Path(expand(configured)).expanduser().resolve())
    except (OSError, RuntimeError):
        return None
    table = table if table is not None else ctx.runtime.processes()
    for pid, row in table.items():
        command = row.get('command', '').strip()
        try:
            argv = shlex.split(command)
        except ValueError:
            argv = command.split()
        direct = bool(argv and argv[0] == target)
        script = bool(
            len(argv) > 1 and argv[1] == target
            and Path(argv[0]).name in {'bash', 'sh', 'zsh', 'python', 'python3', 'node'}
        )
        if direct or script:
            return pid
    return None


def preview(ctx, request):
    import shlex
    return {'message': shlex.join(ctx.call('command')[0])}


def status(ctx, request):
    table = ctx.table or ctx.runtime.processes()
    records = [record for key in (ctx.item['id'], ctx.item['id'] + '-web') if (record := ctx.runtime.owned(key, table))]
    rows = {row['pid']: row for record in records for row in ctx.runtime.family(record['pid'], table)}
    active = bool(records)
    contexts = [r.get('model_context', {}) for r in records]
    from ...model_changes import launched_model
    models = list(dict.fromkeys(model for record in records if (model := launched_model(record))))
    return dict(id=ctx.item['id'], state='running' if active else 'stopped', managed=active, ready=active, pid=records[0]['pid'] if records else 0, cpu=sum(r['cpu'] for r in rows.values()), memory=sum(r['memory'] for r in rows.values()), uptime=table[records[0]['pid']]['uptime'] if records else '', error='', endpoint=contexts[0].get('endpoint', '') if contexts else '', model=models[0] if models else '', models=models, latency=0, details={'model_contexts': contexts})


def model_change(ctx, request):
    """Conservative policy: built-in sessions read their model at startup."""
    return {'action': 'restart', 'reason': 'Cette session applique le modèle au lancement ; sa relance ouvre une nouvelle session.'}


def stop_web(ctx, request):
    ctx.runtime.stop(ctx.item['id'] + '-web')
    wait_web_port(ctx)
    return {'message': 'Dashboard arrêté.'}


def wait_web_port(ctx):
    """Allow a managed agent web server to release its listener before reuse."""
    port = ctx.item.get('settings', {}).get('web_port')
    if port:
        ctx.runtime.wait_port_free('127.0.0.1', port)
