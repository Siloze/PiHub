"""Route a small terminal client through the selected PiHub provider."""
from pihub_manager.hub.configuration import endpoint
from pihub_manager.hub.integrations.agents.common import (
    resolved, launch_base, start, stop, restart, status, preview, model_change,
)
from pihub_manager.hub.integrations.common import logs

terminal = start


def command(ctx, request):
    ctx, provider = resolved(ctx, request)
    argv, environment, cwd, _ = launch_base(ctx)
    environment['DEMO_BASE_URL'] = endpoint(provider)
    return argv, environment, cwd
