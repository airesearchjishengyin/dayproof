"""Launch the real native app with isolated data; verify native and backend behavior."""
import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / 'build/Dayproof.app/Contents/MacOS/Dayproof'
OUTPUT = ROOT / 'artifacts/native'
OUTPUT.mkdir(parents=True, exist_ok=True)
result_file = OUTPUT / 'native-result.json'
result_file.unlink(missing_ok=True)
with tempfile.TemporaryDirectory(prefix='dayproof-native-') as tmp:
    evidence = Path(tmp) / 'evidence'
    evidence.mkdir()
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        port = sock.getsockname()[1]
    env = {**os.environ, 'DAYPROOF_SMOKE_TEST': '1', 'DAYPROOF_SUPPORT_DIR': tmp,
           'DAYPROOF_EVIDENCE_ROOT': str(evidence), 'DAYPROOF_PORT': str(port),
           'DAYPROOF_SMOKE_OUTPUT': str(OUTPUT)}
    proc = subprocess.Popen([str(APP)], cwd='/tmp', env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        proc.wait(timeout=30)
    except subprocess.TimeoutExpired:
        proc.terminate()
        proc.wait(timeout=10)
        raise SystemExit('Native smoke test timed out')
    if not result_file.exists():
        log = Path(tmp) / 'desktop.log'
        raise SystemExit(f'No native test result. exit={proc.returncode}\n' + (log.read_text() if log.exists() else ''))
    result = json.loads(result_file.read_text())
    if not result.get('ok'):
        raise SystemExit(json.dumps(result, ensure_ascii=False, indent=2))
    assert proc.returncode == 0
    with socket.socket() as sock:
        assert sock.connect_ex(('127.0.0.1', port)) != 0, 'Backend survived application quit'
    print(f'PASS: {len(result["checks"])} native checks; quit also stops owned backend.')
    print(f'Native UI snapshots: {OUTPUT}')
