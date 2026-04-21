import Foundation
@testable import Murmur

@MainActor
enum HistoryStoreTests {
    static func run() {
        Harness.suite("HistoryStore") {
            Harness.test("appendReturnsMonotonicIds") {
                let store = try HistoryStore.inMemory()
                let id1 = store.append(text: "one", model: "m")
                let id2 = store.append(text: "two", model: "m")
                Harness.expect(id2 > id1)
            }

            Harness.test("recentOrdersDescendingByTimestamp") {
                let store = try HistoryStore.inMemory()
                let now = Date()
                _ = store.append(text: "older", model: "m", timestamp: now.addingTimeInterval(-60))
                _ = store.append(text: "newer", model: "m", timestamp: now)

                let rows = store.recent(limit: 10)
                Harness.expectEqual(rows.count, 2)
                Harness.expectEqual(rows.first?.text, "newer")
                Harness.expectEqual(rows.last?.text, "older")
            }

            Harness.test("recentLimitIsRespected") {
                let store = try HistoryStore.inMemory()
                for i in 0..<5 {
                    _ = store.append(text: "t\(i)", model: "m")
                }
                Harness.expectEqual(store.recent(limit: 3).count, 3)
            }

            Harness.test("markPastedUpdatesFlag") {
                let store = try HistoryStore.inMemory()
                let id = store.append(text: "hi", model: "m")
                Harness.expectEqual(store.recent(limit: 1).first?.pasted, false)

                store.markPasted(id)
                Harness.expectEqual(store.recent(limit: 1).first?.pasted, true)
            }

            Harness.test("errorRowPreservesMessage") {
                let store = try HistoryStore.inMemory()
                _ = store.append(text: "", model: "m", error: "API key invalid")
                let row = try Harness.unwrap(store.recent(limit: 1).first)
                Harness.expectEqual(row.error, "API key invalid")
                Harness.expectEqual(row.text, "")
            }

            Harness.test("durationRoundtripsThroughNull") {
                let store = try HistoryStore.inMemory()
                _ = store.append(text: "a", model: "m", durationS: nil)
                _ = store.append(text: "b", model: "m", durationS: 1.25)
                let rows = store.recent(limit: 10)
                let byText = Dictionary(uniqueKeysWithValues: rows.map { ($0.text, $0) })
                Harness.expect(byText["a"]?.durationS == nil)
                Harness.expectEqual(byText["b"]?.durationS, 1.25)
            }

            Harness.test("countReflectsInserts") {
                let store = try HistoryStore.inMemory()
                Harness.expectEqual(store.count(), 0)
                _ = store.append(text: "x", model: "m")
                _ = store.append(text: "y", model: "m")
                Harness.expectEqual(store.count(), 2)
            }

            Harness.test("pruneDeletesOlderRows") {
                let store = try HistoryStore.inMemory()
                let now = Date()
                _ = store.append(text: "ancient", model: "m", timestamp: now.addingTimeInterval(-60 * 60 * 24 * 40))
                _ = store.append(text: "recent", model: "m", timestamp: now)

                let deleted = store.prune(retentionDays: 30)
                Harness.expectEqual(deleted, 1)
                Harness.expectEqual(store.recent(limit: 10).map(\.text), ["recent"])
            }

            Harness.test("pruneNoOpForZeroOrNegative") {
                let store = try HistoryStore.inMemory()
                _ = store.append(text: "keep", model: "m", timestamp: Date().addingTimeInterval(-10_000_000))
                Harness.expectEqual(store.prune(retentionDays: 0), 0)
                Harness.expectEqual(store.prune(retentionDays: -5), 0)
                Harness.expectEqual(store.count(), 1)
            }

            Harness.test("usageByModelAggregatesPerModel") {
                let store = try HistoryStore.inMemory()
                _ = store.append(text: "a", model: "whisper-1", durationS: 30)
                _ = store.append(text: "b", model: "whisper-1", durationS: 90)
                _ = store.append(text: "c", model: "gpt-4o-transcribe", durationS: 60)

                let rows = store.usageByModel()
                Harness.expectEqual(rows.count, 2)
                let whisper = try Harness.unwrap(rows.first { $0.model == "whisper-1" })
                Harness.expectEqual(whisper.count, 2)
                Harness.expectEqual(whisper.totalSeconds, 120)
            }

            Harness.test("usageByModelSkipsErrorRowsAndNullDuration") {
                let store = try HistoryStore.inMemory()
                _ = store.append(text: "ok",    model: "whisper-1", durationS: 60)
                _ = store.append(text: "fail",  model: "whisper-1", durationS: 60, error: "boom")
                _ = store.append(text: "nodur", model: "whisper-1", durationS: nil)

                let rows = store.usageByModel()
                Harness.expectEqual(rows.count, 1)
                Harness.expectEqual(rows.first?.count, 1)
                Harness.expectEqual(rows.first?.totalSeconds, 60)
            }

            Harness.test("estimatedCostMatchesPricingTable") {
                // 600s = 10 min × $0.006 = $0.06 for whisper-1.
                let row = HistoryStore.UsageRow(model: "whisper-1", count: 1, totalSeconds: 600)
                Harness.expectEqual(HistoryStore.estimatedCost(for: row), 0.06)
                Harness.expectEqual(HistoryStore.pricePerMinute(model: "gpt-4o-mini-transcribe"), 0.003)
                Harness.expectEqual(HistoryStore.pricePerMinute(model: "unknown"), 0)
            }
        }
    }
}
