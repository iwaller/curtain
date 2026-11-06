#!/usr/bin/env python3
"""Process-level tests. Never locks the screen, changes gamma or touches the running Curtain."""
import os
from pathlib import Path
import signal
import selectors
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'build/watchdog-tests'
OUT.mkdir(parents=True, exist_ok=True)
ARTIFACTS = ROOT / 'artifacts/watchdog-tests'
ARTIFACTS.mkdir(parents=True, exist_ok=True)

def build(output, sources):
    subprocess.run(['xcrun', 'swiftc', '-module-cache-path', str(ROOT / 'build/module-cache'),
                    *sources, '-o', str(output)], cwd=ROOT, check=True)

helper = OUT / 'CurtainWatchdogTest'
client = OUT / 'WatchdogClientTests'
build(helper, ['Sources/Watchdog/HeartbeatDeadline.swift', 'Sources/Watchdog/Watchdog.swift', 'Tests/FakeScreenLock.swift'])
build(client, ['Sources/Watchdog/HeartbeatDeadline.swift', 'Sources/App/RecoveryWatchdog.swift',
               'Sources/Shared/Log.swift', 'Tests/WatchdogClientTests.swift'])

# A disposable parent owns the real protocol pipes. The production recovery loop kills only it.
PARENT = '''
import os, subprocess, sys, time
if sys.argv[2] == 'broken-log':
    read_end, write_end = os.pipe()
    p = subprocess.Popen([sys.argv[1]], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=write_end)
    os.close(read_end); os.close(write_end)
else:
    p = subprocess.Popen([sys.argv[1]], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
assert p.stdout.read(1) == b'R'
print(p.pid, flush=True)
if sys.argv[2] == 'eof':
    p.stdin.close()
elif sys.argv[2] == 'invalid':
    p.stdin.write(b'X'); p.stdin.flush()
elif sys.argv[2] == 'orphan':
    os._exit(0)
elif sys.argv[2] == 'disarm':
    p.stdin.write(b'HHDH'); p.stdin.flush()
    assert p.stdout.read(1) == b'D'
    assert p.wait(timeout=2) == 0
    sys.exit(0)
time.sleep(60)
'''

def wait_gone(pid):
    # Orphan helpers can briefly be zombies before launchd reaps them.
    for _ in range(40):
        status = subprocess.run(['ps', '-o', 'stat=', '-p', str(pid)], capture_output=True, text=True).stdout.strip()
        if not status or status.startswith('Z'):
            return
        time.sleep(.05)
    raise AssertionError(f'helper still running: {pid}')

def await_commit(process):
    # Client log lines precede the marker; use unbuffered bytes so select sees every line.
    selector = selectors.DefaultSelector()
    selector.register(process.stdout, selectors.EVENT_READ)
    output = b''
    deadline = time.monotonic() + 15
    try:
        while time.monotonic() < deadline:
            if not selector.select(.1):
                continue
            chunk = os.read(process.stdout.fileno(), 4096)
            assert chunk, output.decode()
            output += chunk
            if b'RECOVERY_COMMITTED_MAIN_RUNNING' in output:
                return output.decode()
        raise AssertionError('client did not acknowledge recovery commit')
    finally:
        selector.close()

