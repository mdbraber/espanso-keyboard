import Foundation
import JavaScriptCore

/// Runs snippet scripts with JavaScriptCore, the way Bun runs them on the Mac
/// (docs/script-contract.md).
///
/// Each script gets a fresh `JSContext` on its own thread. JavaScriptCore has no public
/// way to stop a running script, so after `timeLimit` the runner stops waiting and the
/// snippet fails; a script that never ends keeps its thread busy.
public final class JavaScriptCoreScriptRunner: ScriptRunner {
    public let timeLimit: TimeInterval

    public init(timeLimit: TimeInterval = 1.0) {
        self.timeLimit = timeLimit
    }

    public func run(scriptPath: String, argv: [String], env: [String: String]) throws -> ScriptOutput {
        let source: String
        do {
            source = try String(contentsOfFile: scriptPath, encoding: .utf8)
        } catch {
            throw EspansoError.Script(message: "can't read \(scriptPath): \(error.localizedDescription)")
        }

        let result = Result()
        let thread = Thread {
            result.finish(Self.evaluate(source, path: scriptPath, argv: argv, env: env))
        }
        thread.name = "EspansoKeyboardCore script"
        thread.start()

        guard let output = result.wait(timeout: timeLimit) else {
            throw EspansoError.Script(message: "\(scriptPath) didn't finish within \(timeLimit) s")
        }
        return output
    }

    /// Runs `source` to the end and collects what it printed.
    static func evaluate(_ source: String, path: String, argv: [String], env: [String: String]) -> ScriptOutput {
        let output = Output()
        guard let context = JSContext(virtualMachine: JSVirtualMachine()) else {
            return ScriptOutput(stdout: "", stderr: "can't create a JavaScript context", success: false)
        }

        // An uncaught error: Bun prints it to standard error and exits with an error.
        context.exceptionHandler = { _, exception in
            output.success = false
            output.stderr += (exception?.toString() ?? "uncaught error") + "\n"
        }
        let log: @convention(block) (String) -> Void = { output.stdout += $0 + "\n" }
        let error: @convention(block) (String) -> Void = { output.stderr += $0 + "\n" }
        context.setObject(log, forKeyedSubscript: "__stdout" as NSString)
        context.setObject(error, forKeyedSubscript: "__stderr" as NSString)
        context.setObject(["argv": argv, "env": env], forKeyedSubscript: "process" as NSString)
        context.evaluateScript(prelude)

        context.evaluateScript(source, withSourceURL: URL(fileURLWithPath: path))
        return ScriptOutput(stdout: output.stdout, stderr: output.stderr, success: output.success)
    }

    /// `console` as in Bun: `log`, `info` and `debug` to standard output, `error` and `warn`
    /// to standard error, one line per call with the arguments joined by spaces.
    static let prelude = """
        (() => {
          const stdout = __stdout, stderr = __stderr;
          delete globalThis.__stdout;
          delete globalThis.__stderr;
          const format = (args) => args.map((a) =>
            typeof a === "string" ? a
              : a !== null && typeof a === "object" ? JSON.stringify(a)
              : String(a)).join(" ");
          globalThis.console = {
            log: (...a) => stdout(format(a)),
            info: (...a) => stdout(format(a)),
            debug: (...a) => stdout(format(a)),
            error: (...a) => stderr(format(a)),
            warn: (...a) => stderr(format(a)),
          };
        })();
        """
}

/// What one script printed; used only on the script's thread.
private final class Output {
    var stdout = ""
    var stderr = ""
    var success = true
}

/// Hands the output from the script's thread to the waiting caller.
private final class Result: @unchecked Sendable {
    private let done = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var output: ScriptOutput?

    func finish(_ output: ScriptOutput) {
        lock.withLock { self.output = output }
        done.signal()
    }

    func wait(timeout: TimeInterval) -> ScriptOutput? {
        guard done.wait(timeout: .now() + timeout) == .success else { return nil }
        return lock.withLock { output }
    }
}
