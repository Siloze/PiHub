"""Small echo API for the PiHub tutorial; does not run an AI model.

Only the routes required by the demo client are implemented. Streaming,
tool calls and general compatibility with production agents are not provided.
"""
import argparse
import json
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class Handler(BaseHTTPRequestHandler):
    def send_json(self, status, value):
        content = json.dumps(value, ensure_ascii=False).encode('utf-8')
        self.send_response(status)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Content-Length', str(len(content)))
        self.end_headers()
        self.wfile.write(content)

    def do_GET(self):
        if self.path.rstrip('/') == '/health':
            self.send_json(200, {'ready': True, 'model': self.server.model})
        elif self.path.rstrip('/') == '/v1/models':
            self.send_json(200, {'data': [{'id': self.server.model, 'object': 'model'}]})
        else:
            self.send_json(404, {'error': 'Route de démonstration inconnue.'})

    def do_POST(self):
        if self.path.rstrip('/') != '/v1/chat/completions':
            self.send_json(404, {'error': 'Route de démonstration inconnue.'})
            return
        try:
            request = json.loads(self.rfile.read(int(self.headers.get('Content-Length', '0'))))
            if request.get('stream'):
                raise ValueError('La démo ne prend pas en charge le streaming.')
            if request.get('model') != self.server.model:
                raise ValueError('Modèle de démonstration inconnu.')
            prompts = [message['content'] for message in request['messages'] if message.get('role') == 'user']
            answer = 'Écho de démonstration : ' + str(prompts[-1] if prompts else '')
        except (ValueError, TypeError, KeyError) as error:
            self.send_json(400, {'error': str(error)})
            return
        self.send_json(200, {
            'id': 'demo-echo', 'object': 'chat.completion', 'created': int(time.time()),
            'model': self.server.model,
            'choices': [{'index': 0, 'message': {'role': 'assistant', 'content': answer}, 'finish_reason': 'stop'}],
        })

    def log_message(self, format, *args):
        # Repeated health probes should not fill the tutorial's log.
        pass


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--host', default='127.0.0.1')
    parser.add_argument('--port', type=int, default=18190)
    parser.add_argument('--model', default='demo-echo')
    args = parser.parse_args()
    with ThreadingHTTPServer((args.host, args.port), Handler) as server:
        server.model = args.model
        print(f'Démo prête : http://{args.host}:{args.port}/v1 — {args.model}', flush=True)
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            pass


if __name__ == '__main__':
    main()
