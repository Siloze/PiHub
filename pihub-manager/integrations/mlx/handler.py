"""Integration lifecycle hooks using PiHub helpers."""

from pihub_manager.hub.integrations.providers.common import http_status as _hook_status

from pihub_manager.hub.integrations.providers.common import test as _hook_test

from pihub_manager.hub.integrations.providers.common import start as _hook_start

from pihub_manager.hub.integrations.providers.common import stop as _hook_stop

from pihub_manager.hub.integrations.providers.common import restart as _hook_restart

from pihub_manager.hub.integrations.providers.common import preview as _hook_preview

from pihub_manager.hub.integrations.providers.common import adopt as _hook_adopt

from pihub_manager.hub.integrations.common import logs as _hook_logs
