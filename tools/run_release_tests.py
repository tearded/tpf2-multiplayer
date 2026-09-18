"""Run independent release test groups; never overlap tests sharing build outputs."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import time

ROOT = Path(__file__).resolve().parents[1]
PRINT_LOCK = threading.Lock()

# Native compiler fixtures stay serial. The lobby group owns the relay's fixed
# ports; other groups use OS-assigned ports and separate temporary directories.
# Updater/MSI tests deliberately run only AFTER packaging in build_release.ps1.
GROUPS = {
    'native': 'test_net_epoch test_net_multipeer test_net_restart test_net_packet_size test_native_control',
    'lobby': 'relay_selftest resync_load_keeps_lobby_test hotjoin_stage_test late_loader_test lobby_mode_test test_lobby_limits test_player_stats',
    'logic': '''release_runner_test luacheck resync_test navigation_test test_sync_operation test_sync_snapshot
        test_sync_runtime test_sync_readiness test_desync_report_reload crossing_replay_test bridge_companion_test edge_demolition_test track_fresh_test
        delay_hold_test preview_test preview_perf_test speed_vote_test hash_cadence_test hash_bigmap_test
        version_gate_test mod_download_test lobby_panel_test chat_directory_test vpos_cap_test''',
    'recovery': 'run_recovery_matrix',
}


def run_command(command, log_path, timeout=600):
    with log_path.open('wb') as stream:
        process = subprocess.Popen(command, cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT)
        try:
            return process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            # Compiler/relay tests spawn children: terminate only this test's tree.
            if os.name == 'nt':
                subprocess.run(['taskkill', '/PID', str(process.pid), '/T', '/F'],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
            process.kill()
            process.wait()
            stream.write(b'\nFAIL: release test runner timeout\n')
            return 1


def run_group(group, folder, jobs):
    results = []
    for name in GROUPS[group].split():
        command = [sys.executable, str(ROOT / 'tools' / (name + '.py'))]
        if name == 'run_recovery_matrix':
            # At most five test processes across all four groups; no nested 4x4 pool.
            command += ['--jobs', str(min(jobs, 2))]
        log = folder / (name + '.log')
        started = time.monotonic()
        try:
            code = run_command(command, log)
        except OSError as error:
            log.write_text(str(error), encoding='utf-8')
            code = 1
        elapsed = time.monotonic() - started
        results.append(dict(test=name, group=group, seconds=round(elapsed, 3), exit_code=code))
        with PRINT_LOCK:
            print(f'[{group}] {name}: {elapsed:.1f}s, exit {code}', flush=True)
            # Preserve successful output too (including skips), without interleaving.
            print(log.read_text(encoding='utf-8', errors='replace'), end='', flush=True)
        if code:
            break
    return results


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--jobs', type=int, choices=range(1, 5), default=4)
    args = parser.parse_args()
    log_root = ROOT / '.local-test' / 'release-tests'
    log_root.mkdir(parents=True, exist_ok=True)
    folder = Path(tempfile.mkdtemp(prefix='run-', dir=log_root))
    print(f'Release test logs: {folder}', flush=True)
    started = time.monotonic()
    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        futures = [pool.submit(run_group, group, folder, args.jobs) for group in GROUPS]
        results = [result for future in futures for result in future.result()]
    elapsed = time.monotonic() - started
    failed = [result['test'] for result in results if result['exit_code']]
    (folder / 'timings.json').write_text(json.dumps(dict(seconds=elapsed, jobs=args.jobs,
                                                        tests=results), indent=2), encoding='utf-8')
    print(f'Release tests: {elapsed:.1f}s; failed: {failed}; logs: {folder}', flush=True)
    return int(bool(failed))


if __name__ == '__main__':
    sys.exit(main())
