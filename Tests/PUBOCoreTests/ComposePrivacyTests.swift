import XCTest
@testable import PUBOCore

final class ComposePrivacyTests: XCTestCase {
    private func reply(_ visibility: String) -> Record {
        Record(.object(["id": .string("note"), "visibility": .string(visibility),
                        "userId": .string("author"), "visibleUserIds": .strings(["me", "friend", "friend"])]))
    }
    private func resolve(_ visibility: String, replyVisibility: String, recipients: [String] = [], seed: Bool = false) -> ComposePrivacy.Selection {
        ComposePrivacy.resolve(visibility: visibility, localOnly: true, recipientIDs: recipients,
                               reply: reply(replyVisibility), channelID: nil, accountID: "me", seedReplyRecipients: seed)
    }
    func testReplyInheritsVisibilityAndRetainsStricterDraft() {
        XCTAssertEqual(resolve("public", replyVisibility: "home").visibility, "home")
        XCTAssertEqual(resolve("public", replyVisibility: "followers").visibility, "followers")
        XCTAssertEqual(resolve("followers", replyVisibility: "home").visibility, "followers")
        XCTAssertEqual(resolve("specified", replyVisibility: "followers", recipients: ["friend"]).recipientIDs, ["friend"])
    }
    func testSpecifiedReplySeedsAuthorAndParticipantsWithoutSelfOrDuplicates() {
        let value = resolve("public", replyVisibility: "specified", seed: true)
        XCTAssertEqual(value.visibility, "specified")
        XCTAssertEqual(value.recipientIDs, ["friend", "author"])
        XCTAssertFalse(value.localOnly)
    }
    func testExistingSpecifiedDraftDoesNotRegainRemovedRecipientsOrAddOutsiders() {
        XCTAssertEqual(resolve("specified", replyVisibility: "specified", recipients: ["friend", "outsider"]).recipientIDs, ["friend"])
        XCTAssertTrue(resolve("specified", replyVisibility: "specified", recipients: []).recipientIDs.isEmpty)
    }
    func testPickerCannotExpandReplyVisibility() {
        XCTAssertEqual(ComposePrivacy.allowedVisibilities(reply: reply("home"), channelID: nil), ["home", "followers", "specified"])
        XCTAssertEqual(ComposePrivacy.allowedVisibilities(reply: reply("followers"), channelID: nil), ["followers", "specified"])
        XCTAssertEqual(ComposePrivacy.allowedVisibilities(reply: reply("specified"), channelID: nil), ["specified"])
    }
    func testChannelAlwaysUsesPublicLocalOnlyAndNoRecipients() {
        let value = ComposePrivacy.resolve(visibility: "specified", localOnly: false, recipientIDs: ["friend"], reply: nil, channelID: "channel", accountID: "me")
        XCTAssertEqual(value.visibility, "public"); XCTAssertTrue(value.localOnly); XCTAssertTrue(value.recipientIDs.isEmpty)
    }
    func testOrdinaryPostPreservesChoiceAndSilencedPostCannotBePublic() {
        let ordinary = ComposePrivacy.resolve(visibility: "followers", localOnly: true, recipientIDs: [], reply: nil, channelID: nil, accountID: "me")
        XCTAssertEqual(ordinary.visibility, "followers"); XCTAssertTrue(ordinary.localOnly)
        XCTAssertEqual(ComposePrivacy.allowedVisibilities(reply: nil, channelID: nil, silenced: true), ["home", "followers", "specified"])
    }
    func testEveryReplyAndDraftCombinationNeverExpandsVisibility() {
        let scopes = ["public", "home", "followers", "specified"]
        for (parentRank, parent) in scopes.enumerated() {
            for (draftRank, draft) in scopes.enumerated() {
                let result = resolve(draft, replyVisibility: parent, recipients: ["friend"])
                XCTAssertEqual(scopes.firstIndex(of: result.visibility), max(parentRank, draftRank))
            }
        }
    }
    func testAuthorFallbackAndSelfReply() {
        let note = Record(.object(["visibility": .string("specified"), "user": .object(["id": .string("me")]), "visibleUserIds": .strings(["friend"])]))
        XCTAssertEqual(ComposePrivacy.replyRecipientIDs(note, accountID: "me"), ["friend"])
    }
}
