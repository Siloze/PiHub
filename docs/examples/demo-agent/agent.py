"""Terminal client for the PiHub echo tutorial; no inference or memory."""
import argparse
import json
import os
import urllib.error
import urllib.request


def answer(base_url, model, prompt):
    payload = json.dumps({
        'model': model, 'stream': False,
        'messages': [{'role': 'user', 'content': prompt}],
    }).encode('utf-8')
    request = urllib.request.Request(
        base_url.rstrip('/') + '/chat/completions', data=payload,
        headers={'Content-Type': 'application/json'},
    )
    with urllib.request.urlopen(request, timeout=20) as response:
        result = json.load(response)
    return result['choices'][0]['message']['content']


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--model', required=True)
    parser.add_argument('--prompt', help='Une requête unique, puis quitter.')
    args = parser.parse_args()
    base_url = os.environ.get('DEMO_BASE_URL', 'http://127.0.0.1:18190/v1')
    if args.prompt is not None:
        print(answer(base_url, args.model, args.prompt))
        return
    print('Agent pédagogique PiHub — /quit pour quitter. Réponses par écho, sans modèle IA.')
    while True:
        try:
            prompt = input('Vous > ').strip()
        except (EOFError, KeyboardInterrupt):
            return
        if prompt in ('/quit', '/exit'):
            return
        if not prompt:
            continue
        try:
            print(answer(base_url, args.model, prompt))
        except (urllib.error.URLError, KeyError, ValueError) as error:
            print(f'Erreur : {error}')


if __name__ == '__main__':
    main()
