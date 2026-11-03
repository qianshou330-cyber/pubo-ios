import XCTest
@testable import PUBOCore

final class AccountVaultTests: XCTestCase {
    func testBuild22CredentialMigratesWithoutChangingAccountOrToken() throws {
        let legacy = try JSONDecoder().decode(LoginSecret.self, from: Data(#"{"token":"synthetic-old","userID":"alice"}"#.utf8))
        let vault = AccountVault(legacy: legacy)
        XCTAssertEqual(vault.active?.userID, "alice"); XCTAssertEqual(vault.active?.token, "synthetic-old"); XCTAssertNil(vault.active?.username)
        XCTAssertEqual(try JSONDecoder().decode(AccountVault.self, from: JSONEncoder().encode(vault)), vault)
    }
    func testSwitchAndRefreshReplaceOnlyTheMatchingCredential() {
        var vault = AccountVault(legacy: LoginSecret(token: "synthetic-a", userID: "alice"))
        vault.install(LoginSecret(token: "synthetic-b", userID: "bob")); vault.install(LoginSecret(token: "synthetic-a-new", userID: "alice"))
        XCTAssertEqual(vault.accounts.count, 2); XCTAssertEqual(vault.active?.token, "synthetic-a-new")
        XCTAssertEqual(vault.accounts.first { $0.userID == "bob" }?.token, "synthetic-b")
    }
    func testLogoutNeverSelectsOrDeletesAnotherAccount() {
        var vault = AccountVault(legacy: LoginSecret(token: "synthetic-a", userID: "alice")); vault.install(LoginSecret(token: "synthetic-b", userID: "bob"))
        vault.remove("alice"); XCTAssertEqual(vault.activeID, "bob"); XCTAssertEqual(vault.accounts.count, 1)
        vault.install(LoginSecret(token: "synthetic-a", userID: "alice")); vault.remove("alice")
        XCTAssertNil(vault.active); XCTAssertEqual(vault.accounts.map(\.userID), ["bob"])
    }
    func testCorruptVaultDoesNotDecodeAsAnEmptyLogout() {
        XCTAssertThrowsError(try JSONDecoder().decode(AccountVault.self, from: Data(#"{"accounts":"broken"}"#.utf8)))
    }
}
