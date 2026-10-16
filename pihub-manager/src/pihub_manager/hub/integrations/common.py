"""Optional helpers shared by providers and agents; none are implicit hooks."""
from pathlib import Path
from ..configuration import values_for, expand


def logs(ctx, request):
    channel = request.get('channel', '')
    suffix = ctx.manifest.get('log_channels', {}).get(channel, '')
    if channel and not suffix:
        raise ValueError('Canal de journal non déclaré : ' + channel)
    path = ctx.data / 'logs' / (ctx.item['id'] + suffix + '.log')
    if not path.exists():
        values = values_for(ctx.item, ctx.manifest)
        for template in ctx.manifest.get('log_paths', []):
            candidate = Path(expand(template).format_map(values))
            if candidate.is_file():
                path = candidate
                break
    if not path.exists():
        return {'message': 'Aucun journal pour cette instance.'}
    with path.open('rb') as stream:
        stream.seek(max(0, path.stat().st_size - 20000))
        return {'message': stream.read().decode('utf-8', errors='replace')}
