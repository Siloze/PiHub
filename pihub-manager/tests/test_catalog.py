"""Catalog/override checks: no network, runtimes, or model weights required."""
import copy
import io
import json
import os
import shutil
import sys
import tarfile
import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import patch

# unittest discovers this module before test_hub. Both use an isolated home.
_temp = tempfile.TemporaryDirectory(prefix='pihub-catalog-tests-')
os.environ['PIHUB_DATA'] = _temp.name
from pihub_manager.hub import storage, catalog, customization, installer, service


class CatalogTests(unittest.TestCase):
    def tearDown(self):
        for key in ('config.json', 'model-changes.json'):
            (storage.DATA / key).unlink(missing_ok=True)

    def test_fresh_workspace_has_no_instances_or_model_references(self):
        (storage.DATA / 'config.json').unlink(missing_ok=True)
        self.assertEqual(storage.config()['providers'], [])
        self.assertEqual(storage.config()['agents'], [])
        self.assertEqual(storage.config()['models'], [])

    def test_presence_detects_instance_override_without_install_receipt(self):
        entry = dict(id='presence', adapter='presence')
        manifest = dict(id='presence', fields=[], executables=['/not/present'])
        item = dict(id='custom-instance', adapter='presence', settings={'executable': '/bin/echo'})
        found = catalog.detect(entry, {'providers': [item], 'agents': []}, {'presence': manifest})
        self.assertEqual(found['origin'], 'external')
        self.assertEqual(found['executable'], '/bin/echo')
        self.assertEqual(found['version'], '')
        self.assertEqual(found['instances'], ['custom-instance'])

    def test_presence_falls_back_to_manifest_and_excludes_missing_file(self):
        entry = dict(id='presence', adapter='presence')
        registry = {'presence': dict(fields=[], executables=['/bin/echo'])}
        current = {'providers': [], 'agents': []}
        self.assertEqual(catalog.detect(entry, current, registry)['origin'], 'external')
        registry['presence']['executables'] = ['/not/present']
        self.assertIsNone(catalog.detect(entry, current, registry))

    def test_remote_api_is_connected_not_a_local_installation(self):
        entry = dict(id='presence', adapter='presence')
        registry = {'presence': dict(fields=[], executables=[])}
        current = {'providers': [dict(id='api', adapter='presence', settings={})], 'agents': []}
        found = catalog.detect(entry, current, registry, {'api': {'ready': True}})
        self.assertEqual(found['origin'], 'connected')
        self.assertEqual(found['executable'], '')
        self.assertIsNone(catalog.detect(entry, current, registry, {'api': {'ready': False}}))

    def test_valid_managed_receipt_is_detected_even_without_instances(self):
        entry = dict(id='presence', adapter='presence')
        registry = {'presence': dict(fields=[], executables=[])}
        with patch.object(catalog, 'read', return_value={'presence': {'executable': '/bin/echo', 'revision': '1.0'}}):
            found = catalog.detect(entry, {'providers': [], 'agents': []}, registry)
        self.assertEqual(found['origin'], 'pihub')
        self.assertEqual(found['version'], '1.0')

    def test_every_shipped_adapter_has_versioned_recipe_and_exportable_template(self):
        registry = storage.manifests()
        entries = catalog.entries()
        for key in ('splash', 'llamacpp', 'mlx', 'ollama', 'remote', 'pi', 'hermes', 'codex'):
            self.assertIn(key, entries)
            definition = catalog.template(entries[key])
            self.assertEqual(definition['id'], registry[key]['id'])
            self.assertTrue(definition['compatibility']['revision'])
            for step in entries[key]['steps']:
                self.assertTrue(step.get('argv') or (step.get('download') and len(step['sha256']) == 64))

    def test_template_only_does_not_launch_or_download_and_avoids_port_collision(self):
        entry = catalog.entries()['llamacpp']
        target = storage.DATA / 'integrations/llamacpp/manifest.json'
        old = target.read_bytes() if target.exists() else None
        try:
            with patch.object(catalog.subprocess, 'Popen') as launch:
                service.action({'action': 'catalog-template', 'id': 'llamacpp'})
                service.action({'action': 'catalog-template', 'id': 'llamacpp'})
                launch.assert_not_called()
            items = storage.config()['providers']
            self.assertNotEqual(items[-1]['settings']['port'], items[-2]['settings']['port'])
            self.assertEqual(items[-1]['settings']['model'], '')
        finally:
            if old is None:
                target.unlink(missing_ok=True)
            else:
                target.write_bytes(old)

    def test_manifest_import_validates_without_launching_and_can_create_instance(self):
        definition = copy.deepcopy(storage.manifests()['remote'])
        definition['id'] = 'imported-fixture'
        definition['name'] = 'Imported fixture'
        target = storage.DATA / 'integrations/imported-fixture/manifest.json'
        config_path = storage.DATA / 'config.json'
        previous_config = config_path.read_bytes() if config_path.exists() else None
        try:
            with patch.object(service.subprocess, 'Popen') as launch:
                response = service.action({
                    'action': 'manifest-import', 'manifest': definition,
                    'create_instance': True,
                })
                launch.assert_not_called()
            self.assertTrue(target.is_file())
            self.assertEqual(response['instance_id'], storage.config()['providers'][-1]['id'])
            instance = storage.config()['providers'][-1]
            self.assertEqual(instance['adapter'], 'imported-fixture')
            self.assertEqual(instance['settings']['model'], '')
            self.assertEqual(response['message'], 'JSON importé et instance créée : Imported fixture')
        finally:
            target.unlink(missing_ok=True)
            if previous_config is None:
                config_path.unlink(missing_ok=True)
            else:
                config_path.write_bytes(previous_config)

    def test_manifest_editor_persists_identity_command_and_unknown_metadata(self):
        definition = copy.deepcopy(storage.manifests()['remote'])
        definition.update(id='editable-fixture', name='My API', icon='leaf', executables=['/bin/echo'], command=['{executable}', 'hello'])
        definition['custom_metadata'] = {'retained': True}
        target = storage.DATA / 'integrations/editable-fixture/manifest.json'
        try:
            service.action({'action': 'manifest-save', 'manifest': definition})
            saved = storage.manifests()['editable-fixture']
            self.assertEqual(saved['icon'], 'leaf')
            self.assertEqual(saved['command'], ['{executable}', 'hello'])
            self.assertTrue(saved['custom_metadata']['retained'])
            service.action({'action': 'manifest-save', 'manifest': saved})
            self.assertTrue(list((storage.DATA / 'backups').glob('editable-fixture-*.json')))
        finally:
            target.unlink(missing_ok=True)

    def test_malformed_manifest_does_not_overwrite_valid_definition(self):
        invalid = copy.deepcopy(storage.manifests()['remote'])
        invalid['command'] = 'echo not-an-argv-array'
        with self.assertRaises(ValueError):
            customization.save_manifest(invalid)
        invalid['command'] = []
        invalid['fields'] = [{'key': 'broken'}]
        with self.assertRaises(ValueError):
            customization.save_manifest(invalid)

    def test_install_requires_confirmation_and_acknowledged_foreign_revision(self):
        with self.assertRaisesRegex(ValueError, 'Confirmez'):
            service.action({'action': 'catalog-install', 'id': 'pi'})
        with self.assertRaisesRegex(ValueError, 'hors référence'):
            service.action({'action': 'catalog-install', 'id': 'pi', 'confirmed': True, 'revision': '9.9.9'})
        with self.assertRaisesRegex(ValueError, 'exacte'):
            service.action({'action': 'catalog-install', 'id': 'splash', 'confirmed': True, 'revision': '9.9.9', 'acknowledge_unverified': True})
        with self.assertRaisesRegex(ValueError, 'invalide'):
            service.action({'action': 'catalog-install', 'id': 'pi', 'confirmed': True, 'revision': '--bad'})

    def test_background_worker_installs_fixture_without_blocking_or_launching_it(self):
        entry = dict(id='install-fixture', adapter='install-fixture', kind='provider', name='Fixture', revision='1.0', verification='fixture', repository='', prerequisites=[], executable='{package}/runtime', manifest=dict(id='install-fixture', kind='provider', name='Fixture', icon='cpu', color='cyan', description='Test', fields=[dict(key='executable', label='Executable', group='Runtime', type='file', default='')], command=['{executable}'], executables=[], handlers={}), steps=[dict(label='Prepare isolated executable', argv=[sys.executable, '-c', 'import shutil,sys,time; time.sleep(.2); shutil.copy("/bin/echo",sys.argv[1])', '{package}/runtime'])])
        try:
            with patch.object(catalog, 'entries', return_value={entry['id']: entry}):
                start = time.monotonic()
                service.action({'action': 'catalog-install', 'id': entry['id'], 'confirmed': True})
                self.assertLess(time.monotonic() - start, 2)
                deadline = time.monotonic() + 12
                while time.monotonic() < deadline:
                    jobs = [j for j in catalog.snapshot()['jobs'] if j['entry_id'] == entry['id']]
                    if jobs and jobs[0]['state'] not in ('queued', 'running'):
                        break
                    time.sleep(.1)
                self.assertEqual(jobs[0]['state'], 'done', jobs)
                installed = catalog.snapshot()['installed'][entry['id']]
                self.assertTrue(Path(installed['executable']).is_file())
                item = storage.config()['providers'][-1]
                self.assertEqual(item['settings']['executable'], installed['executable'])
                self.assertEqual(storage.manifests()[item['adapter']]['handlers'], {})
                self.assertNotIn('recipe', jobs[0])
        finally:
            (storage.DATA / 'integrations/install-fixture/manifest.json').unlink(missing_ok=True)

    def test_folder_validation_checks_type_and_declared_handler_before_copy(self):
        identifier = 'validated-folder-fixture'
        target = storage.DATA / 'integrations' / identifier
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            storage.write(folder / 'manifest.json', dict(
                id=identifier, kind='agent',
                handlers={'status': 'handlers/status.py:status'},
            ))
            request = {'action': 'bundle-validate', 'path': str(folder), 'expected_kind': 'agent', 'expected_id': identifier}
            with self.assertRaisesRegex(ValueError, 'introuvable'):
                service.action(request)
            (folder / 'handlers').mkdir()
            shutil.copy2(Path(__file__).parent / 'fixtures' / 'bundle_handler.py', folder / 'handlers' / 'status.py')
            with self.assertRaisesRegex(ValueError, 'pas un provider'):
                service.action({**request, 'expected_kind': 'provider'})
            self.assertIn('Dossier valide', service.action(request)['message'])
            self.assertFalse(target.exists())
            try:
                service.action({'action': 'bundle-import', 'path': str(folder), 'expected_kind': 'agent', 'expected_id': identifier})
                self.assertTrue((target / 'handlers' / 'status.py').is_file())
                self.assertEqual(storage.manifests()[identifier]['kind'], 'agent')
                self.assertEqual(storage.manifests()[identifier]['name'], identifier)
            finally:
                shutil.rmtree(target, ignore_errors=True)

    def test_portable_folder_import_export_and_real_background_install(self):
        from pihub_manager.hub import bundles
        identifier = 'portable-bundle-fixture'
        personal = storage.DATA / 'integrations' / identifier
        try:
            with tempfile.TemporaryDirectory() as temporary:
                folder = Path(temporary)
                for name in ('bundle_handler.py', 'bundle_helper.py'):
                    shutil.copy2(Path(__file__).parent / 'fixtures' / name, folder / name)
                storage.write(folder / 'manifest.json', dict(
                    id=identifier, kind='provider', name='Portable fixture', icon='cpu', color='mint',
                    description='Portable bundle', command=['{executable}'],
                    fields=[dict(key='executable', label='Runtime', group='Runtime', type='file', default='')],
                    handlers={'status': 'bundle_handler.py:status'},
                    install=dict(revision='1.0', executable='{package}/runtime', steps=[dict(
                        label='Install from bundled resource', argv=[sys.executable, '-c',
                        'import pathlib,shutil,sys; assert pathlib.Path(sys.argv[1]).is_file(); shutil.copy("/bin/echo",sys.argv[2])',
                        '{bundle}/bundle_helper.py', '{package}/runtime'])]),
                ))
                service.action({'action': 'bundle-import', 'path': str(folder)})
            # The source directory is gone: the imported folder must stand alone.
            manifest = storage.manifests()[identifier]
            self.assertTrue((personal / 'bundle_helper.py').is_file())
            self.assertEqual(catalog.entries()[identifier]['revision'], '1.0')
            item = dict(id='portable-status', adapter=identifier, settings={})
            state = service.probe(item, {identifier: manifest}, {})
            self.assertEqual(state['model'], 'portable-bundle-model')
            exported = bundles.export_bundle(manifest)
            self.assertTrue((exported / 'bundle_handler.py').is_file())
            self.assertNotIn('source', storage.read(exported / 'manifest.json'))
            with self.assertRaisesRegex(ValueError, 'existe déjà'):
                bundles.import_bundle(exported)
            bundles.import_bundle(exported, replace=True)
            self.assertTrue(list((storage.DATA / 'backups').glob(identifier + '-bundle-*')))
            service.action({'action': 'catalog-install', 'id': identifier, 'confirmed': True})
            deadline = time.monotonic() + 12
            while time.monotonic() < deadline:
                jobs = [job for job in catalog.snapshot()['jobs'] if job['entry_id'] == identifier]
                if jobs and jobs[0]['state'] not in ('queued', 'running'):
                    break
                time.sleep(.1)
            self.assertEqual(jobs[0]['state'], 'done', jobs)
            self.assertTrue(Path(catalog.snapshot()['installed'][identifier]['executable']).is_file())
        finally:
            if personal.exists():
                shutil.rmtree(personal)

    def test_archive_rejects_traversal_and_escaping_links(self):
        with tempfile.TemporaryDirectory() as folder:
            archive = Path(folder) / 'bad.tar.gz'
            for name, link in [('../escape', ''), ('link', '../../escape')]:
                with tarfile.open(archive, 'w:gz') as bundle:
                    member = tarfile.TarInfo(name)
                    if link:
                        member.type = tarfile.SYMTYPE
                        member.linkname = link
                    bundle.addfile(member, io.BytesIO(b''))
                with self.assertRaises(ValueError):
                    installer.extract(archive, Path(folder) / 'destination')

    def test_save_from_ui_remembers_old_model_without_explicit_request_id(self):
        manifest = storage.manifests()['splash']
        item = dict(id='provider-model-fixture', adapter='splash', name='Fixture', settings=storage.defaults(manifest))
        service.action({'action': 'save', 'item': item})
        before = item['settings']['model']
        item['settings']['model'] = 'changed-model'
        service.action({'action': 'save', 'item': item})
        plan = storage.read(storage.DATA / 'model-changes.json')['provider-model-fixture']
        self.assertEqual(plan['before'], before)
        self.assertEqual(plan['after'], 'changed-model')
