import Foundation
import JavaScriptCore

/// Runs snippet scripts with JavaScriptCore, the way Bun runs them on the Mac
/// (docs/script-contract.md).
///
/// Each script gets a fresh `JSContext` on its own thread. After `timeLimit` the runner
/// stops waiting and the snippet fails. The script itself is stopped soon after, with
/// JavaScriptCore's `JSContextGroupSetExecutionTimeLimit` set to `timeLimit`,
/// which is not public API (docs/decisions.md, "Stop runaway scripts"). Should that
/// function ever be missing, a script that never ends keeps its thread busy.
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
        let timeLimit = timeLimit
        let thread = Thread {
            Self.running.add(1)
            defer { Self.running.add(-1) }
            result.finish(Self.evaluate(source, path: scriptPath, argv: argv, env: env, timeLimit: timeLimit))
        }
        thread.name = "EspansoKeyboardCore script"
        thread.start()

        guard let evaluation = result.wait(timeout: timeLimit), !evaluation.timedOut else {
            throw EspansoError.Script(message: "\(scriptPath) didn't finish within \(timeLimit) s")
        }
        return evaluation.output
    }

    /// Scripts whose thread is still running; for tests.
    static let running = Counter()

    /// Runs `source` to the end, or until JavaScriptCore stops it after `timeLimit`, and
    /// collects what it printed.
    static func evaluate(
        _ source: String, path: String, argv: [String], env: [String: String],
        timeLimit: TimeInterval? = nil
    ) -> Evaluation {
        let output = Output()
        guard let context = JSContext(virtualMachine: JSVirtualMachine()) else {
            let failed = ScriptOutput(stdout: "", stderr: "can't create a JavaScript context", success: false)
            return Evaluation(output: failed, timedOut: false)
        }
        if let timeLimit, let setExecutionTimeLimit {
            setExecutionTimeLimit(
                JSContextGetGroup(context.jsGlobalContextRef), timeLimit, shouldTerminate,
                Unmanaged.passUnretained(output).toOpaque())
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
        return Evaluation(
            output: ScriptOutput(stdout: output.stdout, stderr: output.stderr, success: output.success),
            timedOut: output.timedOut)
    }

    struct Evaluation: Sendable {
        let output: ScriptOutput
        /// The script was stopped at the time limit.
        let timedOut: Bool
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
    var timedOut = false
}

// `JSContextGroupSetExecutionTimeLimit` from JavaScriptCore's private
// `JSContextRefPrivate.h`, looked up at run time as it has no public header.
private typealias ShouldTerminate = @convention(c) (JSContextRef?, UnsafeMutableRawPointer?) -> Bool
private typealias SetExecutionTimeLimit = @convention(c) (
    JSContextGroupRef?, Double, ShouldTerminate?, UnsafeMutableRawPointer?
) -> Void

nonisolated(unsafe) private let setExecutionTimeLimit: SetExecutionTimeLimit? = dlsym(
    UnsafeMutableRawPointer(bitPattern: -2),  // RTLD_DEFAULT
    "JSContextGroupSetExecutionTimeLimit"
).map { unsafeBitCast($0, to: SetExecutionTimeLimit.self) }

/// Called by JavaScriptCore at the time limit: marks the script as timed out and stops it.
private let shouldTerminate: ShouldTerminate = { _, info in
    if let info {
        Unmanaged<Output>.fromOpaque(info).takeUnretainedValue().timedOut = true
    }
    return true
}

/// A thread-safe count.
final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func add(_ delta: Int) { lock.withLock { count += delta } }
    var value: Int { lock.withLock { count } }
}

/// Hands the output from the script's thread to the waiting caller.
private final class Result: @unchecked Sendable {
    private let done = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var output: JavaScriptCoreScriptRunner.Evaluation?

    func finish(_ output: JavaScriptCoreScriptRunner.Evaluation) {
        lock.withLock { self.output = output }
        done.signal()
    }

    func wait(timeout: TimeInterval) -> JavaScriptCoreScriptRunner.Evaluation? {
        guard done.wait(timeout: .now() + timeout) == .success else { return nil }
        return lock.withLock { output }
    }
}
