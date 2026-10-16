"""File-backed Hermes entry point so its restart tooling sees a stable argv.

The upstream generated launcher embeds a multiline Python -c program. Some
runtime restart paths reconstruct it incorrectly. Keep the same bootstrap
semantics with an ordinary script path and let Hermes select its dependencies.
"""
import os
import runpy
import sys

for key in ('PYTHONHOME', 'PYTHONPATH', 'VIRTUAL_ENV'):
    os.environ.pop(key, None)
sys.path.insert(0, os.environ['PIHUB_HERMES_SOURCE'])
sys._hermes_pin_default_home = True
import hermes_bootstrap  # noqa: F401,E402 -- activates Hermes' leased environment
runpy.run_module('hermes_cli.main', run_name='__main__', alter_sys=True)
