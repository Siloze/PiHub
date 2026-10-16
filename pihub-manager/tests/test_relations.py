"""Model relations distinguish current sessions from next-launch settings."""
import unittest
from pihub_manager.hub.relations import model_bindings


class RelationsTests(unittest.TestCase):
    def setUp(self):
        self.models = [dict(id='old', path=''), dict(id='new', path=''), dict(id='other', path='/weights/other.gguf')]
        self.registry = {'engine': {'model_field': 'weights'}, 'assistant': {'routing': {'provider_field': 'target', 'model_field': 'pinned'}}}
        self.current = {'providers': [dict(id='server', adapter='engine', name='Server', settings={'weights': 'new'})], 'agents': [dict(id='follower', adapter='assistant', name='Follower', settings={'target': 'server', 'pinned': ''}), dict(id='pinned', adapter='assistant', name='Pinned', settings={'target': 'server', 'pinned': '/weights/other.gguf'})]}

    def test_configured_provider_and_followers_attach_to_new_model(self):
        value = model_bindings(self.models, self.current, self.registry, {})
        self.assertEqual({r['id'] for r in value['new']}, {'server', 'follower'})
        self.assertTrue(all(r['configured'] and not r['active'] for r in value['new']))
        self.assertEqual(value['new'][1]['via'], 'Server')

    def test_running_old_model_is_not_relabelled_as_new(self):
        states = {'server': {'ready': True, 'model': 'old'}, 'follower': {'ready': True, 'model': 'old'}}
        value = model_bindings(self.models, self.current, self.registry, states)
        self.assertTrue(all(r['active'] and not r['configured'] for r in value['old']))
        self.assertTrue(all(r['configured'] and not r['active'] for r in value['new']))

    def test_pinned_agent_does_not_follow_provider_assignment(self):
        value = model_bindings(self.models, self.current, self.registry, {})
        self.assertEqual(value['other'][0]['id'], 'pinned')
        self.assertEqual(value['other'][0]['via'], '')
        self.assertNotIn('pinned', [r['id'] for r in value['new']])

    def test_stopped_agent_is_not_reported_as_running_on_old_model(self):
        value = model_bindings(self.models, self.current, self.registry, {'follower': {'ready': False, 'model': 'old'}})
        self.assertEqual(value['old'], [])
