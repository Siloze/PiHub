"""Tiny real HTTP process for multi-instance lifecycle integration tests."""
import argparse
import json
from http.server import BaseHTTPRequestHandler, HTTPServer

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(json.dumps({'ready': True, 'data': [{'id': 'fixture-model'}]}).encode())

    def log_message(self, *args):
        pass

parser = argparse.ArgumentParser()
parser.add_argument('--port', type=int, required=True)
args = parser.parse_args()
HTTPServer(('127.0.0.1', args.port), Handler).serve_forever()
