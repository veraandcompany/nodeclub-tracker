import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// File logger for troubleshooting crashes and misbehavior.
///
/// Two independent layers:
///
/// 1. **Chatty logging** (toggle-gated). The "Verbose logging" switch in
///    Settings (`verboseLoggingKey` in UserDefaults) gates `log(_:)`. While
///    enabled, each dashboard refresh appends detail lines to the log file,
///    so the last lines before a death show exactly what the app was doing.
///
/// 2. **Crash capture** (always on once installed). `installCrashHandlers()`
///    registers handlers for fatal signals and uncaught Objective-C
///    exceptions that dump a backtrace to the same file *regardless* of the
///    toggle — a crash dump is one event, not chatter. Note SIGKILL/SIGSTOP
///    are uncatchable by design; for external kills the chatty layer plus
///    the clean-shutdown line is the evidence (a missing shutdown line means
///    the process was killed, not terminated).
///
/// The log defaults to `~/.nodeclub-tracker/logs/nodeclub-tracker.log`,
/// overridable via `PI_LOG_FILE`. Past a couple of MB it rotates to `.old`
/// (one generation). Logging must never crash the app: every I/O failure is
/// swallowed.
public enum VerboseLogger {
    /// UserDefaults key backing the Settings toggle.
    public static let verboseLoggingKey = "verboseLogging"

    private static let maxLogBytes = 2_000_000
    private static let oldFileName = "nodeclub-tracker.log.old"

    public enum Level: String, Sendable {
        case info
        case error
        case fatal
    }

    /// `~/.nodeclub-tracker/logs/nodeclub-tracker.log`, overridable via `PI_LOG_FILE`.
    public static var logFileURL: URL {
        if let override = ProcessInfo.processInfo.environment["PI_LOG_FILE"] {
            return URL(fileURLWithPath: override)
        }
        return URL(fileURLWithPath: NSHomeDirectory() + "/.nodeclub-tracker/logs/nodeclub-tracker.log")
    }

    // MARK: - Chatty logging (toggle-gated)

    /// Append one detail line; a no-op unless the verbose toggle is on.
    public static func log(
        _ message: String,
        level: Level = .info,
        defaults: UserDefaults = .standard,
        to url: URL = logFileURL
    ) {
        guard defaults.bool(forKey: verboseLoggingKey) else { return }
        appendLine(level: level, message: message, to: url)
    }

    /// Marker lines for toggle flips. They bypass the toggle check so the
    /// *disable* event is still recorded before the flag turns off.
    public static func logEnabledMarker() {
        appendLine(level: .info, message: "verbose logging enabled (pid \(ProcessInfo.processInfo.processIdentifier))")
    }

    public static func logDisabledMarker() {
        appendLine(level: .info, message: "verbose logging disabled (pid \(ProcessInfo.processInfo.processIdentifier))")
    }

    // MARK: - Appending

