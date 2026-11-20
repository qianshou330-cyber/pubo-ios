"""Mocked simctl data, not native execution."""
import unittest
from unittest.mock import patch

from iphone_qa_matrix import MATRIX, RUNTIME, create_device, select_template


OWNED = 'aabbccdd-1111-2222-3333-aabbccddeeff'


def device(slot, udid='A', **changes):
    profile = MATRIX[slot]
    return dict({'name': profile['model'], 'deviceTypeIdentifier': profile['deviceTypeIdentifier'],
                 'udid': udid, 'isAvailable': True}, **changes)


class DeviceMatrixTests(unittest.TestCase):
    def test_independent_profiles_select_exact_model(self):
        inventory = {RUNTIME: [device('large', 'z'), device('small', 'm'), device('small', 'a')]}
        self.assertEqual(select_template(inventory, 'small')['udid'], 'a')
        self.assertEqual(select_template(inventory, 'large')['udid'], 'z')
        self.assertEqual(select_template({RUNTIME: [device('large')]}, 'large')['runtime'], RUNTIME)

    def test_no_older_wrong_type_wrong_runtime_or_unavailable_fallback(self):
        for inventory in [
            {RUNTIME: [device('small', name='iPhone SE (3rd generation)'), device('large')]},
            {RUNTIME: [device('small', deviceTypeIdentifier='com.apple.CoreSimulator.SimDeviceType.iPhone-13')]},
            {RUNTIME: [device('small', isAvailable=False)]},
            {'com.apple.CoreSimulator.SimRuntime.iOS-26-0': [device('small')]},
        ]:
            with self.subTest(inventory=inventory), self.assertRaisesRegex(ValueError, 'no fallback'):
                select_template(inventory, 'small')

    @patch('iphone_qa_matrix.available_inventory')
    @patch('iphone_qa_matrix.subprocess.check_output', return_value=OWNED + '\n')
    def test_fresh_owned_device_records_canonical_model(self, output, inventory):
        inventory.return_value = {RUNTIME: [device('small', OWNED, name='PUBO new')]}
        data = create_device('small', dict(device('small'), runtime=RUNTIME), 'PUBO new')
        self.assertEqual((data['model'], data['udid'], data['runtime']), ('iPhone 17', OWNED, RUNTIME))
        self.assertEqual(output.call_args.args[0],
                         ['xcrun', 'simctl', 'create', 'PUBO new', MATRIX['small']['deviceTypeIdentifier'], RUNTIME])

    @patch('iphone_qa_matrix.available_inventory')
    @patch('iphone_qa_matrix.subprocess.run')
    @patch('iphone_qa_matrix.subprocess.check_output', return_value=OWNED + '\n')
    def test_owned_wrong_type_rejected_and_cleaned(self, output, run, inventory):
        inventory.return_value = {RUNTIME: [device('large', OWNED, name='PUBO new')]}
        with self.assertRaisesRegex(ValueError, 'identity'):
            create_device('small', dict(device('small'), runtime=RUNTIME), 'PUBO new')
        self.assertEqual(run.call_args.args[0], ['xcrun', 'simctl', 'delete', OWNED])

    @patch('iphone_qa_matrix.subprocess.run')
    @patch('iphone_qa_matrix.subprocess.check_output', return_value='all\n')
    def test_non_uuid_create_never_deletes(self, output, run):
        with self.assertRaisesRegex(ValueError, 'UUID'):
            create_device('small', dict(device('small'), runtime=RUNTIME), 'PUBO new')
        run.assert_not_called()

    @patch('iphone_qa_matrix.subprocess.check_output')
    def test_invalid_template_never_calls_simctl_create(self, output):
        with self.assertRaisesRegex(ValueError, 'Template'):
            create_device('small', dict(device('large'), runtime=RUNTIME), 'PUBO new')
        output.assert_not_called()
