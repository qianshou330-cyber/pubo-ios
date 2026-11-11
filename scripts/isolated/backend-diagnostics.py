"""Read-only, sanitized loopback diagnostics. Never persist credentials or SQL text."""
import json, math, os, pathlib, re, socket, subprocess, time, urllib.error, urllib.request


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise RuntimeError('Diagnostic endpoint redirected')


def process_metadata(pid):
    assert isinstance(pid, int) and pid > 0
    os.kill(pid, 0)
    # Only whitelisted columns. Never collect args, command, environment or logs.
    value = subprocess.check_output(['ps', '-p', str(pid), '-o', 'pid=,stat=,%cpu=,rss='], text=True, stderr=subprocess.DEVNULL, timeout=3)
    columns = value.split()
    assert len(columns) == 4 and int(columns[0]) == pid
    assert re.fullmatch(r'[A-Z][A-Za-z<>+\-]{0,11}', columns[1])
    cpu, rss = float(columns[2]), int(columns[3])
    assert math.isfinite(cpu) and cpu >= 0 and rss >= 0
    return {'pid': pid, 'state': columns[1], 'cpuPercent': cpu, 'rssKiB': rss}


def api_listener_processes():
    # Unlike the control-script PID, these are the process(es) actually serving
    # the fixed disposable API port, including a child created by the harness.
    value = subprocess.check_output(['lsof', '-nP', '-a', '-iTCP:61812', '-sTCP:LISTEN', '-t'], text=True, stderr=subprocess.DEVNULL, timeout=3)
    rows = value.split()
    assert rows and len(rows) <= 8 and all(re.fullmatch(r'[0-9]{1,10}', row) for row in rows)
    return [process_metadata(pid) for pid in sorted({int(row) for row in rows})]


def api_meta_status():
    # A read-only, unauthenticated request to the exact loopback endpoint.
    # Never follow redirects or read/persist the response body.
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
    request = urllib.request.Request('http://127.0.0.1:61812/api/meta', data=b'{}', headers={'Content-Type': 'application/json'})
    with opener.open(request, timeout=3) as response:
        status = int(response.status)
        assert 200 <= status < 300
        return status


def capture(output):
    result = {'scope': 'disposable loopback backend only', 'checks': {}}
    def check(name, work):
        started = time.monotonic()
        try:
            result['checks'][name] = {'status': 'PASS', 'value': work()}
        except Exception as error:
            result['checks'][name] = {'status': 'FAIL', 'errorType': type(error).__name__}
            if isinstance(error, urllib.error.HTTPError):
                result['checks'][name]['httpStatus'] = int(error.code)
        result['checks'][name]['seconds'] = round(time.monotonic() - started, 3)
    def control():
        # The body contains synthetic tokens. Inspect status only; never read or serialize it.
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
        with opener.open('http://127.0.0.1:61913/context', timeout=3) as response:
            return response.status
    def redis():
        with socket.create_connection(('127.0.0.1', 56312), timeout=3) as connection:
            connection.sendall(b'*1\r\n$4\r\nPING\r\n')
            assert connection.recv(64) == b'+PONG\r\n', 'Expected PONG'
            return 'PONG'
    def process(name):
        pid = int((pathlib.Path(os.environ['RUNNER_TEMP']) / name).read_text().strip())
        return process_metadata(pid)
    def postgres():
        prefix = subprocess.check_output(['brew', '--prefix', 'postgresql@18'], text=True, timeout=5).strip()
        # No queries, parameter values, identities or fixture records in the output.
        sql = "SELECT COALESCE(json_agg(t),'[]'::json) FROM (SELECT state, wait_event_type, wait_event, count(*) AS connections FROM pg_stat_activity WHERE datname='pubo_native_integration' AND pid <> pg_backend_pid() GROUP BY state,wait_event_type,wait_event) t"
        value = subprocess.check_output([str(pathlib.Path(prefix) / 'bin/psql'), '-X', '-A', '-t', '-h', '127.0.0.1', '-p', '54312', '-d', 'pubo_native_integration', '-c', sql], text=True, stderr=subprocess.DEVNULL, timeout=6, env={**os.environ, 'PGCONNECT_TIMEOUT': '3', 'PGOPTIONS': '-c statement_timeout=3000'})
        return json.loads(value)
    check('backendProcess', lambda: process('pubo-native-backend.pid'))
    check('apiListenerProcesses', api_listener_processes)
    check('apiMeta', api_meta_status)
    check('controlEventLoop', control)
    check('redisProcess', lambda: process('pubo-redis.pid'))
    check('redisPing', redis)
    check('postgresActivity', postgres)
    output.write_text(json.dumps(result, indent=2))
