"""Read-only, sanitized loopback diagnostics. Never persist credentials or SQL text."""
import json, os, pathlib, socket, subprocess, time, urllib.request


def capture(output):
    result = {'scope': 'disposable loopback backend only', 'checks': {}}
    def check(name, work):
        started = time.monotonic()
        try:
            result['checks'][name] = {'status': 'PASS', 'value': work()}
        except Exception as error:
            result['checks'][name] = {'status': 'FAIL', 'errorType': type(error).__name__}
        result['checks'][name]['seconds'] = round(time.monotonic() - started, 3)
    def control():
        # The body contains synthetic tokens. Read/discard it; never serialize it.
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        with opener.open('http://127.0.0.1:61913/context', timeout=3) as response:
            response.read()
            return response.status
    def redis():
        with socket.create_connection(('127.0.0.1', 56312), timeout=3) as connection:
            connection.sendall(b'*1\r\n$4\r\nPING\r\n')
            assert connection.recv(64) == b'+PONG\r\n', 'Expected PONG'
            return 'PONG'
    def process(name):
        pid = int((pathlib.Path(os.environ['RUNNER_TEMP']) / name).read_text().strip())
        os.kill(pid, 0)
        # Explicit numeric/state columns only, never command arguments or environment.
        value = subprocess.check_output(['ps', '-p', str(pid), '-o', 'pid=,stat=,%cpu=,rss='], text=True, timeout=3)
        columns = value.split()
        assert len(columns) == 4
        return {'pid': int(columns[0]), 'state': columns[1], 'cpuPercent': float(columns[2]), 'rssKiB': int(columns[3])}
    def postgres():
        prefix = subprocess.check_output(['brew', '--prefix', 'postgresql@18'], text=True, timeout=5).strip()
        # No queries, parameter values, identities or fixture records in the output.
        sql = "SELECT COALESCE(json_agg(t),'[]'::json) FROM (SELECT state, wait_event_type, wait_event, count(*) AS connections FROM pg_stat_activity WHERE datname='pubo_native_integration' AND pid <> pg_backend_pid() GROUP BY state,wait_event_type,wait_event) t"
        value = subprocess.check_output([str(pathlib.Path(prefix) / 'bin/psql'), '-X', '-A', '-t', '-h', '127.0.0.1', '-p', '54312', '-d', 'pubo_native_integration', '-c', sql], text=True, stderr=subprocess.DEVNULL, timeout=6, env={**os.environ, 'PGCONNECT_TIMEOUT': '3', 'PGOPTIONS': '-c statement_timeout=3000'})
        return json.loads(value)
    check('backendProcess', lambda: process('pubo-native-backend.pid'))
    check('controlEventLoop', control)
    check('redisProcess', lambda: process('pubo-redis.pid'))
    check('redisPing', redis)
    check('postgresActivity', postgres)
    output.write_text(json.dumps(result, indent=2))
