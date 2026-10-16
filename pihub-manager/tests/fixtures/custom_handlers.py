"""Example independent integration: no inheritance and no global-manager edits."""
def status(ctx, request):
    return {'ready': True, 'model': 'custom-model'}


def clear_cache(ctx, request):
    return {'message': 'Custom handler invoked', 'instance': ctx.item['id']}


def live_model_change(ctx, request):
    return {'action': 'set_model', 'reason': 'This integration supports a live model update.'}


def set_model(ctx, request):
    return {'message': 'Custom live model applied', 'model': request['model']}
