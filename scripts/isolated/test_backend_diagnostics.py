import importlib.util
import json
import pathlib
import tempfile
import unittest
from unittest.mock import MagicMock, patch

path = pathlib.Path(__file__).with_name('backend-diagnostics.py')
spec = importlib.util.spec_from_file_location('backend_diagnostics', path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class DiagnosticTests(unittest.TestCase):
    def test_collects_only_sanitized_fields(self):
        with tempfile.TemporaryDirectory() as folder:
            root = pathlib.Path(folder)
            for name in ['pubo-native-backend.pid', 'pubo-redis.pid']:
                (root / name).write_text('123')
            response = MagicMock()
            response.__enter__.return_value = response
            response.status = 200
            response.read.return_value = b'{"adminToken":"NEVER_PERSIST"}'
            opener = MagicMock()
            opener.open.return_value = response
            socket = MagicMock()
            socket.__enter__.return_value = socket
            socket.recv.return_value = b'+PONG\r\n'
            def command(args, **kwargs):
                if args[0] == 'ps': return '123 S 0.2 1234'
                if args[0] == 'lsof': return '123\n123\n'
                if args[0] == 'brew': return '/opt/homebrew/opt/postgresql@18\n'
                return '[{"state":"idle","wait_event_type":"Client","wait_event":"ClientRead","connections":3}]'
            with patch.dict(module.os.environ, {'RUNNER_TEMP': folder}), patch.object(module.os, 'kill'), patch.object(module.urllib.request, 'build_opener', return_value=opener), patch.object(module.socket, 'create_connection', return_value=socket), patch.object(module.subprocess, 'check_output', side_effect=command):
                module.capture(root / 'result.json')
            raw = (root / 'result.json').read_text()
            self.assertNotIn('NEVER_PERSIST', raw)
            self.assertEqual(len(json.loads(raw)['checks']), 7)
            self.assertTrue(all(value['status'] == 'PASS' for value in json.loads(raw)['checks'].values()))
            self.assertEqual(json.loads(raw)['checks']['apiListenerProcesses']['value'], [{'pid':123,'state':'S','cpuPercent':0.2,'rssKiB':1234}])
            response.read.assert_not_called()
    def test_failure_messages_cannot_leak_credentials(self):
        with tempfile.TemporaryDirectory() as folder:
            root = pathlib.Path(folder)
            with patch.dict(module.os.environ, {'RUNNER_TEMP': folder}), patch.object(module.urllib.request, 'build_opener', side_effect=RuntimeError('SECRET')), patch.object(module.socket, 'create_connection', side_effect=RuntimeError('SECRET')), patch.object(module.subprocess, 'check_output', side_effect=RuntimeError('SECRET')):
                module.capture(root / 'result.json')
            raw = (root / 'result.json').read_text()
            self.assertNotIn('SECRET', raw)
            self.assertTrue(all(value['status'] == 'FAIL' for value in json.loads(raw)['checks'].values()))

    def test_meta_uses_fixed_unauthenticated_loopback_and_no_body(self):
        response = MagicMock()
        response.__enter__.return_value = response
        response.status = 200
        opener = MagicMock()
        opener.open.return_value = response
        with patch.object(module.urllib.request, 'build_opener', return_value=opener) as build:
            self.assertEqual(module.api_meta_status(), 200)
        request = opener.open.call_args.args[0]
        self.assertEqual(request.full_url, 'http://127.0.0.1:61812/api/meta')
        self.assertEqual(request.data, b'{}')
        self.assertEqual(request.get_method(), 'POST')
        self.assertEqual(request.header_items(), [('Content-type', 'application/json')])
        self.assertEqual(opener.open.call_args.kwargs, {'timeout':3})
        self.assertIsInstance(build.call_args.args[0], module.urllib.request.ProxyHandler)
        self.assertEqual(build.call_args.args[0].proxies, {})
        self.assertIsInstance(build.call_args.args[1], module.NoRedirect)
        response.read.assert_not_called()

    def test_meta_http_failure_is_failed_with_only_status(self):
        error = module.urllib.error.HTTPError('http://127.0.0.1:61812/api/meta?SECRET',503,'SECRET',{'Secret':'SECRET'},None)
        opener = MagicMock()
        opener.open.side_effect = error
        with tempfile.TemporaryDirectory() as folder, patch.dict(module.os.environ, {'RUNNER_TEMP':folder}), patch.object(module.urllib.request, 'build_opener', return_value=opener), patch.object(module.socket, 'create_connection', side_effect=RuntimeError('SECRET')), patch.object(module.subprocess, 'check_output', side_effect=RuntimeError('SECRET')):
            path = pathlib.Path(folder)/'report.json'
            module.capture(path)
            raw = path.read_text()
        self.assertNotIn('SECRET',raw)
        self.assertEqual(json.loads(raw)['checks']['apiMeta']['status'],'FAIL')
        self.assertEqual(json.loads(raw)['checks']['apiMeta']['httpStatus'],503)

    def test_redirects_are_rejected(self):
        with self.assertRaises(RuntimeError):
            module.NoRedirect().redirect_request(None,None,302,'',{},'https://example.com')

    def test_listener_query_is_bounded_and_metadata_only(self):
        def command(args, **kwargs):
            self.assertEqual(kwargs['timeout'],3)
            self.assertEqual(kwargs['stderr'],module.subprocess.DEVNULL)
            if args[0]=='lsof':
                self.assertEqual(args,['lsof','-nP','-a','-iTCP:61812','-sTCP:LISTEN','-t'])
                return '321\n123\n321\n'
            self.assertEqual(args,['ps','-p',args[2],'-o','pid=,stat=,%cpu=,rss='])
            return args[2]+' S< 0.0 4096'
        with patch.object(module.subprocess,'check_output',side_effect=command),patch.object(module.os,'kill'):
            result = module.api_listener_processes()
        self.assertEqual([row['pid'] for row in result],[123,321])
        self.assertTrue(all(set(row)=={'pid','state','cpuPercent','rssKiB'} for row in result))

    def test_invalid_or_unbounded_listener_output_is_not_collected(self):
        for value in ['', 'SECRET', '0', '\n'.join(str(i) for i in range(1,10))]:
            with self.subTest(value=value),patch.object(module.subprocess,'check_output',return_value=value),patch.object(module.os,'kill') as kill:
                with self.assertRaises(AssertionError): module.api_listener_processes()
                kill.assert_not_called()

    def test_process_metadata_rejects_malformed_numeric_fields(self):
        for value in ['999 S 0.0 4096','123 SECRET_WITH_SPACES 0.0 4096','123 S nan 4096','123 S -1 4096','123 S 1 -4']:
            with self.subTest(value=value),patch.object(module.subprocess,'check_output',return_value=value),patch.object(module.os,'kill'):
                with self.assertRaises(AssertionError): module.process_metadata(123)

if __name__ == '__main__': unittest.main()
