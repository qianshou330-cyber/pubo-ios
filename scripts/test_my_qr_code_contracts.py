"""Static source contracts for C112 H5-aligned My QR Code card & scanner bidirectional switch; not a substitute for iOS Simulator screenshots or real camera scanning."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class MyQRCodeContracts(unittest.TestCase):
    def test_qr_renderer_matches_h5_palette_high_ec_and_keeps_light_quiet_zone(self):
        src = (ROOT / 'App/Features/MyQRCodeView.swift').read_text()
        self.assertIn('static let cardBackgroundHex: UInt32 = 0xfbfff0', src)
        self.assertIn('static let moduleColorHex: UInt32 = 0x455c00', src)
        self.assertIn('static let badgeBackgroundHex: UInt32 = 0x0b1412', src)
        self.assertIn('filter.correctionLevel = "H"', src)
        self.assertIn('let quietModules: CGFloat = 4', src)
        self.assertIn('Image(uiImage: qrImage)', src)
        self.assertIn('accessibilityIdentifier("myQR.scan")', src)
        self.assertIn('accessibilityIdentifier("myQR.image")', src)
        self.assertIn('accessibilityIdentifier("myQR.save")', src)
        self.assertIn('accessibilityIdentifier("myQR.share")', src)
        self.assertIn('if session.testMode {', src)
        self.assertIn('隔离测试不写入系统相册', src)

    def test_user_qr_code_core_generator_preserves_strict_h5_parser(self):
        core = (ROOT / 'Sources/PUBOCore/UserQRCode.swift').read_text()
        self.assertIn('public static func userID(from value: String) -> String?', core)
        self.assertIn('public static func url(forUserID id: String) -> URL?', core)
        self.assertIn('public static func displayHandle(username: String?, host: String? = nil) -> String?', core)
        self.assertIn('guard userID(from: raw) == id else { return nil }', core)

    def test_profile_and_scanner_wire_bidirectional_entries_without_breaking_messages_menu(self):
        profile = (ROOT / 'App/Features/ProfileView.swift').read_text()
        self.assertIn('accessibilityIdentifier("me.qrcode")', profile)
        self.assertIn('accessibilityIdentifier("profile.qrcode")', profile)
        self.assertIn('ToolbarItemGroup(placement: .topBarTrailing)', profile)
        self.assertIn('Image(systemName: "lock.shield")', profile)
        self.assertIn('.accessibilityLabel("账号与隐私设置")', profile)

        scanner = (ROOT / 'App/Features/FriendQRScannerView.swift').read_text()
        self.assertIn('UIApplication.openSettingsURLString', scanner)
        self.assertIn('accessibilityIdentifier("scanner.openSettings")', scanner)
        self.assertIn('accessibilityIdentifier("scanner.myQR")', scanner)
        self.assertIn('MyQRCodeView(allowScanSwitch: false)', scanner)

        chat_list = (ROOT / 'App/Features/ChatListView.swift').read_text()
        menu = chat_list.split('Menu {', 1)[1].split('Image(systemName: "plus")', 1)[0]
        self.assertIn('messages.scan', menu)
        self.assertIn('messages.addUsername', menu)
        self.assertNotIn('me.qrcode', menu)

    def test_ui_test_verifies_live_qr_decodability_in_both_themes(self):
        ui = (ROOT / 'UITests/FourTabNavigationUITests.swift').read_text()
        self.assertIn('import CoreImage', ui)
        self.assertIn('CIDetector(ofType: CIDetectorTypeQRCode', ui)
        self.assertIn('https://bolubo.com/users/syntheticself', ui)
        self.assertIn('me-qrcode-', ui)
        self.assertIn('scanner.myQR', ui)


if __name__ == '__main__':
    unittest.main()
