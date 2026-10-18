"""Process ownership, bounded HTTP probes and telemetry. Never uses pkill."""
import json
import os
import shlex
import signal
import socket
import subprocess
import time
import threading
import urllib.error
import urllib.request
from pathlib import Path
from .storage import ROOT, DATA, read, write, valid_id


def http(url, key_env='', timeout=1.2, payload=None):
    headers = {}
    if key_env:
        if not os.environ.get(key_env):
            raise ValueError('Variable de clé API non définie : ' + key_env)
        headers['Authorization'] = 'Bearer ' + os.environ[key_env]
    data = None
    if payload is not None:
        data = json.dumps(payload).encode()
        headers['Content-Type'] = 'application/json'
    with urllib.request.urlopen(urllib.request.Request(url, data=data, headers=headers), timeout=timeout) as response:
        return json.load(response)


def processes():
    # Terminal may use a French locale (decimal commas and localized dates).
    # Keep metrics and the start-time identity identical across launch surfaces.
    out = subprocess.run(['/bin/ps', '-ax', '-o', 'pid=,ppid=,%cpu=,rss=,lstart=,etime=,command='], env={**os.environ, 'LC_ALL': 'C'}, capture_output=True, text=True, timeout=4)
    result = {}
    for line in out.stdout.splitlines():
        parts = line.strip().split(None, 10)
        if len(parts) == 11:
            try:
                result[int(parts[0])] = dict(pid=int(parts[0]), ppid=int(parts[1]), cpu=float(parts[2]), memory=float(parts[3]) / 1024, identity=' '.join(parts[4:9]), uptime=parts[9], command=parts[10])
            except ValueError:
                pass
    return result


def family(pid, table):
    selected = {pid}
    for _ in range(30):
        more = {p for p, row in table.items() if row['ppid'] in selected}
        if more <= selected:
            break
        selected |= more
    return [table[p] for p in selected if p in table]


def record_path(identifier):
    return DATA / 'processes' / (valid_id(identifier) + '.json')


def owned(identifier, table):
    record = read(record_path(identifier), {})
    process = table.get(record.get('pid'))
    # Start time survives exec() but prevents treating a recycled PID as ours.
    if process and record.get('identity') and process['identity'] == record['identity']:
        return record
    return None


def spawn(identifier, argv, environment, cwd=None):
    if owned(identifier, processes()):
        raise ValueError('Ce processus est déjà actif.')
    log = DATA / 'logs' / (valid_id(identifier) + '.log')
    log.parent.mkdir(parents=True, exist_ok=True)
    with log.open('ab') as stream:
        child = subprocess.Popen(argv, env=environment, cwd=cwd or ROOT, stdin=subprocess.DEVNULL, stdout=stream, stderr=stream, start_new_session=True)
    threading.Thread(target=child.wait, daemon=True).start()
    time.sleep(.2)
    table = processes()
    row = table.get(child.pid)
    if not row:
        raise ValueError('Le processus a quitté au démarrage. ' + log.read_text(errors='replace')[-1200:])
    write(record_path(identifier), dict(pid=child.pid, identity=row['identity'], started=time.time(), argv=argv, group=True))
    return child.pid


