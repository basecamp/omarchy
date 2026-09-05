#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"
require_command python3

# Real advisory locks and real subscription writers. Only package lookup,
# confirmation, notification, and the OPML parser are replaced by fixtures.
python3 - "$ROOT" <<'PY'
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

repo = Path(sys.argv[1])
with tempfile.TemporaryDirectory(prefix='feeds-concurrency-') as directory:
    root = Path(directory)
    home, binaries, checkout = root / 'home', root / 'bin', root / 'checkout'
    for path in (home / '.config/newsboat', binaries, checkout / 'bin', root / 'desktop-runtime', root / 'scouts'):
        path.mkdir(parents=True, exist_ok=True)

    def executable(path, text):
        path.write_text(text)
        path.chmod(0o755)

    executable(binaries / 'omarchy-pkg-missing', '#!/bin/bash\nexit 1\n')
    executable(binaries / 'omarchy-notification-send', '#!/bin/bash\nexit 0\n')
    executable(checkout / 'bin/omarchy-newsboat-confirm', '#!/bin/bash\nexit 0\n')
    (checkout / 'bin/omarchy-newsboat-internal.py').symlink_to(repo / 'bin/omarchy-newsboat-internal.py')
    # Python supplies the same flock syscall on Linux and macOS. The inherited
    # descriptor keeps the lock held by the actual shell after this helper exits.
    executable(binaries / 'flock', '#!' + sys.executable + '''
import fcntl, os, pathlib, sys
if os.environ.get('LOCK_ATTEMPT'):
    pathlib.Path(os.environ['LOCK_ATTEMPT']).touch()
fcntl.flock(int(sys.argv[1]), fcntl.LOCK_EX)
''')
    executable(binaries / 'mv', '#!' + sys.executable + '''
import os, pathlib, sys, time
if any('.urls.scout.' in arg for arg in sys.argv):
    pathlib.Path(os.environ['STAGED']).touch()
    deadline = time.monotonic() + 15
    while not pathlib.Path(os.environ['RELEASE']).exists():
        if time.monotonic() > deadline: sys.exit(90)
        time.sleep(0.02)
os.execv('/bin/mv', ['mv', *sys.argv[1:]])
''')
    executable(binaries / 'newsboat', '''#!/bin/bash
while (($#)); do
  if [[ $1 == -u ]]; then destination=$2; shift; fi
  shift
done
printf 'https://imported.example/feed\n' >>"$destination"
''')
    target = root / 'dotfiles-urls'
    urls = home / '.config/newsboat/urls'
    urls.symlink_to(target)
    opml = root / 'input.opml'
    opml.write_text('<opml version="2.0"><body/></opml>')
    env = dict(os.environ, HOME=str(home), OMARCHY_PATH=str(checkout), PATH=str(binaries) + ':' + os.environ['PATH'], XDG_RUNTIME_DIR=str(root / 'desktop-runtime'), NEWSBOAT_URLS_FILE=str(urls), NEWSBOAT_SCOUT_STATE_DIR=str(root / 'scouts'), STAGED=str(root / 'staged'), RELEASE=str(root / 'release'))

    def wait_file(path):
        deadline = time.monotonic() + 15
        while not path.exists():
            if time.monotonic() > deadline: raise AssertionError(f'timed out waiting for {path.name}')
            time.sleep(0.02)

    for action, argument in [('add', 'https://added.example/feed'), ('remove', 'https://existing.example/feed'), ('import', str(opml))]:
        for name in ('staged', 'release', 'attempt'):
            (root / name).unlink(missing_ok=True)
        target.write_text('https://existing.example/feed\n')
        proposal = root / 'scouts/scout.locktest1'
        proposal.write_text(json.dumps({'version': 1, 'created_at': int(time.time()), 'subscriptions': ['https://existing.example/feed'], 'candidates': [{'id': 'F001', 'feed_url': 'https://scouted.example/feed'}]}))
        scout = subprocess.Popen(['/bin/bash', str(repo / 'bin/omarchy-newsboat-scout-apply'), 'locktest1', '1', 'F001'], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        worker = None
        try:
            wait_file(root / 'staged')
            worker = subprocess.Popen(['/bin/bash', str(repo / f'bin/omarchy-newsboat-{action}'), argument], env=dict(env, LOCK_ATTEMPT=str(root / 'attempt')), stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            wait_file(root / 'attempt')
            time.sleep(0.2)
            assert worker.poll() is None, f'{action} bypassed the Scout subscription lock'
            (root / 'release').touch()
            out, err = scout.communicate(timeout=15)
            assert scout.returncode == 0, (out, err)
            out, err = worker.communicate(timeout=15)
            assert worker.returncode == 0, (out, err)
            assert urls.is_symlink(), 'writer replaced subscriptions symlink'
            feeds = target.read_text().splitlines()
            expected = ['https://scouted.example/feed'] if action == 'remove' else ['https://existing.example/feed', 'https://scouted.example/feed', f'https://{"added" if action == "add" else "imported"}.example/feed']
            assert feeds == expected, (action, feeds)
            assert not proposal.exists()
            print(f'ok - Scout and {action} serialize real writes across desktop and agent runtime paths')
        finally:
            (root / 'release').touch()
            for process in (scout, worker):
                if process is not None and process.poll() is None:
                    process.terminate()
                    process.wait(timeout=5)
PY
