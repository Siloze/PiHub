"""Explicit configured vs running model attachments, independent of adapters."""


def model_bindings(models, current, registry, states):
    output = {}
    for model in models:
        identifiers = {v for v in (model['id'], model.get('path')) if v}
        rows = []
        configured_providers = set()
        for provider in current['providers']:
            manifest = registry.get(provider['adapter'], {})
            configured = provider['settings'].get(manifest.get('model_field', 'model'), '') in identifiers
            if configured:
                configured_providers.add(provider['id'])
            state = states.get(provider['id'], {})
            active = bool(state.get('ready') and state.get('model') in identifiers)
            if configured or active:
                rows.append(dict(id=provider['id'], name=provider['name'], kind='provider', configured=configured, active=active, via=''))
        for agent in current['agents']:
            routing = registry.get(agent['adapter'], {}).get('routing', {})
            target = agent['settings'].get(routing.get('provider_field', ''), '')
            pinned = agent['settings'].get(routing.get('model_field', 'model'), '')
            configured = pinned in identifiers if pinned else target in configured_providers
            state = states.get(agent['id'], {})
            # Agent status.models contains actual session models (not an API catalogue).
            active = bool(state.get('ready') and (state.get('model') in identifiers or any(m in identifiers for m in state.get('models', []))))
            if configured or active:
                provider = next((p for p in current['providers'] if p['id'] == target), None)
                rows.append(dict(id=agent['id'], name=agent['name'], kind='agent', configured=configured, active=active, via='' if pinned else provider['name'] if provider else ''))
        output[model['id']] = rows
    return output
