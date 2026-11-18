from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[1]
class ConfirmedDraftTests(unittest.TestCase):
 def test_rebase_only_after_readback_guard(self):
  s=(ROOT/'App/Features/AccountSettingsView.swift').read_text()
  save=s.split('private func save() async {',1)[1].split('\n}\n',1)[0]
  self.assertLess(save.index('guard changed.allSatisfy({ confirmed'),save.index('values = AccountSettingsPolicy.confirmedPrivacyDraft'))
  self.assertLess(save.index('values = AccountSettingsPolicy.confirmedPrivacyDraft'),save.index('original = confirmed'))
  self.assertIn('fresh[$0.key] == original[$0.key]',save)
  self.assertIn('editableKeys: Array(values.keys)',save)
 def test_projection_does_not_include_account_fields(self):
  s=(ROOT/'Sources/PUBOCore/AccountSettingsPolicy.swift').read_text()
  self.assertIn('Set(editableKeys).map { ($0, confirmed[$0]) }',s)
