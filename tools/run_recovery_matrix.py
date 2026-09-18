"""Run isolated lobby regressions concurrently, retaining every scenario and log."""
import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
import subprocess
import sys
import time


ROOT = Path(__file__).resolve().parents[1]
PLAYERS = (2, 3, 5, 8)


def run_case(players):
    started = time.monotonic()
    command = [sys.executable, str(ROOT / 'tools/test_auto_sync_lobby.py'),
               '--players', str(players)]
    try:
        result = subprocess.run(command, cwd=ROOT, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, timeout=180)
        return players, result.returncode, result.stdout, time.monotonic() - started
    except subprocess.TimeoutExpired as error:
        return players, 1, (error.stdout or b'') + b'\nRunner timeout after 180s\n', time.monotonic() - started


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--jobs', type=int, choices=range(1, 5), default=4,
                        help='Concurrent processes; 1 runs the same matrix serially.')
    args = parser.parse_args()
    started = time.monotonic()
    failed = []
    # Each child owns its Python globals, temp directory and OS-assigned ports.
    # Finish all cases even on failure, and print each complete log together.
    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        futures = [pool.submit(run_case, players) for players in PLAYERS]
        for future in as_completed(futures):
            players, code, output, elapsed = future.result()
            print(f'--- Recovery: {players} players, {elapsed:.1f}s, exit {code} ---', flush=True)
            print(output.decode('utf-8', errors='replace').replace('\r\n', '\n'), end='', flush=True)
            if code:
                failed.append(players)
    print(f'Recovery matrix: {time.monotonic() - started:.1f}s; failed: {sorted(failed)}', flush=True)
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
