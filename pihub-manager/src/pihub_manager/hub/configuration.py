"""Shared argv/configuration helpers; no integration-specific dispatch."""
import glob
import json
import os
import shutil
from pathlib import Path
from urllib.parse import urlparse
from .storage import ROOT, DATA, defaults, valid_id


def expand(value):
    return str(value).replace('{root}', str(ROOT)).replace('{home}', str(Path.home()))


def executable(item, manifest):
    override = item['settings'].get('executable', '')
    candidates = [override] if override else manifest.get('executables', [])
    for candidate in candidates:
        candidate = expand(candidate)
        found = shutil.which(candidate)
        if found:
            return found
        for path in sorted(glob.glob(candidate), reverse=True):
            if Path(path).is_file() and os.access(path, os.X_OK):
                return path
    return ''


def env_for(manifest, values):
    env = dict(os.environ)
    env['PIHUB_ROOT'] = str(ROOT)
    env['PIHUB_DATA'] = str(DATA)
    env['PATH'] = ':'.join([str(ROOT / 'env/pi-client/node_modules/.bin'), '/opt/homebrew/bin', '/usr/local/bin', env.get('PATH', '/usr/bin:/bin')])
    for key, value in manifest.get('env', {}).items():
        env[key] = expand(value).format_map(values)
    return env


def values_for(item, manifest):
    values = {**defaults(manifest), **item['settings']}
    values = {key: expand(value) for key, value in values.items()}
    values.update(root=str(ROOT), home=str(Path.home()), executable=executable(item, manifest))
    values['bundle'] = str(Path(manifest['source']).parent) if manifest.get('source') else ''
    return values


def build_command(item, manifest):
    values = values_for(item, manifest)
    if not values['executable']:
        raise ValueError('Runtime introuvable. Installez-le ou indiquez son exécutable dans Avancé.')
    argv = [expand(arg).format_map(values) for arg in manifest['command']]
    for key, mapping in manifest.get('flags', {}).items():
        argv.extend(mapping.get(values.get(key, '').lower(), []))
    args = json.loads(values.get('extra_args') or '[]')
    if not isinstance(args, list) or not all(isinstance(a, str) and '\x00' not in a for a in args):
        raise ValueError('Arguments supplémentaires : utilisez une liste JSON de chaînes.')
    return argv + args, env_for(manifest, values), values


def endpoint(item):
    settings = item['settings']
    if settings.get('base_url'):
        return settings['base_url'].rstrip('/')
    host = settings.get('host', '127.0.0.1')
    if host in ('0.0.0.0', '::'):
        host = '127.0.0.1'
    return f"http://{host}:{settings.get('port', '18000')}/v1"


def validate(item, manifest):
    valid_id(item['id'])
    if not item.get('name', '').strip():
        raise ValueError('Donnez un nom à cette instance.')
    allowed = {f['key']: f for f in manifest['fields']}
    for key, value in item.get('settings', {}).items():
        if not isinstance(value, str) or '\x00' in value:
            raise ValueError('Les réglages doivent être des chaînes sans caractère nul.')
        field = allowed.get(key)
        if not field:
            raise ValueError(f'Réglage inconnu : {key}')
        if field['type'] == 'select' and value not in field.get('options', []):
            raise ValueError(f'Choix invalide : {key}')
        if field['type'] == 'toggle' and value not in ('true', 'false'):
            raise ValueError(f'Interrupteur invalide : {key}')
        if field['type'] in ('number', 'slider'):
            number = float(value)
            if not __import__('math').isfinite(number) or number < float(field.get('min', 0)) or number > float(field.get('max', 10000000)):
                raise ValueError(f'Valeur hors limites : {key}')
            if 'port' in key and (not number.is_integer() or not 1024 <= number <= 65535):
                raise ValueError('Le port doit être un entier entre 1024 et 65535.')
    for key in ('template_args',):
        if key in item['settings'] and not isinstance(json.loads(item['settings'][key]), dict):
            raise ValueError('Les arguments de template doivent être un objet JSON.')
    args = json.loads(item.get('settings', {}).get('extra_args') or '[]')
    if not isinstance(args, list) or not all(isinstance(a, str) for a in args):
        raise ValueError('Les arguments supplémentaires doivent être une liste JSON de chaînes.')
    if item['settings'].get('base_url'):
        parsed = urlparse(item['settings']['base_url'])
        if parsed.scheme not in ('http', 'https') or not parsed.hostname:
            raise ValueError('URL HTTP(S) requise.')
