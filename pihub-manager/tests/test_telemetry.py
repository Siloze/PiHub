"""GPU metrics are observed, nullable, and never attributed by guesswork."""
import plistlib
import unittest
from unittest.mock import patch
from pihub_manager.hub import telemetry


class TelemetryTests(unittest.TestCase):
    def test_gpu_reads_actual_system_counters(self):
        payload = plistlib.dumps([{'model': 'Test GPU', 'PerformanceStatistics': {'Device Utilization %': 42, 'In use system memory': 2 * 1024**3}}])
        with patch.object(telemetry.subprocess, 'check_output', return_value=payload):
            value = telemetry.gpu()
        self.assertEqual(value['usage'], 42)
        self.assertEqual(value['memory'], 2048)
        self.assertEqual(value['scope'], 'system')

    def test_unavailable_gpu_is_not_zero(self):
        with patch.object(telemetry.subprocess, 'check_output', side_effect=OSError('unavailable')):
            value = telemetry.gpu()
        self.assertIsNone(value['usage'])
        self.assertIsNone(value['memory'])

    def test_invalid_gpu_counter_is_rejected(self):
        payload = plistlib.dumps([{'PerformanceStatistics': {'Device Utilization %': 4294967295}}])
        with patch.object(telemetry.subprocess, 'check_output', return_value=payload):
            self.assertIsNone(telemetry.gpu()['usage'])
