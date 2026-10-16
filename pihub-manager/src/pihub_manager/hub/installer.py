"""Isolated recipe worker. Explicit argv only; no shell interpolation."""
import hashlib
import os
import platform
import shutil
import subprocess
import sys
import urllib.request
import tarfile
from pathlib import Path
from .storage import ROOT, DATA, read, write, valid_id, locked


def extract(archive, destination):
    destination = destination.resolve()
    with tarfile.open(archive) as bundle:
        for member in bundle.getmembers():
            target = (destination / member.name).resolve()
            if not target.is_relative_to(destination):
                raise ValueError('Archive : chemin hors destination.')
            if member.issym() or member.islnk():
                link = (target.parent if member.issym() else destination) / member.linkname
                if not link.resolve().is_relative_to(destination):
                    raise ValueError('Archive : lien hors destination.')
            if member.isdev() or member.isfifo():
                raise ValueError('Archive : fichier spécial interdit.')
        bundle.extractall(destination)


def run(identifier):
    path = DATA / 'install-jobs' / (valid_id(identifier) + '.json')
    with locked():
        job = read(path)
        if not job or job['state'] != 'queued':
            return
        job.update(state='running', message='Vérification des prérequis')
        write(path, job)
    package = DATA / 'packages' / identifier
    try:
        recipe = job['recipe']
        if recipe.get('min_macos') and (platform.system() != 'Darwin' or int(platform.mac_ver()[0].split('.')[0]) < recipe['min_macos']):
            raise ValueError('macOS ' + str(recipe['min_macos']) + '+ requis.')
        for binary in recipe.get('prerequisites', []):
            if not shutil.which(binary):
                raise ValueError('Prérequis manquant : ' + binary + '. Installez-le puis réessayez.')
        package.mkdir(parents=True, exist_ok=False)
        values = dict(package=str(package), root=str(ROOT), data=str(DATA), revision=job['revision'], repository=recipe.get('repository', ''), bundle=str(Path(recipe.get('recipe_source', '.')).parent))
        environment = dict(os.environ, CI='1', GIT_TERMINAL_PROMPT='0')
        for key, value in recipe.get('env', {}).items():
            environment[key] = value.format_map(values)
        steps = recipe['steps']
        for index, step in enumerate(steps):
            job.update(progress=index / len(steps), message=step['label'])
            write(path, job)
            print('\n[' + step['label'] + ']', flush=True)
            if step.get('download'):
                destination = package / 'download.tar.gz'
                request = urllib.request.Request(step['download'], headers={'User-Agent': 'PiHub/2'})
                digest = hashlib.sha256()
                with urllib.request.urlopen(request, timeout=60) as response, destination.open('wb') as output:
                    while True:
                        block = response.read(1024 * 1024)
                        if not block:
                            break
                        output.write(block)
                        digest.update(block)
                if digest.hexdigest() != step['sha256']:
                    raise ValueError('La somme SHA-256 ne correspond pas à la recette.')
                extract(destination, package)
            else:
                argv = [v.format_map(values) for v in step['argv']]
                print(' → ' + repr(argv), flush=True)
                subprocess.run(argv, cwd=step.get('cwd', '{package}').format_map(values), env=environment, stdin=subprocess.DEVNULL, check=True, timeout=3600)
        executable = Path(recipe['executable'].format_map(values))
        if not executable.is_file() or not os.access(executable, os.X_OK):
            raise ValueError('La recette n’a pas produit l’exécutable annoncé : ' + str(executable))
        resolved = job['revision']
        if (package / 'source/.git').exists():
            resolved = subprocess.check_output(['git', '-C', str(package / 'source'), 'rev-parse', 'HEAD'], text=True).strip()
        with locked():
            if read(path)['state'] == 'cancelled':
                return
            from .catalog import add_instance
            from .storage import config
            import time
            if recipe.get('runtime_env'):
                job['definition'].setdefault('env', {}).update({k: v.format_map(values) for k, v in recipe['runtime_env'].items()})
            current = config()
            instances = [i for i in current['providers'] + current['agents'] if i['adapter'] == recipe['adapter']]
            item = instances[0] if instances else None
            if instances:
                for instance in instances:
                    instance['settings']['executable'] = str(executable)
                write(DATA / 'config.json', current)
            else:
                item = add_instance(recipe, str(executable), job['definition'])
            installations = read(DATA / 'installations.json', {})
            installations[recipe['id']] = dict(revision=job['revision'], resolved_revision=resolved, reference=recipe['revision'], executable=str(executable), path=str(package), installed=time.time())
            write(DATA / 'installations.json', installations)
            job.update(state='done', progress=1, message='Installé · choisissez un modèle et un routage avant de lancer.', instance_id=item['id'])
            write(path, job)
    except Exception as error:
        with locked():
            if read(path, {}).get('state') == 'cancelled':
                return
            job.update(state='failed', message=str(error))
            write(path, job)
        print(str(error), flush=True)


if __name__ == '__main__':
    run(sys.argv[1])
