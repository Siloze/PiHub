"""Read-only macOS GPU counters. Never infer per-process GPU attribution."""
import math
import plistlib
import subprocess


def gpu():
    unavailable = {'usage': None, 'memory': None, 'name': '', 'source': 'IORegistry', 'scope': 'system'}
    for device_class in ('AGXAccelerator', 'IOAccelerator'):
        try:
            payload = plistlib.loads(subprocess.check_output(['/usr/sbin/ioreg', '-a', '-r', '-c', device_class, '-d', '1'], timeout=2))
            for device in payload:
                stats = device.get('PerformanceStatistics', {})
                usage = stats.get('Device Utilization %')
                memory = stats.get('In use system memory')
                if isinstance(usage, (int, float)) and math.isfinite(usage) and 0 <= usage <= 100:
                    return dict(unavailable, usage=float(usage), memory=memory / 1024**2 if isinstance(memory, (int, float)) and memory >= 0 else None, name=str(device.get('model', 'GPU')))
        except (OSError, ValueError, TypeError, subprocess.SubprocessError):
            continue
    return unavailable
