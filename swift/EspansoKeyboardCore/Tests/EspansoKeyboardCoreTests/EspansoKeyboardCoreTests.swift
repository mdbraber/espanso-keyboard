import Foundation
import XCTest

@testable import EspansoKeyboardCore

/// The Rust core through its Swift interface, with scripts run by JavaScriptCore
/// (plan step 3). Runs in the iPhone Simulator.
final class EspansoKeyboardCoreTests: XCTestCase {
    /// fixtures/espanso/, found from this file's location in the repository.
    static let fixture = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // EspansoKeyboardCoreTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // EspansoKeyboardCore
        .deletingLastPathComponent()  // swift
        .deletingLastPathComponent()  // repository
        .appendingPathComponent("fixtures/espanso")

    static let jitsiPrefix = "https://meet.jit.si/mdb-"

    func testJitsiExpandsWithANewRoomEachTime() throws {
        let engine = try EspansoEngine(
            configFolder: Self.fixture.path, scriptRunner: JavaScriptCoreScriptRunner())
        XCTAssertEqual(engine.warnings(), [])

        var links = Set<String>()
        for _ in 0..<3 {
            let expansion = try XCTUnwrap(type(";jitsi", into: engine), engine.lastError() ?? "")
            XCTAssertEqual(expansion.deleteCount, 6)
            XCTAssertTrue(expansion.insert.hasPrefix(Self.jitsiPrefix), expansion.insert)
            let room = expansion.insert.dropFirst(Self.jitsiPrefix.count)
            XCTAssertEqual(room.count, 10, expansion.insert)
            XCTAssertTrue(room.allSatisfy { "abcdefghjkmnpqrstuvwxyz23456789".contains($0) })
            links.insert(expansion.insert)
            engine.reset()
        }
        XCTAssertEqual(links.count, 3)
    }

    func testEarlierVariablesReachTheScript() throws {
        let engine = try EspansoEngine(
            configFolder: Self.fixture.path, scriptRunner: JavaScriptCoreScriptRunner())
        XCTAssertEqual(type(";hallo", into: engine)?.insert, "Hallo Anna!")
    }

    func testARunawayScriptFailsWithinAboutASecond() throws {
        let engine = try engine(script: "for (;;) {}")
        let start = Date()
        XCTAssertNil(type(";s", into: engine))
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 1.5)
        XCTAssertGreaterThan(elapsed, 0.9)
        XCTAssertTrue(engine.lastError()?.contains("didn't finish") ?? false, engine.lastError() ?? "")

        // The script was stopped, not just abandoned: its thread ends. JavaScriptCore's
        // stop isn't precise; in gloob it took 1.1 to 8.4 seconds (docs/plan.md, step 3).
        let stopped = expectation(description: "script thread ends")
        DispatchQueue.global().async {
            while JavaScriptCoreScriptRunner.running.value > 0 { usleep(10_000) }
            stopped.fulfill()
        }
        wait(for: [stopped], timeout: 15)

