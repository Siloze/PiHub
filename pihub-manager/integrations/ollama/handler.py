"""Ollama owns its daemon/resident-model distinction and hot loading API."""
from pihub_manager.hub.integrations.providers.common import http_status
from pihub_manager.hub.configuration import endpoint


def status(ctx, request):
    result = http_status(ctx, request)
    if result['ready']:
        try:
            models = ctx.runtime.http(endpoint(ctx.item)[:-3] + '/api/ps', ctx.item['settings'].get('key_env', '')).get('models', [])
            result['model'] = models[0].get('name', '') if models else ''
        except Exception as error:
            result['error'] = str(error)
    return result


def load(ctx, request):
    model = ctx.item['settings'].get('model', '')
    if not model:
        raise ValueError('Choisissez un modèle Ollama.')
    ctx.runtime.http(endpoint(ctx.item)[:-3] + '/api/generate', ctx.item['settings'].get('key_env', ''), timeout=120, payload=dict(model=model, stream=False, keep_alive=0 if request.get('unload') else ctx.item['settings'].get('keep_alive', '10m')))
    return {'message': 'Modèle libéré.' if request.get('unload') else 'Modèle chargé.'}


def unload(ctx, request):
    return load(ctx, {'unload': True})

from pihub_manager.hub.integrations.providers.common import test as _hook_test

from pihub_manager.hub.integrations.providers.common import start as _hook_start

from pihub_manager.hub.integrations.providers.common import stop as _hook_stop

from pihub_manager.hub.integrations.providers.common import restart as _hook_restart

from pihub_manager.hub.integrations.providers.common import preview as _hook_preview

from pihub_manager.hub.integrations.providers.common import adopt as _hook_adopt

from pihub_manager.hub.integrations.common import logs as _hook_logs
