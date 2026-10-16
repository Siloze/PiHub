from .bundle_helper import MODEL


def status(ctx, request):
    return {'ready': True, 'model': MODEL}