        let other = try self.engine(script: "console.log('ok')")
        XCTAssertEqual(type(";s", into: other)?.insert, "[ok]")
    }

    func testTheTimeLimitCannotBeIgnored() throws {
        let folder = try espansoFolder(script: "console.log('partial'); for (;;) {}", ignoreError: true)
        let engine = try EspansoEngine(configFolder: folder.path, scriptRunner: JavaScriptCoreScriptRunner())
        XCTAssertNil(type(";s", into: engine))
    }

    func testConsoleErrorFailsTheSnippet() throws {
        let engine = try engine(script: "console.log('x'); console.error('bad')")
        XCTAssertNil(type(";s", into: engine))
        XCTAssertTrue(engine.lastError()?.contains("bad") ?? false, engine.lastError() ?? "")
    }

    func testAThrownErrorFailsTheSnippet() throws {
        let engine = try engine(script: "console.log('x'); throw new Error('broken')")
        XCTAssertNil(type(";s", into: engine))
        XCTAssertTrue(engine.lastError()?.contains("broken") ?? false, engine.lastError() ?? "")
    }

    func testAMissingScriptFailsTheSnippet() throws {
        let folder = try espansoFolder(script: nil)
        let engine = try EspansoEngine(configFolder: folder.path, scriptRunner: JavaScriptCoreScriptRunner())
        XCTAssertNil(type(";s", into: engine))
    }

    func testRunnerMatchesBun() throws {
        // process.argv, process.env, console.log joining, and non-string values.
        let output = JavaScriptCoreScriptRunner.evaluate(
            """
            console.log(process.argv[2], process.env.ESPANSO_X);
            console.log(1 + 1, { a: [true] }, null);
            console.warn("careful");
            """,
            path: "/x.js", argv: ["bun", "/x.js", "arg"], env: ["ESPANSO_X": "y"]
        ).output
        XCTAssertEqual(output, ScriptOutput(stdout: "arg y\n2 {\"a\":[true]} null\n", stderr: "careful\n", success: true))
    }

    /// Plan step 3, item 4: memory used by loading and by running a script. Printed for
    /// docs/plan.md; the assertion is the plan's "stop and discuss" limit. Other tests
    /// leave freed memory behind, so measure it on its own:
    /// `scripts/test-swift.sh -only-testing:EspansoKeyboardCoreTests/EspansoKeyboardCoreTests/testMemoryAfterLoad`
    func testMemoryAfterLoad() throws {
        let synthetic = try espansoFolder(snippets: 2000)
        for (name, folder) in [("fixture", Self.fixture), ("2000 snippets", synthetic)] {
            let before = footprint()
            let engine = try EspansoEngine(configFolder: folder.path, scriptRunner: JavaScriptCoreScriptRunner())
            _ = type("abc", into: engine)
            let after = footprint()
            let used = after - before
            print(String(format: "MEMORY %@: %.2f MB after load (footprint %.1f MB)",
                         name, used, after))
            XCTAssertLessThan(used, 30)
            withExtendedLifetime(engine) {}
        }

        // Running a script adds a JavaScriptCore virtual machine while it runs.
        let engine = try EspansoEngine(configFolder: Self.fixture.path, scriptRunner: JavaScriptCoreScriptRunner())
        let before = footprint()
        XCTAssertNotNil(type(";jitsi", into: engine))
        let after = footprint()
        print(String(format: "MEMORY first ;jitsi: %.2f MB (footprint %.1f MB)",
                     after - before, after))
        for _ in 0..<20 {
            engine.reset()
            XCTAssertNotNil(type(";jitsi", into: engine))
        }
        print(String(format: "MEMORY after 20 more ;jitsi: footprint %.1f MB", footprint()))
    }

    // MARK: Helpers

    /// Types `text` one character at a time and returns the last expansion.
    private func type(_ text: String, into engine: EspansoEngine) -> Expansion? {
        var last: Expansion?
        for character in text {
            if let expansion = engine.typeText(text: String(character)) {
                last = expansion
            }
        }
        return last
    }

    /// An engine on a throwaway folder whose `;s` snippet runs `script`.
    private func engine(script: String) throws -> EspansoEngine {
        let folder = try espansoFolder(script: script)
        let engine = try EspansoEngine(configFolder: folder.path, scriptRunner: JavaScriptCoreScriptRunner())
        XCTAssertEqual(engine.warnings(), [])
        return engine
    }

    private func espansoFolder(script: String?, ignoreError: Bool = false) throws -> URL {
        let folder = try newFolder()
        try write("", to: folder.appendingPathComponent("config/default.yml"))
        try write("""
            matches:
              - trigger: ";s"
                replace: "[{{out}}]"
                vars:
                  - name: out
                    type: script
                    params:
                      args: [bun, "%CONFIG%/scripts/s.js"]
                      ignore_error: \(ignoreError)
            """, to: folder.appendingPathComponent("match/base.yml"))
        if let script {
            try write(script, to: folder.appendingPathComponent("scripts/s.js"))
        }
        return folder
    }

    private func espansoFolder(snippets: Int) throws -> URL {
        let folder = try newFolder()
        try write("", to: folder.appendingPathComponent("config/default.yml"))
        var yaml = "matches:\n"
        for i in 0..<snippets {
            yaml += "  - trigger: \";snippet\(i)\"\n    replace: \"Replacement text number \(i), a sentence of ordinary length.\"\n"
        }
        try write(yaml, to: folder.appendingPathComponent("match/base.yml"))
        return folder
    }

    private func newFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return folder
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    /// The process's memory footprint in MB, as iOS counts it against the keyboard's
    /// limit. A `Double`, as it can shrink between measurements.
    private func footprint() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }
}
