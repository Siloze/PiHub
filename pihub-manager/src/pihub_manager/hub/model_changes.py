"""Generic provider→agent dependency planning, delegated to optional policy hooks."""
import uuid
import time
from .integrations import Context, call, resolve
from .storage import DATA, read, write
from .configuration import endpoint

PATH = DATA / 'model-changes.json'


def remember(previous, incoming, current, registry):
    if not previous:
        return
    field = registry[incoming['adapter']].get('model_field', 'model')
    before = previous['settings'].get(field, '')
    after = incoming['settings'].get(field, '')
    if before == after:
        return
    pending = read(PATH, {})
    pending[incoming['id']] = dict(id=str(uuid.uuid4()), provider_id=incoming['id'], provider_name=incoming['name'], before=before, after=after)
    write(PATH, pending)


def launched_model(record):
    context = record.get('model_context', {})
    if context.get('model'):
        return context['model']
    argv = record.get('argv', [])
    if '--model' in argv and len(argv) > argv.index('--model') + 1:
        return argv[argv.index('--model') + 1]
    return ''


def plans(current, registry, states, table):
    output = []
    for pending in read(PATH, {}).values():
        provider = next((p for p in current['providers'] if p['id'] == pending['provider_id']), None)
        if not provider or provider['adapter'] not in registry:
            continue
        manifest = registry[provider['adapter']]
        if provider['settings'].get(manifest.get('model_field', 'model'), '') != pending['after']:
            continue
        state = states.get(provider['id'], {})
        process = Context(provider, current, registry).runtime.owned(provider['id'], table) or {}
        matches = state.get('model') == pending['after'] or process.get('model_context', {}).get('model') == pending['after']
        if manifest.get('multi_model'):
            matches = pending['after'] in state.get('models', [])
        provider_active = bool(process or state.get('pid'))
        provider_restart_available = bool(
            provider_active and not matches and resolve(manifest, 'restart')
        )
        provider_restart_uncertain = bool(provider_restart_available and (
            provider['settings'].get('executable') or not process
        ))
        result = dict(
            pending,
            provider_ready=bool(state.get('ready') and matches),
            provider_restart_available=provider_restart_available,
            provider_restart_uncertain=provider_restart_uncertain,
            provider_restart_reason=(
                'Exécutable personnalisé ou processus externe : PiHub va tenter la relance, '
                'mais ne peut pas garantir que le programme acceptera la commande.'
                if provider_restart_uncertain else
                'Le moteur sera arrêté puis relancé avec la nouvelle configuration.'
                if provider_restart_available else ''
            ),
            agents=[],
        )
        for agent in current['agents']:
            agent_manifest = registry.get(agent['adapter'], {})
            routing = agent_manifest.get('routing', {})
            if not routing or agent['settings'].get(routing.get('provider_field', 'provider')) != provider['id']:
                continue
            ctx = Context(agent, current, registry, table=table)
            records = [r for identifier in (agent['id'], agent['id'] + '-web') if (r := ctx.runtime.owned(identifier, table))]
            from .integrations.agents.common import external_pid
            external = external_pid(ctx, table) if not records else None
            pinned = bool(agent['settings'].get(routing.get('model_field', 'model'), ''))
            row = dict(
                id=agent['id'], name=agent['name'], active=bool(records or external), pinned=pinned,
                action='', reason='', needs_action=False,
                uncertain=bool(agent['settings'].get('executable') or external),
                external=bool(external),
            )
            if pinned:
                row['reason'] = 'Modèle fixé dans cet agent : il ne suit pas automatiquement le moteur.'
            elif not records and not external:
                row['reason'] = 'Arrêté : le nouveau modèle sera appliqué au prochain lancement.'
            elif records and all(launched_model(r) == pending['after'] for r in records):
                row['reason'] = 'Cette session utilise déjà le modèle sélectionné.'
            elif not resolve(agent_manifest, 'model_change'):
                row['reason'] = 'Aucun handler de changement de modèle déclaré : intervention manuelle.'
            else:
                try:
                    decision = call(ctx, 'model_change', {'model': pending['after'], 'previous_model': pending['before'], 'provider': provider})
                    action = decision.get('action', '')
                    reason = decision.get('reason', '')
                    if external:
                        reason = 'Processus externe correspondant à l’exécutable personnalisé détecté ; relance tentée seulement après confirmation. ' + reason
                    row.update(action=action, reason=reason)
                    row['needs_action'] = bool(action and action not in {'command', 'prepare', 'status', 'model_change'} and resolve(agent_manifest, action))
                    if action and not row['needs_action']:
                        row['reason'] = 'Action de mise à jour non implémentée : ' + action
                except Exception as error:
                    row['reason'] = 'Handler de changement : ' + str(error)
            result['agents'].append(row)
        output.append(result)
    return output


