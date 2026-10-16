"""Pi owns its private model catalogue, launch flags and model application."""
from pihub_manager.hub.integrations.agents.common import resolved, launch_base
from pihub_manager.hub.configuration import endpoint
from pihub_manager.hub.storage import write


def configure_model(ctx, provider):
    settings = ctx.item['settings']
    home = ctx.data / 'agents' / ctx.item['id']
    home.mkdir(parents=True, exist_ok=True)
    model = settings['model']
    write(home / 'models.json', {'providers': {'pihub': {'baseUrl': endpoint(provider), 'api': 'openai-completions', 'apiKey': provider['settings'].get('key_env') or 'pihub-local', 'models': [{'id': model, 'name': model, 'reasoning': settings.get('thinking') != 'off', 'input': ['text'], 'cost': {'input':0,'output':0,'cacheRead':0,'cacheWrite':0}, 'contextWindow': int(provider['settings'].get('context', 32768)), 'maxTokens':8192}]}}})
    return home


def set_model(ctx, request):
    ctx, provider = resolved(ctx, request)
    configure_model(ctx, provider)
    return {'message': 'Catalogue Pi configuré.', 'model': ctx.item['settings']['model'], 'requires_restart': True}


def command(ctx, request):
    ctx, provider = resolved(ctx, request)
    argv, environment, cwd, _ = launch_base(ctx)
    environment['PI_CODING_AGENT_DIR'] = str(configure_model(ctx, provider))
    if ctx.item['settings'].get('tools'):
        argv += ['--tools', ctx.item['settings']['tools']]
    return argv, environment, cwd

from pihub_manager.hub.integrations.agents.common import model_change as _hook_model_change

from pihub_manager.hub.integrations.agents.common import status as _hook_status

from pihub_manager.hub.integrations.agents.common import start as _hook_start

from pihub_manager.hub.integrations.agents.common import start as _hook_terminal

from pihub_manager.hub.integrations.agents.common import stop as _hook_stop

from pihub_manager.hub.integrations.agents.common import restart as _hook_restart

from pihub_manager.hub.integrations.agents.common import preview as _hook_preview

from pihub_manager.hub.integrations.common import logs as _hook_logs
