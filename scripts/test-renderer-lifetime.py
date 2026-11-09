#!/usr/bin/env python3
"""Exercise only disposable renderer processes; never touch the live privacy session."""
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parent.parent
HELPER = ROOT / 'build/Curtain.app/Contents/Helpers/CurtainRenderer'
ARGS = [str(HELPER), '/System/Library/CoreServices/DefaultDesktop.heic', '1024', '1024']

def alive(pid):
    result = subprocess.run(['ps', '-p', str(pid), '-o', 'stat='], capture_output=True, text=True)
    return result.returncode == 0 and not result.stdout.strip().startswith('Z')

# An undrained pipe forces the helper to remain alive after its render finishes.
worker = subprocess.Popen(ARGS, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
try:
    assert worker.stdout.read(24)[:4] == b'BTRC'
    start = time.monotonic()
    assert worker.wait(timeout=10) != 0
    assert time.monotonic() - start < 9
    print('PASS independent renderer deadline while stdout is blocked', flush=True)
finally:
    if worker.poll() is None:
        worker.kill(); worker.wait()
    worker.stdout.close()

# Keep the reader open in this test process so parent-death detection, not EPIPE, ends the child.
read_fd, write_fd = os.pipe()
parent_code = '''
import subprocess, sys, time
p = subprocess.Popen(sys.argv[1:-1], stdout=int(sys.argv[-1]), stderr=subprocess.DEVNULL)
print(p.pid, flush=True)
time.sleep(30)
'''
parent = subprocess.Popen([sys.executable, '-c', parent_code, *ARGS, str(write_fd)],
                          pass_fds=(write_fd,), stdout=subprocess.PIPE, text=True)
os.close(write_fd)
pid = None
try:
    pid = int(parent.stdout.readline())
    assert os.read(read_fd, 24)[:4] == b'BTRC'
    assert alive(pid)
    start = time.monotonic()
    parent.kill(); parent.wait()
    while alive(pid) and time.monotonic() - start < 2:
        time.sleep(0.02)
    assert not alive(pid), 'Renderer survived parent death'
    print('PASS abrupt parent death ends blocked renderer within two seconds', flush=True)
finally:
    if parent.poll() is None:
        parent.kill(); parent.wait()
    parent.stdout.close()
    if pid and alive(pid):
        os.kill(pid, signal.SIGKILL)
    os.close(read_fd)
