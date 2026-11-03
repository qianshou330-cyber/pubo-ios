import XCTest
@testable import PUBOCore

final class AdminSchemaTests: XCTestCase {
    func testRoleMembershipIDNeverBecomesUserOrRoleTarget() {
        let member: JSONValue = .object(["id": .string("assignment"), "user": .object(["id": .string("person"), "username": .string("name")])])
        XCTAssertEqual(AdminSchema.identity("userId", record: member, source: "admin/roles/users", context: ["roleId": .string("role")]), .string("person"))
        XCTAssertEqual(AdminSchema.identity("roleId", record: member, source: "admin/roles/users", context: ["roleId": .string("role")]), .string("role"))
        XCTAssertNil(AdminSchema.identity("roleId", record: member, source: "admin/roles/users", context: [:]))
        XCTAssertNil(AdminSchema.identity("userId", record: .object(["id": .string("role")]), source: "admin/roles/list", context: [:]))
    }
    func testBulkPartialSuccessAndDeletionAreDistinguished() {
        let fields: [String: JSONValue] = ["ids": .strings(["a", "b", "missing"]), "category": .string("new")]
        let rows: [JSONValue] = [.object(["id": .string("a"), "category": .string("new")]), .object(["id": .string("b"), "category": .string("old")])]
        XCTAssertEqual(AdminSchema.bulkResults(operation: "set-category-bulk", fields: fields, rows: rows), ["a": true, "b": false, "missing": false])
        XCTAssertEqual(AdminSchema.bulkResults(operation: "delete-bulk", fields: fields, rows: rows), ["a": false, "b": false, "missing": true])
    }
    func testCombinedObjectSchemaPreservesRequiredFields() throws {
        let schema: JSONValue = .object(["allOf": .array([.object(["type": .string("object"), "properties": .object(["id": .object(["type": .string("string")])]), "required": .strings(["id"])]), .object(["type": .string("object"), "properties": .object(["name": .object(["type": .string("string")])])])])])
        let form = AdminSchema.form(schema)
        XCTAssertEqual(form["type"].string, "object")
        XCTAssertNotNil(form["properties"].object["name"])
        XCTAssertThrowsError(try AdminSchema.validate(.object(["name": .string("test")]), schema: schema))
        XCTAssertNoThrow(try AdminSchema.validate(.object(["id": .string("target"), "name": .string("test")]), schema: schema))
    }
    func testVerificationAllStatusIsValidButEmptyStringIsNot() throws {
        let schema: JSONValue = .object(["type": .string("object"), "properties": .object(["status": .object(["type": .string("string"), "enum": .strings(["pending", "approved", "rejected", "revoked", "all"])]), "type": .object(["type": .string("string"), "nullable": .bool(true), "enum": .array([.string("actor"), .null])])])])
        XCTAssertNoThrow(try AdminSchema.validate(.object(["status": .string("all"), "type": .null]), schema: schema))
        XCTAssertThrowsError(try AdminSchema.validate(.object(["status": .string("")]), schema: schema))
    }
    func testOnlyChangedFieldsAndIdentityAreSubmitted() {
        let old: JSONValue = .object(["id": .string("test"), "name": .string("old"), "secret": .string("synthetic"), "enabled": .bool(true)])
        let changed = AdminSchema.changes(["id": .string("test"), "name": .string("new"), "enabled": .bool(true)], original: old, identityKeys: ["id"])
        XCTAssertEqual(changed, ["id": .string("test"), "name": .string("new")]); XCTAssertNil(changed["secret"])
    }
    func testSensitiveResponseValuesNeverAppearInGenericResults() {
        let value: JSONValue = .object(["name": .string("user"), "token": .string("synthetic"), "documents": .array([.object(["mime": .string("image/png"), "data": .string("synthetic")])]), "smtpPassWord": .string("synthetic")])
        let safe = AdminSchema.redacted(value); XCTAssertTrue(safe["token"].isNull); XCTAssertTrue(safe["smtpPassWord"].isNull); XCTAssertTrue(safe["documents"].array[0]["data"].isNull); XCTAssertEqual(safe["name"].string, "user")
    }
    func testAdminAndModeratorGatesRemainDistinct() throws {
        let admin = try JSONDecoder().decode(AdminEndpoint.self, from: Data(#"{"id":"admin/meta","schema":{},"requireAdmin":true,"requireModerator":false,"requiredRolePolicy":"","secure":true,"kind":"read:admin:meta","mutation":false}"#.utf8))
        XCTAssertFalse(admin.available(to: .object([:]))); XCTAssertFalse(admin.available(to: .object(["isModerator": .bool(true)]))); XCTAssertTrue(admin.available(to: .object(["isAdmin": .bool(true)])))
    }
    func testNumericAndArrayLimitsRejectDangerousBulkInput() {
        let number: JSONValue = .object(["type": .string("integer"), "minimum": .number(1), "maximum": .number(100)])
        XCTAssertThrowsError(try AdminSchema.validate(.number(101), schema: number)); XCTAssertThrowsError(try AdminSchema.validate(.number(1.5), schema: number))
        let array: JSONValue = .object(["type": .string("array"), "uniqueItems": .bool(true), "items": .object(["type": .string("string")])])
        XCTAssertThrowsError(try AdminSchema.validate(.strings(["same", "same"]), schema: array))
    }
}
