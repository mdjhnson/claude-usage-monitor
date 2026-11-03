import XCTest
@testable import PaceBarCore

final class ChatBoardTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_793_744_400)

    /// A real `~/.claude/sessions/<pid>.json`, as Claude Code 2.1 writes it.
    let realFile = """
    {"pid":11666,"sessionId":"befed815-eaca-481f-96cd-f9b276f16c21","cwd":"/Users/me/GitHub/claude-usage-monitor",\
    "startedAt":1793744319418,"procStart":"Tue Nov  3 22:18:38 2026","version":"2.1.317","peerProtocol":1,\
    "peerFeatures":["notify_idle"],"kind":"interactive","entrypoint":"claude-vscode","pidDomain":"darwin",\
    "messagingSocketPath":"/tmp/cc-socks/11666.sock","name":"claude-usage-monitor-30","nameSource":"derived",\
    "nameSince":1793744319418,"status":"busy","updatedAt":1793744361336,"statusUpdatedAt":1793744361336,\
    "bridgeSessionId":"session_01Gh1FEWtDuAR8QXA3g7i17k"}
    """

    func file(
        _ pid: Int32, status: String?, ago: TimeInterval, name: String? = nil, nameSource: String? = "derived",
        cwd: String? = "/Users/me/GitHub/curvelog", waitingFor: String? = nil
    ) -> SessionFile {
        SessionFile(
            pid: pid, cwd: cwd, name: name, nameSource: nameSource, status: status, waitingFor: waitingFor,
            statusUpdatedAt: now.addingTimeInterval(-ago).timeIntervalSince1970 * 1000
        )
    }

    func board(_ files: [SessionFile], lifetime: TimeInterval = 3600) -> ChatBoard {
        ChatBoard.make(from: files, cacheLifetime: lifetime, theme: ["chill": 0x32D74B], now: now)
    }

    func testDecodesARealFile() throws {
        let file = try XCTUnwrap(SessionFile.decode(Data(realFile.utf8)))
        XCTAssertEqual(file.pid, 11666)
        XCTAssertEqual(file.status, "busy")
        XCTAssertEqual(file.procStart, "Tue Nov  3 22:18:38 2026")
        let chat = try XCTUnwrap(board([file]).chats.first)
        XCTAssertEqual(chat.title, "claude-usage-monitor")
        XCTAssertNil(chat.folder)
        XCTAssertEqual(chat.activity, .working)
        XCTAssertEqual(chat.since, Date(timeIntervalSince1970: 1_793_744_361.336))
    }

    func testRejectsFilesWithoutAPID() {
        XCTAssertNil(SessionFile.decode(Data("{\"status\":\"busy\"}".utf8)))
        XCTAssertNil(SessionFile.decode(Data("not json".utf8)))
    }

    /// Only `<pid>.json` is ever opened, never the `.key` files beside them.
    func testFileNameFilter() {
        XCTAssertTrue(SessionFile.isSessionFileName("11666.json"))
        XCTAssertFalse(SessionFile.isSessionFileName("11666.765c05dacf59c4d5.key"))
        XCTAssertFalse(SessionFile.isSessionFileName("11666.json.key"))
        XCTAssertFalse(SessionFile.isSessionFileName(".json"))
        XCTAssertFalse(SessionFile.isSessionFileName("abc.json"))
        XCTAssertFalse(SessionFile.isSessionFileName("../1.json"))
        XCTAssertFalse(SessionFile.isSessionFileName("١٢.json"), "non-ASCII digits")
    }

    func testStatusMapping() {
        let b = board([
            file(1, status: "waiting", ago: 10, waitingFor: "dialog open"),
            file(2, status: "busy", ago: 10),
            file(3, status: "idle", ago: 10),
            file(4, status: "somethingNew", ago: 10),
            file(5, status: nil, ago: 10),
        ])
        let byID = Dictionary(uniqueKeysWithValues: b.chats.map { ($0.id, $0) })
        XCTAssertEqual(byID[1]?.activity, .needsYou)
        XCTAssertEqual(byID[1]?.reason, "dialog open")
        XCTAssertEqual(byID[2]?.activity, .working)
        XCTAssertNil(byID[2]?.reason)
        XCTAssertEqual(byID[3]?.activity, .idle)
        XCTAssertEqual(byID[4]?.activity, .idle, "unknown statuses count as idle")
        XCTAssertEqual(byID[5]?.activity, .idle)
    }

    func testTitleIsTheChatNameOnlyWhenSomeoneNamedIt() {
        let b = board([
            file(1, status: "idle", ago: 1, name: "Magic world bugs", nameSource: "user", cwd: "/x/ridebook"),
            file(2, status: "idle", ago: 1, name: "ridebook-ab", nameSource: "derived", cwd: "/x/ridebook"),
            file(3, status: "idle", ago: 1, name: "  ", nameSource: "user", cwd: "/x/curvelog"),
            file(4, status: "idle", ago: 1, name: nil, nameSource: nil, cwd: nil),
        ])
        let byID = Dictionary(uniqueKeysWithValues: b.chats.map { ($0.id, $0) })
        XCTAssertEqual(byID[1]?.title, "Magic world bugs")
        XCTAssertEqual(byID[1]?.folder, "ridebook")
        XCTAssertEqual(byID[2]?.title, "ridebook")
        XCTAssertNil(byID[2]?.folder)
        XCTAssertEqual(byID[3]?.title, "curvelog")
        XCTAssertEqual(byID[4]?.title, "Claude Code")
    }

    func testLongTitlesAreClipped() {
        let b = board([file(1, status: "idle", ago: 1, name: String(repeating: "a", count: 200), nameSource: "user")])
        XCTAssertEqual(b.chats.first?.title.count, ChatBoard.maxTitleLength)
        XCTAssertEqual(b.chats.first?.title.last, "…")
    }

    func testCacheGoesColdAtTheLifetime() throws {
        let b = board([file(1, status: "idle", ago: 0)], lifetime: 300)
        let chat = try XCTUnwrap(b.chats.first)
        XCTAssertEqual(b.state(of: chat, at: now), .cached(expires: now.addingTimeInterval(300)))
        XCTAssertEqual(b.state(of: chat, at: now.addingTimeInterval(299)), .cached(expires: now.addingTimeInterval(300)))
        XCTAssertEqual(b.state(of: chat, at: now.addingTimeInterval(300)), .cold)
        XCTAssertEqual(b.expiries(after: now), [now.addingTimeInterval(300)])
        XCTAssertEqual(b.expiries(after: now.addingTimeInterval(400)), [])
    }

    func testWorkingAndWaitingChatsNeverGoCold() throws {
        let b = board([file(1, status: "busy", ago: 7200), file(2, status: "waiting", ago: 7200)])
        XCTAssertEqual(b.chats.map { b.state(of: $0, at: now) }, [.needsYou, .working])
    }

    func testMostUrgentFirst() {
        let b = board([
            file(1, status: "idle", ago: 7200),       // cold, older
            file(2, status: "idle", ago: 4000),       // cold, more recent
            file(3, status: "idle", ago: 600),        // cached, 50 min left
            file(4, status: "idle", ago: 3000),       // cached, 10 min left
            file(5, status: "busy", ago: 60),
            file(6, status: "busy", ago: 300),
            file(7, status: "waiting", ago: 5),
            file(8, status: "waiting", ago: 50),
        ])
        XCTAssertEqual(b.chats.map(\.id), [8, 7, 6, 5, 4, 3, 2, 1])
        let groups = b.grouped(at: now)
        XCTAssertEqual(groups.needsYou.map(\.id), [8, 7])
        XCTAssertEqual(groups.working.map(\.id), [6, 5])
        XCTAssertEqual(groups.cached.map(\.id), [4, 3])
        XCTAssertEqual(groups.cold.map(\.id), [2, 1])
    }

    func testBoardIsCapped() {
        let b = board((1...50).map { file(Int32($0), status: "idle", ago: Double($0)) })
        XCTAssertEqual(b.chats.count, ChatBoard.maxChats)
    }

    func testStaleOnlyWhenALiveBoardStopsBeingRewritten() {
        let live = board([])
        XCTAssertFalse(live.isStale(readAt: now.addingTimeInterval(ChatBoard.staleAge)))
        XCTAssertTrue(live.isStale(readAt: now.addingTimeInterval(ChatBoard.staleAge + 1)))
        XCTAssertFalse(ChatBoard.empty(.off, now: now, theme: [:]).isStale(readAt: now.addingTimeInterval(86_400)))
        XCTAssertFalse(ChatBoard.empty(.closed, now: now, theme: [:]).isStale(readAt: now.addingTimeInterval(86_400)))
    }

    func testNeedsYouIDs() {
        let b = board([file(1, status: "waiting", ago: 1), file(2, status: "busy", ago: 1)])
        XCTAssertEqual(b.needsYouIDs, [1])
    }

    func testProcessIdentity() {
        let start = Date(timeIntervalSince1970: 1_793_744_318.6) // Tue Nov 3 22:18:38.6 2026 UTC
        XCTAssertEqual(ProcessIdentity.date(procStart: "Tue Nov  3 22:18:38 2026"), Date(timeIntervalSince1970: 1_793_744_318))
        XCTAssertTrue(ProcessIdentity.matches(procStart: "Tue Nov  3 22:18:38 2026", startTime: start))
        XCTAssertFalse(ProcessIdentity.matches(procStart: "Tue Nov  3 21:18:38 2026", startTime: start), "a reused PID")
        XCTAssertTrue(ProcessIdentity.matches(procStart: nil, startTime: start))
        XCTAssertTrue(ProcessIdentity.matches(procStart: "garbage", startTime: start))
    }

    func testRoundTripsThroughTheFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let store = WidgetSnapshotStore(fileURL: dir.appendingPathComponent(WidgetSnapshotStore.fileName))
        XCTAssertNil(store.readBoard())
        let original = board([file(1, status: "waiting", ago: 5, waitingFor: "input needed"), file(2, status: "idle", ago: 60)])
        try store.write(original)
        XCTAssertEqual(store.readBoard(), original)
        XCTAssertEqual(store.chatsURL.lastPathComponent, "chats.json")
    }

    /// The file holds titles, folder names, states and times only, never IDs, sockets or paths.
    func testEncodedBoardLeavesOutEverythingElse() throws {
        let file = try XCTUnwrap(SessionFile.decode(Data(realFile.utf8)))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let json = String(decoding: try encoder.encode(board([file])), as: UTF8.self)
        for leaked in ["befed815", "session_01", "cc-socks", "/Users/me", "sessionId", "bridge", "procStart", "claude-vscode"] {
            XCTAssertFalse(json.contains(leaked), "\(leaked) leaked into the board")
        }
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["feed", "observedAt", "cacheLifetime", "theme", "chats"])
        let chat = try XCTUnwrap((object["chats"] as? [[String: Any]])?.first)
        XCTAssertTrue(Set(chat.keys).isSubset(of: ["id", "title", "folder", "activity", "reason", "since"]))
    }
}
