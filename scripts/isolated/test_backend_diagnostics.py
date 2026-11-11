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
                if args[0] == 'brew': return '/opt/homebrew/opt/postgresql@18\n'
                return '[{"state":"idle","wait_event_type":"Client","wait_event":"ClientRead","connections":3}]'
            with patch.dict(module.os.environ, {'RUNNER_TEMP': folder}), patch.object(module.os, 'kill'), patch.object(module.urllib.request, 'build_opener', return_value=opener), patch.object(module.socket, 'create_connection', return_value=socket), patch.object(module.subprocess, 'check_output', side_effect=command):
                module.capture(root / 'result.json')
            raw = (root / 'result.json').read_text()
            self.assertNotIn('NEVER_PERSIST', raw)
            self.assertEqual(len(json.loads(raw)['checks']), 5)
            self.assertTrue(all(value['status'] == 'PASS' for value in json.loads(raw)['checks'].values()))
    def test_failure_messages_cannot_leak_credentials(self):
        with tempfile.TemporaryDirectory() as folder:
            root = pathlib.Path(folder)
            with patch.dict(module.os.environ, {'RUNNER_TEMP': folder}), patch.object(module.urllib.request, 'build_opener', side_effect=RuntimeError('SECRET')), patch.object(module.socket, 'create_connection', side_effect=RuntimeError('SECRET')), patch.object(module.subprocess, 'check_output', side_effect=RuntimeError('SECRET')):
                module.capture(root / 'result.json')
            raw = (root / 'result.json').read_text()
            self.assertNotIn('SECRET', raw)
            self.assertTrue(all(value['status'] == 'FAIL' for value in json.loads(raw)['checks'].values()))

if __name__ == '__main__': unittest.main()
