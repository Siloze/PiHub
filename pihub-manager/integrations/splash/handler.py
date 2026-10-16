"""Splash-specific status normalization. Lifecycle hooks come from common."""
from pihub_manager.hub.integrations.providers.common import http_status


def status(ctx, request):
    result = http_status(ctx, request)
    model = result['details'].get('memory_plan', {}).get('model', {}).get('model_name', '')
    if model:
        result['model'] = model
    return result

from pihub_manager.hub.integrations.providers.common import test as _hook_test

from pihub_manager.hub.integrations.providers.common import start as _hook_start

from pihub_manager.hub.integrations.providers.common import stop as _hook_stop

from pihub_manager.hub.integrations.providers.common import restart as _hook_restart

from pihub_manager.hub.integrations.providers.common import preview as _hook_preview

from pihub_manager.hub.integrations.providers.common import adopt as _hook_adopt

from pihub_manager.hub.integrations.common import logs as _hook_logs
