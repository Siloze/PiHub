"""Check the documented bundles together in an isolated temporary workspace.

Run from the project root:
  PYTHONPATH=pihub-manager/src /usr/bin/python3 docs/examples/check_examples.py
"""
import os
import socket
import subprocess
import tempfile
import time
from pathlib import Path


def main():
    with tempfile.TemporaryDirectory(prefix='pihub-doc-examples-') as temporary:
        os.environ['PIHUB_DATA'] = temporary
        from pihub_manager.hub import storage, service, catalog, runtime
        from pihub_manager.hub.bundles import import_bundle

        examples = Path(__file__).resolve().parent
        import_bundle(examples / 'demo-provider')
        import_bundle(examples / 'demo-agent')
        provider_id = catalog.action({'action': 'catalog-template', 'id': 'demo-provider'})['instance_id']
        provider = service.find_item(storage.config(), provider_id)
        with socket.socket() as listener:
            listener.bind(('127.0.0.1', 0))
            port = listener.getsockname()[1]
        provider['settings'].update(model='demo-echo', host='127.0.0.1', port=str(port))
        service.action({'action': 'save', 'item': provider})
        try:
            service.action({'action': 'start', 'id': provider_id})
            deadline = time.monotonic() + 8
            while True:
                state = service.probe(provider, storage.manifests(), runtime.processes())
                if state['ready']:
                    break
                if time.monotonic() >= deadline:
                    raise RuntimeError('Le provider de démonstration ne devient pas prêt : ' + state['error'])
                time.sleep(.1)
            agent_id = catalog.action({'action': 'catalog-template', 'id': 'demo-agent'})['instance_id']
            agent = service.find_item(storage.config(), agent_id)
            agent['settings']['provider'] = provider_id
            service.action({'action': 'save', 'item': agent})
            argv, environment, cwd = service.agent_command(agent, storage.manifests(), storage.config())
            result = subprocess.run(
                argv + ['--prompt', 'Bonjour PiHub'], env=environment, cwd=cwd,
                capture_output=True, text=True, timeout=10, check=True,
            )
            assert 'Écho de démonstration : Bonjour PiHub' in result.stdout, result.stdout
            assert state['models'] == ['demo-echo'], state
            print('Exemples validés : import, démarrage, routage, requête et arrêt du provider.')
        finally:
            if runtime.owned(provider_id, runtime.processes()):
                service.action({'action': 'stop', 'id': provider_id})


if __name__ == '__main__':
    main()
