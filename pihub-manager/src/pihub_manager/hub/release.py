"""Build a source-only archive from an explicit allowlist, never private state.

Usage: PYTHONPATH=pihub-manager/src python3 -m pihub_manager.hub.release
"""
import tarfile
from pathlib import Path
from .storage import ROOT, DATA

SOURCES = [
    'README.md', 'CONTRIBUTING.md', '.gitignore', '.github', 'Makefile', 'docs',
    'pihub-manager/integrations', 'pihub-manager/swift', 'pihub-manager/src',
    'pihub-manager/tests', 'pihub-manager/templates',
    'pihub-manager/build-swift.sh',
]


def source_filter(info):
    parts = Path(info.name).parts
    if '__pycache__' in parts or info.name.endswith(('.pyc', '.pyo')) or info.issym() or info.islnk():
        return None
    info.uid = info.gid = 0
    info.uname = info.gname = ''
    return info


def package():
    output = DATA / 'exports/PiHub-source.tar.gz'
    output.parent.mkdir(parents=True, exist_ok=True)
    with tarfile.open(output, 'w:gz') as archive:
        for relative in SOURCES:
            source = ROOT / relative
            if source.exists():
                archive.add(source, arcname='PiHub/' + relative, filter=source_filter)
    return output


if __name__ == '__main__':
    print(package())
