import Foundation
@testable import Murmur

/// All tests run against a throwaway service name so the user's real
/// `murmur` slot is never touched.
enum KeychainTests {
    static let testSlot = Keychain.Slot(
        service: "murmur.tests",
        account: "roundtrip"
    )

    static func run() {
        Harness.suite("Keychain") {
            Harness.test("readMissingReturnsNil") {
                try? Keychain.delete(testSlot)
                let value = try Keychain.read(testSlot)
                Harness.expect(value == nil)
            }

            Harness.test("writeThenReadRoundtrip") {
                try? Keychain.delete(testSlot)
                try Keychain.write(testSlot, value: "sk-test-abc123")
                let value = try Keychain.read(testSlot)
                Harness.expectEqual(value, "sk-test-abc123")
                try Keychain.delete(testSlot)
            }

            Harness.test("writeOverwritesExistingValue") {
                try? Keychain.delete(testSlot)
                try Keychain.write(testSlot, value: "first")
                try Keychain.write(testSlot, value: "second")
                let value = try Keychain.read(testSlot)
                Harness.expectEqual(value, "second")
                try Keychain.delete(testSlot)
            }

            Harness.test("deleteMakesReadReturnNil") {
                try Keychain.write(testSlot, value: "value")
                try Keychain.delete(testSlot)
                let value = try Keychain.read(testSlot)
                Harness.expect(value == nil)
            }

            Harness.test("deleteMissingIsNoOp") {
                try? Keychain.delete(testSlot)
                try Keychain.delete(testSlot) // second call should not throw
            }

            Harness.test("openAISlotHasExpectedIdentity") {
                // The Python prototype writes to exactly this slot via `keyring`.
                // If this ever fails, migrated users lose their key.
                Harness.expectEqual(Keychain.openAIKey.service, "murmur")
                Harness.expectEqual(Keychain.openAIKey.account, "openai_api_key")
            }
        }
    }
}
