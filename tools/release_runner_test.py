"""Failure handling for the release test scheduler, using disposable processes."""
from pathlib import Path
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

import run_release_tests as runner


class ReleaseRunner(unittest.TestCase):
    def test_exit_code_and_output(self):
        with tempfile.TemporaryDirectory() as folder:
            log = Path(folder) / 'test.log'
            code = runner.run_command([sys.executable, '-c', "print('fixture'); raise SystemExit(7)"], log)
            self.assertEqual(code, 7)
            self.assertIn('fixture', log.read_text())

    def test_timeout_is_failure_and_retains_output(self):
        with tempfile.TemporaryDirectory() as folder:
            log = Path(folder) / 'test.log'
            started = time.monotonic()
            code = runner.run_command([sys.executable, '-c',
                                       "import time; print('started', flush=True); time.sleep(60)"],
                                      log, timeout=1)
            self.assertNotEqual(code, 0)
            self.assertLess(time.monotonic() - started, 15)
            self.assertIn('started', log.read_text())
            self.assertIn('timeout', log.read_text())

    def test_group_stops_after_failure(self):
        with tempfile.TemporaryDirectory() as folder:
            def fail(command, log):
                log.write_text('intentional failure\n')
                return 9
            with patch.dict(runner.GROUPS, fixture='first second'), patch.object(runner, 'run_command', side_effect=fail) as run:
                results = runner.run_group('fixture', Path(folder), 4)
            self.assertEqual(run.call_count, 1)
            self.assertEqual(results[0]['exit_code'], 9)


if __name__ == '__main__':
    unittest.main()