    /// Append a timestamped line to `url`. Never throws; injected date and
    /// calendar make it pin-testable against a temp file.
    public static func appendLine(
        level: Level,
        message: String,
        to url: URL = logFileURL,
        now: Date = Date(),
        calendar: Calendar = Calendar.current
    ) {
        let line = "\(timestamp(for: now, calendar: calendar)) [\(level.rawValue)] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            rotateIfNeeded(url: url, fileManager: fileManager)
            if fileManager.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }
                handle.seekToEndOfFile()
                try handle.write(contentsOf: data)
                handle.synchronizeFile()
            } else {
                try data.write(to: url, options: .atomic)
            }
        } catch {
            // Logging must never take the app down with it.
        }
    }

    /// Past `maxLogBytes`, shift one generation: `.old` is replaced by the current file.
    private static func rotateIfNeeded(url: URL, fileManager: FileManager) {
        guard
            let attributes = try? fileManager.attributesOfItem(atPath: url.path),
            let size = attributes[.size] as? Int,
            size > maxLogBytes
        else { return }
        let oldURL = url.deletingLastPathComponent().appendingPathComponent(oldFileName)
        try? fileManager.removeItem(at: oldURL)
        try? fileManager.moveItem(at: url, to: oldURL)
    }

    /// "2026-07-03 14:22:31" in the given calendar. Pure and pin-testable.
    public static func timestamp(for date: Date, calendar: Calendar = Calendar.current) -> String {
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(
            format: "%04d-%02d-%02d %02d:%02d:%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0,
            components.hour ?? 0,
            components.minute ?? 0,
            components.second ?? 0
        )
    }

    // MARK: - Crash capture

    /// Register handlers for fatal signals and uncaught Objective-C
    /// exceptions. Call once at launch. SIGKILL/SIGSTOP cannot be caught.
    public static func installCrashHandlers() {
        // Pin the log path up front; the signal handler must not
        // touch ProcessInfo or Foundation.
        _ = crashLogPath
        for signalNumber in [SIGSEGV, SIGBUS, SIGFPE, SIGILL, SIGTRAP, SIGABRT] {
            signal(signalNumber, crashSignalHandler)
        }
        NSSetUncaughtExceptionHandler(uncaughtExceptionHandler)
    }

    /// Handler for fatal signals. Deliberately limited to async-signal-safe-ish
    /// calls (open/write/backtrace, no Foundation, no Swift strings, no actor
    /// hops) — the runtime may be wedged by the time we get here. Re-raises
    /// with the default handler so the system still writes a crash report.
    fileprivate static func handleFatalSignalInternal(_ signalNumber: Int32) {
        crashLogPath.withCString { path in
            let fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
            guard fd >= 0 else { return }
            defer { close(fd) }

            // asctime_r format: "Thu Jul  3 14:22:31 2026"; first 24 chars.
            var timeNow = time(nil)
            var timeInfo = tm()
            var timestamp = [CChar](repeating: 0, count: 64)
            if localtime_r(&timeNow, &timeInfo) != nil {
                _ = asctime_r(&timeInfo, &timestamp)
            }

            var header = [CChar](repeating: 0, count: 256)
            buildHeader(&header, signalNumber: signalNumber, timestamp: timestamp)
            _ = write(fd, &header, strlen(&header))

            var frames = [UnsafeMutableRawPointer?](repeating: nil, count: 128)
            let frameCount = backtrace(&frames, 128)
            if frameCount > 0, let symbols = backtrace_symbols(&frames, frameCount) {
                var index = 0
                while index < frameCount {
                    if let symbol = symbols[index] {
                        let length = strlen(symbol)
                        if length > 0 { _ = write(fd, symbol, length) }
                    }
                    index += 1
                }
            }
            let footer = "=== end of crash dump ===\n"
            _ = write(fd, footer, strlen(footer))
            _ = fsync(fd)
        }
        restoreAndReraise(signalNumber)
    }

    /// Handler for uncaught Objective-C exceptions. The runtime is intact
    /// here (the exception is in flight, the allocator works), so Foundation
    /// is safe. Aborts afterwards so the SIGABRT handler also records a
    /// native backtrace and ReportCrush still gets its report.
    fileprivate static func handleUncaughtExceptionInternal(name: String, reason: String?) {
        appendLine(level: .fatal, message: "uncaught exception \(name): \(reason ?? "no reason")")
        appendLine(level: .fatal, message: Thread.callStackSymbols.joined(separator: "\n"))
        abort()
    }

    /// Assemble the crash header without snprintf (variadic C calls are
    /// unavailable under Swift 6 strict concurrency).
    private static func buildHeader(_ buffer: inout [CChar], signalNumber: Int32, timestamp: [CChar]) {
        var offset = 0
        func append(_ bytes: UnsafePointer<CChar>) {
            var pointer = bytes
            while pointer.pointee != 0 {
                buffer[offset] = pointer.pointee
                offset += 1
                pointer += 1
            }
        }
        func appendInt(_ value: Int32) {
            var n = value < 0 ? -value : value
            var digits = [CChar](repeating: 0, count: 16)
            var count = 0
            if value < 0 { buffer[offset] = 45; offset += 1 } // "-"
            while n > 0 {
                digits[count] = CChar(48 + n % 10)
                count += 1
                n /= 10
            }
            if count == 0 { buffer[offset] = 48; offset += 1 } // "0"
            while count > 0 {
                count -= 1
                buffer[offset] = digits[count]
                offset += 1
            }
        }
        append("\n=== FATAL SIGNAL ".withCString { $0 })
        appendInt(signalNumber)
        append(" (".withCString { $0 })
        signalName(signalNumber).withCString(append)
        append(") pid ".withCString { $0 })
        appendInt(getpid())
        append(" at ".withCString { $0 })
        // asctime_r output: first 24 chars, no trailing newline.
        var index = 0
        while index < 24, timestamp[index] != 0 {
            buffer[offset] = timestamp[index]
            offset += 1
            index += 1
        }
        append(" ===\n".withCString { $0 })
        buffer[offset] = 0
    }

    private static func signalName(_ signalNumber: Int32) -> String {
        switch signalNumber {
        case SIGSEGV: return "SIGSEGV"
        case SIGBUS: return "SIGBUS"
        case SIGFPE: return "SIGFPE"
        case SIGILL: return "SIGILL"
        case SIGTRAP: return "SIGTRAP"
        case SIGABRT: return "SIGABRT"
        default: return "UNKNOWN"
        }
    }

    private static func restoreAndReraise(_ signalNumber: Int32) {
        signal(signalNumber, SIG_DFL)
        raise(signalNumber)
        // Unreachable: raise with the default handler terminates the process.
        _exit(128 + signalNumber)
    }

    /// Process-lifetime log path; the signal handler must not touch
    /// ProcessInfo or env, so it is pinned at `installCrashHandlers()` time.
    /// `String` is `Sendable`, and `withCString` in the handler is
    /// allocation-free for a Swift string.
    private static let crashLogPath: String = logFileURL.path
}

// MARK: - C function pointer shims
//
// `signal()` and `NSSetUncaughtExceptionHandler` need `@convention(c)`
// pointers, which Swift forms from top-level functions rather than enum
// member references, so the entry points live here and delegate inward.

private func crashSignalHandler(_ signalNumber: Int32) {
    VerboseLogger.handleFatalSignalInternal(signalNumber)
}

private func uncaughtExceptionHandler(_ exception: NSException) {
    VerboseLogger.handleUncaughtExceptionInternal(
        name: exception.name.rawValue,
        reason: exception.reason
    )
}