def dismiss(identifier):
    pending = read(PATH, {})
    pending = {key: value for key, value in pending.items() if value['id'] != identifier}
    write(PATH, pending)


def provider_matches(state, process, manifest, target):
    """Use the provider's own status plus PiHub's launch context as evidence."""
    if manifest.get('multi_model'):
        return target in state.get('models', [])
    return (
        state.get('model') == target
        or process.get('model_context', {}).get('model') == target
    )


def wait_for_provider(ctx, manifest, target, timeout=45):
    """Do not touch dependent agents until the restarted provider is usable."""
    deadline = time.monotonic() + timeout
    last_state = {}
    while time.monotonic() < deadline:
        last_state = call(ctx, 'status', {})
        table = ctx.runtime.processes()
        process = ctx.runtime.owned(ctx.item['id'], table) or {}
        if last_state.get('ready') and provider_matches(last_state, process, manifest, target):
            return
        time.sleep(.5)
    detail = last_state.get('error') or 'il n’est pas encore prêt avec le nouveau modèle.'
    raise ValueError(
        'Le moteur a été relancé, mais PiHub ne confirme pas encore le modèle « '
        + target + ' » : ' + detail + ' Aucun agent n’a été arrêté.'
    )


def apply(current, registry, plan, request):
    provider_ready = bool(plan.get('provider_ready'))
    if request.get('restart_provider'):
        if not plan.get('provider_restart_available'):
            raise ValueError('Le moteur ne peut pas être relancé automatiquement. Redémarrez-le depuis son application ou son terminal.')
        if plan.get('provider_restart_uncertain') and not request.get('confirm_uncertain'):
            raise ValueError('Confirmez la relance incertaine du moteur personnalisé ou externe.')
        provider = next((p for p in current['providers'] if p['id'] == plan['provider_id']), None)
        if not provider:
            raise ValueError('Moteur introuvable ; actualisez PiHub.')
        provider_ctx = Context(provider, current, registry)
        provider_table = provider_ctx.runtime.processes()
        external = not provider_ctx.runtime.owned(provider['id'], provider_table)
        call(
            provider_ctx, 'restart',
            {'confirm_external': bool(external and request.get('confirm_uncertain'))},
        )
        provider_ctx.runtime.event(
            'Relance du moteur', provider['name'], plan['after'],
        )
        # The provider status handler is authoritative for readiness.  Waiting
        # here makes a single confirmation safe: no agent handler is called
        # until the new endpoint/model is actually available.
        wait_for_provider(provider_ctx, registry[provider['adapter']], plan['after'])
        provider_ready = True
        # Backward-compatible provider-only action from older clients.
        if 'agents' not in request:
            return {'message': 'Moteur relancé et prêt avec le nouveau modèle. Les agents peuvent maintenant être mis à jour.'}
    if not provider_ready:
        raise ValueError('Chargez d’abord le nouveau modèle sur le moteur. Aucun agent n’a été arrêté.')
    eligible = {a['id']: a for a in plan['agents'] if a['needs_action']}
    selected = request.get('agents', list(eligible))
    if not all(identifier in eligible for identifier in selected):
        raise ValueError('La sélection d’agents a changé ; actualisez la proposition.')
    if any(eligible[identifier].get('uncertain') for identifier in selected) and not request.get('confirm_uncertain'):
        raise ValueError('Confirmez la relance des agents utilisant un exécutable personnalisé.')
    errors = []
    for identifier in selected:
        agent = next(a for a in current['agents'] if a['id'] == identifier)
        ctx = Context(agent, current, registry)
        try:
            row = eligible[identifier]
            call(ctx, row['action'], {
                'model': plan['after'], 'provider_id': plan['provider_id'],
                'confirm_external': bool(row.get('external') and request.get('confirm_uncertain')),
            })
            for key in (identifier, identifier + '-web'):
                record = ctx.runtime.owned(key, ctx.runtime.processes())
                if record:
                    record['model_context'] = {'model': plan['after'], 'provider': plan['provider_id']}
                    write(ctx.runtime.record_path(key), record)
            ctx.runtime.event('Mise à jour du modèle', agent['name'], plan['after'])
        except Exception as error:
            errors.append(agent['name'] + ' : ' + str(error))
    if not errors and set(selected) == set(eligible):
        dismiss(plan['id'])
    if errors:
        raise ValueError('Certaines mises à jour ont échoué : ' + ' ; '.join(errors))
    return {'message': f'{len(selected)} agent(s) mis à jour / relancés.'}