with tempfile.TemporaryDirectory(dir=ARTIFACTS) as tmp:
    env = dict(os.environ, CURTAIN_TEST_LOCK_MARKER=str(Path(tmp) / 'locked'), CURTAIN_TEST_LOCK_RESULT='locked')
    subprocess.run([str(client), '--broken-log'], check=True, env=env, timeout=5)
    subprocess.run([str(client), str(helper), 'startup-failure'], check=True,
                   env=dict(env, CURTAIN_TEST_LOCK_AVAILABLE='0'), timeout=5)
    unresponsive = OUT / 'unresponsive-helper'
    unresponsive.write_text('#!' + sys.executable + '\nimport time\ntime.sleep(60)\n')
    unresponsive.chmod(0o700)
    subprocess.run([str(client), str(unresponsive), 'startup-failure'], check=True, env=env, timeout=6)
    closed_command = OUT / 'committed-closed-input-helper'
    closed_command.write_text('#!' + sys.executable + '\nimport os,time\nos.write(1,b"RF")\nos.close(0)\ntime.sleep(3)\n')
    closed_command.chmod(0o700)
    subprocess.run([str(client), str(closed_command), 'closed-command-channel'], check=True, env=env, timeout=7)
    subprocess.run([str(client), str(helper), 'normal'], check=True, env=env, timeout=20)
    with open(ARTIFACTS / 'client-helper-death.log', 'w+') as log:
        p = subprocess.Popen([str(client), str(helper), 'death'], stdout=log, stderr=log, env=env)
        try:
            time.sleep(.5)
            child = subprocess.check_output(['pgrep', '-P', str(p.pid)], text=True).strip()
            os.kill(int(child), signal.SIGKILL)
            assert p.wait(timeout=8) == 0
        finally:
            if p.poll() is None:
                p.kill(); p.wait()
    print('PASS helper death', flush=True)

    cases = [('disarm', 'locked'), ('orphan', 'locked'), ('hang', 'locked'), ('eof', 'locked'), ('invalid', 'locked'), ('broken-log', 'locked'),
             ('hang', 'failed'), ('hang', 'hung')]
    for mode, lock_result in cases:
        marker = Path(tmp) / 'locked'
        marker.unlink(missing_ok=True)
        env['CURTAIN_TEST_LOCK_RESULT'] = lock_result
        with open(ARTIFACTS / f'{mode}-{lock_result}.log', 'w+') as log:
            p = subprocess.Popen([sys.executable, '-c', PARENT, str(helper), mode], stdout=subprocess.PIPE, stderr=log, env=env, text=True)
            helper_pid = int(p.stdout.readline())
            started = time.monotonic()
            try:
                if mode == 'hang':
                    os.kill(p.pid, signal.SIGSTOP)  # Main process suspended, helper must still run.
                result = p.wait(timeout=17)
                elapsed = time.monotonic() - started
                if mode in ('disarm', 'orphan'):
                    assert result == 0 and not marker.exists()
                else:
                    assert result == -signal.SIGKILL, result
                    assert marker.exists() == (lock_result == 'locked')
                    if mode == 'hang':
                        assert 9 <= elapsed <= 15, elapsed
                    if mode != 'broken-log':
                        log.flush(); log.seek(0)
                        content = log.read()
                        assert f'lock-confirmed={str(lock_result == "locked").lower()}' in content
                        assert content.index('requesting system lock') < content.index('terminating parent=')
                wait_gone(helper_pid)
                print(f'PASS {mode} lock={lock_result} elapsed={elapsed:.2f}s', flush=True)
            finally:
                if p.poll() is None:
                    p.kill(); p.wait()
                wait_gone(helper_pid)

    for mode in ('late-disarm', 'recovery-helper-death'):
        Path(env['CURTAIN_TEST_LOCK_MARKER']).unlink(missing_ok=True)
        env['CURTAIN_TEST_LOCK_RESULT'] = 'hung'
        with open(ARTIFACTS / f'{mode}.log', 'w') as log:
            p = subprocess.Popen([str(client), str(helper), mode], stdout=subprocess.PIPE, stderr=log, env=env)
            helper_pid = None
            locker_pids = []
            try:
                log.write(await_commit(p))
                helper_pid = int(subprocess.check_output(['pgrep', '-P', str(p.pid)], text=True).strip())
                state = subprocess.check_output(['ps', '-o', 'stat=', '-p', str(p.pid)], text=True).strip()
                assert not state.startswith('T'), 'guardian must never suspend its parent'
                if mode == 'recovery-helper-death':
                    locker_pids = list(map(int, subprocess.run(['pgrep', '-P', str(helper_pid)], capture_output=True, text=True).stdout.split()))
                    os.kill(helper_pid, signal.SIGKILL)
                    assert p.wait(timeout=8) == 0
                else:
                    assert p.wait(timeout=6) == -signal.SIGKILL
                log.write(p.stdout.read().decode())
                wait_gone(helper_pid)
                for locker_pid in locker_pids:
                    wait_gone(locker_pid)
                print(f'PASS {mode}: committed recovery cannot be cancelled; parent never forcibly paused; no orphan locker', flush=True)
            finally:
                if p.poll() is None:
                    p.kill(); p.wait()
                if helper_pid:
                    wait_gone(helper_pid)
print('All watchdog tests passed. No real screen lock requested.')
