import XCTest

/// Focused, synthetic, read-only. This test neither rewrites app state nor constructs AX labels.
final class C99FriendsChildHandlesUITests: XCTestCase {
    private enum ProofError: Error {
        case wrongRoute, ambiguousList, invalidGeometry, wrongRows, ambiguousRow, wrongText, changed
    }

    private struct RowReading: Equatable {
        let id: String
        let text: [String]
        let frame: CGRect
    }

    override func setUpWithError() throws { continueAfterFailure = false }

    func testFollowingFromFriends() throws {
        try exercise("following", title: "关注", ids: ["out0", "out1", "out2", "out3"],
                     handles: ["@twin@out-a.invalid", "@twin@out-b.invalid", "@twin", nil])
    }

    func testFollowersFromFriends() throws {
        try exercise("followers", title: "关注者", ids: ["in0", "in1", "in2", "in3"],
                     handles: ["@twin@in-a.invalid", "@twin@in-b.invalid", "@twin", nil])
    }

    private func exercise(_ route: String, title: String, ids: [String], handles: [String?]) throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reduce-motion", "--c99-child-handles"]
        app.launch()
        defer { app.terminate() }
        puboSelectTab(app, "好友")
        let scopeID = "c99.list." + route
        // Scope discovery may start at the app; all identity and subtitle reads are inside this list.
        let query = app.descendants(matching: .any).matching(identifier: scopeID)
        guard !query.firstMatch.exists else { throw ProofError.wrongRoute }
        puboTapVisible(app, "friends." + route)
        guard app.navigationBars[title].waitForExistence(timeout: 10),
              query.firstMatch.waitForExistence(timeout: 10), query.count == 1 else {
            throw ProofError.ambiguousList
        }
        let scope = query.element(boundBy: 0)
        let rowIDs = ids.map { "c99.row." + route + ".rel-" + $0 + ".uid-" + $0 }
        guard scope.descendants(matching: .any).matching(identifier: rowIDs[3])
            .firstMatch.waitForExistence(timeout: 10) else { throw ProofError.wrongRows }

        for id in rowIDs {
            let buttons = scope.buttons.matching(identifier: id)
            let cells = scope.cells.matching(identifier: id)
            let matches = buttons.count == 0 ? cells : buttons
            guard matches.count == 1, matches.element(boundBy: 0).isHittable else {
                throw ProofError.ambiguousRow
            }
        }
        let window = app.windows.firstMatch.frame
        // Keep the original PNG bracketed by *fresh*, immutable, list-scoped reads.
        // No waiting for replacement content, retries, AX dumps, or fabricated screenshots.
        let before = try read(scope.snapshot(), scopeID: scopeID, rowIDs: rowIDs, handles: handles, window: window)
        let shot = app.screenshot()
        let after = try read(scope.snapshot(), scopeID: scopeID, rowIDs: rowIDs, handles: handles, window: window)
        guard before == after else { throw ProofError.changed }
        let png = XCTAttachment(data: shot.pngRepresentation, uniformTypeIdentifier: "public.png")
        png.name = "C99-Friends-" + route + ".png"
        png.lifetime = .keepAlways
        add(png)
    }

    private func read(_ root: XCUIElementSnapshot, scopeID: String, rowIDs: [String],
                      handles: [String?], window: CGRect) throws -> [RowReading] {
        guard root.identifier == scopeID,
              root.elementType == .collectionView || root.elementType == .table else { throw ProofError.wrongRoute }
        let viewport = root.frame.intersection(window)
        guard positive(viewport) else { throw ProofError.invalidGeometry }
        let tagged = puboSnapshotDescendants(root).filter { $0.identifier.hasPrefix("c99.row.") }
        guard Set(tagged.map { $0.identifier }) == Set(rowIDs) else { throw ProofError.wrongRows }
        var readings: [RowReading] = []
        for (i, id) in rowIDs.enumerated() {
            let sameID = tagged.filter { $0.identifier == id }
            // SwiftUI may mark both an enclosing cell and its link. Prefer the unique link.
            // Refuse duplicate buttons/cells rather than choosing firstMatch.
            let buttons = sameID.filter { $0.elementType == .button }
            let cells = sameID.filter { $0.elementType == .cell }
            guard buttons.count <= 1, cells.count <= 1,
                  let row = buttons.first ?? cells.first else { throw ProofError.ambiguousRow }
            let frame = row.frame
            guard positive(frame), viewport.contains(frame),
                  readings.last.map({ $0.frame.maxY <= frame.minY + 0.5 }) ?? true else {
                throw ProofError.invalidGeometry
            }
            // Read rendered text, never a test-populated value or a generated display handle.
            let textNodes = puboSnapshotDescendants(row).filter { $0.elementType == .staticText }
            let labels = row.label.isEmpty ? textNodes.map { $0.label } : [row.label]
            let tokens = labels.flatMap { $0.components(separatedBy: CharacterSet(charactersIn: ",，\n")) }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            let expected = ["同名样本"] + [handles[i]].compactMap { $0 }
            guard tokens == expected else { throw ProofError.wrongText }
            readings.append(RowReading(id: id, text: tokens, frame: frame))
        }
        return readings
    }

    private func positive(_ r: CGRect) -> Bool {
        !r.isNull && !r.isInfinite && [r.minX, r.minY, r.width, r.height].allSatisfy { $0.isFinite }
            && r.width > 0 && r.height > 0
    }
}
