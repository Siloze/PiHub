"""JSON request on stdin; JSON response on stdout. Also usable by Terminal."""
import json
import sys
from .service import action, run_agent


def main():
    try:
        if sys.argv[1:2] == ['run-agent']:
            return run_agent(sys.argv[2])
        if len(sys.argv) > 1:
            request = {'action': sys.argv[1], 'id': sys.argv[2] if len(sys.argv) > 2 else ''}
        else:
            request = json.load(sys.stdin) if not sys.stdin.isatty() else {'action': 'snapshot'}
        print(json.dumps({'ok': True, 'data': action(request)}, ensure_ascii=False))
        return 0
    except Exception as error:
        print(json.dumps({'ok': False, 'error': str(error)}, ensure_ascii=False))
        return 1


if __name__ == '__main__':
    sys.exit(main())
