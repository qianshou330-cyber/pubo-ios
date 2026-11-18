from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[1]
class ChatLoadOwnershipTests(unittest.TestCase):
 def test_separate_tokens_and_disappearance(self):
  s=(ROOT/'App/Features/ChatView.swift').read_text()
  self.assertIn('loadOwnership = LoadRequestOwnership()', s)
  self.assertIn('contextOwnership = LoadRequestOwnership()', s)
  self.assertIn('active = false; loadOwnership.invalidate(); contextOwnership.invalidate()', s)
  self.assertIn('defer { loadOwnership.finish(request);', s)
  self.assertEqual(s.count('defer { contextOwnership.finish(request) }'), 2)
  self.assertNotIn('loading = true', s)
  self.assertNotIn('contextBusy = true', s)
 def test_cancelled_lifecycle_and_scroll_cannot_reenter(self):
  s=(ROOT/'App/Features/ChatView.swift').read_text()
  self.assertIn('await refreshPeer()\n                guard !Task.isCancelled, active else { return }', s)
  self.assertIn('guard active, !Task.isCancelled, let request = loadOwnership.begin()', s)
  self.assertEqual(s.count('guard active, !Task.isCancelled, let request = contextOwnership.begin()'), 2)
  self.assertEqual(s.count('await Task.yield(); guard active, epoch == syncEpoch, !Task.isCancelled else { return }; scrollTarget'), 2)
 def test_content_and_security_guards_retained(self):
  s=(ROOT/'App/Features/ChatView.swift').read_text()
  self.assertIn('guard epoch == syncEpoch, !Task.isCancelled else { return }', s)
  self.assertIn('Set([peer.id, ownerID ?? ""]) && row["toRoomId"].isNull', s)
  self.assertIn('if active, epoch == syncEpoch, !Task.isCancelled { loadError', s)
