"""Source guardrails for C109 privacy switch layout stability, finite-window AX guard, and note-body activation point."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class C109PrivacyAndNoteTapContractTests(unittest.TestCase):
    def test_privacy_loading_indicator_lives_in_toolbar_not_form_rows(self):
        source = (ROOT / 'App/Features/AccountSettingsView.swift').read_text()
        privacy = source.split('struct PrivacySettingsView: View {', 1)[1].split('private struct PrivacySwitchEventProbe:', 1)[0]
        form = privacy.split('Form {', 1)[1].split('}.puboForm()', 1)[0]
        self.assertNotIn('ProgressView(', form)
        self.assertIn('.toolbar {', privacy)
        self.assertIn('ToolbarItem(placement: .topBarTrailing)', privacy)
        self.assertIn('ProgressView().controlSize(.small).accessibilityLabel("读取当前设置…")', privacy)
        # Ensure values are populated atomically before original marks loaded.
        load_fn = privacy.split('private func load() async {', 1)[1].split('private func save()', 1)[0]
        self.assertLess(load_fn.index('values = loadedValues'), load_fn.index('original = fetched'))

    def test_privacy_switch_ui_tests_guard_hittability_with_finite_window_rect(self):
        for rel in ('UITests/AccountSettingsParityUITests.swift', 'UITests/PUBOUITests.swift'):
            source = (ROOT / rel).read_text()
            self.assertIn('puboWindowContainsFiniteRect(', source)
            set_switch = source.split('private func setSwitch(', 1)[1].split('XCTAssertEqual(outcome, .completed)', 1)[0]
            self.assertNotIn('XCTAssertTrue(control.isHittable)', set_switch)
            self.assertLess(
                set_switch.index('puboWindowContainsFiniteRect(row.frame, in: window)'),
                set_switch.index('let rowHittable = control.isHittable'),
            )
            self.assertIn('puboNativeSwitchFitsAXRow(bounds, row: row.frame)', set_switch)
            self.assertIn('actual.tap()', set_switch)

    def test_tappable_note_body_centers_accessibility_activation_point_only_when_tappable(self):
        source = (ROOT / 'App/Components/RichNoteText.swift').read_text()
        self.assertIn('view.opensOnTap = onTap != nil', source)
        self.assertIn('override var accessibilityActivationPoint: CGPoint', source)
        self.assertIn('guard opensOnTap, window != nil, !bounds.isEmpty else { return super.accessibilityActivationPoint }', source)
        self.assertIn('UIAccessibility.convertToScreenCoordinates(bounds, in: self)', source)


if __name__ == '__main__':
    unittest.main()
