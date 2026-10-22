#!/usr/bin/env python3
"""Isolated Native Messaging integration checks; never touches browser profiles."""
import base64, hashlib, json, os, pathlib, select, struct, subprocess, sys, tempfile
HOST = pathlib.Path(sys.argv[1]).resolve()
MANIFEST = pathlib.Path(__file__).resolve().parents[1] / 'BrowserExtension/manifest.json'
public = base64.b64decode(json.loads(MANIFEST.read_text())['key'])
identifier = ''.join(chr(97 + int(n, 16)) for n in hashlib.sha256(public).hexdigest()[:32])
origin = f'chrome-extension://{identifier}/'

def payload(**change):
    result = dict(version=1, type='snapshot', browser='chrome', profile='11111111-1111-4111-8111-111111111111', receivedBytes=25, totalBytes=100, activeCount=1, unknownCount=0)
    result.update(change)
    return result

def exact(stream, count):
    data = b''
    while len(data) < count:
        assert select.select([stream], [], [], 3)[0], 'native reply timed out'
        chunk = os.read(stream.fileno(), count - len(data))
        assert chunk, 'unexpected EOF'
        data += chunk
    return data

def reply(process):
    count = struct.unpack('<I', exact(process.stdout, 4))[0]
    assert 0 < count < 1024
    return json.loads(exact(process.stdout, count))

with tempfile.TemporaryDirectory(prefix='taskdock-native-test-') as tmp:
    root = pathlib.Path(tmp)
    environment = {**os.environ, 'TASKDOCK_BROWSER_BRIDGE_STATE_DIR': str(root / 'state')}
    processes = []
    def start(source=origin):
        p = subprocess.Popen([str(HOST), source], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=environment, bufsize=0)
        processes.append(p)
        return p
    def send(p, value, split=False):
        body = json.dumps(value, separators=(',', ':')).encode()
        data = struct.pack('<I', len(body)) + body
        if split:
            for offset in range(0, len(data), 3): p.stdin.write(data[offset:offset + 3])
        else: p.stdin.write(data)
        return reply(p)
    def finish(p):
        p.stdin.close()
        p.wait(timeout=3)
        assert p.stderr.read() == b'', 'unexpected diagnostic / private data on native transport'
    def files(): return list((root / 'state').glob('*.json'))
    try:
        p = start(); assert send(p, payload(), True)['ok']
        assert len(files()) == 1
        stored = json.loads(files()[0].read_text())
        assert stored['snapshot']['receivedBytes'] == 25
        assert files()[0].stat().st_mode & 0o777 == 0o600
        assert (root / 'state').stat().st_mode & 0o777 == 0o700
        assert send(p, payload(receivedBytes=75))['ok']
        assert json.loads(files()[0].read_text())['snapshot']['receivedBytes'] == 75
        assert send(p, payload(receivedBytes=0, totalBytes=0, activeCount=0))['ok']
        v2=payload(version=2, downloads=[dict(id=7,filename='测试文件.zip',receivedBytes=25,totalBytes=100,paused=False)])
        assert send(p,v2)['ok']
        assert json.loads(files()[0].read_text())['snapshot']['downloads'][0]['filename']=='测试文件.zip'
        invalid=payload(version=2, downloads=[dict(id=7,filename='/private/测试文件.zip',receivedBytes=25,totalBytes=100,paused=False)])
        assert not send(p,invalid)['ok']
        finish(p); assert not files(), 'disconnect must clear its own state'
        bad = start('chrome-extension://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/')
        bad.wait(timeout=3); assert bad.returncode == 2 and bad.stdout.read() == b'' and not files()
        for invalid in [payload(receivedBytes=-1), payload(profile='../../escape'), payload(browser='firefox'), payload(filename='private.txt')]:
            bad = start(); assert not send(bad, invalid)['ok']; finish(bad); assert not files()
        bad = start(); bad.stdin.write(struct.pack('<I', 262145)); assert not reply(bad)['ok']; finish(bad)
        bad = start(); bad.stdin.write(b'\x04\x00'); bad.stdin.close(); assert not reply(bad)['ok']; bad.wait(timeout=3)
        # A connection is bound to its first browser/profile.
        bad = start(); assert send(bad, payload())['ok']; assert not send(bad, payload(browser='edge'))['ok']; finish(bad); assert not files()
        first = start(); second = start()
        assert send(first, payload())['ok']; assert send(second, payload(receivedBytes=80))['ok']
        finish(first); assert json.loads(files()[0].read_text())['snapshot']['receivedBytes'] == 80
        finish(second); assert not files()
        completed_file=root/'completed.txt'; completed_file.write_text('test')
        done=start()
        finished=payload(version=3,receivedBytes=0,totalBytes=0,activeCount=0,downloads=[dict(id=8,filename='completed.txt',receivedBytes=4,totalBytes=4,paused=False,complete=True,localPath=str(completed_file))])
        assert send(done,finished)['ok']; finish(done)
        assert json.loads(files()[0].read_text())['snapshot']['downloads'][0]['complete'], 'completed record must survive EOF'
        print('NATIVE_MESSAGING_OK framing chunks multi-message validation origin profile-binding session-safe-cleanup permissions')
    finally:
        for process in processes:
            if process.poll() is None: process.kill(); process.wait()
