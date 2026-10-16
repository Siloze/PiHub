"""Codex owns its model/provider arguments and reasoning/sandbox configuration."""
import json
from pihub_manager.hub.integrations.agents.common import resolved, launch_base
from pihub_manager.hub.configuration import endpoint


def model_arguments(ctx, provider):
    args = []
    settings = ctx.item['settings']
    if settings.get('model'):
        args += ['--model', settings['model']]
    if provider:
        args += ['-c', 'model_provider="pihub"', '-c', 'model_providers.pihub.name="PiHub"', '-c', 'model_providers.pihub.base_url=' + json.dumps(endpoint(provider)), '-c', 'model_providers.pihub.wire_api="responses"']
        key = provider['settings'].get('key_env')
        if key:
            args += ['-c', 'model_providers.pihub.env_key=' + json.dumps(key)]
    return args


def set_model(ctx, request):
    ctx, provider = resolved(ctx, request)
    return {'message': 'Arguments de modèle Codex préparés pour la prochaine session.', 'arguments': model_arguments(ctx, provider), 'requires_restart': True}


def command(ctx, request):
    ctx, provider = resolved(ctx, request)
    argv, environment, cwd, _ = launch_base(ctx)
    settings = ctx.item['settings']
    argv += ['--sandbox', settings.get('sandbox', 'workspace-write'), '-c', 'model_reasoning_effort=' + json.dumps(settings.get('thinking', 'medium'))]
    argv += model_arguments(ctx, provider)
    return argv, environment, cwd

from pihub_manager.hub.integrations.agents.common import model_change as _hook_model_change

from pihub_manager.hub.integrations.agents.common import status as _hook_status

from pihub_manager.hub.integrations.agents.common import start as _hook_start

from pihub_manager.hub.integrations.agents.common import start as _hook_terminal

from pihub_manager.hub.integrations.agents.common import stop as _hook_stop

from pihub_manager.hub.integrations.agents.common import restart as _hook_restart

from pihub_manager.hub.integrations.agents.common import preview as _hook_preview

from pihub_manager.hub.integrations.common import logs as _hook_logs
