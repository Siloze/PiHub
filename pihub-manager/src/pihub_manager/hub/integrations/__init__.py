"""Optional, manifest-declared integration hooks. No agent/provider names here."""
import copy
import importlib
import importlib.util
import sys
import threading
from dataclasses import dataclass, field
from pathlib import Path
from ..storage import ROOT, DATA

PUBLIC_ACTIONS = {'start', 'stop', 'restart', 'terminal', 'web', 'stop-web', 'test', 'preview', 'adopt', 'load', 'unload', 'set_model'}
INTERNAL_HOOKS = {'status', 'command', 'prepare', 'model_change', 'after_install'}


@dataclass
class Context:
    item: dict
    current: dict
    registry: dict
    request: dict = field(default_factory=dict)
    table: dict = field(default_factory=dict)

    @property
    def manifest(self):
        return self.registry[self.item['adapter']]

    @property
    def root(self):
        return ROOT

    @property
    def data(self):
        return DATA

    @property
    def runtime(self):
        from .. import runtime
        return runtime

    def with_item(self, item):
        return Context(copy.deepcopy(item), self.current, self.registry, self.request, self.table)

    def call(self, action, request=None):
        return call(self, action, self.request if request is None else request)

    def provider(self):
        routing = self.manifest.get('routing', {})
        key = routing.get('provider_field')
        identifier = self.item['settings'].get(key, '') if key else ''
        return next((p for p in self.current['providers'] if p['id'] == identifier), None)


_MODULES = {}
_LOAD_LOCK = threading.RLock()


def load_file(path):
    path = Path(path).resolve()
    signature = (str(path), path.stat().st_mtime_ns)
    with _LOAD_LOCK:
        if signature not in _MODULES:
            spec = importlib.util.spec_from_file_location('pihub_extension_' + str(abs(hash(signature))), path, submodule_search_locations=[str(path.parent)])
            module = importlib.util.module_from_spec(spec)
            sys.modules[spec.name] = module
            try:
                spec.loader.exec_module(module)
            except Exception:
                sys.modules.pop(spec.name, None)
                raise
            _MODULES[signature] = module
    return _MODULES[signature]


def resolve(manifest, action):
    reference = manifest.get('handlers', {}).get(action)
    if not reference:
        return None
    module_name, separator, function_name = reference.rpartition(':')
    if not separator or not function_name.isidentifier():
        raise ValueError('Référence de handler invalide : ' + reference)
    if module_name.endswith('.py'):
        # Paths are relative to the manifest. Extensions are trusted local code.
        path = (Path(manifest['source']).parent / module_name).resolve()
        module = load_file(path)
    else:
        module = importlib.import_module(module_name)
    function = getattr(module, function_name, None)
    if not callable(function):
        raise ValueError('Handler introuvable : ' + reference)
    return function


def call(context, action, request=None):
    function = resolve(context.manifest, action)
    if function is None:
        raise ValueError(f"{context.item['name']} ne propose pas l’action « {action} ».")
    return function(context, request or {})


def capabilities(manifest):
    available, errors = [], []
    for action in manifest.get('handlers', {}):
        try:
            if resolve(manifest, action) and action not in INTERNAL_HOOKS:
                available.append(action)
        except Exception as error:
            errors.append(action + ' : ' + str(error))
    return available, errors