def stop(identifier):
    table = processes()
    record = owned(identifier, table)
    if not record:
        raise ValueError('Aucun processus géré par PiHub. Une instance externe ne sera pas arrêtée.')
    # Keep the exact descendants seen while the supervised launcher is alive.
    # Some runtimes spawn a server in another process group; after their parent
    # exits that server is re-parented and no longer appears in family().
    # Identity checks below ensure PiHub never signals a recycled or unrelated
    # PID.
    descendants = {
        row['pid']: row['identity'] for row in family(record['pid'], table)
        if row['pid'] != record['pid']
    }
    if record.get('group'):
        # A launcher can exit before the server it started.  The process group is
        # the ownership boundary created by spawn(), so wait for the *whole*
        # group rather than only the recorded launcher PID.  Otherwise a server
        # can still own its port just after PiHub says it has stopped.
        try:
            os.killpg(record['pid'], signal.SIGTERM)
        except ProcessLookupError:
            record_path(identifier).unlink(missing_ok=True)
            return
        deadline = time.monotonic() + 6
        while time.monotonic() < deadline:
            if not group_alive(record['pid']):
                terminate_descendants(descendants)
                record_path(identifier).unlink(missing_ok=True)
                return
            time.sleep(.15)
        # This is limited to the dedicated PiHub session/process group. It is
        # deliberately never used for an adopted external process.
        try:
            os.killpg(record['pid'], signal.SIGKILL)
        except ProcessLookupError:
            pass
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            if not group_alive(record['pid']):
                terminate_descendants(descendants)
                record_path(identifier).unlink(missing_ok=True)
                return
            time.sleep(.1)
        raise ValueError('Arrêt demandé, mais un sous-processus PiHub est encore actif. Consultez le journal.')
    else:
        os.kill(record['pid'], signal.SIGTERM)
    deadline = time.monotonic() + 6
    while time.monotonic() < deadline:
        if not owned(identifier, processes()):
            record_path(identifier).unlink(missing_ok=True)
            return
        time.sleep(.15)
    raise ValueError('Arrêt demandé, mais le processus ne s’est pas encore terminé. Consultez le journal.')


def group_alive(pgid):
    try:
        os.killpg(int(pgid), 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def matching_descendants(descendants):
    table = processes()
    return [pid for pid, identity in descendants.items() if table.get(pid, {}).get('identity') == identity]


def terminate_descendants(descendants):
    """Stop children that escaped a managed launch group, by PID identity only."""
    alive = matching_descendants(descendants)
    for pid in alive:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.monotonic() + 2
    while alive and time.monotonic() < deadline:
        time.sleep(.1)
        alive = matching_descendants(descendants)
    for pid in alive:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    deadline = time.monotonic() + 1
    while matching_descendants(descendants) and time.monotonic() < deadline:
        time.sleep(.1)


def port_free(host, port):
    with socket.socket() as sock:
        try:
            sock.bind((host, int(port)))
        except OSError:
            raise ValueError(f'Le port {port} est occupé ou l’adresse {host} est invalide.')


def wait_port_free(host, port, timeout=3):
    """Wait briefly for a port released by an owned process group.

    It avoids a race between a successful stop and the kernel making the
    listener available to the next start.  It never kills or probes a process
    by name; bind remains the source of truth.
    """
    deadline = time.monotonic() + timeout
    while True:
        try:
            port_free(host, port)
            return
        except ValueError:
            if time.monotonic() >= deadline:
                raise ValueError(f'Le port {port} est toujours utilisé après l’arrêt. Un processus externe le retient peut-être.')
            time.sleep(.1)


def terminal(identifier):
    # Static Python module + one validated identifier, no user settings in AppleScript.
    command = shlex.join(['/usr/bin/env', 'PIHUB_ROOT=' + str(ROOT), 'PIHUB_DATA=' + str(DATA), 'PYTHONPATH=' + str(ROOT / 'pihub-manager/src'), '/usr/bin/python3', '-m', 'pihub_manager.hub', 'run-agent', valid_id(identifier)])
    script = 'tell application "Terminal"\nactivate\ndo script ' + json.dumps(command) + '\nend tell'
    subprocess.run(['/usr/bin/osascript', '-e', script], check=True, capture_output=True, timeout=10)


def reveal(path):
    subprocess.run(['/usr/bin/open', str(path)], check=True, capture_output=True, timeout=5)


def event(action, name, detail=''):
    path = DATA / 'events.json'
    entries = read(path, [])
    entries.insert(0, dict(id=str(time.time_ns()), time=time.strftime('%H:%M:%S'), action=action, name=name, detail=detail[:500]))
    write(path, entries[:250])
