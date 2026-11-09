#!/usr/bin/env python3
"""Real guardian protocol + simulated gamma. Never locks the workstation or changes gamma."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import os
import signal
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'build/recovery-gamma-tests'
LOGS = ROOT / 'artifacts/recovery-gamma-tests'
OUT.mkdir(parents=True, exist_ok=True)
LOGS.mkdir(parents=True, exist_ok=True)

def compile_to(path, sources):
    subprocess.run(['xcrun', 'swiftc', '-Osize', '-whole-module-optimization', '-module-cache-path', str(ROOT / 'build/module-cache'),
                    *map(str, sources), '-o', str(path)], cwd=ROOT, check=True)

shared = sorted((ROOT / 'Sources/Shared').glob('*.swift'))
helper = OUT / 'GuardianTest'
client = OUT / 'RecoveryGammaTests'
compile_to(helper, ['Sources/Watchdog/Watchdog.swift', 'Sources/Watchdog/HeartbeatDeadline.swift', 'Tests/FakeScreenLock.swift'])
compile_to(client, [*shared, 'Sources/App/RecoveryWatchdog.swift', 'Tests/RecoveryGammaTests.swift'])

# Replace only backend construction. All CLI start/failure/cleanup/exit code stays production code.
poc = (ROOT / 'Sources/POC/main.swift').read_text()
assert poc.count('let blackout = GammaBlackout()') == 1
(OUT / 'main.swift').write_text(poc.replace('let blackout = GammaBlackout()', 'let blackout = makeRegressionGamma()'))
cli = OUT / 'curtain-poc-failure-test'
compile_to(cli, [*shared, 'Tests/RecoveryGammaCLIBackend.swift', OUT / 'main.swift'])

scenarios = ['refresh-enumeration', 'refresh-write', 'active-start-enumeration', 'active-start-write',
             'initial-start-enumeration', 'initial-start-write', 'relock-start-enumeration', 'relock-start-write']

def run_case(case):
    scenario, policy = case
    with tempfile.TemporaryDirectory(dir=LOGS) as tmp:
        env = dict(os.environ, CURTAIN_TEST_LOCK_RESULT='hung', CURTAIN_TEST_LOCK_MARKER=str(Path(tmp) / 'lock-marker'))
        with (LOGS / f'{scenario}-{policy}.log').open('w') as log:
            p = subprocess.Popen([str(client), str(helper), scenario, policy, str(Path(tmp) / 'gamma.lock')],
                                 stdout=log, stderr=log, env=env, cwd=ROOT)
            try:
                result = p.wait(timeout=18)
                log.flush()
                text = (LOGS / f'{scenario}-{policy}.log').read_text()
                if policy == 'committed':
                    assert result == -signal.SIGKILL and 'HELD_UNTIL_GUARDIAN_DECISION' in text, (case, result, text)
                    assert 'gamma-restored' not in text.split('recovery-committed; requesting system lock', 1)[1], text
                else:
                    assert result == 0 and 'PASS ' in text, (case, result, text)
                print(f'PASS {scenario} {policy}', flush=True)
            finally:
                if p.poll() is None:
                    p.kill(); p.wait()

cases = [(s, 'normal') for s in scenarios] + [(s, 'committed') for s in scenarios]
cases += [('refresh-enumeration', 'guardian-exit')]
with ThreadPoolExecutor(max_workers=3) as pool:
    list(pool.map(run_case, cases))

for mode in ('initial', 'runtime'):
    with tempfile.TemporaryDirectory(dir=LOGS) as tmp:
        result = subprocess.run([str(cli), '--gamma', '--duration', '2'], cwd=ROOT,
                                env=dict(os.environ, CURTAIN_TEST_GAMMA_FAILURE=mode, CURTAIN_TEST_GAMMA_LEASE=str(Path(tmp) / 'gamma.lock')),
                                capture_output=True, text=True, timeout=6)
        (LOGS / f'cli-{mode}.log').write_text(result.stdout + result.stderr)
        assert result.returncode == 1 and result.stdout.count('CLI_BACKEND_RESTORED') == 1, result
        print(f'PASS production CLI {mode} gamma failure: rollback once, exit 1', flush=True)
print('All combined recovery/gamma regressions passed; no real display or lock action.')
