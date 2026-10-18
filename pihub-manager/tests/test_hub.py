"""Integration checks run in an isolated data directory; no model loads."""
import json
import copy
import shutil
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from unittest.mock import patch

_temp = tempfile.TemporaryDirectory(prefix='pihub-tests-')
os.environ['PIHUB_DATA'] = _temp.name
from pihub_manager.hub import storage, runtime, service
# Another discovery module may have initialized storage first.
os.environ['PIHUB_DATA'] = str(storage.DATA)
from pihub_manager.hub import model_changes
from pihub_manager.hub.integrations import capabilities, Context, load_file

hermes_handler = load_file(storage.INTEGRATIONS / 'hermes/handler.py')
splash_handler = load_file(storage.INTEGRATIONS / 'splash/handler.py')


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        payload = {'data': [{'id': 'test-model'}]} if self.path.endswith('/models') else {'ready': True}
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps(payload).encode())

    def log_message(self, *args):
        pass


class HubTests(unittest.TestCase):
    def setUp(self):
        # Tests explicitly create fixtures; a fresh user workspace stays empty.
        registry = storage.manifests()
        fixture = storage.config()
        for group, keys in [('providers', ('splash', 'llamacpp', 'mlx', 'ollama', 'remote')), ('agents', ('pi', 'hermes', 'codex'))]:
            fixture[group] = [dict(id=k, adapter=k, name=registry[k]['name'], settings=storage.defaults(registry[k])) for k in keys]
        storage.write(storage.DATA / 'config.json', fixture)
        self.current = storage.config()

    def tearDown(self):
        for key in ('config.json', 'models-cache.json', 'model-changes.json'):
            (storage.DATA / key).unlink(missing_ok=True)

    def test_registry_and_schema(self):
        for manifest in storage.manifests().values():
            self.assertEqual(len({f['key'] for f in manifest['fields']}), len(manifest['fields']))
            instance = dict(id=manifest['id'], adapter=manifest['id'], name=manifest['name'], settings=storage.defaults(manifest))
            service.validate(instance, manifest)

    def test_atomic_save_reload_delete_and_port_collision(self):
        item = self.current['providers'][0]
        item['name'] = 'My Splash'
        service.action(dict(action='save', item=item))
        self.assertEqual(storage.config()['providers'][-1]['name'], 'My Splash')
        duplicate = {**item, 'id': 'second'}
        with self.assertRaisesRegex(ValueError, 'port'):
            service.action(dict(action='save', item=duplicate))
        service.action(dict(action='delete', id=item['id']))
        self.assertFalse(any(p['id'] == item['id'] for p in storage.config()['providers']))

    def test_http_external_endpoint_and_catalog(self):
        server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            item = self.current['providers'][-1]
            item['settings']['base_url'] = f'http://127.0.0.1:{server.server_port}/v1'
            state = service.probe(item, storage.manifests(), {})
            self.assertTrue(state['ready'])
            self.assertEqual(state['models'], ['test-model'])
            self.assertFalse(state['managed'])
            with self.assertRaisesRegex(ValueError, 'port'):
                runtime.port_free('127.0.0.1', server.server_port)
        finally:
            server.shutdown(); server.server_close()

    def test_subprocess_ownership_survives_exec_and_stop(self):
        argv = ['/bin/sh', '-c', 'exec /bin/sleep 30']
        pid = runtime.spawn('fixture', argv, dict(os.environ))
        try:
            self.assertIsNotNone(runtime.owned('fixture', runtime.processes()))
            runtime.stop('fixture')
            self.assertIsNone(runtime.owned('fixture', runtime.processes()))
        finally:
            try: os.kill(pid, 15)
            except ProcessLookupError: pass

    def test_recycled_pid_is_not_owned(self):
        storage.write(runtime.record_path('recycled'), dict(pid=os.getpid(), identity='different start time'))
        self.assertIsNone(runtime.owned('recycled', runtime.processes()))
        with self.assertRaises(ValueError): runtime.stop('recycled')

    def test_process_metrics_are_locale_independent(self):
        with patch.dict(os.environ, {'LC_ALL': 'fr_FR.UTF-8'}):
            self.assertIn(os.getpid(), runtime.processes())

    def test_path_traversal_rejected(self):
        with self.assertRaises(ValueError): runtime.record_path('../unsafe')
        with self.assertRaises(ValueError): service.action(dict(action='logs', id='../unsafe'))

    def test_shell_metacharacters_are_literal_arguments(self):
        item = self.current['agents'][-1]
        item['settings']['executable'] = '/bin/echo'
        item['settings']['extra_args'] = '["$(touch /tmp/pihub-should-not-exist)", "; echo test"]'
        argv, env, values = service.build_command(item, storage.manifests()['codex'])
        self.assertEqual(argv[-2], '$(touch /tmp/pihub-should-not-exist)')

    def test_custom_manifest_and_instance(self):
        extension = storage.DATA / 'integrations/test-provider/manifest.json'
        storage.write(extension, dict(id='test-provider', kind='provider', name='Test', icon='cpu', color='mint', description='Fixture', executables=['/bin/echo'], command=['{executable}', '{model}'], fields=[dict(key='model', label='Model', group='Model', type='text', default='tiny')]))
        try:
            registry = storage.manifests()
            item = dict(id='my-custom', adapter='test-provider', name='Custom', settings=storage.defaults(registry['test-provider']))
            service.action(dict(action='save', item=item))
            self.assertEqual(service.build_command(item, registry['test-provider'])[0], ['/bin/echo', 'tiny'])
        finally:
            extension.unlink()

    def test_invalid_numbers_and_args_rejected(self):
        item = self.current['providers'][0]
        for value in ('nan', 'inf', '-1', '65536', '18000.5'):
            item['settings']['port'] = value
            with self.assertRaises(ValueError): service.validate(item, storage.manifests()['splash'])
        item['settings']['port'] = '18000'
        item['settings']['extra_args'] = '{}'
        with self.assertRaises(ValueError): service.validate(item, storage.manifests()['splash'])

    def test_hermes_custom_endpoint_is_explicit(self):
        agent = self.current['agents'][1]
        with patch.object(splash_handler, 'status', return_value={'ready': True, 'model': 'tiny'}), patch('pihub_manager.hub.configuration.executable', return_value='/bin/echo'):
            argv, env, cwd = service.agent_command(agent, storage.manifests(), self.current)
        self.assertEqual(env['CUSTOM_BASE_URL'], 'http://127.0.0.1:18000/v1')
        self.assertIn('tiny', argv)

    def test_pi_tool_presets_are_forwarded_as_a_real_pi_allowlist(self):
        agent = self.current['agents'][0]
        with patch.object(splash_handler, 'status', return_value={'ready': True, 'model': 'tiny'}), \
             patch('pihub_manager.hub.configuration.executable', return_value='/bin/echo'):
            argv, _, _ = service.agent_command(agent, storage.manifests(), self.current)
        self.assertEqual(argv[-2:], ['--tools', 'read,bash,edit,write,grep,find,ls'])

    def test_hermes_gateway_initializes_from_default_host_profile(self):
        agent = self.current['agents'][1]
        ctx = Context(agent, self.current, storage.manifests())
        outputs = [
            subprocess.CompletedProcess([], 0, 'Migration complete', ''),
            subprocess.CompletedProcess([], 0, 'Gateway restarted', ''),
            subprocess.CompletedProcess([], 0, 'Gateways:\n  ✓ default — running\n  ✓ pihub-hermes — running', ''),
        ]
        with patch.object(hermes_handler, 'resolved', return_value=(ctx, None)), \
             patch.object(hermes_handler, 'set_model'), \
             patch.object(hermes_handler, 'executable', return_value='/opt/hermes/bin/hermes'), \
             patch.object(hermes_handler.subprocess, 'run', side_effect=outputs) as run:
            result = hermes_handler.gateway(ctx, {})
        self.assertEqual(result['profile'], 'pihub-hermes')
        self.assertIn('Gateway hôte PiHub actif', result['message'])
        self.assertEqual(run.call_args_list[0].args[0][1:4], ['--profile', 'default', 'gateway'])
        self.assertEqual(run.call_args_list[1].args[0][1:4], ['--profile', 'default', 'gateway'])
        self.assertEqual(run.call_args_list[2].args[0][1:4], ['--profile', 'default', 'gateway'])
        self.assertEqual(run.call_args_list[0].kwargs['env']['HERMES_HOME'], str(storage.ROOT / 'hermes'))

    def test_hermes_gateway_reports_when_profile_is_not_served(self):
        agent = self.current['agents'][1]
        ctx = Context(agent, self.current, storage.manifests())
        outputs = [
            subprocess.CompletedProcess([], 0, 'Migration complete', ''),
            subprocess.CompletedProcess([], 0, 'Gateway restarted', ''),
            subprocess.CompletedProcess([], 0, 'Gateways:\n  ✓ default — running\n  ✗ pihub-hermes — not running', ''),
        ]
        with patch.object(hermes_handler, 'resolved', return_value=(ctx, None)), \
             patch.object(hermes_handler, 'set_model'), \
             patch.object(hermes_handler, 'executable', return_value='/opt/hermes/bin/hermes'), \
             patch.object(hermes_handler.subprocess, 'run', side_effect=outputs):
            with self.assertRaisesRegex(ValueError, 'ne confirme pas'):
                hermes_handler.gateway(ctx, {})

    def test_hermes_status_checks_whether_pihub_profile_is_served(self):
        agent = self.current['agents'][1]
        ctx = Context(agent, self.current, storage.manifests())
        listing = subprocess.CompletedProcess([], 0, 'Gateways:\n  ✓ default — running\n  ✓ pihub-hermes — running', '')
        with patch.object(hermes_handler, 'process_status', return_value={'managed': False}), \
             patch.object(hermes_handler, 'executable', return_value='/opt/hermes/bin/hermes'), \
             patch.object(hermes_handler.subprocess, 'run', return_value=listing) as run:
            result = hermes_handler.status(ctx, {})
        self.assertIsInstance(result['profile_configured'], bool)
        self.assertTrue(result['gateway_initialized'])
        self.assertEqual(run.call_args.args[0], ['/opt/hermes/bin/hermes', '--profile', 'default', 'gateway', 'list'])
        self.assertEqual(run.call_args.kwargs['env']['HERMES_HOME'], str(storage.ROOT / 'hermes'))

    def test_optional_onboarding_hook_runs_only_for_new_instance(self):
        agent = copy.deepcopy(self.current['agents'][1])
        agent['id'] = 'hermes-onboarding-fixture'
        guide = dict(title='Welcome', message='First run', steps=['Choose a provider'])
        with patch('pihub_manager.hub.service.call', return_value=guide) as call, \
             patch('pihub_manager.hub.service.rt.event'):
            result = service.action({'action': 'save', 'item': agent})
            self.assertEqual(result['onboarding'], guide)
            self.assertEqual(call.call_count, 1)
            updated = copy.deepcopy(agent)
            updated['name'] = 'Hermes edited'
            result = service.action({'action': 'save', 'item': updated})
            self.assertNotIn('onboarding', result)
            self.assertEqual(call.call_count, 1)

    def test_provider_model_change_offers_cautious_restart_for_custom_processes(self):
        provider = self.current['providers'][0]
        provider['settings']['model'] = 'new-model'
        provider['settings']['executable'] = '/custom/splash-server'
        agent = self.current['agents'][1]
        agent['settings']['provider'] = provider['id']
        agent['settings']['executable'] = '/custom/hermes'
        registry = storage.manifests()
        pending = {provider['id']: dict(
            id='change-1', provider_id=provider['id'], provider_name=provider['name'],
            before='old-model', after='new-model',
        )}

        def owned(identifier, table):
            if identifier == provider['id']:
                return None
            if identifier == agent['id']:
                return {'model_context': {'model': 'old-model'}}
            return None

        with patch.object(model_changes, 'read', return_value=pending), \
             patch('pihub_manager.hub.runtime.owned', side_effect=owned):
            plans = model_changes.plans(
                self.current, registry,
                {provider['id']: {'ready': True, 'model': 'old-model', 'pid': 4321}},
                {},
            )
        plan = plans[0]
        self.assertTrue(plan['provider_restart_available'])
        self.assertTrue(plan['provider_restart_uncertain'])
        affected = next(row for row in plan['agents'] if row['id'] == agent['id'])
        self.assertTrue(affected['needs_action'])
        self.assertTrue(affected['uncertain'])

    def test_external_provider_restart_requires_explicit_confirmation(self):
        provider = self.current['providers'][0]
        plan = dict(
            provider_id=provider['id'], after='new-model', provider_restart_available=True,
            provider_restart_uncertain=True,
        )
        registry = storage.manifests()
        with self.assertRaisesRegex(ValueError, 'Confirmez'):
            model_changes.apply(self.current, registry, plan, {'restart_provider': True})
        with patch('pihub_manager.hub.runtime.processes', return_value={}), \
             patch('pihub_manager.hub.runtime.owned', return_value=None), \
             patch('pihub_manager.hub.runtime.event'), \
             patch.object(model_changes, 'call', side_effect=lambda ctx, action, request: {'ready': True, 'model': 'new-model'} if action == 'status' else {'message': 'ok'}) as call:
            result = model_changes.apply(
                self.current, registry, plan,
                {'restart_provider': True, 'confirm_uncertain': True},
            )
        self.assertIn('Moteur relancé et prêt', result['message'])
        self.assertTrue(call.call_args_list[0].args[2]['confirm_external'])

    def test_custom_agent_process_is_offered_cautious_relaunch(self):
        provider = self.current['providers'][0]
        provider['settings']['model'] = 'new-model'
        agent = self.current['agents'][1]
        agent['settings']['provider'] = provider['id']
        agent['settings']['executable'] = '/custom/hermes'
        registry = storage.manifests()
        pending = {provider['id']: dict(
            id='change-external', provider_id=provider['id'], provider_name=provider['name'],
            before='old-model', after='new-model',
        )}
        process = {4321: dict(pid=4321, command='/custom/hermes --profile pihub-hermes', identity='custom-process')}
        with patch.object(model_changes, 'read', return_value=pending), \
             patch('pihub_manager.hub.runtime.owned', return_value=None), \
             patch('pihub_manager.hub.runtime.processes', return_value=process):
            plans = model_changes.plans(
                self.current, registry,
                {provider['id']: {'ready': True, 'model': 'old-model', 'pid': 0}},
                process,
            )
        row = next(item for item in plans[0]['agents'] if item['id'] == agent['id'])
        self.assertTrue(row['active'])
        self.assertTrue(row['external'])
        self.assertTrue(row['uncertain'])
        self.assertTrue(row['needs_action'])

    def test_external_agent_restart_requires_confirmation_and_exact_executable(self):
        from unittest.mock import Mock
        from pihub_manager.hub.integrations.agents import common as agent_common

        ctx = Mock()
        ctx.item = {'id': 'hermes', 'settings': {'executable': '/custom/hermes'}}
        ctx.manifest = {'handlers': {'terminal': 'terminal:terminal'}}
        table = {4321: {'pid': 4321, 'identity': 'custom-process', 'command': '/custom/hermes --profile pihub-hermes'}}
        ctx.runtime.processes.return_value = table
        ctx.runtime.record_path.return_value = '/tmp/pihub-test-record'
        ctx.runtime.owned.return_value = None
        ctx.call.side_effect = lambda *args, **kwargs: None
        with patch.object(agent_common, 'resolve', side_effect=lambda manifest, action: action == 'terminal'), \
             patch.object(agent_common, 'external_pid', return_value=4321), \
             patch.object(agent_common, 'stop') as stop, \
             patch.object(agent_common, 'write') as write_record:
            with self.assertRaisesRegex(ValueError, 'après confirmation'):
                agent_common.restart(ctx, {})
            agent_common.restart(ctx, {'confirm_external': True, 'model': 'new-model'})
        write_record.assert_called_once()
        stop.assert_called_once()
        self.assertEqual(ctx.call.call_args.args[0], 'terminal')

    def test_agent_restart_persists_handler_configuration_before_stopping(self):
        from unittest.mock import Mock
        from pihub_manager.hub.integrations.agents import common as agent_common

        ctx = Mock()
        ctx.item = {'id': 'hermes'}
        ctx.manifest = {'handlers': {'prepare': 'prepare:prepare', 'web': 'web:web'}}
        ctx.runtime.processes.return_value = {}
        ctx.runtime.owned.side_effect = [dict(pid=10), None]
        calls = []
        ctx.call.side_effect = lambda action, request=None: calls.append((action, request))
        with patch.object(agent_common, 'resolve', side_effect=lambda manifest, action: action in {'prepare', 'web', 'terminal'}), \
             patch.object(agent_common, 'stop') as stop:
            agent_common.restart(ctx, {'model': 'new-model'})
        self.assertEqual(calls[0][0], 'prepare')
        self.assertEqual(calls[0][1], {'model': 'new-model'})
        self.assertEqual(calls[1][0], 'command')
        stop.assert_called_once()
        self.assertEqual(calls[-1][0], 'terminal')

    def test_two_independent_provider_processes(self):
        manifest = dict(id='fixture-provider', kind='provider', name='Fixture', icon='cpu', color='mint', description='Test fixture', executables=[sys.executable], command=['{executable}', str(Path(__file__).parent / 'fixtures/provider.py'), '--port', '{port}'], fields=[dict(key='port', label='Port', group='Network', type='number', default='18190')], health='/status')
        manifest['handlers'] = {'start': 'pihub_manager.hub.integrations.providers.common:start', 'status': 'pihub_manager.hub.integrations.providers.common:http_status'}
        items = []
        for index in range(2):
            with socket.socket() as sock:
                sock.bind(('127.0.0.1', 0))
                port = sock.getsockname()[1]
            item = dict(id='fixture-' + str(index), adapter=manifest['id'], name='Fixture', settings={'port': str(port)})
            service.provider_start(item, manifest)
            items.append(item)
        try:
            registry = {manifest['id']: manifest}
            for _ in range(20):
                states = [service.probe(item, registry, runtime.processes()) for item in items]
                if all(state['ready'] for state in states): break
                time.sleep(.05)
            self.assertTrue(all(s['ready'] and s['managed'] for s in states))
            runtime.stop(items[0]['id'])
            self.assertTrue(service.probe(items[1], registry, runtime.processes())['ready'])
        finally:
            for item in items:
                if runtime.owned(item['id'], runtime.processes()): runtime.stop(item['id'])

    def test_invalid_extension_does_not_break_registry(self):
        path = storage.DATA / 'integrations/broken/manifest.json'
        storage.write(path, {'id': '../bad'})
        try:
            self.assertIn('splash', storage.manifests())
            self.assertTrue(storage.REGISTRY_ERRORS)
        finally:
            path.unlink()

    def test_export_import_and_backup(self):
        result = service.action(dict(action='export'))
        exported = storage.read(Path(result['message']))
        self.assertIn('{root}', exported['settings']['model_roots'])
        service.action(dict(action='import', config=exported))
        self.assertTrue(list((storage.DATA / 'backups').glob('*.json')))
        self.assertEqual(storage.config()['version'], 2)

    def test_import_rejects_repeated_ids(self):
        self.current['providers'].append(self.current['providers'][0])
        with self.assertRaises(ValueError): service.action(dict(action='import', config=self.current))

    def test_missing_key_env_is_reported_without_request(self):
        with self.assertRaisesRegex(ValueError, 'Variable'):
            runtime.http('http://127.0.0.1:1/status', key_env='PIHUB_TEST_MISSING_SECRET')

    def test_saved_model_reference_survives_reload(self):
        model = dict(id='my/model', name='My model', format='mlx', path='', size=0, source='personal')
        service.action(dict(action='model-save', model=model))
        self.assertIn(model, storage.config()['models'])
        service.action(dict(action='model-delete', id='my/model'))
        self.assertEqual(storage.config()['models'], [])

    def test_custom_model_format_is_preserved_for_custom_provider_manifests(self):
        model = dict(id='/models/custom/model.exl2', name='Custom EXL2', format='exl2', path='/models/custom/model.exl2', size=0, source='personal')
        service.action(dict(action='model-save', model=model))
        self.assertEqual(storage.config()['models'][0]['format'], 'exl2')

    def test_terminal_supervisor_is_tracked_and_stops_child(self):
        path = storage.DATA / 'integrations/sleeper/manifest.json'
        manifest = dict(id='sleeper', kind='agent', name='Sleeper', icon='terminal', color='mint', description='Fixture', executables=['/bin/sleep'], command=['{executable}', '30'], fields=[])
        manifest['handlers'] = {'command': 'pihub_manager.hub.integrations.agents.common:command', 'stop': 'pihub_manager.hub.integrations.agents.common:stop'}
        storage.write(path, manifest)
        service.action(dict(action='save', item=dict(id='sleeper', adapter='sleeper', name='Sleeper', settings={})))
        runner = subprocess.Popen([sys.executable, '-m', 'pihub_manager.hub', 'run-agent', 'sleeper'], env=dict(os.environ), stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        child_pid = None
        try:
            for _ in range(40):
                record = runtime.owned('sleeper', runtime.processes())
                if record: break
                time.sleep(.05)
            self.assertIsNotNone(record)
            self.assertEqual(record['pid'], runner.pid)
            children = [row for row in runtime.family(runner.pid, runtime.processes()) if row['pid'] != runner.pid]
            self.assertTrue(children)
            child_pid = children[0]['pid']
            service.action(dict(action='stop', id='sleeper'))
            runner.communicate(timeout=5)
            self.assertNotIn(child_pid, runtime.processes())
        finally:
            if runner.poll() is None:
                runner.terminate(); runner.communicate(timeout=5)
            path.unlink()

    def test_absent_handlers_do_not_advertise_or_run_actions(self):
        manifest = dict(id='metadata-only', kind='agent', name='Metadata only', fields=[])
        path = storage.DATA / 'integrations/metadata-only/manifest.json'
        storage.write(path, manifest)
        try:
            registry = storage.manifests()
            self.assertEqual(capabilities(registry['metadata-only']), ([], []))
            item = dict(id='metadata-only', adapter='metadata-only', name='Metadata only', settings={})
            service.action(dict(action='save', item=item))
            with self.assertRaisesRegex(ValueError, 'ne propose pas'):
                service.action(dict(action='start', id=item['id']))
        finally:
            path.unlink()

    def test_local_python_handlers_and_custom_action_are_discovered(self):
        directory = storage.DATA / 'integrations/custom-hooks'
        directory.mkdir(parents=True, exist_ok=True)
        module_path = directory / 'custom_handlers.py'
        shutil.copy(Path(__file__).parent / 'fixtures/custom_handlers.py', module_path)
        path = directory / 'manifest.json'
        storage.write(path, dict(id='custom-hooks', kind='provider', handlers={'status': 'custom_handlers.py:status', 'clear-cache': 'custom_handlers.py:clear_cache', 'broken': 'custom_handlers.py:missing'}))
        try:
            registry = storage.manifests()
            actions, errors = capabilities(registry['custom-hooks'])
            self.assertEqual(actions, ['clear-cache'])
            self.assertEqual(len(errors), 1)
            item = dict(id='custom-hooks', adapter='custom-hooks', name='Custom', settings={})
            service.action(dict(action='save', item=item))
            self.assertEqual(service.action(dict(action='clear-cache', id=item['id']))['instance'], item['id'])
            status = service.probe(item, registry, {})
            self.assertTrue(status['ready'])
            self.assertEqual(status['model'], 'custom-model')
            self.assertEqual(status['memory'], 0)
        finally:
            path.unlink(); module_path.unlink()

    def model_change_fixture(self, pinned=False):
        current = copy.deepcopy(self.current)
        provider = current['providers'][0]
        before = copy.deepcopy(provider)
        provider['settings']['model'] = 'new-model'
        if pinned:
            current['agents'][1]['settings']['model'] = 'pinned-model'
        registry = storage.manifests()
        model_changes.remember(before, provider, current, registry)
        records = {a['id']: {'pid': 900 + index, 'argv': ['agent', '--model', 'old-model']} for index, a in enumerate(current['agents'][:2])}
        return current, registry, provider, records

    def test_model_change_detects_following_agents_but_not_pinned(self):
        current, registry, provider, records = self.model_change_fixture(pinned=True)
        with patch.object(runtime, 'owned', side_effect=lambda identifier, table: records.get(identifier)):
            plan = model_changes.plans(current, registry, {provider['id']: {'ready': True, 'model': 'old-model'}}, {})[0]
        self.assertFalse(plan['provider_ready'])
        self.assertTrue(next(a for a in plan['agents'] if a['id'] == 'pi')['needs_action'])
        self.assertFalse(next(a for a in plan['agents'] if a['id'] == 'hermes')['needs_action'])
        self.assertFalse(any(a['id'] == 'codex' for a in plan['agents']))

    def test_model_change_with_missing_policy_cannot_offer_restart(self):
        current, registry, provider, records = self.model_change_fixture()
        registry['pi']['handlers'].pop('model_change')
        with patch.object(runtime, 'owned', side_effect=lambda identifier, table: records.get(identifier)):
            plan = model_changes.plans(current, registry, {}, {})[0]
        pi = next(a for a in plan['agents'] if a['id'] == 'pi')
        self.assertFalse(pi['needs_action'])
        self.assertIn('Aucun handler', pi['reason'])

    def test_model_change_does_not_interrupt_before_provider_ready(self):
        current, registry, provider, records = self.model_change_fixture()
        with patch.object(runtime, 'owned', side_effect=lambda identifier, table: records.get(identifier)):
            plan = model_changes.plans(current, registry, {}, {})[0]
        with patch.object(model_changes, 'call') as handler:
            with self.assertRaisesRegex(ValueError, 'Aucun agent'):
                model_changes.apply(current, registry, plan, {})
            handler.assert_not_called()

    def test_model_change_skips_agents_already_on_target(self):
        current, registry, provider, records = self.model_change_fixture()
        for record in records.values(): record['model_context'] = {'model': 'new-model'}
        with patch.object(runtime, 'owned', side_effect=lambda identifier, table: records.get(identifier)):
            plan = model_changes.plans(current, registry, {provider['id']: {'ready': True, 'model': 'new-model'}}, {})[0]
        self.assertTrue(plan['provider_ready'])
        self.assertFalse(any(a['needs_action'] for a in plan['agents']))

    def test_model_update_calls_only_selected_handler(self):
        current, registry, provider, records = self.model_change_fixture()
        with patch.object(runtime, 'owned', side_effect=lambda identifier, table: records.get(identifier)):
            plan = model_changes.plans(current, registry, {provider['id']: {'ready': True, 'model': 'new-model'}}, {})[0]
        with patch.object(model_changes, 'call', return_value={'message': 'ok'}) as hook, patch.object(runtime, 'owned', return_value=None):
            model_changes.apply(current, registry, plan, {'agents': ['pi']})
        self.assertEqual(hook.call_count, 1)
        self.assertEqual(hook.call_args[0][0].item['id'], 'pi')
        self.assertEqual(hook.call_args[0][1], 'restart')
        self.assertEqual(hook.call_args[0][2]['model'], 'new-model')

    def test_combined_model_change_waits_for_provider_then_uses_agent_handler(self):
        current, registry, provider, records = self.model_change_fixture()
        provider_record = {'pid': 777, 'model_context': {'model': 'old-model'}}

        def planned_owned(identifier, table):
            if identifier == provider['id']:
                return provider_record
            return records.get(identifier)

        with patch.object(runtime, 'owned', side_effect=planned_owned):
            plan = model_changes.plans(
                current, registry,
                {provider['id']: {'ready': True, 'model': 'old-model', 'pid': 777}}, {},
            )[0]
        self.assertTrue(plan['provider_restart_available'])

        def handler(ctx, action, request):
            if ctx.item['id'] == provider['id'] and action == 'status':
                return {'ready': True, 'model': 'new-model'}
            return {'message': 'ok'}

        with patch.object(runtime, 'processes', return_value={}), \
             patch.object(runtime, 'owned', return_value=None), \
             patch.object(runtime, 'event'), \
             patch.object(model_changes, 'call', side_effect=handler) as hook:
            result = model_changes.apply(
                current, registry, plan,
                {'restart_provider': True, 'agents': ['pi']},
            )
        calls = [(entry.args[0].item['id'], entry.args[1]) for entry in hook.call_args_list]
        self.assertEqual(calls, [(provider['id'], 'restart'), (provider['id'], 'status'), ('pi', 'restart')])
        self.assertIn('1 agent', result['message'])

    def test_pi_handler_writes_its_own_resolved_model_catalog(self):
        with patch.object(splash_handler, 'status', return_value={'ready': True, 'model': 'live-pi-model'}), patch('pihub_manager.hub.configuration.executable', return_value='/bin/echo'):
            argv, environment, cwd = service.agent_command(self.current['agents'][0], storage.manifests(), self.current)
        catalogue = storage.read(Path(environment['PI_CODING_AGENT_DIR']) / 'models.json')
        self.assertEqual(catalogue['providers']['pihub']['models'][0]['id'], 'live-pi-model')
        self.assertIn('live-pi-model', argv)

    def test_codex_handler_preserves_native_or_resolves_selected_provider(self):
        agent = copy.deepcopy(self.current['agents'][2])
        with patch('pihub_manager.hub.configuration.executable', return_value='/bin/echo'):
            native, _, _ = service.agent_command(agent, storage.manifests(), self.current)
        self.assertNotIn('model_provider="pihub"', native)
        agent['settings']['provider'] = 'splash'
        with patch.object(splash_handler, 'status', return_value={'ready': True, 'model': 'live-codex-model'}), patch('pihub_manager.hub.configuration.executable', return_value='/bin/echo'):
            routed, _, _ = service.agent_command(agent, storage.manifests(), self.current)
        self.assertIn('live-codex-model', routed)
        self.assertIn('model_provider="pihub"', routed)

    def test_live_custom_model_handler_does_not_restart(self):
        current, registry, provider, records = self.model_change_fixture()
        directory = storage.DATA / 'integrations/custom-hooks'
        directory.mkdir(parents=True, exist_ok=True)
        module_path = directory / 'custom_live.py'
        shutil.copy(Path(__file__).parent / 'fixtures/custom_handlers.py', module_path)
        registry['pi']['source'] = str(directory / 'custom-live.json')
        registry['pi']['handlers']['model_change'] = 'custom_live.py:live_model_change'
        registry['pi']['handlers']['set_model'] = 'custom_live.py:set_model'
        try:
            with patch.object(runtime, 'owned', side_effect=lambda identifier, table: records.get(identifier)):
                plan = model_changes.plans(current, registry, {provider['id']: {'ready': True, 'model': 'new-model'}}, {})[0]
            self.assertEqual(next(a for a in plan['agents'] if a['id'] == 'pi')['action'], 'set_model')
            with patch.object(runtime, 'owned', return_value=None), patch.object(runtime, 'stop') as stop:
                model_changes.apply(current, registry, plan, {'agents': ['pi']})
                stop.assert_not_called()
        finally:
            module_path.unlink()


if __name__ == '__main__':
    unittest.main()
