import ApplicationServices
import Foundation

/// Synthesizes a real screen lock without a third-party installer or kernel driver.
///
/// Strategy (first success wins):
///  1. `/System/Library/.../CGSession -suspend` — the classic lock tool (removed on macOS 25+)
///  2. Control+Command+Q ("Lock Screen" shortcut via CGEvent) — needs Accessibility permission
///  3. `open -a ScreenSaverEngine` with `askForPassword` — permission-free; shows the classic
///     lock wallpaper and requires a password (or Watch/Touch ID) to dismiss
///  4. `pmset displaysleepnow` — last-resort permission-free display sleep
public enum LockController {
    @discardableResult
    public static func lockScreen() -> Bool {
        let cgSessionCandidates = [
            "/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession",
            "/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession.app/Contents/MacOS/CGSession"
        ]
        for path in cgSessionCandidates where FileManager.default.fileExists(atPath: path) {
            if run(executable: path, arguments: ["-suspend"]) {
                log("cgsession -> ok")
                return true
            }
        }

        if AXIsProcessTrusted() {
            log("ax trusted, posting cmd-ctrl-q")
            if postLockScreenShortcut() {
                log("posted cmd-ctrl-q -> ok")
                return true
            }
        } else {
            log("ax NOT trusted")
        }

        log("fallback: screen-saver lock")
        enforcePasswordOnWake()
        _ = run(executable: "/usr/bin/killall", arguments: ["cfprefsd"])
        let readback = readAskForPassword() ?? -1
        log("policy readback=\(readback)")
        if run(executable: "/usr/bin/open", arguments: ["-a", "ScreenSaverEngine"]) {
            log("screensaver launched -> ok")
            return true
        }
        log("screensaver failed, falling back to pmset displaysleepnow")
        return run(executable: "/usr/bin/pmset", arguments: ["displaysleepnow"])
    }

    private static func log(_ message: String) {
        let url = URL(fileURLWithPath: NSHomeDirectory() + "/presence_lock.log")
        let line = (Date().ISO8601Format() + " " + message + "\n").data(using: .utf8) ?? Data()
        if let handle = FileHandle(forWritingAtPath: url.path) {
            try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            _ = FileManager.default.createFile(atPath: url.path, contents: line)
        }
    }

    /// Enables the "require password immediately after sleep / screen saver" policy for
    /// this user via the per-host preferences domain. No special permission needed.
    @discardableResult
    private static func enforcePasswordOnWake() -> Bool {
        let writes = [
            run(defaults: ["-currentHost", "write", "com.apple.screensaver", "askForPassword", "-int", "1"]),
            run(defaults: ["-currentHost", "write", "com.apple.screensaver", "askForPasswordDelay", "-int", "0"])
        ]
        return writes.allSatisfy { $0 }
    }

    /// Posts the Control+Command+Q keystroke that triggers macOS "Lock Screen".
    /// Requires the process to be trusted for Accessibility.
    private static func postLockScreenShortcut() -> Bool {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x0C, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x0C, keyDown: false)
        else { return false }

        keyDown.flags = [.maskControl, .maskCommand]
        keyUp.flags = [.maskControl, .maskCommand]
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }

    private static func run(executable: String, arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        do {
            try process.run()
            return true
        } catch {
            return false
        }
    }

    private static func run(defaults arguments: [String]) -> Bool {
        run(executable: "/usr/bin/defaults", arguments: arguments)
    }

    private static func readAskForPassword() -> Int? {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["-currentHost", "read", "com.apple.screensaver", "askForPassword"]
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return Int(String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
    }
}